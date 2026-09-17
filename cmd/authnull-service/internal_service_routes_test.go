package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

// These assert the Phase 1 wiring against the REAL router, without a database or a container.
//
// That is possible because routing and middleware both resolve before any handler runs: a 404 is
// decided by the route table, and a 401 by InternalKeyOrAuthnz aborting. So the two things most
// likely to be wrong -- is the path the one authn-service is pointed at, and is it protected -- are
// exactly the two things testable in-process.
//
// Handlers are never executed here. Every positive case is asserted through the route table rather
// than by issuing a request, because RegisterAllRoutes is built on gin.New() with no Recovery
// middleware and the handlers reach for a database that does not exist in a unit test. That the key
// ADMITS a caller is covered in pkg/middleware, against a stub handler.

// routePaths returns the set of registered POST paths.
func routePaths(t *testing.T) map[string]bool {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	out := map[string]bool{}
	for _, ri := range r.Routes() {
		if ri.Method == http.MethodPost {
			out[ri.Path] = true
		}
	}
	return out
}

// The two paths authn-service is configured to call must exist, at exactly these spellings.
//
// docker-compose.yml points TENANT_POLICY and TENANT_AUDIT here. A typo or a rename on either side
// is a 404 that authn-service reports as a failed policy lookup -- and under the no-policy-is-allow
// rule, a failed lookup that is mistaken for "no policy" would let logins through unchallenged. So
// the compose values and these routes are one contract, asserted here.
func TestRoutesAuthnServiceIsPointedAtExist(t *testing.T) {
	paths := routePaths(t)

	for _, p := range []string{
		"/api/v1/policy/json/searchPolicy", // TENANT_POLICY
		"/api/v1/policy/logAccessRequest",  // TENANT_AUDIT
	} {
		if !paths[p] {
			t.Errorf("%s is NOT registered — authn-service is pointed at it in docker-compose.yml "+
				"and would get a 404", p)
		}
	}
}

// The path authn-service used to hardcode must stay absent.
//
// CallSearchPolicyJSONAPI addressed http://onprem.prod.authnull.com/api/v1/policyService/
// searchPolicyJSON -- an Authnull-owned host over plain HTTP, on a path that exists in neither
// service. It was a data-egress bug AND a 404. If this path ever starts answering, someone has
// "fixed" the 404 by adding the route instead of fixing the caller, and the egress is back.
func TestSearchPolicyJSONPathStaysAbsent(t *testing.T) {
	if routePaths(t)["/api/v1/policyService/searchPolicyJSON"] {
		t.Error("/api/v1/policyService/searchPolicyJSON is registered. It never existed, and " +
			"authn-service's hardcoded call to it was removed rather than accommodated — " +
			"adding the route re-legitimises the wrong URL.")
	}
}

// The internal pair must REFUSE a request with no key.
//
// This is the check the whole InternalKeyOrAuthnz middleware exists for. nginx/authnull.conf
// proxies all of /api/ to this service, so if these two ever mount unauthenticated they become an
// anonymous policy read and an anonymous audit write reachable from the internet. The plan's first
// draft proposed exactly that, on the grounds that the unattended agents are already
// unauthenticated -- the difference being that the DC sensor and the RADIUS binary have no
// credential to present, while authn-service is a container on the same compose network.
func TestInternalServiceRoutesRefuseAnAnonymousCaller(t *testing.T) {
	// Set BEFORE RegisterAllRoutes: AuthnzCall reads AUTH_DISABLED when the handler is
	// constructed, and returns a pass-everything handler if it is "true" -- which would make every
	// assertion below pass while proving nothing.
	t.Setenv("AUTH_DISABLED", "")
	t.Setenv("AUTHNZ_URL", "")
	t.Setenv("INTERNAL_API_KEY", "correct-horse-battery-staple")

	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	for _, path := range []string{
		"/api/v1/policy/json/searchPolicy",
		"/api/v1/policy/logAccessRequest",
	} {
		for _, tc := range []struct{ name, key string }{
			{"no key at all", ""},
			{"wrong key", "not-the-key"},
		} {
			t.Run(path+" / "+tc.name, func(t *testing.T) {
				req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(`{"orgId":1,"tenantId":1}`))
				req.Header.Set("Content-Type", "application/json")
				if tc.key != "" {
					req.Header.Set("X-Internal-Api-Key", tc.key)
				}
				w := httptest.NewRecorder()
				r.ServeHTTP(w, req)

				if w.Code != http.StatusUnauthorized {
					t.Errorf("got %d, want 401 — this endpoint is reachable without a valid key, "+
						"and nginx proxies /api/ publicly", w.Code)
				}
			})
		}
	}
}

// The legacy policyService alias must NOT accept the service key.
//
// /policyService/SearchPolicy reads did.auth_policies, while policies are authored into
// did.auth_policy_json. Pointed there, authn-service would get a well-formed EMPTY list rather than
// an error -- which reads as "no policy covers this user" and, under no-policy-is-allow, lets every
// login through unchallenged. It stays on plain session auth so it cannot quietly become the
// service's policy source.
func TestLegacySearchPolicyDoesNotAcceptTheServiceKey(t *testing.T) {
	t.Setenv("AUTH_DISABLED", "")
	t.Setenv("AUTHNZ_URL", "")
	t.Setenv("INTERNAL_API_KEY", "correct-horse-battery-staple")

	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/policyService/SearchPolicy",
		strings.NewReader(`{"orgId":1,"tenantId":1}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Api-Key", "correct-horse-battery-staple")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401: the legacy SearchPolicy accepted a service key. It reads the "+
			"wrong table, so a service reaching it gets an empty list instead of an error.", w.Code)
	}
}
