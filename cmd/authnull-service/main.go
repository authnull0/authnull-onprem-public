// authnull-service: consolidated entrypoint for the merged microservices.
//
// Wires every module — ad, dashboard, database, dbconsole, endpoint, entra,
// issuer, mfa, org, pam, policy, serviceaccounts, tenant, user, verifier,
// wallet — into a single Gin engine. Auth is applied per-module inside each
// RegisterRoutes call.
//
// All modules are mounted under /api/v1, plus root-level and legacy aliases the
// admin UI and self-service console still call. See ROUTE-MAPPING.md for the
// generated list of what is actually registered.
//
// Note: an earlier plan to re-tier these paths as /admin/v1, /ssc/v1 and /tenant/v1 was never
// implemented. The 440 "// NEW:" comments that described it have been removed: not one named a
// path this router serves, so anyone who trusted one got a 404, and the note explaining that lived
// only here while the false comments lived next to every route.
//
// The "// OLD:" comments that remain are pre-consolidation history -- the URL a route answered on
// when its service was deployed separately. Two cautions when reading them. They are not served
// here unless something registers them as an explicit alias, for which see
// policy.PolicyServiceRoutes and the aliases in RegisterAllRoutes. And some carry the abandoned
// tier prefix as well as the real path: internal/policy/routes.go has entries like
// "/admin/v1/api/v1/policyService/CreatePolicy", where only the "/api/v1/..." half was ever real.
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/authnull0/authnull-service/internal/mfapush"
	"github.com/authnull0/authnull-service/pkg/db"
	"github.com/authnull0/authnull-service/pkg/license"
	"github.com/authnull0/authnull-service/pkg/logger"
	"github.com/authnull0/authnull-service/pkg/middleware"

	// Service initialization (bootstrap, not route registration).
	"github.com/authnull0/authnull-service/internal/ad"
	"github.com/authnull0/authnull-service/internal/entra"
	orgservice "github.com/authnull0/authnull-service/internal/org/service"
	"github.com/authnull0/authnull-service/internal/pam/conf"
	// DID-REMOVAL: imported only for StartMerkleWorker (blockchain anchoring).
	// serviceaccounts.RegisterRoutes is still wired up in routes.go, which has
	// its own import.
	// "github.com/authnull0/authnull-service/internal/serviceaccounts"
)

func main() {
	logger.Init()

	// Load config/config.yaml and apply environment overrides before anything
	// reads Viper. Previously this ran only as a side effect of constructing a
	// pam handler during route registration, which meant every Viper key read by
	// the issuer, policy and serviceaccounts modules depended on pam route
	// registration happening first.
	conf.ReadInConfig()

	db.InitRedisInstance()
	ad.Init() // ad-service global DB connection
	if err := entra.Init(); err != nil {
		log.Printf("entra init failed (sync disabled): %v", err)
	} else {
		entra.StartScheduler() // entra periodic user sync
	}
	// DID-REMOVAL: blockchain Merkle-tree anchoring worker. Was already disabled
	// (hardcoded org 105; ethereum.go panics on empty DB name), now unreferenced.
	// serviceaccounts.StartMerkleWorker()
	// _ = serviceaccounts.StartMerkleWorker

	// Start org provisioning cron — auto-creates DB for new orgs every 5 minutes.
	go orgservice.StartProvisioningCronBackground()

	// Push-MFA activity maintenance: reap challenges nobody polled, purge past retention.
	// A no-op unless MFA_PUSH_SWEEP_ENABLED=true, which should be set on exactly ONE
	// replica — there is no leader election here, and both jobs write to every org
	// database.
	mfapush.StartSweeper(mfapush.AllOrgDatabases)

	// Report any column this service writes that the database does not have.
	//
	// Runs in the background: it opens a connection to every org database, which on a large
	// tenant count is the slowest thing in this function, and nothing about serving requests
	// depends on the answer. Non-fatal by design -- a missing column degrades one feature,
	// whereas refusing to boot takes down authentication for everything.
	go verifySchema()

	gin.DisableConsoleColor()
	r := gin.Default()

	// Without this gin trusts every proxy, which means c.ClientIP() returns the LEFTMOST
	// X-Forwarded-For entry — a value the client supplies. Anything that reasons about
	// where a request came from (risk scoring, the location in an MFA prompt, rate limits)
	// is then trivially spoofable, which is worse than not having it at all.
	//
	// Unset means "trust nothing": ClientIP() falls back to the socket peer, correct for a
	// direct connection and conservative behind a proxy. Set TRUSTED_PROXIES to the
	// comma-separated CIDRs of your ingress to get the real client address.
	if tp := strings.TrimSpace(os.Getenv("TRUSTED_PROXIES")); tp != "" {
		var proxies []string
		for _, p := range strings.Split(tp, ",") {
			if p = strings.TrimSpace(p); p != "" {
				proxies = append(proxies, p)
			}
		}
		if err := r.SetTrustedProxies(proxies); err != nil {
			log.Printf("main: TRUSTED_PROXIES is invalid (%v); trusting none", err)
			_ = r.SetTrustedProxies(nil)
		}
	} else {
		_ = r.SetTrustedProxies(nil)
	}
	r.Use(middleware.CORS())

	// Health endpoints
	r.GET("/system/v1/health", health)
	r.GET("/system/v1/health/readiness", health)
	r.GET("/system/v1/health/liveness", health)

	// Licence: built before routes so the gate can read it, and applied as ONE global middleware.
	//
	// Global is safe here specifically because Gate consults license.IsGated(c.FullPath()) first and
	// falls straight through for anything not on the control-plane list. That is deliberately the
	// opposite of attaching it to route groups: a group-level Use() would gate whatever later shares
	// the prefix, and on this service that could be a sensor endpoint.
	initLicense()
	r.Use(license.Gate(licenseStatus))

	RegisterAllRoutes(r)

	startServer(r)
}

// health reports liveness, and surfaces schema drift alongside it.
//
// Still 200 when the schema is short of a column, deliberately: the process IS serving, and
// returning 503 here would take the container out of rotation over a degraded feature. The
// drift is reported in the body so it is visible to anyone who looks, rather than living only
// in a startup log line that scrolls away.
func health(c *gin.Context) {
	body := gin.H{"status": "ok"}
	if problems := schemaProblems(); len(problems) > 0 {
		reported := make([]string, 0, len(problems))
		for _, p := range problems {
			reported = append(reported, p.String())
		}
		body["schema"] = gin.H{"ok": false, "problems": reported}
	} else {
		body["schema"] = gin.H{"ok": true}
	}

	// Licence state, reported alongside schema for the same reason: an operator debugging "why can I
	// not save a policy" should find the answer here rather than in a scrolled-away log line.
	//
	// Still 200 when unlicensed. The process IS serving and enforcement IS running; a 503 would pull
	// the container out of rotation over a billing state, which is precisely the outage this design
	// avoids.
	st := licenseStatus()
	lic := gin.H{"state": st.State, "licensed": st.Licensed}
	if st.Reason != "" {
		lic["reason"] = st.Reason
	}
	if st.ExpiresAt != nil {
		lic["expiresAt"] = st.ExpiresAt.UTC()
		lic["daysRemaining"] = st.DaysRemaining
	}
	if st.Customer != "" {
		lic["customer"] = st.Customer
	}
	body["license"] = lic

	c.JSON(http.StatusOK, body)
}

func startServer(r *gin.Engine) {
	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = "8080"
	}
	srv := &http.Server{Addr: ":" + port, Handler: r}

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("Listen: %s\n", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Server forced to shutdown: %s\n", err)
	}
	log.Println("Server exiting")
}
