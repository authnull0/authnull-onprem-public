# RADIUS MFA — implementation task

Add RADIUS MFA so an AD user reaching a VPN, switch, firewall or any other RADIUS
client gets an Authnull push, with policies authored in the console.

**Roughly 4–5 days.** Parts 1–6 are all yours. Each part says which files to touch, what
to copy from, how to test, and when it is finished.

Part 1 is a written specification rather than code — it was designed, prototyped and then
removed deliberately, so you own the implementation. The design decisions in it are the
output of that prototype and are not guesses; the reasoning for each is given so you can
disagree with it knowingly rather than by accident.

Read [§0](#0-the-architecture) before writing anything — the biggest risk on this task is
a design misunderstanding, not a coding mistake.

---

## Status — built, then partly superseded

Everything below was implemented and merged (PR #15). The decision path then **changed
direction twice on instruction**, so sections are annotated rather than deleted: the
reasoning is still what a reader needs, even where the code it describes is gone.

| Change | Effect on this doc |
|---|---|
| MFA moved to **authn-service `do-authenticationV4`** | §0, §5, §6 rewritten |
| **`evaluateRadius` retired** (PR #20) | §3 obsolete; §2, §4 unreachable |
| Matcher moved to `internal/radius/` | §1, §10 paths corrected |

**The one thing to understand before touching RADIUS:** the live lookup matches on
`policy_json->'permissions'->'iam_users'` — an email, nothing else. The `radius` policy
block in [§1a](#1a-the-policy-block), and therefore all device, calling-station and
service-type scoping, **is not read by anything on the live path.** RADIUS policy is
user-scoped today. The matcher that implements that scoping is kept, tested and marked
`NOT CURRENTLY REACHED`, because it is what the scoping would be built on — see
[§11](#11-what-is-not-reached-and-what-it-would-take).

Verified end to end against the dev VM with a real Okta push — results in [§8](#8-verification).

---

## 0. The architecture

```
VPN / switch / firewall
        │  RADIUS (UDP 1812)
        ▼
   FreeRADIUS                 ← the CUSTOMER installs and owns this
        │  1. primary auth (password) against their AD
        │  2. post-auth: exec our binary
        ▼
   authnull-radius-mfa        ← our binary, one process per request
        │  HTTPS — ONE blocking call
        ▼
   authn-service              ← do-authenticationV4
        ├─ ResolveUserEmail    logon name → person
        ├─ LookupPolicy ───────► authnull-service /policy/json/searchPolicy
        └─ ChallengeMFA        push, waits for the verdict
                                 answers isValid
```

**UPDATED.** This originally read `authnull-service ← evaluateRadius, then poll
getMFAChallenge`. Both halves are gone: the endpoint was retired ([§3](#3-evaluateradius--the-decision-endpoint))
and there is nothing to poll, because V4 blocks until the user answers. The binary makes
**one** call and reads one boolean.

Note the service split — the binary talks to **authn-service**, which calls
authnull-service for the policy. `API_BASE_URL` in the binary's config therefore points at
authn-service (`:2882`). Pointing it at authnull-service yields 404s.

**FreeRADIUS does the password. We only do the second factor.** This is not a detail to
work around — it is the design. The customer's FreeRADIUS binds to their directory, and by
the time our binary runs, the user has already proved who they are. Our binary answers one
question: *should this be challenged, and was it approved?*

Two consequences worth internalising:

- **Never verify a password in our code.** If you find yourself reaching for
  `User-Password`, stop and re-read this section.
- **The existing `radius-server` directory is a standalone RADIUS server that does NOT
  check passwords.** As a front door that is a security hole. You are not deploying it as
  one — you are reshaping it into the post-auth binary above, where not checking the
  password is correct.

### Identity comes from AD, and that is deliberate

The user arriving over RADIUS is an AD user, so groups and OUs resolve through the same
transitive closure the AD engine uses (`resolveGroupClosure` in
`internal/policy/repo/ad_identity.go`). A user nested inside `VPN-Users` is a member for
both engines or neither. Do not write a second group resolver.

**This is now load-bearing in a way worth stating plainly.** On the live path,
`utils.ResolveUserEmail` in authn-service maps the logon name the binary sends to a person
by DB lookup only — `did.ad_users.logoname`, `did.users.logon_name`, then `did.epm_users`.
There is no other mapping. So:

> **A RADIUS-only customer cannot authenticate.** With nothing populating those tables,
> every login ends at `could not identify the user for multi-factor approval` (401).
> **AD sync is a hard prerequisite for RADIUS**, unless we add a RADIUS-specific mapping
> or have the binary send `user@DOMAIN` — the latter only correct where the AD UPN suffix
> equals the mail domain, which often it is not.

Raised on PR #20 and not yet decided.

### What differs from AD, and why RADIUS has its own policy structure

An AD policy scopes a login by domain context — protocol, the SPN requested, the DC
involved. A RADIUS login has none of those. What it has is a **network device** and a
**service type**, and neither fits in the AD block. That is why `dto.Radius` exists.

---

## 1. The RADIUS policy structure and matcher

**Built. Lives in `internal/radius/`, not `internal/policy/repo/`** — moved on instruction,
so the matcher does not sit inside the AD engine's package. The helpers it reuses are
exported from `repo` through `internal/policy/repo/radius_exports.go`, one-line wrappers
that exist only to break the import cycle without touching AD call sites.

| Actual | Purpose |
|---|---|
| `internal/radius/matcher.go` | given one RADIUS event and one policy, does it apply? |
| `internal/radius/matcher_test.go` | the rules below, each as a case |
| `internal/radius/decision.go` | `loadCandidates`, `BuildAuthContext`, `GetEffectivePolicy` |
| `internal/policy/repo/radius_exports.go` | exported wrappers over the AD normalisers |

Plus one addition to `internal/policy/dto/dto.go`: a `Radius` block on `PolicyJSON`,
alongside the existing `ad`, `database` and `serviceaccount` blocks.

> **NOT CURRENTLY REACHED.** The matcher is correct and tested, but nothing on the live
> path calls it — see [§11](#11-what-is-not-reached-and-what-it-would-take). Kept because
> it is the foundation for device and service-type scoping, and deleting it would mean
> rediscovering all seven rules below.

**Already in place, do not rebuild:** `FeatureRADIUS` in `pkg/license`, so RADIUS is
already licensable and sellable in any combination with AD and Database.

### 1a. The policy block

```go
// On PolicyJSON, beside Database:
Radius Radius `json:"radius,omitempty"`

type Radius struct {
	// identity: who
	Domain   string   `json:"domain,omitempty"`
	Users    []string `json:"users,omitempty"`
	Groups   []string `json:"groups,omitempty"`
	Ous      []string `json:"ous,omitempty"`
	MatchAll bool     `json:"matchAll,omitempty"`

	// the network device: NAS-Identifier, IP, CIDR, or "*"
	Clients []string `json:"clients,omitempty"`

	// where the user is: Calling-Station-Id, exact or CIDR
	CallingStations []string `json:"callingStations,omitempty"`

	// kind of access: login | framed | administrative | nas-prompt
	ServiceTypes []string `json:"serviceTypes,omitempty"`
}
```

Note there is already a `Radius RadiusNetwork` field on the **`PolicyLog`** struct and a
`RadiusNetwork` type used by `networks`. Both are pre-existing and unrelated — do not
extend them, and do not be confused by the name collision.

**The collision turned out to matter.** The pre-existing `networks` / `RadiusNetwork` pair
is what the **live** lookup reads (`SearchRadiuspolicy`, lower-case `p`), while the `radius`
block above is read only by the matcher that is no longer called. So the two structures
swapped roles: the one this section calls "pre-existing and unrelated" is the live one, and
the one it specifies is dormant. Check which you are looking at before changing either.

### 1b. Duplicate the identity fields; do not point at the AD block

Identity still comes from AD, because FreeRADIUS authenticates against the customer's
directory before we are consulted. Resolve groups and OUs with the **same** transitive
closure the AD engine uses — `resolveGroupClosure` and `resolveOUs` in
`internal/policy/repo/ad_identity.go`. Do not write a second resolver.

But keep the fields on the `Radius` block rather than reading `pj.AD`. A reader of a RADIUS
policy should not have to know which half of the AD block applies to them, and the two
policy types will diverge further, not less.

### 1c. The matcher

Mirror `internal/policy/repo/ad_matcher.go`: a normalising constructor, a result type that
records how far matching got, identity predicates evaluated before context predicates.

```go
type RadiusAuthContext struct {
	Domain, User          string
	Groups, Ous           []string
	NASIdentifier, NASIP  string
	CallingStation        string
	ServiceType           string
}

func NewRadiusAuthContext(...) RadiusAuthContext   // normalise once, here
func matchRadiusPolicy(pj dto.PolicyJSON, ctx RadiusAuthContext) radiusMatchResult
```

Reuse `matchSource` for `CallingStations` and `Clients` address matching — it already
implements exact-plus-CIDR-plus-wildcard and is tested. Reuse `normalizePrincipal`,
`normalizeGroup`, `normalizeOU`, `normalizeSet`, `containsNormalized`. A second
implementation of any of these is a second set of bugs.

Keep it free of database access, like the AD matcher, so every rule is testable without a
tenant DB.

### 1d. The seven rules, and why each one is that way

These came out of the prototype. Each is a decision, not an accident.

1. **Empty `clients` means EVERY device.** A customer's first RADIUS policy is "everyone
   gets MFA on the VPN"; making them enumerate hardware to say that is a bad first
   experience. It is the permissive direction, so state it in a comment rather than leaving
   it inferred from a zero-length slice.
2. **Match a device on NAS-Identifier first, then address.** The identifier is what an
   administrator recognises and will type; the address is what is reliably present, because
   plenty of equipment never sends an identifier. A policy written either way must work.
3. **A missing Service-Type is NOT an exemption.** Equipment omits attributes constantly.
   Treating unknown as "matches nothing" would silently exempt those requests from
   enforcement — the wrong way for a security control to fail. Same rule `matchProtocol`
   applies to an unclassified protocol.
4. **Normalise Service-Type through an alias table.** RADIUS sends numbers *or* long names:
   `6`, `Administrative-User` and `administrative` are one value. Without this a policy
   works on one vendor's switch and silently not on another's.
5. **Report identity as matched even when context rejects.** That is what lets a decision
   say "we know this user, but not from that switch" instead of "unknown user". Collapsing
   the two makes a whitelist-style deny impossible to explain.
6. **Most specific identity scope wins the reason** — user, then group, then OU, then
   baseline — so a decision log names the tightest rule that applied.
7. **A policy naming a domain must not cover another one.** A customer with two directories
   needs one rule per directory.

### 1e. `supportedProtocols` — leave it alone

`matchRadiusPolicy` must call neither `matchProtocol` nor `matchAuthType`. Those are AD
context predicates and RADIUS has its own.

There is a commented-out `"radius": true` in `supportedProtocols`
(`internal/policy/repo/ad_matcher.go`). **Leave it commented.** Uncommenting it would start
matching AD policies against RADIUS events, which is the coupling this whole structure
exists to avoid.

### Done when

`go test ./internal/policy/repo/ -run TestRadius` covers all seven rules above, including:
a device matched by CIDR when NAS-Identifier is absent; `6` / `Administrative-User` /
`administrative` treated identically; an event with no Service-Type still covered; and
identity-matched-but-context-rejected reported distinctly.

---

## 2. `SearchRadiusPolicy` — find candidate policies

**Built as specified, and NOT on the live path.** `SearchRadiusPolicy` (capital `P`, keyed
on the `radius` block) is what this section describes. What actually runs is the
pre-existing **`SearchRadiuspolicy`** (lower-case `p`), reached because authn-service posts
`credentialType: "RADIUS"` to `/policy/json/searchPolicy`; it matches
`policy_json->'permissions'->'iam_users' @> '"<email>"'` and nothing else, since
`IAM.IAMUSers` is the only discriminator authn-service populates for RADIUS.

Two functions one capital letter apart, with different policy shapes. Rename before this
bites someone.

**File:** `internal/policy/repo/policyjson_repository.go`
**Copy from:** `SearchADPolicy` in the same file (starts ~line 1525)

Same shape: run one query per scope, concatenate, dedupe, sort by `Priority ASC` (lower
number wins).

```go
func (r *PolicyJSONRepo) SearchRadiusPolicy(db *gorm.DB, req dto.SearchPolicyJSONRequest) ([]model.PolicyModel, error) {
	baseQuery := func() *gorm.DB {
		q := db.Model(&model.PolicyModel{}).
			Where("status = ?", "Approved").
			Where(datatypes.JSONQuery("policy_json").HasKey("radius"))
		q = IsAllowedPolicies(q, req.OrgId, req.TenantId)
		q = TimeBasedFilter(q, req.Schedule)
		return q
	}
	// 1. baseline:  policy_json->'radius'->>'matchAll' = 'true'
	// 2. per OU:    policy_json->'radius'->'ous'    @> '["Engineering"]'
	// 3. per group: policy_json->'radius'->'groups' @> '["VPN-Users"]'
	// 4. per user:  policy_json->'radius'->'users'  @> '["satyam.gupta"]'
}
```

Use the `@>` containment operator exactly as the AD version does, and marshal the value
with `json.Marshal([]string{x})` rather than `fmt.Sprintf` — a group name containing a
quote would otherwise produce broken SQL.

**Do NOT filter by `clients` in SQL.** Device matching involves CIDRs and a
NAS-Identifier/address fallback that Postgres containment cannot express. Fetch the
candidates by identity, then let `matchRadiusPolicy` decide. That is the same division the
AD engine uses.

**Done when:** given a user in `VPN-Users`, the function returns both a `matchAll` policy
and a group-scoped one, deduped, lowest `Priority` first.

---

## 3. `evaluateRadius` — the decision endpoint

> ## ⛔ RETIRED — PR #20 — do not rebuild this
>
> Built as specified, shipped in PR #15, then removed. **The section is kept because the
> reason it was removed is the most important thing in this document.**
>
> Once the binary moved to `do-authenticationV4`, that one call did identity, policy AND
> MFA. Keeping `evaluateRadius` in front of it meant **policy was evaluated twice by two
> different matchers over two different policy shapes** — and the failure was not
> symmetric. V4's lookup matches on email alone, so where the two disagreed it answered
> `isValid: true`, which mapped to `allow`, and **the login was permitted with no MFA at
> all.** A second opinion that can only ever weaken the first is not a safety net.
>
> Removed: both route registrations, the handler, the service method,
> `radiusAsAuthRequest`, `logRadiusDecision`, `radiusDeviceOf`, the `dataPlanePaths`
> entries in `pkg/license/license_test.go`, and the route-set assertion in
> `cmd/authnull-service/onprem_package_test.go`.
>
> Still present, unused: `dto.EvaluateRadiusRequest` / `EvaluateRadiusResponse`, because
> `internal/radius/decision.go` uses the request type as its input struct.
>
> **The rule this leaves behind:** one decision point per login. If a future change gives
> authnull-service a say in the RADIUS verdict again, it must *replace* V4's decision, not
> sit alongside it.

The original specification follows, for the record.

A **separate** endpoint, not a branch inside `EvaluateAuth`. Keeping the two engines apart
all the way to the HTTP layer is the point of the separate structure; branching inside
would put RADIUS back inside the AD code path.

### 3a. Request and response DTOs

**File:** `internal/policy/dto/dto.go`

```go
type EvaluateRadiusRequest struct {
	OrgId    int    `json:"org_id"`
	TenantId int    `json:"tenant_id"`
	AdUser   string `json:"ad_user"`         // User-Name, any of the three shapes
	Domain   string `json:"domain"`

	NASIdentifier  string `json:"nas_identifier,omitempty"`   // often absent
	NASIP          string `json:"nas_ip,omitempty"`
	CallingStation string `json:"calling_station,omitempty"`
	ServiceType    string `json:"service_type,omitempty"`
	SessionId      string `json:"session_id,omitempty"`
}

type EvaluateRadiusResponse struct {
	Decision    string `json:"decision"`     // allow | block | mfa_required
	PolicyName  string `json:"policy_name,omitempty"`
	Reason      string `json:"reason,omitempty"`
	ChallengeID string `json:"challenge_id,omitempty"`  // set when mfa_required
}
```

### 3b. Service

**File:** `internal/policy/service/auth_decision_service.go`
**Copy from:** `EvaluateAuth` in the same file

Sequence:

1. Resolve the tenant DB (`resolveTenantDB(req.OrgId)`)
2. Resolve identity: AD user id, then `resolveGroupClosure` and `resolveOUs`
3. Build the context with `repo.NewRadiusAuthContext(...)` — it normalises everything once
4. `SearchRadiusPolicy`, then `matchRadiusPolicy` over the results, lowest priority first
5. Map the winning policy's `policyFlow` to `allow` / `block` / `mfa_required`
6. On `mfa_required`, call `SendMFAChallenge` (~line 520) and return its challenge id
7. Log the decision the way `EvaluateAuth` does

**No matching policy → allow.** Same default as AD: a customer who has not written a RADIUS
policy must not have their VPN stop working the moment they install us.

### 3c. Handler and route

**Files:** `internal/policy/handler/auth_decision_handler.go`, `internal/policy/routes.go`

Mirror `EvaluateAuth` (~line 17): bind, validate `ad_user`/`domain`/`org_id`/`tenant_id`,
call the service, return.

Register **both** spellings, because the binary is configured by hand and someone will get
the case wrong:

```go
rg.POST("/policy/auth/evaluateRadius", authDecisionHandler.EvaluateRadius)
rg.POST("/policy/auth/EvaluateRadius", authDecisionHandler.EvaluateRadius)
```

**This is a DATA-PLANE path. Do not add it to `pkg/license/gate.go`.** A licence lapse must
never stop VPN logins. Add both paths to `dataPlanePaths` in
`pkg/license/license_test.go` so the rule is asserted.

**Done when:** curl with a user in a covered group returns `mfa_required` and a challenge
id, a phone gets a push, and `/api/v1/ad/getMFAChallenge` shows the challenge.

---

## 4. Make the push prompt say "VPN", not a Kerberos SPN

**Built as specified. Not reached on the live path** — the push is now issued by
authn-service's `utils.ChallengeMFA`, so `challengeContextFor` in this repo never sees a
RADIUS challenge. The `case mfapush.KindRADIUS:` and its
`TestRadiusChallengeDoesNotInheritADContext` twin are kept and marked, because the AD
context-leak hazard below is real and returns the moment RADIUS pushes come through here
again.

Whether the *live* prompt says "VPN" or inherits AD context is a question about
authn-service's own context building, and has not been checked. Worth verifying before
claiming the prompt is right.

**Files:** `internal/mfapush/provider.go`, `internal/mfapush/context.go`,
`internal/ad/src/repository/mfa_push_repository.go`

Follow the `KindDatabase` work exactly — it is the same three-part change.

1. `KindRADIUS ChallengeKind = "radius"` beside `KindAD` and `KindDatabase`
2. `RADIUSResource(nasIdentifier, nasIP, serviceType string) ChallengeContext` in
   `internal/mfapush/context.go`, modelled on `DatabaseResource`. Resource name falls back
   NAS-Identifier → NAS-IP → `"Network device"`. Add
   `ResourceTypeNetworkDevice = "Network device"`.
3. A `case mfapush.KindRADIUS:` in `challengeContextFor`

### Why this matters more than it looks

`correlateFromAuthLog` back-fills blank context fields from the user's most recent **AD**
event, matched on org + email alone. Without a `KindRADIUS` case, a VPN login by a user who
also logs into Windows would inherit that logon's Kerberos SPN, domain, AD username and
source IP — the prompt would describe an authentication that is not happening.

`challengeContextFor` already zeroes the correlation for any kind that is not `KindAD`, so
adding the case is all that is required. There is a test for the database equivalent
(`TestDatabaseChallengeDoesNotInheritADContext`); **write the RADIUS twin.**

**Done when:** the push reads *"Approve VPN sign-in — vpn-hq"* and a test proves no AD
context leaks in.

---

## 5. The binary

**Repo:** `authnull0/radius-bridge` — the git BLOCKER below is resolved. Everything lives
in `golangScript.go` with `bridge_test.go` beside it, plus `radius-bridge.env.example` and
a README carrying the install and troubleshooting tables.

*Original: `/media/gandalf/New Volume/K1/radius-server`, not in git.*

### What changed

Today it is a UDP listener on 1812. It becomes a **one-shot process** FreeRADIUS execs.

- **Deleted:** the `layeh.com/radius` server, packet parsing, shared-secret handling —
  FreeRADIUS does all of that. **And `awaitMFA`**, the poll loop this section said to keep:
  V4 blocks until the user answers, so there is no challenge id and nothing to poll.
- **Added:** flag parsing, exit codes — `0` approved, `1` denied/timeout/error — and a
  config file read fresh per request, so edits need no FreeRADIUS restart.
- **Points at** `do-authenticationV4` on **authn-service**, not `evaluateRadius`.

```
authnull-radius-mfa --user='%{User-Name}' --nas-ip='%{NAS-IP-Address}' \
                    --nas-id='%{NAS-Identifier}' --station='%{Calling-Station-Id}' \
                    --service-type='%{Service-Type}' --nas-port='%{NAS-Port}' \
                    --packet-src-ip='%{Packet-Src-IP-Address}' \
                    --session-id='%{Acct-Session-Id}'
```

Two flags worth knowing about:

- **`--packet-src-ip` — do not drop it.** The device address is taken from the UDP packet
  source in preference to the `NAS-IP-Address` attribute. Both name the device, but only
  the packet source is observed by FreeRADIUS and authenticated by the shared secret; the
  attribute is client-supplied and can be absent or wrong. Since a device-scoped policy
  matching nothing ends in default-allow, taking the address only from the attribute let a
  client escape a device-scoped MFA policy by omitting it.
- **`--service-type` is accepted, logged, and NOT sent.** `DoAuthenticationV4RequestDTO`
  has no field for it. See [§11](#11-what-is-not-reached-and-what-it-would-take).

Keep `splitUserDomain` — it handles the three username shapes and the matcher's tests
depend on that normalisation being done consistently. Note it sends the **bare** logon
name, which is what makes AD sync a prerequisite ([§0](#identity-comes-from-ad-and-that-is-deliberate)).

**Fail closed everywhere.** Every error path returns exit 1, including a contradictory
response (`code != 200` with `isValid: true`). `FAIL_OPEN=true` inverts this and is a
deliberate downgrade, not a convenience — a backend outage then admits everyone with no
MFA.

**No `Auth-Type` is ever emitted**, so the binary can deny but never grant. An earlier
version emitted `Auth-Type := Accept` and thereby overrode FreeRADIUS's own password
check — a wrong password plus an approved push was an Accept. `bridge_test.go` has the
regression test; keep it.

---

## 6. FreeRADIUS configuration and the timeout problem

### The snippet the customer installs

```
# mods-available/authnull, symlinked into mods-enabled/
exec authnull_mfa {
    wait = yes
    program = "/usr/local/bin/authnull-radius-mfa --user='%{User-Name}' ..."
    timeout = 90
}

# sites-enabled/default
post-auth {
    authnull_mfa
    if (fail) {
        update reply { Reply-Message := "MFA denied or not approved in time" }
        reject
    }
}
```

`post-auth`, not `authorize` — primary authentication must have already succeeded.

### The timeout problem — READ THIS, IT WILL BITE YOU

RADIUS is UDP with short timeouts. Push approval takes 10–30 seconds of human time. **Four**
separate timeouts will kill the request before the user reaches their phone — the original
three, plus the binary's own:

| Setting | Default | Must be |
|---|---|---|
| NAS (VPN/switch) retry timeout | ~5s, 3 retries | 60s+, 1 retry |
| FreeRADIUS `max_request_time` | 30s | 90s |
| `rlm_exec` `timeout` | 10s | 90s |
| `MFA_TIMEOUT_SEC` (the binary) | 60 | must stay **below** `rlm_exec timeout` |
| the binary's HTTP timeout | — | derived: `MFA_TIMEOUT_SEC + 15s`, not configurable |

The HTTP timeout is derived rather than fixed on purpose: a fixed value shorter than the
MFA wait abandons the request while the user is still reaching for their phone, and the
symptom is indistinguishable from a denial.

**Server side:** authn-service needs `TENANT_POLICY` set (its policy lookup, pointing at
authnull-service) and an MFA provider configured for the org. Also `ENCRYPTION_KEY` — a
missing one leaves the Okta config undecryptable, which falls back to a provider that is
not there, 500s, and surfaces as an Access-Reject with nothing obviously wrong. That cost
an afternoon.

**All of them, or the first test will look like a broken integration.** Duo's RADIUS proxy has
the identical constraint and documents raising the NAS timeout, so this is an accepted
pattern rather than a workaround — but it must be in the install guide, prominently.

The alternative is RADIUS `Access-Challenge` (reply immediately, user re-submits after
approving). Two round trips, no long block, but many VPN clients handle
challenge-response badly. Do not attempt it without discussing first.

---

## 7. Console screen — separate task, UI team

Genuinely new UI: none of the AD policy form's fields apply. It needs identity pickers
(reuse `listADGroups` / `listADUsers` / `listOU`), a device list, a calling-station list,
and a service-type selector. The JSON it must produce is the `radius` block in [§1a](#1a-the-policy-block).

**REVISED — the target JSON has changed, and most of that form would be inert.** A policy
only takes effect through `permissions.iam_users`, so what the screen must write today is:

```json
{ "permissions": { "iam_users": ["user@example.com"], "allowed": true },
  "policyFlow": "mfa_required" }
```

- **User picker** — required, and it must emit **email addresses**, not logon names.
- **Device list, calling-station list, service-type selector** — would write to the `radius`
  block, which nothing reads. Building them now ships controls that silently do nothing,
  which is worse than their absence. Also note `did.network_devices` has nothing populating
  it, so a device picker would be empty regardless.
- **Group-based scoping** — `permissions.iam_groups` is matched by the live query, but
  authn-service sends no groups for RADIUS, so it cannot fire either.

`CreatePolicyPage.jsx` has `{ value: "radius", disabled: true }` and `AdPoliciesPage.jsx`
filters on `policyType === "ad"`, so nothing is exposed yet. Full analysis in
`RADIUS-UI-PLAN.md`; parts of that plan assumed the `radius` block and are marked.

---

## 8. Verification

Unit, no infrastructure needed:

```sh
go build ./... && go test -vet=off ./internal/policy/... ./pkg/license/ ./internal/mfapush/
```

End to end, on a VM with FreeRADIUS:

1. `radtest` with a user in **no** policy → Access-Accept, no push *(default allow)*
2. Add a `matchAll` + `mfa_required` policy → push arrives, approve → Accept
3. Deny the push → Reject, promptly
4. Ignore the push → Reject after the timeout, no hung FreeRADIUS worker
5. Scope the policy to `clients: ["some-other-device"]` → no push, Accept
6. Scope to `serviceTypes: ["administrative"]`, send a Framed request → no push
7. Stop authnull-service → **Reject** (fail closed), not Accept
8. Expire the licence → RADIUS logins **keep working**; only the console goes read-only

Step 7 and step 8 are the two that matter most. Step 7 proves we fail closed; step 8 proves
licensing never touches the data plane.

### Results — run against the dev VM, real Okta push

Binary invoked directly against authn-service, policy inserted in `did.auth_policy_json`
and deleted afterwards.

| # | Scenario | Result |
|---|---|---|
| 1 | No policy covers the user | ✅ `ALLOW (no policy covers this login)`, exit 0, no push |
| 2 | Policy matches, approved on the phone | ✅ `ALLOW (approved)` after 19s, exit 0 |
| 3 | Policy matches, denied on the phone | ✅ `REJECT code=401 (denied)` after 8s, exit 1 |
| 4 | Backend unreachable, `FAIL_OPEN=false` | ✅ `FAIL-CLOSED`, exit 1 |
| 5 | Backend unreachable, `FAIL_OPEN=true` | ✅ `FAIL-OPEN`, exit 0 |
| 6 | Unknown user (`AUTHNULL\nosuchuser`) | ✅ exit 1 — cannot identify, so refuse |
| 7 | No `User-Name`; missing config file | ✅ exit 1 both |

**Steps 5 and 6 of the original list cannot pass** and were not run: device scoping and
service-type scoping are unreachable ([§11](#11-what-is-not-reached-and-what-it-would-take)).
Since no match means allow, such a policy does not block — it silently never fires.

**Step 8 (licence expiry) not re-run** after the retirement. It is now moot in this repo —
there is no RADIUS route left here to gate — but the equivalent question moved to
authn-service's V4 route and has not been checked there.

One trap worth recording: a hand-inserted test policy with a non-UUID `created_by` makes
the row unscannable (`PolicyModel.CreatedBy` is `uuid.UUID`), so the whole search 500s and
the login is refused with `could not evaluate policy`. The refusal is correct behaviour —
but the cause is bad test data, not the code.

---

## 9. Gotchas, collected

- **`NAS-Identifier` is frequently absent.** Always fall back to `NAS-IP-Address`, in the
  matcher, the prompt and the logs.
- **Three username shapes** — `jdoe`, `DOMAIN\jdoe`, `jdoe@realm`. `normalizePrincipal`
  handles all three; use it rather than writing string handling.
- **Accounting packets** (`Accounting-Request`) are not authentication. Ignore them.
- **Never gate a RADIUS path on the licence.** §3c.
- **Don't reintroduce `"radius"` into `supportedProtocols`** (`internal/policy/repo/ad_matcher.go`). §1.
- **Two policies can tie on `Priority`** (default 500). Sort is `Priority ASC`, then scope
  specificity, then policy id — deterministic rather than dependent on query order.
- ~~**The trailing `radius-server` is not in git.**~~ Resolved: `authnull0/radius-bridge`.

Added since:

- **JSONB `@>` containment is case-sensitive.** `'"User@x.com"'` does not match
  `'"user@x.com"'`. It is why identity cannot be narrowed further in SQL and is matched in
  Go instead, and why the UI must emit the address in the case the directory stores.
- **`SearchRadiusPolicy` vs `SearchRadiuspolicy`** — one capital letter, different policy
  shapes, and only the lower-case one runs. §2.
- **`repo.NormalizePrincipal` and friends are wrappers**
  (`internal/policy/repo/radius_exports.go`) that exist only to break an import cycle after
  the matcher moved to `internal/radius`. Do not add logic to them.
- **Never run `gofmt -w` on a pre-existing file in this repo.** Blobs are LF, `core.autocrlf`
  is true, so a rewrite re-terminates every line and produces a whole-file diff — 4,492
  lines on one file. Rebase with `-Xrenormalize` if it has already happened.
- **The binary sends the bare logon name**, so AD sync is a prerequisite. §0.
- **Service-Type never leaves the binary.** §11.

---

## 10. Files at a glance

As built, not as originally specified:

| Part | Files | Live? |
|---|---|---|
| 1 | `internal/radius/matcher{,_test}.go`, `internal/radius/decision.go`, `internal/policy/repo/radius_exports.go`, `internal/policy/dto/dto.go` (`type Radius`) | no — §11 |
| 2 | `internal/policy/repo/policyjson_repository.go` (`SearchRadiusPolicy`, `radius_search_test.go`) | no — §2 |
| 3 | *retired* — only `dto.EvaluateRadius{Request,Response}` remain, as `decision.go`'s input | no |
| 4 | `internal/mfapush/provider.go`, `internal/mfapush/context.go`, `internal/ad/src/repository/mfa_push_repository.go`, `radius_challenge_context_test.go` | no — §4 |
| 5 | `authnull0/radius-bridge`: `golangScript.go`, `bridge_test.go`, `radius-bridge.env.example`, `README.md` | **yes** |
| 6 | on-prem package docs — see [ONPREM-PACKAGING-PLAN.md](ONPREM-PACKAGING-PLAN.md) | — |

The live decision path is: **the binary (part 5) → authn-service → `SearchRadiuspolicy`.**
Parts 1–4 in this repo are all off it.

Related reading: [AD-MFA-FLOW.md](AD-MFA-FLOW.md) for the AD engine this mirrors,
[LICENSING-PLAN.md](LICENSING-PLAN.md) for how RADIUS is sold,
`RADIUS-UI-PLAN.md` for the console screen.

---

## 11. What is not reached, and what it would take

Parts 1, 2 and 4 are correct, tested, and called by nothing. This section exists so the next
person neither trusts them as live nor deletes them as dead.

**Why.** authn-service owns the RADIUS decision. Its `LookupPolicy` sends
`IAM.IAMUSers: [email]` and leaves every other scope block deliberately empty, so the
lookup that runs matches on `permissions.iam_users` and nothing else. The `radius` block,
the matcher's seven rules, `SearchRadiusPolicy` and the push-context case are all
downstream of a call that no longer happens.

**Consequences to be explicit about:**

- Device, calling-station and service-type scoping **cannot match**. Because no match means
  allow, such a policy does not fail loudly — it silently never fires, which is the failure
  direction §1d rule 3 was written to avoid.
- `Service-Type` is dropped at the service boundary: `DoAuthenticationV4RequestDTO` has no
  field for it. The alias table in §1d rule 4 has nothing to normalise.
- Group scoping cannot fire either — the live query reads `permissions.iam_groups`, but
  authn-service sends no groups for RADIUS.

**To make it reach, in order:**

1. Add `serviceType` (and device fields) to `DoAuthenticationV4RequestDTO` in authn-service,
   and have the binary send them — it already parses and logs them.
2. Populate the corresponding hints in `LookupPolicy`'s `CallPolicySearch` payload.
3. Either extend the live `SearchRadiuspolicy` to read the `radius` block, or route
   `credentialType: "RADIUS"` to `SearchRadiusPolicy` + `matchRadiusPolicy`, which already
   implement all of it.
4. Only then build the device and service-type controls in the console (§7).

Both gaps are recorded on PR #20 and are not ours to decide alone: they change authn-service
and the shape of the UI.
