// Package middleware holds cross-cutting HTTP middleware shared across all
// merged services (CORS + Authnz). Hoisted from each microservice's src/utils.
// NOTE (merge): minimal shared middleware set for the consolidated service.
package middleware

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	pkgdb "github.com/authnull0/authnull-service/pkg/db"
	"github.com/authnull0/authnull-service/pkg/httpclient"
	"github.com/authnull0/authnull-service/pkg/session"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

// AuthnzResponseDTO is the response shape from the authnz (authn-service) call.
type AuthnzResponseDTO struct {
	Validation bool
}

// CORS allows cross-origin requests (preserves the per-service CORS behavior).
func CORS() gin.HandlerFunc {
	return func(c *gin.Context) {
		logrus.Info("Middleware:CORS: allowOrigin: *")
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		// The X-Authnull-Device-* set is the AuthNull Authenticator's request signature.
		// A native app is not subject to CORS, but the browser-based enrollment tester
		// and any future web console reuse of this API are.
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With, X-Authorization, withCredentials, User-Agent, x-requesturl, X-RequestUrl, x-authorization, X-Authnull-Device-Alg, X-Authnull-Device-Org, X-Authnull-Device-Key, X-Authnull-Device-Nonce, X-Authnull-Device-Timestamp, X-Authnull-Device-Signature")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT,DELETE")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}

// AuthnzMiddleware gates a route group by validating the X-Authorization token
// against authn-service (AUTHNZ_URL). It is the canonical name used by the
// module RegisterRoutes wiring; it reuses AuthnzCall.
//
// Demo/local escape hatch: when AUTH_DISABLED=true (or no AUTHNZ_URL is
// configured), validation is skipped so routes are reachable without a live
// authn-service. With AUTHNZ_URL set and AUTH_DISABLED unset, behavior is
// unchanged (full validation).
func AuthnzMiddleware() gin.HandlerFunc {
	return AuthnzCall()
}

// InternalAPIKeyHeader is the header a CO-LOCATED SERVICE presents in place of a user session.
//
// The name and the INTERNAL_API_KEY env var behind it are not new: UpdateMfaFlagADUsers in
// internal/ad/src/controller has checked this exact pair inline since before the consolidation, and
// the variable is already declared in .env, .env.prod and both compose files. This promotes that
// one-off to middleware rather than inventing a second mechanism beside it.
const InternalAPIKeyHeader = "X-Internal-Api-Key"

// InternalKeyOrAuthnz gates a route group for callers that may be EITHER a signed-in person OR a
// co-located internal service such as authn-service.
//
// WHY THIS EXISTS RATHER THAN AN UNAUTHENTICATED GROUP
//
// authn-service needs SearchPolicy and logAccessRequest, and it holds no user session. The obvious
// move -- put them next to the agent routes in policy.RegisterAgentRoutes, which are deliberately
// unauthenticated -- is wrong here, and the reason is nginx: authnull.conf proxies ALL of /api/ to
// this service, so anything mounted there is reachable from the internet. That would make
// SearchPolicy an anonymous policy READ (leaking AD group names, and enumerable across tenants
// because orgId travels in the body) and logAccessRequest an anonymous audit WRITE.
//
// The agent routes earn their exemption by necessity: the DC sensor, the RADIUS binary and the
// database-agent run on customer infrastructure with no credential to present, which is the
// known, deferred gap documented on RegisterAgentRoutes. authn-service has no such excuse -- it is
// a container on the same compose network and can perfectly well hold a key. So it does.
//
// A caller presenting the key gets the same access a console session would. That is the intended
// blast radius: this is a service credential, not a scope.
func InternalKeyOrAuthnz() gin.HandlerFunc {
	authnz := AuthnzMiddleware()
	return func(c *gin.Context) {
		if internalKeyMatches(c) {
			c.Next()
			return
		}
		authnz(c)
	}
}

// internalKeyMatches reports whether the request carries this deployment's internal service key.
//
// AN UNSET KEY NEVER MATCHES. If INTERNAL_API_KEY is empty -- which is how it ships in .env -- this
// returns false for every request, including one sending an empty header, so the route falls back to
// session auth and stays closed. Getting that backwards would turn "the operator has not configured
// a key yet" into "the endpoint is open to anyone", which is the failure this whole function exists
// to avoid.
//
// Compared with constant time so the key cannot be recovered a byte at a time.
func internalKeyMatches(c *gin.Context) bool {
	want := strings.TrimSpace(os.Getenv("INTERNAL_API_KEY"))
	if want == "" {
		return false
	}
	got := strings.TrimSpace(c.GetHeader(InternalAPIKeyHeader))
	if got == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
}

