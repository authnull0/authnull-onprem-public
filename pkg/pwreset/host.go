package pwreset

import "strings"

// Host reduces a caller-supplied tenant URL to bare "host[:port]".
//
// The two consoles disagree about what they put in the `url` field of a reset request:
// the SSC sends a bare domain ("default.alpha.dev.authnull.com"), while did-react sends
// the page it happens to be on ("https://default.alpha.dev.authnull.com/tenant/
// forgot-password"). Both identify the same tenant.
//
// That value is stored on the reset token, echoed to the reset page as &url=, and
// returned in the reset response, where it is used to seed the console's domain and
// resolve authentication factors. A path-laden value breaks all three, so normalise once
// at the point it enters the system rather than expecting every caller and every consumer
// to agree.
func Host(raw string) string {
	h := strings.TrimSpace(raw)
	if i := strings.Index(h, "://"); i != -1 {
		h = h[i+3:]
	}
	if i := strings.IndexAny(h, "/?#"); i != -1 {
		h = h[:i]
	}
	return strings.Trim(h, ".")
}

// OrgLabel extracts the organisation label from a tenant URL of the form
// "<tenant>.<org>.<base>", tolerating a scheme, port or path.
//
// The reset handlers derived this with a bare strings.Split(url, ".")[1], which panics on
// any URL with fewer than two dot-separated labels — an empty or malformed `url` in the
// request body became a 500. ok is false instead, so the caller can answer 400.
func OrgLabel(raw string) (string, bool) {
	parts := strings.Split(Host(raw), ".")
	if len(parts) < 2 || parts[1] == "" {
		return "", false
	}
	return parts[1], true
}
