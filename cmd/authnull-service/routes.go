// Route registration for authnull-service.
// All endpoints live under /api/v1. Auth is enforced per-route inside each package.
package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"github.com/authnull0/authnull-service/pkg/middleware"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	pkgdb "github.com/authnull0/authnull-service/pkg/db"
	"github.com/gin-gonic/gin"

	"github.com/authnull0/authnull-service/internal/ad"
	"github.com/authnull0/authnull-service/internal/dashboard"
	"github.com/authnull0/authnull-service/internal/database"
	"github.com/authnull0/authnull-service/internal/database/dbmfa"
	"github.com/authnull0/authnull-service/internal/dbconsole"
	"github.com/authnull0/authnull-service/internal/deviceapi"
	"github.com/authnull0/authnull-service/internal/endpoint"
	"github.com/authnull0/authnull-service/internal/entra"
	// DID-REMOVAL: "github.com/authnull0/authnull-service/internal/issuer"
	"github.com/authnull0/authnull-service/internal/mfa"
	"github.com/authnull0/authnull-service/internal/org"
	"github.com/authnull0/authnull-service/internal/pam"
	"github.com/authnull0/authnull-service/internal/policy"
	"github.com/authnull0/authnull-service/internal/serviceaccounts"
	tenantpkg "github.com/authnull0/authnull-service/internal/tenant"
	"github.com/authnull0/authnull-service/internal/user"
	// DID-REMOVAL: "github.com/authnull0/authnull-service/internal/verifier"
	// DID-REMOVAL: "github.com/authnull0/authnull-service/internal/wallet"
)

// proxyTo forwards a request to the given target URL, copying headers and body.
func proxyTo(c *gin.Context, target string) {
	body, _ := io.ReadAll(c.Request.Body)
	req, err := http.NewRequest(c.Request.Method, target, bytes.NewBuffer(body))
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "proxy error"})
		return
	}
	for k, vs := range c.Request.Header {
		for _, v := range vs {
			req.Header.Add(k, v)
		}
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "upstream unreachable"})
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	for k, vs := range resp.Header {
		for _, v := range vs {
			c.Header(k, v)
		}
	}
	c.Data(resp.StatusCode, resp.Header.Get("Content-Type"), respBody)
}