// isRedisSession checks if the token is a valid session stored in Redis.
// Token format: "sessionID" or "sessionID&DOMAIN&domainUrl" or "sessionID&ORGLOGIN&..."
func isRedisSession(token string) bool {
	sessionID := token
	if idx := strings.Index(token, "&DOMAIN&"); idx > 0 {
		sessionID = token[:idx]
	} else if idx := strings.Index(token, "&ORGLOGIN&"); idx > 0 {
		sessionID = token[:idx]
	}
	if sessionID == "" {
		return false
	}
	redisClient := pkgdb.GetRedisInstance()
	if redisClient == nil {
		return false
	}
	val, err := redisClient.Get(context.Background(), sessionID).Result()
	if err != nil || val == "" {
		return false
	}

	// Absolute cap. The companion key is written once at login and never refreshed, so
	// its expiry bounds total session lifetime no matter how active the session is.
	// Without it the sliding window below never closes — a request every 19 minutes
	// would keep a session alive indefinitely.
	//
	// Sessions created before this check existed have no companion key and are therefore
	// rejected, which logs everyone out once on deploy. That is intended: there is no way
	// to know when those sessions began.
	if exists, err := redisClient.Exists(context.Background(), session.AbsoluteKey(sessionID)).Result(); err != nil || exists == 0 {
		return false
	}

	// Sliding expiry: extend the session on each authorised request.
	//
	// A Redis TTL is absolute, so without this an actively-used session would be cut off
	// a fixed 20 minutes after sign-in regardless of activity. Refreshing here makes the
	// idle window mean "idle for this long" while the companion key above still enforces
	// the ceiling.
	//
	// Best-effort: failing to extend must not fail an otherwise valid request. The worst
	// case is the session expiring at its original time.
	if ttl := session.IdleTTL(); ttl > 0 {
		_ = redisClient.Expire(context.Background(), sessionID, ttl).Err()
	}

	return true
}

// AuthnzCall gates a route group by validating the X-Authorization token.
// It first checks Redis (for on-prem password-login sessions), then falls
// back to authnz (for Okta/JWT tokens). AUTH_DISABLED=true bypasses all checks.
func AuthnzCall() gin.HandlerFunc {
	if os.Getenv("AUTH_DISABLED") == "true" {
		return func(c *gin.Context) { c.Next() }
	}
	return func(c *gin.Context) {
		token := c.GetHeader("X-Authorization")
		if token == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
			c.Abort()
			return
		}
		// Check Redis first (on-prem password-login sessions)
		if isRedisSession(token) {
			c.Next()
			return
		}
		// Fall back to authnz (Okta/JWT tokens) if AUTHNZ_URL is set
		if os.Getenv("AUTHNZ_URL") == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
			c.Abort()
			return
		}
		if !Authnz(token, c, 0) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
			c.Abort()
			return
		}
		c.Next()
	}
}

// Authnz performs the HTTP validation call to authn-service.
func Authnz(token string, ctx *gin.Context, orgid int) bool {
	// Bounded, shared client. This call runs inline inside every authenticated request, so an
	// unbounded one -- which is what &http.Client{} is -- means a single unresponsive authnz
	// instance parks every in-flight request forever, each still holding its database
	// connection. Failing fast returns a clean 401 the caller can retry.
	client := httpclient.Auth()
	authnzurl := os.Getenv("AUTHNZ_URL")

	// The request carries the caller's context, so a client that gives up or disconnects
	// cancels the authorization call instead of leaving it running with nobody waiting.
	req, err := http.NewRequestWithContext(ctx.Request.Context(), "GET", authnzurl, nil)
	if err != nil {
		log.Default().Println(err)
		return false
	}
	req.Header.Set("X-Authorization", token)
	req.Header.Set("X-Request-Path", ctx.Request.URL.Path)
	req.Header.Set("X-Org-Id", strconv.Itoa(orgid))

	resp, err := client.Do(req)
	if err != nil {
		log.Default().Println(err)
		return false
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Default().Println(err)
		return false
	}

	var response AuthnzResponseDTO
	if err := json.Unmarshal(body, &response); err != nil {
		log.Default().Println(err)
		return false
	}
	return response.Validation
}
