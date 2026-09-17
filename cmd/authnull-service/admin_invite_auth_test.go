package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

// adminInvite mints an enrollment token for SOMEBODY ELSE, which makes it the one endpoint where a
// missing authorization check hands an attacker a credential rather than merely information. These
// assert the routing and the fail-closed default; the role check itself needs a live session and is
// covered by the handler's own guards.
func TestAdminInviteRequiresASession(t *testing.T) {
	gin.SetMode(gin.TestMode)
	t.Setenv("AUTH_DISABLED", "")
	t.Setenv("AUTHNZ_URL", "http://authnz.invalid")

	r := gin.New()
	RegisterAllRoutes(r)

	// No session at all.
	req := httptest.NewRequest(http.MethodPost, "/api/v1/mfa/push/adminInvite",
		strings.NewReader(`{"email":"victim@corp.com"}`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code == http.StatusOK {
		t.Fatal("adminInvite returned 200 with no session — it mints an enrollment credential")
	}
	if w.Code != http.StatusUnauthorized {
		t.Errorf("want 401, got %d: %s", w.Code, w.Body.String())
	}
}

// It must NOT be reachable on the unauthenticated phone-facing alias. The device routes and the
// /authentication/* aliases exist precisely because the app holds no session — an invite minter
// there would be open to anyone who can reach the host.
func TestAdminInviteIsNotOnAnUnauthenticatedAlias(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	registered := map[string]bool{}
	for _, ri := range r.Routes() {
		registered[ri.Method+" "+ri.Path] = true
	}
	// The bare SSC alias carries no middleware at all.
	for _, forbidden := range []string{
		"POST /authentication/push/adminInvite",
		"POST /api/v1/device/adminInvite",
		"POST /ad/adminInvite",
	} {
		if registered[forbidden] {
			t.Errorf("adminInvite must not be registered at %s — that path has no session behind it", forbidden)
		}
	}
	// And it must exist where it belongs.
	if !registered["POST /api/v1/mfa/push/adminInvite"] {
		t.Error("adminInvite is not registered on the authenticated group")
	}
}