// RegisterAllRoutes wires every domain package under /api/v1.
// Each package gets its own isolated sub-group via api.Group("") so that
// rg.Use() calls inside a package do not leak middleware to sibling packages.
//
// Aliases are registered for URL patterns the UI v2 uses that differ from
// the canonical /api/v1/{domain}/... pattern.
func RegisterAllRoutes(r *gin.Engine) {
	api := r.Group("/api/v1")

	// ── licence ──────────────────────────────────────────────────────────────
	//
	// Registered here, on the plain api group, rather than inside a domain package: the licence is a
	// property of the DEPLOYMENT, not of an organisation or a feature, and the handlers need the
	// loader that main.go owns.
	//
	// Neither path is in license.controlPlaneWrites, and must never be. An expired deployment has to
	// be able to install a licence, so gating these would make renewal impossible without direct
	// database access. Asserted by TestLicenseEndpointsAreNeverGated.
	{
		lic := api.Group("")
		lic.Use(middleware.AuthnzMiddleware())
		lic.GET("/license", GetLicense)
		lic.POST("/license/upload", UploadLicense)
	}

	// ── canonical routes ─────────────────────────────────────────────────────
	ad.RegisterRoutes(api.Group(""))
	dashboard.RegisterRoutes(api.Group(""))
	database.RegisterRoutes(api.Group(""))
	dbconsole.RegisterRoutes(api.Group(""))
	endpoint.RegisterRoutes(api.Group(""))
	entra.RegisterRoutes(api.Group(""))
	// DID-REMOVAL: issuer (SSI / DID / VC) endpoints — 47 routes.
	// issuer.RegisterRoutes(api.Group(""))
	mfa.RegisterRoutes(api.Group(""))
	org.RegisterRoutes(api.Group(""))
	pam.RegisterRoutes(api.Group("/pam"))
	policy.RegisterRoutes(api.Group(""))
	serviceaccounts.RegisterRoutes(api.Group(""))
	tenantpkg.RegisterRoutes(api.Group("/tenant"))
	tenantpkg.RegisterRoutes(api.Group("/tenants"))
	user.RegisterRoutes(api.Group(""))
	// SSC calls org endpoints under /tenants/* (old tenants-service flat pattern)
	user.RegisterSscCompatRoutes(api.Group("/tenants"))
	// DID-REMOVAL: verifier (presentation request / verification) endpoints.
	// Called by installed endpoint / AD / RADIUS agents, not by any browser UI.
	// verifier.RegisterRoutes(api.Group(""))
	// DID-REMOVAL: wallet endpoints under /api/v1/wallet/*.
	// wallet.RegisterRoutes(api.Group(""))

	// ── dashboardService alias: UI v2 calls /api/v1/dashboardService/* ───────
	dashboard.RegisterDashboardServiceRoutes(api.Group("/dashboardService"))

	// ── databaseService alias: UI calls /api/v1/databaseService/* ────────────
	database.RegisterDatabaseServiceRoutes(api.Group("/databaseService"))

	// ── walletService alias: SSC calls /api/v1/walletService/* ───────────────
	// The admin UI's IAM-user picker still posts to /api/v1/walletService/walletUserList, and the
	// policy screens cannot be used without it. Served from did.users by internal/user rather than
	// by re-registering the wallet group -- see RegisterLegacyWalletUserListRoute for why the
	// original route would have returned an empty list even if it were mounted.
	user.RegisterLegacyWalletUserListRoute(api.Group("/walletService"))

	// DID-REMOVAL: same 28 handlers as wallet.RegisterRoutes, under the legacy
	// prefix the mobile wallet app calls.
	// wallet.RegisterWalletServiceRoutes(api.Group("/walletService"))

	// ── /api/v1/tenants/tenants/* alias (UI double-prefixes some tenant paths) ─
	tenantpkg.RegisterRoutes(api.Group("/tenants/tenants"))

	// ── /api/v1/did/* and /api/v1/credential/* — issuer short-path aliases ───
	// DID-REMOVAL: 12 admin-UI short paths (/api/v1/did/DIDList etc).
	// issuer.RegisterDidAliasRoutes(api.Group(""))

	// ── /api/v1/secretservice/* stub (vault not in scope for on-prem) ────────
	api.POST("/secretservice/getConnectionMode", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"code": 200, "status": "success", "connectionMode": 0})
	})
	api.POST("/secretservice/createSecretinVault", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"code": 200, "status": "success", "message": "vault not configured"})
	})

	// ── AuthNull Authenticator self-service ─────────────────────────────────
	// Mounted EXACTLY ONCE, unlike ad/mfa which are each registered twice: the device
	// signs the gin route pattern, so a second mount would mean a signature valid at
	// one path and rejected at the other.
	deviceapi.RegisterRoutes(api.Group(""))

	// ── /ad/* alias at root: UI calls /ad/GetAuthLog etc. without /api/v1 ───
	ad.RegisterRoutes(r.Group(""))

	// ── UI v2 aliases ────────────────────────────────────────────────────────
	// UI calls /pam/api/v1/...  →  canonical: /api/v1/pam/...
	pam.RegisterRoutes(r.Group("/pam/api/v1"))

	// UI calls /api/v1/policyService/...  →  flat PascalCase aliases
	policy.RegisterPolicyServiceRoutes(api.Group("/policyService"))

	// ProxySQL's authorisation call. Its own group with NO auth middleware: ProxySQL runs on the
	// customer's VM and its config carries an org id, a tenant id and a URL, nothing more. The
	// one-time token in the request is what identifies the person. Data-plane, never licence-gated.
	dbmfa.RegisterRoutes(api.Group(""))

	// Unattended agents: the DC sensor, the database-agent and the RADIUS binary. Its own
	// group so policy's AuthnzMiddleware does not apply -- none of them has a credential, and
	// these are data-plane paths that must not be gateable. See RegisterAgentRoutes.
	policy.RegisterAgentRoutes(api.Group(""))

	// Co-located services: authn-service's policy lookup and audit write. NOT the same posture as
	// the agent group above -- these require an INTERNAL_API_KEY, because nginx proxies all of
	// /api/ here and an unauthenticated mount would be an anonymous policy read and audit write
	// reachable from the internet. The agents are exempt by necessity; a container on this compose
	// network is not. See policy.RegisterInternalServiceRoutes.
	policy.RegisterInternalServiceRoutes(api.Group(""))

	// UI calls /api/v1/service-accounts/...  →  canonical: /api/v1/serviceAccounts/...
	serviceaccounts.RegisterRoutes(api.Group("/service-accounts"))

	// ── SSC auth aliases: /authentication/* ─────────────────────────────────
	// SSC uses REACT_APP_BASE_URL (no /api/v1 prefix) for auth calls.
	// Paths with /mfa/ in them are handled by RegisterRoutes on /authentication.
	// Paths WITHOUT /mfa/ (normalLogin, ssomfa, verifyUser) need RegisterSscAuthRoutes.
	mfa.RegisterRoutes(r.Group("/authentication"))
	mfa.RegisterSscAuthRoutes(r.Group("/authentication"))

	// ── /authnz/* proxy → authnz service ─────────────────────────────────────
	// Admin UI calls /authnz/getUserDetails on port 8080 (authnull-service).
	// Forward these to the authnz container which handles session validation.
	authnzURL := os.Getenv("AUTHNZ_URL")
	if authnzURL == "" {
		authnzURL = "http://localhost:6066/authnz/authenticate"
	}
	// Extract base: http://authnz:6066 from AUTHNZ_URL
	authnzBase := authnzURL
	if idx := len(authnzURL) - len("/authnz/authenticate"); idx > 0 && authnzURL[idx:] == "/authnz/authenticate" {
		authnzBase = authnzURL[:idx]
	}
	// getUserDetails — validates the session token from normalLogin and returns user info.
	// The token format is: sessionID&DOMAIN&domainUrl  (from AUTH_TOKEN_DOMAIN() in the UI)
	// sessionID maps to base64(orgId:domainId:userId) stored in Redis during login.
	r.POST("/authnz/getUserDetails", func(c *gin.Context) {
		token := c.GetHeader("X-Authorization")
		siteURL := c.GetHeader("X-RequestUrl")
		if siteURL == "" {
			siteURL = c.GetHeader("x-requesturl")
		}

		// Extract sessionID from "sessionID&DOMAIN&domainUrl" or plain sessionID
		sessionID := token
		if idx := strings.Index(token, "&DOMAIN&"); idx > 0 {
			sessionID = token[:idx]
		} else if idx := strings.Index(token, "&ORGLOGIN&"); idx > 0 {
			sessionID = token[:idx]
		}

		if sessionID == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"Validation": false, "Message": "Missing token"})
			return
		}

		// Look up sessionID in Redis → base64(orgId:domainId:userId)
		redisClient := pkgdb.GetRedisInstance()
		if redisClient == nil {
			// Redis unavailable — try authnz proxy fallback
			proxyTo(c, authnzBase+"/authnz/getUserDetails")
			return
		}

		encoded, err := redisClient.Get(context.Background(), sessionID).Result()
		if err != nil {
			// Not in Redis — forward to authnz (Okta/JWT tokens)
			proxyTo(c, authnzBase+"/authnz/getUserDetails")
			return
		}

		// Decode base64(orgId:domainId:userId)
		decoded, err := base64.StdEncoding.DecodeString(encoded)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"Validation": false, "Message": "Invalid session"})
			return
		}

		parts := strings.Split(string(decoded), ":")
		if len(parts) < 3 {
			c.JSON(http.StatusUnauthorized, gin.H{"Validation": false, "Message": "Invalid session format"})
			return
		}

		orgID, _ := strconv.Atoi(parts[0])
		domainID, _ := strconv.Atoi(parts[1])
		userID, _ := strconv.Atoi(parts[2])
		username := ""
		userRoleID := 1 // default ADMIN
		if len(parts) >= 4 {
			username = parts[3]
		}
		if len(parts) >= 5 {
			userRoleID, _ = strconv.Atoi(parts[4])
		}

		// Map role ID to role name
		userRole := "ADMIN"
		switch userRoleID {
		case 1:
			userRole = "ADMIN"
		case 2:
			userRole = "SUPERADMIN"
		case 3:
			userRole = "ENDUSER"
		}

		_ = siteURL

		c.JSON(http.StatusOK, gin.H{
			"Validation": true,
			"Message":    "User Details",
			"Status":     "Success",
			"Code":       200,
			"UserID":     userID,
			"OrgID":      orgID,
			"DomainID":   domainID,
			"UserRole":   userRole,
			"Username":   username,
		})
	})
	r.GET("/authnz/authenticate", func(c *gin.Context) {
		proxyTo(c, authnzBase+"/authnz/authenticate")
	})

	// ── /ssc/signin redirect → self-service-console container ────────────────
	r.GET("/ssc/signin", func(c *gin.Context) {
		sscURL := os.Getenv("SSC_URL")
		if sscURL == "" {
			sscURL = "http://localhost:3000"
		}
		c.Redirect(302, sscURL+"/ssc/signin?"+c.Request.URL.RawQuery)
	})
}
