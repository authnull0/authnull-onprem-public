package main

import (
	"testing"

	"github.com/gin-gonic/gin"
)

// TestRegisterAllRoutes builds the full engine and asserts the endpoints ported
// back during the consolidation review are actually registered, and that adding
// them introduced no duplicate method+path (gin panics on a duplicate, so a
// clean run is itself the collision check).
func TestRegisterAllRoutes(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()

	RegisterAllRoutes(r)

	got := make(map[string]bool)
	for _, ri := range r.Routes() {
		got[ri.Method+" "+ri.Path] = true
	}

	want := []string{
		// pam network_device (RADIUS registry) — restored
		"POST /api/v1/pam/network_device/CreateDevice",
		"POST /api/v1/pam/network_device/ListDevices",
		"POST /api/v1/pam/network_device/DeleteDevice",
		// the UI calls these via REACT_APP_PAM_API = <host>/pam/api/v1
		"POST /pam/api/v1/network_device/ListDevices",
		"POST /pam/api/v1/network_device/DeleteDevice",

		// policy handlers — restored, canonical paths
		"POST /api/v1/policy/addEndpoint",
		"POST /api/v1/policy/listLinuxCommands",
		"POST /api/v1/policy/storeSudoers",
		"POST /api/v1/policy/changeStatus",
		// policyService aliases the admin UI actually calls
		"POST /api/v1/policyService/listLinuxCommands",
		"POST /api/v1/policyService/changeStatus",
		"POST /api/v1/policyService/addEndpoint",
		"POST /api/v1/policyService/storeSudoers",

		// AD Shield DC sensor. These five paths are hardcoded in the sensor
		// (AuthnullBackendClient.cs / AdSyncService.cs) and it ships from a different repo,
		// so the server cannot rename them. gin is case-sensitive: the PascalCase spelling
		// is what must be registered, not the camelCase canonical route.
		"POST /api/v1/policyService/EvaluateAuth",
		"POST /ad/InitiateMFAChallenge",
		"POST /ad/GetMFAChallenge",
		"POST /ad/UserSync",
		"POST /ad/UpdateDomainStatus",

		// Admin UI: change monitor/enforce + fallback after registration. Without this the
		// only way to move a domain to enforce is a manual SQL UPDATE.
		"POST /ad/updateDomainEnforcement",

		// Users screen: MFA coverage evaluated with the enforcement-path matcher.
		"POST /api/v1/policy/ad/mfaCoverage",

		// AuthNull Authenticator (phone). These MUST be on the bare /authentication alias,
		// which carries no AuthnzMiddleware -- the app redeems its enrollment invite and
		// answers challenges before any session exists, so the /api/v1/mfa spelling can only
		// return 401 to it. confirmSetup in particular was missing here, which left the app
		// able to answer challenges it could never enroll to receive.
		// AuthNull Authenticator self-service. Signature-authenticated, mounted once.
		"POST /api/v1/device/accounts/list",
		"POST /api/v1/device/accounts/update",
		"POST /api/v1/device/accounts/remove",
		"POST /api/v1/device/pushToken/refresh",
		"POST /api/v1/device/rename",
		"POST /api/v1/device/push",
		"POST /api/v1/device/unenroll",
		"POST /api/v1/device/key/biometric",

		"POST /authentication/push/confirmSetup",
		"POST /authentication/push/getChallenge",
		"POST /api/v1/mfa/push/selfEnroll",
		"POST /api/v1/mfa/push/adminInvite",
		"POST /api/v1/device/activity",
		"POST /api/v1/ad/GetEnrollmentSummary",
		"POST /authentication/push/respond",
		"POST /authentication/push/challenge",
		"POST /authentication/push/status",
	}

	for _, w := range want {
		if !got[w] {
			t.Errorf("route not registered: %s", w)
		}
	}

	if len(r.Routes()) == 0 {
		t.Fatal("no routes registered")
	}
	t.Logf("total routes registered: %d", len(r.Routes()))
}
