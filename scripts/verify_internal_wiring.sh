#!/bin/bash
# =============================================================================
# Phase 1 verification: can authn-service reach authnull-service, and is the
# policy/audit pair actually protected?
#
# Usage:
#   bash scripts/verify_internal_wiring.sh                  # from the host
#   INTERNAL_API_KEY=... bash scripts/verify_internal_wiring.sh
#   AUTHNULL_BASE=http://authnull-service:8080 bash ...      # from inside a container
#
# WHY THIS EXISTS
#
# authn-service's outbound calls used to address user-service:8000 and
# policy-service:7079, neither of which exists after the consolidation, so every
# tenant, policy and audit lookup went to a host that does not resolve. Two of
# those calls did not even read their env var -- the policy URL was a literal
# naming onprem.prod.authnull.com. Re-pointing them is easy to get subtly wrong
# and the symptoms are quiet, so this asserts the wiring rather than trusting it.
#
# WHAT IT DISTINGUISHES, AND WHY EACH MATTERS
#
#   000  connection refused    -> wrong host, or the service is not up
#   404  wrong path            -> the alias/canonical mix-up, e.g. SearchPolicy
#                                 vs policy/json/searchPolicy
#   401  auth rejected         -> INTERNAL_API_KEY unset or mismatched
#   200  reachable             -> what we want
#
# The two NEGATIVE checks are the point of the whole file: policy and audit must
# REFUSE a request with no key. nginx proxies all of /api/ to authnull-service, so
# if those two ever mount unauthenticated they become an anonymous policy read and
# an anonymous audit write reachable from the internet. A positive-only harness
# would pass just as happily in that state.
# =============================================================================

BASE="${AUTHNULL_BASE:-http://localhost:8080}"
KEY="${INTERNAL_API_KEY:-}"

PASS=0
FAIL=0
WARN=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; WARN=$((WARN+1)); }

# post <path> <payload> [send_key]
# Sets HTTP_CODE and HTTP_BODY.
post() {
    local path="$1" payload="$2" send_key="${3:-no}"
    local args=(-s -o /tmp/.viw_body -w '%{http_code}' --max-time 10
                -X POST -H 'Content-Type: application/json' -d "$payload")
    if [ "$send_key" = "yes" ] && [ -n "$KEY" ]; then
        args+=(-H "X-Internal-Api-Key: $KEY")
    fi
    HTTP_CODE=$(curl "${args[@]}" "${BASE}${path}" 2>/dev/null)
    HTTP_BODY=$(cat /tmp/.viw_body 2>/dev/null)
    rm -f /tmp/.viw_body
}

# Reachable and not auth-gated. Used for the four endpoints that sit ABOVE
# AuthnzMiddleware in tenant/routes.go and user/routes.go and so need no key.
check_open() {
    local name="$1" path="$2" payload="$3"
    echo -e "${CYAN}$name${NC}  POST $path"
    post "$path" "$payload" no
    case "$HTTP_CODE" in
        000) fail "connection refused — is authnull-service up at $BASE?" ;;
        404) fail "404 — path is wrong" ;;
        401) fail "401 — this endpoint is expected to be reachable WITHOUT a key; it moved behind auth" ;;
        200) if [ -z "$HTTP_BODY" ] || [ "$HTTP_BODY" = "null" ]; then
                 warn "200 but empty body — reachable, but returned nothing (seeded data?)"
             else
                 pass "200 (${#HTTP_BODY} bytes)"
             fi ;;
        *)   warn "HTTP $HTTP_CODE — reachable but unexpected: $(echo "$HTTP_BODY" | head -c 160)" ;;
    esac
}

