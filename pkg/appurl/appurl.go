// Package appurl resolves the browser-facing base URL of this deployment.
//
// It exists because the admin-UI hostname was hardcoded as
// "https://app.authnull.com" in email templates and redirect targets. On an
// on-prem install that sends users to Authnull's SaaS instead of their own
// deployment, and no environment variable could override it.
package appurl

import (
	"os"
	"strings"
)

// LegacyAppHost is the SaaS hostname that used to be hardcoded throughout the
// email templates. Retained so Rewrite can find and replace it.
const LegacyAppHost = "https://app.authnull.com"

// Client returns the base URL the browser should be sent to, without a trailing
// slash. Resolution order:
//
//	CLIENT_URL   — the admin UI / client base URL (what the browser talks to)
//	SYSTEM_URL   — this deployment's base URL, if CLIENT_URL is unset
//	LegacyAppHost — last resort, preserving the historical default
//
// Both variables are already part of the documented configuration, so this adds
// no new deployment surface.
func Client() string {
	for _, key := range []string{"CLIENT_URL", "SYSTEM_URL"} {
		if v := strings.TrimSpace(os.Getenv(key)); v != "" {
			return strings.TrimRight(v, "/")
		}
	}
	return LegacyAppHost
}

// API returns the base URL an APP should call, without a trailing slash.
//
// Deliberately NOT Client()'s order. CLIENT_URL is the browser-facing admin UI, which on a
// split deployment is a different host from the API — and an enrollment invite carrying the
// browser URL cannot be redeemed at all. Resolution order:
//
//	API_BASE_URL — this deployment's API base (what an app talks to)
//	SYSTEM_URL   — this deployment's base URL
//	Client()     — last resort, correct on a single-host deployment
//
// API_BASE_URL should be treated as REQUIRED on any split deployment: a single app-store
// binary serving both SaaS and on-prem has no way to guess it, so it must travel inside the
// invite.
func API() string {
	for _, key := range []string{"API_BASE_URL", "SYSTEM_URL"} {
		if v := strings.TrimSpace(os.Getenv(key)); v != "" {
			return strings.TrimRight(v, "/")
		}
	}
	return Client()
}

// LegacyTenantBaseDomain is the tenant base domain that provisioning used to
// hardcode. Retained as the default so an unset TENANT_BASE_DOMAIN reproduces
// the historical hostname exactly.
const LegacyTenantBaseDomain = "prod.authnull.com"

// TenantSiteURL returns the hostname stored in tenants.site_url for a newly
// provisioned org: "default.<org>.<TENANT_BASE_DOMAIN>".
//
// This value is the join key tenant login matches on. getAuthMethod and
// getTenantAuthFactor both resolve the tenant with
//
//	WHERE site_url = <the Host the browser sent> AND status = 'active'
//
// so it has to equal the hostname actually served by nginx/DNS, or login fails
// with "Tenant not found or inactive".
//
// Provisioning built this by concatenating a hardcoded "prod":
//
//	"default." + org.OrganizationName + "." + "prod" + ".authnull.com" //Append Env
//
// The "//Append Env" note (still present in the pre-consolidation
// user-service) shows "prod" was a placeholder for the environment segment that
// was never substituted. It went unnoticed because the code only ever ran in
// prod, where the placeholder was accidentally correct; any other environment
// gets a hostname it does not serve, and every provisioned org then needs a
// manual UPDATE of tenants.site_url.
//
// The same URL is also built for the confirmation email, but from ENV -- which
// is "production" here, a third spelling matching neither the database nor the
// deployment. Both now come from this one function.
func TenantSiteURL(orgName string) string {
	base := strings.Trim(strings.TrimSpace(os.Getenv("TENANT_BASE_DOMAIN")), ".")
	if base == "" {
		base = LegacyTenantBaseDomain
	}
	return "default." + orgName + "." + base
}

// Rewrite replaces every occurrence of the hardcoded SaaS host in s with the
// configured client URL.
//
// It is applied to already-rendered templates rather than threading another
// format argument through each one: the templates are long fmt.Sprintf calls
// with positional arguments, so adding a verb to each would be easy to get
// wrong, and a URL containing '%' would corrupt the format string. Replacing
// after rendering is order-independent and cannot break the format.
func Rewrite(s string) string {
	client := Client()
	if client == LegacyAppHost {
		return s
	}
	return strings.ReplaceAll(s, LegacyAppHost, client)
}
