package license

import (
	"net/http"
	"sort"
	"strings"

	"github.com/gin-gonic/gin"
)

// WHICH DIRECTION THE LIST RUNS, AND WHY IT MATTERS MORE THAN IT LOOKS
//
// There are two ways to build this, and they fail differently:
//
//   A. Gate everything, exempt a list of data-plane paths.
//      A route added later is gated BY DEFAULT. Forget to exempt a new sensor endpoint and a
//      licence lapse stops authentication — an outage, on a customer's domain controllers.
//
//   B. Gate only a list of control-plane paths.
//      A route added later is free BY DEFAULT. Forget to add a new console endpoint and an expired
//      customer can still change one setting — revenue leak.
//
// B, without hesitation. A mistake must cost money rather than availability, and in a product that
// sits in the authentication path that is not a close call. The original plan said "allow-list of
// paths that must never be gated"; this is the opposite, and deliberately so.
//
// EXACT PATHS, NEVER PREFIXES
//
// A prefix is how B quietly becomes A. `/api/v1/policy/json/` looks like it means "policy writes",
// but it also matches listPolicy, getEffectivePolicy and simulatePolicy — all reads. Gating those
// would make the console unusable when expired, when the entire point is that it stays READ-ONLY.
// So the table below is exact paths only, and IsGated does no prefix matching.

// FeatureAny marks a gated path that needs a valid licence but no particular feature.
//
// Policy authoring lives here. AD, database and RADIUS policies are all created through the SAME
// endpoints — CreateJSONPolicy and friends — with the type carried in the request body, so a URL
// cannot tell them apart. The middleware enforces "you have a licence"; the per-type check belongs
// where policyType has been parsed. See FeatureForPolicyType.
const FeatureAny = ""

// controlPlaneWrites maps each gated path to the feature it belongs to.
//
// Every entry creates or changes configuration. Reads are absent on purpose: an expired deployment
// must still be able to show its policies, its directories and its logs, or "read-only" is a
// euphemism for "broken".
//
// # SELLING FEATURES SEPARATELY
//
// A customer may buy AD, database or RADIUS in any combination, so a path tied to one module is
// refused when that module is not licensed — even while the licence itself is perfectly valid. That
// is a different refusal from expiry and says so.
//
// WHAT IS DELIBERATELY NOT HERE: the database module's agent endpoints (dbSync, dbTable, dbUser,
// getJobQueue, updateQueue, registerDbAgent, updateLastActive) and listConnections. Those are the
// DATA plane — the agent syncing, and a user obtaining the credentials to open a database session.
// Gating them would stop database logins on a licence lapse, which is the exact outage this whole
// design exists to prevent.
var controlPlaneWrites = map[string]string{
	// --- Policy authoring: shared by all three products, so no single feature ---
	"/api/v1/policyService/CreateJSONPolicy":        FeatureAny,
	"/api/v1/policyService/UpdateJSONPolicy":        FeatureAny,
	"/api/v1/policyService/deletePolicyJSON":        FeatureAny,
	"/api/v1/policyService/PolicyAction":            FeatureAny,
	"/api/v1/policyService/ApprovePolicy":           FeatureAny,
	"/api/v1/policyService/ApprovePolicyAgentless":  FeatureAny,
	"/api/v1/policyService/RevokePolicyAgentless":   FeatureAny,
	"/api/v1/policyService/ApplyDiscoveredPolicies": FeatureAny,
	"/api/v1/policyService/CreatePolicy":            FeatureAny,
	"/api/v1/policyService/UpdatePolicy":            FeatureAny,
	"/api/v1/policy/json/createPolicy":              FeatureAny,
	"/api/v1/policy/json/updatePolicy":              FeatureAny,
	"/api/v1/policy/json/deletePolicy":              FeatureAny,
	"/api/v1/policy/json/approvePolicy":             FeatureAny,
	"/api/v1/policy/json/revokePolicy":              FeatureAny,
	"/api/v1/policy/json/policyAction":              FeatureAny,
	"/api/v1/policy/json/applyDiscoveredPolicies":   FeatureAny,
	"/api/v1/policy/json/createBaselinePolicy":      FeatureAny,
	"/api/v1/policy/json/approveAllBaselines":       FeatureAny,
	"/api/v1/policy/json/approvePolicyAgentless":    FeatureAny,
	"/api/v1/policy/json/revokePolicyAgentless":     FeatureAny,
	"/api/v1/policy/createPolicy":                   FeatureAny,
	"/api/v1/policy/updatePolicy":                   FeatureAny,
	"/api/v1/policy/approvePolicy":                  FeatureAny,

	// --- AD ---
	// Discovery reads the directory and proposes policies, so it is AD-specific configuration work.
	"/api/v1/policyService/DiscoverADPolicies": FeatureAD,
	"/api/v1/policy/json/discoverADPolicies":   FeatureAD,
	"/api/v1/policy/createADGroupJob":          FeatureAD,
	"/api/v1/policyService/createADGroupJob":   FeatureAD,
	// Minting an enrolment invite for another user.
	"/api/v1/mfa/push/adminInvite": FeatureAD,
	// mfa.RegisterRoutes is mounted TWICE -- on /api/v1 and on /authentication -- so the same
	// handler answers on two paths and gating only one leaves the other wide open. Exact-path
	// matching is what makes this possible to get wrong, and it is the trade taken deliberately
	// (see the note at the top). TestGatedHandlersAreGatedAtEveryMount asserts every mount of a
	// gated handler is itself gated, so the next double-mount cannot slip through.
	"/authentication/mfa/push/adminInvite": FeatureAD,

	// --- Database ---
	// Registering and removing the database hosts under management. The agent's own sync and job
	// endpoints are excluded above and must stay that way.
	"/api/v1/database/createDbHost":              FeatureDatabase,
	"/api/v1/database/deleteDatabaseHost":        FeatureDatabase,
	"/api/v1/database/deleteAgentHost":           FeatureDatabase,
	"/api/v1/databaseService/createDbHost":       FeatureDatabase,
	"/api/v1/databaseService/deleteDatabaseHost": FeatureDatabase,
	"/api/v1/databaseService/deleteAgentHost":    FeatureDatabase,

	// --- RADIUS ---
	// No RADIUS-specific configuration endpoints exist yet; RADIUS policies are authored through the
	// shared policy paths above. Entries land here when the RADIUS module gains its own screens.
}