# Reachable WITH the key, and refused WITHOUT it. Both halves are required.
check_keyed() {
    local name="$1" path="$2" payload="$3"
    echo -e "${CYAN}$name${NC}  POST $path"

    if [ -z "$KEY" ]; then
        warn "INTERNAL_API_KEY is not set in this shell — cannot test the positive case"
    else
        post "$path" "$payload" yes
        case "$HTTP_CODE" in
            000) fail "connection refused — is authnull-service up at $BASE?" ;;
            404) fail "404 with a valid key — path is wrong (canonical vs policyService alias?)" ;;
            401) fail "401 WITH a key — INTERNAL_API_KEY does not match authnull-service's" ;;
            200) pass "200 with the key (${#HTTP_BODY} bytes)" ;;
            *)   warn "HTTP $HTTP_CODE with the key: $(echo "$HTTP_BODY" | head -c 160)" ;;
        esac
    fi

    # The half that matters most.
    post "$path" "$payload" no
    case "$HTTP_CODE" in
        401) pass "401 without a key (correctly protected)" ;;
        000) fail "connection refused on the negative check" ;;
        200) fail "200 WITHOUT A KEY — this endpoint is OPEN. nginx proxies /api/ publicly, so this is an anonymous policy read or audit write." ;;
        404) fail "404 without a key — path is wrong, so the protection is untested" ;;
        *)   warn "HTTP $HTTP_CODE without a key (not a clean 401): $(echo "$HTTP_BODY" | head -c 160)" ;;
    esac
}

echo "============================================================"
echo " Phase 1 internal wiring check"
echo " target: $BASE"
if [ -n "$KEY" ]; then echo " key:    set (${#KEY} chars)"; else echo " key:    NOT SET"; fi
echo "============================================================"
echo

ORG='{"orgId":1,"tenantId":1}'

echo "--- Unauthenticated by design (above AuthnzMiddleware) ---"
check_open "TENANT_URL                   " "/api/v1/tenant/getTenantDetail" "$ORG"
check_open "TENANT_GETUSERDETAILURL      " "/api/v1/tenant/getUserDetailFromAuthService" "$ORG"
check_open "TENANT_GETENDPOINTDETAILURL  " "/api/v1/user/getEndpointandUserDetail" "$ORG"
check_open "TENANT_GETWALLETUSERDETAILURL" "/api/v1/user/getWalletUserDetail" "$ORG"
echo

echo "--- Key required (InternalKeyOrAuthnz) ---"
check_keyed "TENANT_POLICY                " "/api/v1/policy/json/searchPolicy" "$ORG"
check_keyed "TENANT_AUDIT                 " "/api/v1/policy/logAccessRequest" "$ORG"
echo

echo "--- Paths that must NOT answer (regression guards) ---"
# The legacy handler reads did.auth_policies, not did.auth_policy_json. If
# TENANT_POLICY is ever pointed here it returns an empty list rather than an
# error, which reads as "no policy covers this user" and, under no-policy-is-allow,
# lets every login through unchallenged. Behind session auth, so 401 is correct.
#
# Note both guards refuse to pass on 000. "I could not reach it" is not evidence
# that a route is closed -- treating it as such is how a negative check silently
# stops testing anything, which is the same absence-vs-cannot-determine mistake
# the decision engine has to avoid.
echo -e "${CYAN}legacy SearchPolicy is still session-gated${NC}"
post "/api/v1/policyService/SearchPolicy" "$ORG" yes
case "$HTTP_CODE" in
    000) fail "unreachable — cannot tell whether this is gated, so this guard proved nothing" ;;
    200) fail "the legacy policyService/SearchPolicy answered 200 to a service key — it should require a session" ;;
    401|403) pass "HTTP $HTTP_CODE (session required, as intended)" ;;
    *)   warn "HTTP $HTTP_CODE — not 200, but not a clean auth refusal either" ;;
esac

# searchPolicyJSON was the hardcoded path in authn-service and exists in neither
# service. If it ever starts answering, something re-added it by mistake.
echo -e "${CYAN}searchPolicyJSON does not exist${NC}"
post "/api/v1/policyService/searchPolicyJSON" "$ORG" yes
case "$HTTP_CODE" in
    000) fail "unreachable — cannot confirm this path is absent" ;;
    404) pass "404 (as expected — this path was always a dead end)" ;;
    *)   warn "HTTP $HTTP_CODE — expected 404; did someone add this path?" ;;
esac
echo

echo "============================================================"
echo -e " ${GREEN}pass $PASS${NC}   ${RED}fail $FAIL${NC}   ${YELLOW}warn $WARN${NC}"
echo "============================================================"
[ "$FAIL" -eq 0 ] || exit 1
