package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

// The property this whole file exists for: AN UNSET KEY NEVER MATCHES.
//
// INTERNAL_API_KEY ships EMPTY in .env and .env.prod, so "unset" is the state most deployments are
// in until an operator fills it in. If an empty configured key compared equal to an empty (or
// absent, or arbitrary) header, then every route mounted with InternalKeyOrAuthnz would be open to
// anyone the moment nginx proxied it -- which for RegisterInternalServiceRoutes means an anonymous
// policy read and an anonymous audit write, reachable from the internet.
//
// That is the failure mode of "operator has not configured this yet" silently meaning "this is
// public". It is one `if` away in either direction, so it is pinned here.
func TestUnsetInternalKeyNeverMatches(t *testing.T) {
	for _, env := range []string{"", "   "} {
		for _, header := range []string{"", "   ", "anything", "null", "0"} {
			t.Setenv("INTERNAL_API_KEY", env)

			c, _ := gin.CreateTestContext(httptest.NewRecorder())
			c.Request = httptest.NewRequest(http.MethodPost, "/", nil)
			if header != "" {
				c.Request.Header.Set(InternalAPIKeyHeader, header)
			}

			if internalKeyMatches(c) {
				t.Errorf("INTERNAL_API_KEY=%q with header %q MATCHED — an unconfigured deployment "+
					"would expose every InternalKeyOrAuthnz route to anyone", env, header)
			}
		}
	}
}

// A configured key must match itself and nothing else.
//
// The near-misses are the point: a prefix or suffix comparison, or a case-insensitive one, would
// each pass some of these. TrimSpace on both sides IS intended, so an operator who pastes a key
// with a trailing newline into an env file gets a working deployment rather than a mystery 401.
func TestInternalKeyMatchesOnlyExactValue(t *testing.T) {
	const key = "s3cret-service-key"

	cases := []struct {
		name   string
		header string
		want   bool
	}{
		{"exact", key, true},
		{"padded is trimmed on both sides", "  " + key + "  ", true},
		{"absent", "", false},
		{"whitespace only", "   ", false},
		{"wrong value", "not-the-key", false},
		{"prefix of the key", key[:8], false},
		{"key plus suffix", key + "x", false},
		{"prefix plus key", "x" + key, false},
		{"different case", "S3CRET-SERVICE-KEY", false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("INTERNAL_API_KEY", key)

			c, _ := gin.CreateTestContext(httptest.NewRecorder())
			c.Request = httptest.NewRequest(http.MethodPost, "/", nil)
			if tc.header != "" {
				c.Request.Header.Set(InternalAPIKeyHeader, tc.header)
			}

			if got := internalKeyMatches(c); got != tc.want {
				t.Errorf("internalKeyMatches with header %q = %v, want %v", tc.header, got, tc.want)
			}
		})
	}
}

// End to end through the middleware: a matching key is admitted, and everything else is handed to
// the session check rather than waved through.
//
// Delegation is detected without any network: AuthnzCall answers 401 on a missing X-Authorization
// before it would ever call authnz. AUTH_DISABLED is pinned empty because AuthnzCall reads it at
// CONSTRUCTION time and returns a pass-everything handler when it is "true" -- with it set, every
// case below would return 200 and the test would prove nothing.
func TestInternalKeyOrAuthnzAdmitsOnlyTheKey(t *testing.T) {
	gin.SetMode(gin.TestMode)

	cases := []struct {
		name     string
		envKey   string
		header   string
		wantCode int
	}{
		{"matching key is admitted", "the-key", "the-key", http.StatusOK},
		{"wrong key falls through to the session check", "the-key", "wrong", http.StatusUnauthorized},
		{"no header falls through to the session check", "the-key", "", http.StatusUnauthorized},
		{"unset key is not a bypass", "", "the-key", http.StatusUnauthorized},
		{"unset key and no header is not a bypass", "", "", http.StatusUnauthorized},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("AUTH_DISABLED", "")
			t.Setenv("AUTHNZ_URL", "")
			t.Setenv("INTERNAL_API_KEY", tc.envKey)

			// Built INSIDE the subtest: AuthnzCall captures AUTH_DISABLED when the handler is
			// constructed, not when it runs.
			r := gin.New()
			g := r.Group("", InternalKeyOrAuthnz())
			g.POST("/guarded", func(c *gin.Context) { c.Status(http.StatusOK) })

			req := httptest.NewRequest(http.MethodPost, "/guarded", nil)
			if tc.header != "" {
				req.Header.Set(InternalAPIKeyHeader, tc.header)
			}
			w := httptest.NewRecorder()
			r.ServeHTTP(w, req)

			if w.Code != tc.wantCode {
				t.Errorf("got %d, want %d", w.Code, tc.wantCode)
			}
		})
	}
}
