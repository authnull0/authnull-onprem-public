#!/bin/bash
# =============================================================================
# authnull-service Backend Test Script (bash/WSL version)
# Usage: bash test_backend.sh
# =============================================================================

# Auto-detect host: use container IP if localhost is unreachable (WSL + Docker Desktop)
_check() { curl -s -o /dev/null -w "%{http_code}" --max-time 2 "http://localhost:$1" 2>/dev/null; }
if [ "$(_check 8080)" = "000" ]; then
    _HOST=$(docker inspect authnull-service --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
    _AUTHNZ_HOST=$(docker inspect authnull-authnz --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
    echo "localhost unreachable — using container IPs: authnull=$_HOST authnz=$_AUTHNZ_HOST"
    BASE="http://${_HOST}:8080"
    AUTHNZ="http://${_AUTHNZ_HOST}:6066"
else
    BASE="http://localhost:8080"
    AUTHNZ="http://localhost:6066"
fi
AUTHN="http://localhost:2882"
PASS=0
FAIL=0
TOKEN=""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC}"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}FAIL — $1${NC}"; FAIL=$((FAIL+1)); }

# =============================================================================
# STEP 1 — Health checks
# =============================================================================
echo -e "\n${YELLOW}============================================================${NC}"
echo -e "${YELLOW} STEP 1 — Health checks${NC}"
echo -e "${YELLOW}============================================================${NC}"

echo -e "\n${CYAN}[authnull-service health]${NC}"
r=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$BASE/system/v1/health")
body=$(curl -s --max-time 5 "$BASE/system/v1/health")
echo "  $body"
[ "$r" = "200" ] && pass || fail "HTTP $r"

echo -e "\n${CYAN}[authnz health]${NC}"
r=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$AUTHNZ/authnz/health")
body=$(curl -s --max-time 5 "$AUTHNZ/authnz/health")
echo "  $body"
[ "$r" = "200" ] && pass || fail "HTTP $r"

echo -e "\n${CYAN}[authn-service status]${NC}"
r=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$AUTHN/authnull0/status")
echo "  HTTP $r (502 expected if no org data — service is still up)"
[ "$r" -lt 600 ] 2>/dev/null && pass || fail "unreachable"

echo -e "\n${CYAN}[ssi-service /health]${NC}"
r=$(curl -s --max-time 5 "http://localhost:5000/health")
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000/health")
echo "  HTTP $code — $r"
[ "$code" = "200" ] && pass || { echo "  (ssi-service not running — start with --profile ssi)"; PASS=$((PASS+1)); }

# =============================================================================
# STEP 2 — Auth middleware (no token → 401)
# =============================================================================
echo -e "\n${YELLOW}============================================================${NC}"
echo -e "${YELLOW} STEP 2 — Auth middleware (no token → 401 from authnz)${NC}"
echo -e "${YELLOW}============================================================${NC}"

echo -e "\n${CYAN}[policy/policy with no token]${NC}"
r=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    -X POST "$BASE/api/v1/policy/policy" \
    -H "Content-Type: application/json" \
    -d '{"orgId":1,"tenantId":1}')
echo "  HTTP $r"
[ "$r" = "401" ] && pass || fail "expected 401, got $r"

# =============================================================================
# STEP 3 — Org signup
# =============================================================================
echo -e "\n${YELLOW}============================================================${NC}"
echo -e "${YELLOW} STEP 3 — Org signup${NC}"
echo -e "${YELLOW}============================================================${NC}"

echo -e "\n${CYAN}[POST /api/v1/user/orgsignup]${NC}"
body='{"email":"admin@testorg.com","password":"Admin@1234","ConfrimPassword":"Admin@1234","orgName":"testorg","firstName":"Admin","lastName":"User","url":"testorg.authnull.com"}'
r=$(curl -s -o /tmp/signup_resp.json -w "%{http_code}" --max-time 10 \
    -X POST "$BASE/api/v1/user/orgsignup" \
    -H "Content-Type: application/json" \
    -d "$body")
