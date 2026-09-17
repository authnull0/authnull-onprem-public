package pwreset

import "testing"

// The two consoles send different shapes for the same tenant: the SSC a bare domain,
// did-react the full page URL it is on. Both must reduce to the same host, because that
// value is echoed to the reset page and used to seed the console's domain.
func TestHostNormalisesBothConsoleShapes(t *testing.T) {
	const want = "default.alpha.dev.authnull.com"
	for _, in := range []string{
		"default.alpha.dev.authnull.com",
		"https://default.alpha.dev.authnull.com",
		"https://default.alpha.dev.authnull.com/tenant/forgot-password",
		"default.alpha.dev.authnull.com/tenant/forgot-password",
		"http://default.alpha.dev.authnull.com/tenant/login?x=1",
		"  https://default.alpha.dev.authnull.com/#frag  ",
	} {
		if got := Host(in); got != want {
			t.Errorf("Host(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestHostPreservesPort(t *testing.T) {
	if got := Host("https://box.local:8443/x"); got != "box.local:8443" {
		t.Errorf("Host() = %q, want box.local:8443", got)
	}
}

func TestOrgLabel(t *testing.T) {
	cases := map[string]struct {
		want string
		ok   bool
	}{
		"default.alpha.dev.authnull.com":                        {"alpha", true},
		"https://default.beta.dev.authnull.com/tenant/login":    {"beta", true},
		"default.alpha":                                         {"alpha", true},
		// Fewer than two labels: previously a panic via Split(...)[1], now a clean false
		// so the handler can answer 400 instead of 500.
		"localhost": {"", false},
		"":          {"", false},
		".":         {"", false},
	}
	for in, exp := range cases {
		got, ok := OrgLabel(in)
		if got != exp.want || ok != exp.ok {
			t.Errorf("OrgLabel(%q) = (%q, %v), want (%q, %v)", in, got, ok, exp.want, exp.ok)
		}
	}
}
