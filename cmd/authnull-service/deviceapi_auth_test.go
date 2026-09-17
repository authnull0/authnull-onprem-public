package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/authnull0/authnull-service/internal/deviceapi"
)

// The device self-service API can repoint where a push is delivered and unenroll a
// device. It carries no session middleware — deliberately, since the phone holds none —
// so the request signature is the only thing standing between it and anyone who can
// reach the port.
//
// These tests assert the lockdown at the routing layer, where a mistake is silent: a
// missing middleware, a route registered on the wrong group, or a stray public alias all
// look fine until someone tries them.
var deviceRoutes = []string{
	"/api/v1/device/accounts/list",
	"/api/v1/device/accounts/update",
	"/api/v1/device/accounts/remove",
	"/api/v1/device/pushToken/refresh",
	"/api/v1/device/rename",
	"/api/v1/device/push",
	"/api/v1/device/unenroll",
	"/api/v1/device/key/biometric",
}

// No route may be reachable without a signature. Any 2xx here means unauthenticated
// device management.
func TestDeviceAPIRejectsUnsignedRequests(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	for _, path := range deviceRoutes {
		req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(`{}`))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)

		if w.Code == http.StatusNotFound {
			t.Errorf("%s is not registered", path)
			continue
		}
		if w.Code >= 200 && w.Code < 300 {
			t.Errorf("%s answered %d WITHOUT a signature — this endpoint can repoint pushes "+
				"and unenroll devices", path, w.Code)
		}
		if w.Code != http.StatusUnauthorized {
			t.Errorf("%s = %d, want 401 for an unsigned request", path, w.Code)
		}
	}
}

// Partial or malformed signature headers must be rejected too, and must fail
// identically. A middleware that distinguishes "unknown key" from "bad signature" from
// "unknown org" is an oracle for enumerating devices and organisations.
//
// Worth being precise about what this proves. There is no Redis in the test process, and
// the nonce is claimed before any database work, so every attempt here is rejected at
// that first gate. So this asserts two things: the response shape is uniform, AND the API
// fails CLOSED when Redis is unavailable — which is the intended behaviour, because a
// per-replica in-memory nonce set is not a nonce set at all. It does not exercise the
// later stages; those are covered by the unit tests on VerifyRequest.
func TestDeviceAPIFailuresAreIndistinguishable(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	attempts := []struct {
		name    string
		headers map[string]string
	}{
		{"no headers at all", nil},
		{"org only", map[string]string{deviceapi.HeaderOrg: "2"}},
		{"org + key, no signature", map[string]string{
			deviceapi.HeaderOrg: "2", deviceapi.HeaderKey: strings.Repeat("a", 64),
		}},
		{"unknown key id", map[string]string{
			deviceapi.HeaderOrg:       "2",
			deviceapi.HeaderKey:       strings.Repeat("b", 64),
			deviceapi.HeaderNonce:     "0123456789abcdef0123",
			deviceapi.HeaderTimestamp: "1770000000",
			deviceapi.HeaderSignature: "bm90LWEtc2lnbmF0dXJl",
		}},
		{"garbage org", map[string]string{
			deviceapi.HeaderOrg:       "not-a-number",
			deviceapi.HeaderKey:       strings.Repeat("c", 64),
			deviceapi.HeaderNonce:     "0123456789abcdef0123",
			deviceapi.HeaderTimestamp: "1770000000",
			deviceapi.HeaderSignature: "bm90LWEtc2lnbmF0dXJl",
		}},
		{"unsupported algorithm", map[string]string{
			deviceapi.HeaderAlg: "rsa-2048", deviceapi.HeaderOrg: "2",
		}},
	}

	var bodies []string
	for _, a := range attempts {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/device/unenroll", strings.NewReader(`{}`))
		req.Header.Set("Content-Type", "application/json")
		for k, v := range a.headers {
			req.Header.Set(k, v)
		}
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)

		if w.Code != http.StatusUnauthorized {
			t.Errorf("%s: got %d, want 401", a.name, w.Code)
		}
		bodies = append(bodies, w.Body.String())
	}
	for i, b := range bodies {
		if b != bodies[0] {
			t.Errorf("%s produced a distinguishable failure body %q (first was %q) — "+
				"differing responses let a caller enumerate devices and orgs",
				attempts[i].name, b, bodies[0])
		}
	}
}

// The device signs the gin route pattern, so each handler must be reachable at exactly
// one pattern. internal/ad and internal/mfa are each mounted twice; if deviceapi ever is,
// a signature valid at one path silently fails at the other.
func TestDeviceAPIIsMountedExactlyOnce(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	seen := map[string]int{}
	for _, ri := range r.Routes() {
		if strings.Contains(ri.Path, "/device/") {
			seen[ri.Method+" "+ri.Path]++
		}
	}
	for route, n := range seen {
		if n > 1 {
			t.Errorf("%s registered %d times", route, n)
		}
	}
	// Guard against a second mount appearing at root or under another prefix, which
	// would not collide with the first and so would not panic.
	for _, ri := range r.Routes() {
		if strings.HasSuffix(ri.Path, "/device/unenroll") && ri.Path != "/api/v1/device/unenroll" {
			t.Errorf("device API mounted at an unexpected second prefix: %s", ri.Path)
		}
	}
}
