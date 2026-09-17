package main

import (
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/authnull0/authnull-service/internal/policy"
)

// consolePolicyCalls is every /api/v1/policyService/* path the admin console calls.
//
// This list is not a guess. It was extracted from the DEPLOYED console bundle
// (https://onprem.dev.authnull.com/static/js/main.6e721090.js) by pulling every string literal
// containing "policyService", which yields exactly these 36 in two equivalent shapes:
//
//	"".concat(REACT_APP_DID_API_URL, "/policyService/CreatePolicy")   // 9 of them
//	"/api/v1/policyService/CreateJSONPolicy"                          // 27 of them
//
// REACT_APP_POLICY_API_URL is NOT involved -- it is absent from the deployed env.js and reads as
// undefined -- so these hardcoded literals are the whole contract.
//
// # WHY THIS TEST EXISTS
//
// When it was first written, 23 of these 36 were unregistered: the entire JSON policy engine, all
// four manual-endpoint-rule endpoints, both AD-group-job screens, and the access-request views.
// The failure mode is what makes it worth a test -- a missing alias is a 404 in someone's browser.
// It does not fail the build, does not error in the server log, and does not show up in any test
// that exercises the handler directly, because the handler is fine. Only the route is missing.
//
// Two entries differ from their neighbours by case alone (UpdateEndpointRule, AuthenticationLog).
// gin matches case-sensitively, so those are genuinely distinct routes, and writing the lowercase
// spelling while the console calls the PascalCase one is a 404 that reads like a typo nobody sees.
//
// If a future console build drops an endpoint, this test does not fail -- extra aliases are
// harmless and deliberately kept for older bundles. It only fails when the console asks for
// something the server does not serve, which is the direction that breaks a user.
var consolePolicyCalls = []string{
	"/api/v1/policyService/AccessRequest",
	"/api/v1/policyService/ApplyDiscoveredPolicies",
	"/api/v1/policyService/ApprovePolicyAgentless",
	"/api/v1/policyService/ArchiveRequest",
	"/api/v1/policyService/AuthenticationLog",
	"/api/v1/policyService/CreateJSONPolicy",
	"/api/v1/policyService/CreatePolicy",
	"/api/v1/policyService/DiscoverADPolicies",
	"/api/v1/policyService/FilterAccessRequest",
	"/api/v1/policyService/FilterPolicy",
	"/api/v1/policyService/IsPolicyExists",
	"/api/v1/policyService/ListPolicy",
	"/api/v1/policyService/PolicyAction",
	"/api/v1/policyService/RevokePolicyAgentless",
	"/api/v1/policyService/UpdateEndpointRule",
	"/api/v1/policyService/UpdateJSONPolicy",
	"/api/v1/policyService/UpdatePolicy",
	"/api/v1/policyService/UpdateUserAccessRequest",
	"/api/v1/policyService/changeStatus",
	"/api/v1/policyService/createADGroupJob",
	"/api/v1/policyService/createManualEndpointRule",
	"/api/v1/policyService/deleteManualEndpointRule",
	"/api/v1/policyService/deletePolicyJSON",
	"/api/v1/policyService/listADGroups",
	"/api/v1/policyService/listADLogGroup",
	"/api/v1/policyService/listDestinationIP",
	"/api/v1/policyService/listEndpointRule",
	"/api/v1/policyService/listEndpointUser",
	"/api/v1/policyService/listEndpoints",
	"/api/v1/policyService/listLinuxCommands",
	"/api/v1/policyService/listManualEndpointRule",
	"/api/v1/policyService/listOU",
	"/api/v1/policyService/listSourceIP",
	"/api/v1/policyService/listViewADGroupJobs",
	"/api/v1/policyService/listViewPermission",
	"/api/v1/policyService/updateManualEndpointRule",
}

// TestPolicyServiceRoutesCoverConsole asserts every path the console calls is registered.
func TestPolicyServiceRoutesCoverConsole(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	have := map[string]bool{}
	for _, ri := range r.Routes() {
		have[ri.Method+" "+ri.Path] = true
	}

	missing := 0
	for _, p := range consolePolicyCalls {
		if !have["POST "+p] {
			t.Errorf("console calls POST %s, which is NOT registered", p)
			missing++
		}
	}
	t.Logf("%d/%d console policy paths registered", len(consolePolicyCalls)-missing, len(consolePolicyCalls))
}

// TestPolicyServiceRoutesAreUnique guards the table itself.
//
// gin PANICS on a duplicate path registration, so a copy-paste slip in the table takes the whole
// service down at boot rather than failing one endpoint. That is a worse outcome than the 404 this
// table exists to fix, and it would be caught only by actually starting the server -- so it is
// caught here instead.
func TestPolicyServiceRoutesAreUnique(t *testing.T) {
	seen := map[string]bool{}
	for _, r := range policy.PolicyServiceRoutes() {
		if seen[r.Path] {
			t.Errorf("duplicate path %q in the policyService table -- gin will panic at boot", r.Path)
		}
		seen[r.Path] = true
		if r.Handler == nil {
			t.Errorf("path %q has a nil handler", r.Path)
		}
	}
	t.Logf("%d unique policyService aliases", len(seen))
}
