package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

// Endpoints that MINT something must not be reachable without authentication.
//
// listConnections shipped outside its file's authenticated group and was verified reachable
// from the internet on the live deployment: a POST with a malformed body returned 400 from the
// JSON binder — meaning the handler ran — while listDatabase in the same group returned 401.
// It parks an MFAState{UserId} in Redis that ProxySQL later resolves to authorise a database
// login, so unauthenticated it was a credential-minting oracle for any named user.
//
// This asserts the routing, which is where the defect was. It is deliberately blunt: an
// unauthenticated request must not reach the handler, and "reaching the handler" is observable
// because the body is invalid, so a handler that runs answers 400 while the middleware answers
// 401.
func TestCredentialMintingEndpointsRequireAuth(t *testing.T) {
	gin.SetMode(gin.TestMode)

	// AUTH_DISABLED short-circuits AuthnzCall entirely, which is legitimate for local
	// development but would make this test vacuous.
	t.Setenv("AUTH_DISABLED", "")
	t.Setenv("AUTHNZ_URL", "http://authnz.invalid")

	r := gin.New()
	RegisterAllRoutes(r)

	// Both mounts. The endpoint is registered twice, and fixing only one leaves the hole open
	// at the other path — which is exactly how it would regress.
	paths := []string{
		"/api/v1/databaseService/listConnections",
		"/api/v1/database/listConnections",
	}
	for _, p := range paths {
		// A malformed body, so a handler that runs is distinguishable from middleware.
		req := httptest.NewRequest(http.MethodPost, p, strings.NewReader("{"))
		req.Header.Set("Content-Type", "application/json")
		// The header the handler used to trust. It must not be a substitute for a session.
		req.Header.Set("userId", "1")
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)

		if w.Code == http.StatusBadRequest {
			t.Errorf("%s returned 400: the handler RAN without authentication. This endpoint "+
				"mints a database credential and must sit behind AuthnzCall.", p)
			continue
		}
		if w.Code != http.StatusUnauthorized {
			t.Errorf("%s returned %d, want 401", p, w.Code)
		}
	}
}

// The authenticated sibling in the same file must keep behaving the same way, so the test above
// is measuring authentication rather than a route that stopped existing.
func TestListDatabaseStillRequiresAuth(t *testing.T) {
	gin.SetMode(gin.TestMode)
	t.Setenv("AUTH_DISABLED", "")
	t.Setenv("AUTHNZ_URL", "http://authnz.invalid")

	r := gin.New()
	RegisterAllRoutes(r)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/databaseService/listDatabase",
		strings.NewReader("{"))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("listDatabase returned %d, want 401 — the control for the test above", w.Code)
	}
}