// FeatureForPolicyType maps a policy's type to the feature that must be licensed to author it.
//
// The shared policy endpoints cannot be gated by URL, because AD, database and RADIUS policies all
// arrive at the same path with the type in the body. This is the check for the place that HAS the
// type — call it once policyType is parsed, and refuse when the feature is not licensed.
//
// An unrecognised type returns FeatureAny rather than an error: a new policy type should not become
// unauthorable because this map has not caught up, and the licence-validity check still applies.
func FeatureForPolicyType(policyType string) string {
	switch strings.ToLower(strings.TrimSpace(policyType)) {
	case "ad", "groupad":
		return FeatureAD
	case "database":
		return FeatureDatabase
	case "radius":
		return FeatureRADIUS
	default:
		return FeatureAny
	}
}

// FeatureFor returns the feature a gated path belongs to, and whether the path is gated at all.
func FeatureFor(path string) (string, bool) {
	if f, ok := controlPlaneWrites[path]; ok {
		return f, true
	}
	f, ok := controlPlaneWrites[strings.TrimRight(path, "/")]
	return f, ok
}

// IsGated reports whether a path requires a licence. Exact match only — see the note above.
func IsGated(path string) bool {
	_, ok := FeatureFor(path)
	return ok
}

// GatedPaths returns the gated set, sorted. For tests and for the licence page, so the list can be
// inspected rather than inferred.
func GatedPaths() []string {
	out := make([]string, 0, len(controlPlaneWrites))
	for p := range controlPlaneWrites {
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

// Gate returns middleware that refuses control-plane writes when the licence does not permit them.
//
// status is a function rather than a value so the middleware always reads the CURRENT state: a
// customer who uploads a licence must be unblocked without restarting the service, and one whose
// licence expires mid-session must not be.
//
// Applied per-route from the gated table rather than to a whole group, so it is impossible for a
// group-level Use() to catch a data-plane route that happens to share a prefix.
func Gate(status func() Status) gin.HandlerFunc {
	return func(c *gin.Context) {
		feature, gated := FeatureFor(c.FullPath())
		if !gated {
			c.Next()
			return
		}
		st := status()
		if !st.Licensed {
			c.AbortWithStatusJSON(http.StatusPaymentRequired, gin.H{
				"error":    "license required",
				"state":    st.State,
				"message":  gateMessage(st),
				"licensed": false,
			})
			return
		}
		// Licensed, but this module may not be part of what they bought.
		if feature != FeatureAny && !st.Has(feature) {
			c.AbortWithStatusJSON(http.StatusPaymentRequired, gin.H{
				"error":    "feature not licensed",
				"state":    st.State,
				"feature":  feature,
				"licensed": true,
				"message": "your licence does not include " + featureLabel(feature) +
					". Existing policies continue to be enforced; only changes are blocked.",
			})
			return
		}
		c.Next()
	}
}

// featureLabel renders a feature name for a message an administrator reads.
func featureLabel(feature string) string {
	switch feature {
	case FeatureAD:
		return "Active Directory MFA"
	case FeatureDatabase:
		return "Database MFA"
	case FeatureRADIUS:
		return "RADIUS MFA"
	default:
		return feature
	}
}

func gateMessage(st Status) string {
	base := st.Reason
	if base == "" {
		base = "this deployment has no valid licence"
	}
	// The second sentence is the part that prevents a panicked escalation: an admin who cannot
	// create a policy needs to know immediately that authentication is still being enforced.
	return base + ". Existing policies continue to be enforced; only changes are blocked."
}
