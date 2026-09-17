package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

// The AD Shield DC sensor posts this exact body to /api/v1/policyService/EvaluateAuth.
// Copied from AuthnullBackendClient.PolicyCheckAsync — field names must match
// dto.EvaluateAuthRequest's json tags or gin binds them to zero values and the handler
// answers 400 "org_id and tenant_id are required" for every authentication.
const sensorEvaluateAuthBody = `{
  "org_id": 2,
  "tenant_id": 1,
  "ad_user": "jdoe",
  "domain": "ad.acx",
  "protocol": "kerberos",
  "source_ip": "10.0.0.5",
  "destination": "cifs/fs01.ad.acx",
  "session_id": "DC01-4624-20260804120000",
  "suppress_mfa": true
}`

const sensorEvaluateAuthPath = "/api/v1/policyService/EvaluateAuth"

// Asserts the sensor's policy call gets past routing, middleware and JSON binding.
//
// Three failure modes this pins down, all of which the sensor reports identically (as an API
// failure that trips its circuit breaker after cb_threshold consecutive hits, after which
// every authentication falls through to fallback_action):
//
//   - 404: gin is case-sensitive and the canonical route is /api/v1/policy/auth/evaluateAuth,
//     so the sensor's PascalCase spelling needs its own registration.
//   - 401: the sensor presents no credential at all, so the route must not inherit
//     AuthnzMiddleware. The canonical route DOES inherit it, which is why aliasing into the
//     existing /policyService group would not have been enough either.
//   - 400: a field-name mismatch between the sensor's payload and dto.EvaluateAuthRequest.
//
// The blank ad_user is what keeps this database-free: it trips the handler's own validation
// before authDecisionService.EvaluateAuth is called, so reaching that specific message proves
// the whole chain up to the handler body without needing a live DB. org_id and tenant_id are
// left populated on purpose — if the json tags did not match, the handler would reject on
// those first, which is exactly what a binding mismatch looks like.
func TestSensorEvaluateAuthReachesHandlerWithoutAuth(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	body := strings.Replace(sensorEvaluateAuthBody, `"ad_user": "jdoe"`, `"ad_user": ""`, 1)

	req := httptest.NewRequest(http.MethodPost, sensorEvaluateAuthPath, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	// Deliberately no Authorization header — the sensor has none to send.
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	switch w.Code {
	case http.StatusNotFound:
		t.Fatalf("%s is not registered (404) — the sensor's policy calls go nowhere",
			sensorEvaluateAuthPath)
	case http.StatusUnauthorized, http.StatusForbidden:
		t.Fatalf("%s requires auth (%d) — the sensor sends no credential, so every policy "+
			"check fails and its circuit breaker opens", sensorEvaluateAuthPath, w.Code)
	}

	if w.Code != http.StatusBadRequest {
		t.Fatalf("want 400 from the handler's own validation, got %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "ad_user") {
		t.Errorf("want the ad_user validation error, got: %s", w.Body.String())
	}
	if strings.Contains(w.Body.String(), "org_id") {
		t.Errorf("org_id/tenant_id did not bind from the sensor's payload — json tag mismatch: %s",
			w.Body.String())
	}
}

// Complements the test above by sending the sensor's payload COMPLETE, so execution carries on
// past the handler into AuthDecisionService.EvaluateAuth.
//
// There is no database in this process, so resolveTenantDB dereferences a nil *gorm.DB and
// panics. That panic is the assertion: it can only be reached from inside the service, which
// means the route matched, no middleware rejected the unauthenticated request, and every field
// bound. A 404 or 401 would return cleanly instead and fail this test.
//
// gin.New() is used without gin.Recovery(), so the panic surfaces here rather than becoming a
// 500 — recovering it deliberately keeps the suite green while still proving reachability.
func TestSensorEvaluateAuthPayloadReachesPolicyService(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	req := httptest.NewRequest(http.MethodPost, sensorEvaluateAuthPath, strings.NewReader(sensorEvaluateAuthBody))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	reachedService := func() (reached bool) {
		defer func() {
			// A panic here originates below the handler (nil DB in the service layer).
			reached = recover() != nil
		}()
		r.ServeHTTP(w, req)
		return false
	}()

	if reachedService {
		return // handler ran and called into the policy service — what we wanted to prove
	}

	// No panic: the request was answered without reaching the DB. Only a rejection explains
	// that here, since the payload is complete and passes the handler's validation.
	switch w.Code {
	case http.StatusNotFound:
		t.Fatalf("%s is not registered (404)", sensorEvaluateAuthPath)
	case http.StatusUnauthorized, http.StatusForbidden:
		t.Fatalf("%s rejected the unauthenticated sensor request (%d)", sensorEvaluateAuthPath, w.Code)
	case http.StatusBadRequest:
		t.Fatalf("%s rejected the sensor's payload (400): %s\nfield names must match "+
			"dto.EvaluateAuthRequest json tags", sensorEvaluateAuthPath, w.Body.String())
	default:
		// A real DB-backed environment lands here with 200/500 — both mean the handler ran.
		t.Logf("handler ran and returned %d without panicking (a database is reachable)", w.Code)
	}
}