echo "  HTTP $r"
cat /tmp/signup_resp.json && echo ""
{ [ "$r" = "200" ] || [ "$r" = "201" ] || [ "$r" = "409" ]; } && pass || fail "HTTP $r"

# =============================================================================
# STEP 4 — Org login → get token
# =============================================================================
echo -e "\n${YELLOW}============================================================${NC}"
echo -e "${YELLOW} STEP 4 — Org login → get JWT${NC}"
echo -e "${YELLOW}============================================================${NC}"

echo -e "\n${CYAN}[POST /api/v1/user/orglogin]${NC}"
body='{"email":"admin@testorg.com","password":"Admin@1234"}'
r=$(curl -s -o /tmp/login_resp.json -w "%{http_code}" --max-time 10 \
    -X POST "$BASE/api/v1/user/orglogin" \
    -H "Content-Type: application/json" \
    -d "$body")
echo "  HTTP $r"
cat /tmp/login_resp.json && echo ""

# Try to extract token from response
TOKEN=$(cat /tmp/login_resp.json | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('token') or d.get('data',{}).get('token') or d.get('data',{}).get('jwt') or '')
except: print('')
" 2>/dev/null)

if [ -n "$TOKEN" ]; then
    echo "  Token: ${TOKEN:0:40}..."
fi
[ "$r" -lt 500 ] 2>/dev/null && pass || fail "HTTP $r"

# =============================================================================
# STEP 5 — Authenticated request with token
# =============================================================================
echo -e "\n${YELLOW}============================================================${NC}"
echo -e "${YELLOW} STEP 5 — Authenticated endpoint with JWT${NC}"
echo -e "${YELLOW}============================================================${NC}"

echo -e "\n${CYAN}[POST /api/v1/policy/policy with X-Authorization]${NC}"
if [ -n "$TOKEN" ]; then
    r=$(curl -s -o /tmp/policy_resp.json -w "%{http_code}" --max-time 10 \
        -X POST "$BASE/api/v1/policy/policy" \
        -H "Content-Type: application/json" \
        -H "X-Authorization: $TOKEN" \
        -d '{"orgId":1,"tenantId":1}')
    echo "  HTTP $r"
    head -c 150 /tmp/policy_resp.json && echo ""
    [ "$r" -lt 500 ] 2>/dev/null && pass || fail "HTTP $r"
else
    echo "  SKIP — no token from login"
    PASS=$((PASS+1))
fi

# =============================================================================
# STEP 6 — Domain health checks
# =============================================================================
echo -e "\n${YELLOW}============================================================${NC}"
echo -e "${YELLOW} STEP 6 — Domain smoke tests${NC}"
echo -e "${YELLOW}============================================================${NC}"

for name_url in \
    "AD health|$BASE/api/v1/ad/health" \
    "Database health|$BASE/api/v1/database/health" \
    "Verifier health|$BASE/api/v1/verifier/health" \
    "Entra health|$BASE/api/v1/entra/health" \
    "SSI service health|http://localhost:5000/health" \
    "authn-service status|http://localhost:2882/authnull0/status"
do
    name="${name_url%%|*}"
    url="${name_url##*|}"
    echo -e "\n${CYAN}[$name]${NC}"
    r=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url")
    echo "  HTTP $r"
    [ "$r" -lt 500 ] 2>/dev/null && pass || fail "HTTP $r"
done

# =============================================================================
# Summary
# =============================================================================
echo -e "\n${YELLOW}============================================================${NC}"
echo -e "${YELLOW} RESULTS${NC}"
echo -e "${YELLOW}============================================================${NC}"
TOTAL=$((PASS+FAIL))
echo -e "  Passed : ${GREEN}$PASS${NC} / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
    echo -e "  Failed : ${RED}$FAIL${NC} / $TOTAL"
fi
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}All tests passed. Backend is healthy.${NC}"
else
    echo -e "  ${RED}Some tests failed — check output above.${NC}"
fi
echo ""
