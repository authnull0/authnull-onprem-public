package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

// The AuthNull Authenticator redeems its enrollment invite before any session exists, so
// /push/confirmSetup has to be reachable without one. It previously lived only on the
// /api/v1/mfa group, which applies AuthnzMiddleware — the app got a 401 and platform enrollment
// was impossible, while it could still answer challenges it had no way to enroll for.
//
// A status code is the whole test here: 401 means the request is still being intercepted before
// the handler, 404 means the route is gone. Anything else means the handler ran, which is what
// "reachable" means. The payload deliberately carries an invalid push token so validatePushToken
// rejects it before any database access — this stays honest with no DB in the test process.
func TestAuthenticatorEnrollmentIsReachableWithoutSession(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	const path = "/authentication/push/confirmSetup"
	body := `{"email":"a@b.com","tenantId":1,"orgId":2,"userId":3,
	          "enrollmentToken":"bogus","pushToken":"!","pushTransport":"fcm",
	          "platform":"android","deviceName":"test"}`

	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	// No Authorization header and no session cookie — exactly what the phone sends.
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	switch w.Code {
	case http.StatusNotFound:
		t.Fatalf("%s is not registered — the app cannot complete platform enrollment", path)
	case http.StatusUnauthorized, http.StatusForbidden:
		t.Fatalf("%s still requires a session (%d) — it is on the authenticated group, so the "+
			"phone can only ever get a 401", path, w.Code)
	}
}

// The browser console initiates enrollment and does have a session, so beginSetup must NOT be
// opened up alongside confirmSetup. Exposing it would let anyone mint an enrollment invite for an
// arbitrary user, which is the one thing the enrollment token is protecting.
func TestBeginSetupStaysAuthenticated(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	for _, ri := range r.Routes() {
		if ri.Method == http.MethodPost && ri.Path == "/authentication/push/beginSetup" {
			t.Fatal("push/beginSetup must not be exposed on the unauthenticated alias — it is " +
				"browser-initiated, and opening it would allow minting invites for any user")
		}
	}
}
