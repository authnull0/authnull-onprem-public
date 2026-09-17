package appurl

import "testing"

func TestClientResolutionOrder(t *testing.T) {
	cases := []struct {
		name      string
		clientURL string
		systemURL string
		want      string
	}{
		{"CLIENT_URL wins", "https://onprem.dev.authnull.com", "https://other.example.com", "https://onprem.dev.authnull.com"},
		{"falls back to SYSTEM_URL", "", "https://onprem.dev.authnull.com", "https://onprem.dev.authnull.com"},
		{"trailing slash trimmed", "https://onprem.dev.authnull.com/", "", "https://onprem.dev.authnull.com"},
		{"whitespace ignored", "   ", "https://sys.example.com", "https://sys.example.com"},
		{"neither set keeps legacy default", "", "", LegacyAppHost},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv("CLIENT_URL", c.clientURL)
			t.Setenv("SYSTEM_URL", c.systemURL)
			if got := Client(); got != c.want {
				t.Errorf("Client() = %q, want %q", got, c.want)
			}
		})
	}
}

func TestTenantSiteURL(t *testing.T) {
	cases := []struct {
		name string
		base string
		want string
	}{
		// The case that broke this deployment: infra serves .dev., provisioning
		// wrote .prod., so tenant login could never match.
		{"configured base domain", "dev.authnull.com", "default.beta.dev.authnull.com"},
		{"leading/trailing dots tolerated", ".dev.authnull.com.", "default.beta.dev.authnull.com"},
		{"whitespace ignored", "  dev.authnull.com  ", "default.beta.dev.authnull.com"},
		// Unset must reproduce the old hardcoded hostname byte for byte so the
		// existing SaaS deployment is unaffected. Note ENV is deliberately NOT
		// consulted -- it is "production" here, which was the third spelling.
		{"unset keeps the legacy hostname", "", "default.beta.prod.authnull.com"},
		{"blank keeps the legacy hostname", "   ", "default.beta.prod.authnull.com"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv("TENANT_BASE_DOMAIN", c.base)
			t.Setenv("ENV", "production")
			if got := TenantSiteURL("beta"); got != c.want {
				t.Errorf("TenantSiteURL(\"beta\") = %q, want %q", got, c.want)
			}
		})
	}
}

func TestRewrite(t *testing.T) {
	const tmpl = `<a href="https://app.authnull.com/org/login">login</a> ` +
		`and <a href="https://app.authnull.com/tenant/forgot-password">reset</a>`

	t.Run("replaces every occurrence", func(t *testing.T) {
		t.Setenv("CLIENT_URL", "https://onprem.dev.authnull.com")
		t.Setenv("SYSTEM_URL", "")
		got := Rewrite(tmpl)
		if want := `<a href="https://onprem.dev.authnull.com/org/login">login</a> ` +
			`and <a href="https://onprem.dev.authnull.com/tenant/forgot-password">reset</a>`; got != want {
			t.Errorf("got  %q\nwant %q", got, want)
		}
	})

	t.Run("unset config leaves the template untouched", func(t *testing.T) {
		t.Setenv("CLIENT_URL", "")
		t.Setenv("SYSTEM_URL", "")
		if got := Rewrite(tmpl); got != tmpl {
			t.Errorf("expected no change, got %q", got)
		}
	})

	// A '%' in the URL must survive: this is exactly why Rewrite runs on the
	// already-rendered template rather than being threaded through fmt.Sprintf.
	t.Run("percent in url is not a format verb", func(t *testing.T) {
		t.Setenv("CLIENT_URL", "https://host/a%2Fb")
		t.Setenv("SYSTEM_URL", "")
		got := Rewrite(`x https://app.authnull.com/y`)
		if want := `x https://host/a%2Fb/y`; got != want {
			t.Errorf("got %q, want %q", got, want)
		}
	})

	// Other authnull hosts in the templates (help., www., the logo CDN) must not
	// be touched -- only the admin-UI host is deployment-specific.
	t.Run("other authnull hosts untouched", func(t *testing.T) {
		t.Setenv("CLIENT_URL", "https://onprem.dev.authnull.com")
		t.Setenv("SYSTEM_URL", "")
		in := `https://help.authnull.com/docs https://authnull.com/assets/images/logo.png http://www.authnull.com`
		if got := Rewrite(in); got != in {
			t.Errorf("expected untouched, got %q", got)
		}
	})
}
