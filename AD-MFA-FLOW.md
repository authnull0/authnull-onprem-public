# AD MFA — end-to-end flow

How an Active Directory MFA policy gets created, and what happens on every AD
authentication once it exists. Written against the code in `internal/policy` and
`internal/ad` as of migrations 001–009.

Referenced by function name rather than line number throughout, because line
numbers rot and function names don't.

Companion document: [AD-MFA-ARCHITECTURE.md](AD-MFA-ARCHITECTURE.md) — components,
storage, trust boundaries and failure modes. This one is the sequences.

---

## 0. The two halves, and a naming trap

The feature splits cleanly:

- **Authoring** — an admin creates a policy row in `did.auth_policy_json`.
- **Enforcement** — the DC sensor asks the backend what to do about one live
  authentication, and the backend answers from those rows.

**The naming trap, up front:** there are two log tables with almost the same name.

| Table | Owner | Contents |
|---|---|---|
| `did.auth_log` (singular) | `internal/ad` | raw authentication events batched up by the sensor |
| `did.auth_logs` (plural) | `internal/policy` | decisions written by `EvaluateAuth` |

Neither is derived from the other. `SimulateADPolicy` replays the **singular**
one; the logs screen reads the **plural** one. Getting these confused is the
easiest mistake to make in this subsystem.

---

## 1. Policy creation

Three entry paths, all converging on `did.auth_policy_json`.

### 1a. Manual create — the main path

```
[optional] POST /admin/v1/policy/json/previewImpact
             └─ PolicyJSONRepo.PreviewImpact          → "applies to N users" (capped 50k)

POST /admin/v1/policy/json/createPolicy
  └─ PolicyJSONHandler.CreateJSONPolicy
      └─ PolicyJSONService.CreateJSONPolicy
          ├─ buildCandidatePolicyForConflictCheck
          ├─ PolicyJSONRepo.DetectPolicyConflicts
          │    ├─ hard  → refuse unless request sets force:true
          │    └─ soft  → returned as a warning alongside success
          └─ PolicyJSONRepo.CreateJSONPolicy
               ├─ normalise: authTypes→["ad"], policyMode→"online",
               │             mfaPromptTemplate→default, resolve domain from adId
               ├─ INSERT status='Approved', version=1, parent_id=id
               └─ ApproveADPolicy / ApproveGroupADPolicy  (side effects, inline)
```

`DetectPolicyConflicts` treats only `matchAll` vs `matchAll` on the same domain as
a hard conflict. User, group and baseline overlaps are soft warnings — priority
resolves them at decision time.

**Note:** this path inserts `status='Approved'` directly. It never enters the
approval queue; `approvePolicy` exists for the template path below.

### 1b. Baseline templates

`POST /policy/json/createBaselinePolicy` → `PolicyJSONRepo.CreateBaselinePolicy`,
idempotent per (template, domain):

| Template | Scope | Priority | MFA |
|---|---|---|---|
| `privileged_access` | Domain Admins, Enterprise Admins | 100 | yes |
| `baseline` | matchAll | 900 | yes |

Two templates were retired. `service_account` set `matchAll: false` and named no
users, groups or OUs — and since those four fields are the whole of
`matchADPrincipal`, it built a policy that could never fire, under a name telling
the admin their service accounts were covered. `remote_access` produced
byte-identical PolicyJSON to `baseline` and, being a second `matchAll` on one
domain, hard-conflicted with it; it is now an accepted alias resolving to
`baseline`. Migration 010 suspends any already-created policy that cannot match
anyone, matching on shape rather than template name so discovery-created rows
are untouched.

The definitions live in `ad_baseline_templates.go`, deliberately free of the
database: `TestEveryTemplateProducesAPolicyThatCanMatchSomebody` walks every
template and fails if one names nothing, which is the check that was missing.

Group membership on `privileged_access` is matched **by name**, so a localized or
renamed directory (`Domänen-Admins`) will not match it. Resolving built-ins by
their well-known SID is the fix and needs the group sync to carry the SID.

Created `status='Pending'`, `is_baseline=true`. Reviewed via
`listPendingBaselines`, then `approveAllBaselines` flips them in one transaction
with one audit line per policy.

### 1c. Discovery

```
POST /policy/json/discoverADPolicies
  └─ DiscoverADPolicies
      ├─ walk did.ad_groups for the AD
      ├─ classifyADGroup:
      │    knownPrivilegedGroups          → privileged, recommend mfa_required
      │    svc-/svc_/sa-/service- prefix  → service,    recommend allow
      │    otherwise                      → standard,   recommend mfa_required
      ├─ member count + 50-name sample
      ├─ existing-coverage check
      └─ back-fill is_privileged_hint, member_count on the group row

POST /policy/json/applyDiscoveredPolicies
  └─ ApplyDiscoveredPolicies
      └─ INSERT status='Approved', is_baseline=true, discovery_source='ad_group',
         priority 100/300/900 by class, idempotent per group
```

Discovery-created policies carry `ad.adId` and **no** `ad.domain`. The candidate
query scopes on either, so both shapes match — see §2.3.

### 1d. Approve / revoke side effects

`POST /policy/json/approvePolicy` → `ApprovePolicyJSON` sets the status, then
dispatches on `PolicyType`:

- **`ApproveADPolicy`** — resolves IAM users × AD users, issues a shared AD
  credential per pair, writes `policy_credential_mapping`. The credential API
  calls are largely no-ops (see the DID-removal comments).
- **`ApproveADPolicyAgentless`** — the gateway path: one `enrolled_set_changes`
  row with `action='add'` per logoname, then ad-service
  `UpdateMfaFlagADUsers(mfa_flag=1)`.

Revoke mirrors both (`action='remove'`, `mfa_flag=0`). The agentless gateway polls
`GetEnrolledSetDelta` with a `sinceUnixMs` cursor and receives collapsed add/remove
sets — last action per account wins.

### 1e. Lifecycle

- `UpdateJSONPolicy` — writes a **new row** and chains it through `parent_id`;
  version history rather than in-place edit.
- `PolicyAction` — two modes:
  - `actionType: "status"` → Approved / Suspended / Deleted, firing the same
    approve/revoke side effects.
  - `actionType: "action"` → the coarse Allow/Deny toggle. Writes `policyFlow`
    **and** `permissions.allowed`, and clears `mfaConfig.required` so the row
    asserts one action rather than three.

---

## 2. Enforcement — one authentication, start to finish

### Phase 0 — Setup

1. **Register the directory.** `POST /ad/addDomain` writes
   `did.active_directories`. Two name columns, and the difference matters:
   - `domain_name` — the AD FQDN the sensor reports (`corp.lab`)
   - `directory_name` — the label the admin typed on the form

   Plus `enforcement_mode` and `fallback_action`, both passed through sanitisers
   so the DB and the sensor cannot disagree.

2. **Sensor config.** `GET /ad/downloadSensorConfig?adId&orgId&tenantId` →
   `buildSensorConfig` emits `sensor.yml`:

   ```yaml
   mode: "enforce"                       # ALWAYS. See below.
   fallback_action: "<allow|deny>"
   mfa_timeout_seconds: 60
   allow_deduplication_window_ms: 300000
   ad_sync_interval_minutes: 10
   ```

   `mode: "enforce"` does **not** mean "block logins". To the sensor it means
   *ask Authnull on every authentication and apply the verdict*. Whether the
   domain challenges anyone is decided server-side from
   `active_directories.enforcement_mode`, so an admin can move a domain between
   monitoring and enforcing from the dashboard and have it take effect on the
   next authentication — no re-download, no service restart on every DC.
   Setting `mode: "monitor"` locally is an emergency kill switch: the sensor
   stops calling the backend entirely and allows everything.

3. **Install on each DC.** Directory sync runs every 10 min via
   `POST /ad/userSync` → `ad_users`, `ad_groups`, `ad_user_group_mappings`,
   `ad_ous`.

4. **Enroll users.** `POST /ad/sendEnrollmentEmail` → token → user opens link →
   `GET /ad/getEnrollmentDetails` → mobile app registers → `RegisterDevice`
   stores push token and public key in the shared device registry, reusing the
   device row if that phone already enrolled for platform login. Alternatively
   `SetMFAProvider` points the org at Duo or Okta, which needs no device row.

5. **Policies exist** (§1).

### Phase 1 — The decision

User authenticates against a DC (Kerberos AS-REQ/TGS-REQ, NTLM event 4776, or
LDAP bind). The sensor intercepts via WFP and calls:

```
POST /api/v1/policyService/EvaluateAuth      ← UNAUTHENTICATED (see §4)
  └─ AuthDecisionHandler.EvaluateAuth
      └─ AuthDecisionService.EvaluateAuth
```

```
 a. resolveTenantDB(orgId)
 b. domainEnforcementMode(db, domain)
      lower(domain_name) lookup; anything not clearly "enforce" → monitor
      (a lookup failure costs visibility, never availability)
 c. IsUserBlocked  → did.blocked_principals → block  [logged]
 d. GetEffectivePolicy
 e. no candidate matched:
      near miss (a policy targets them, none covers this context)
                                      → allow  [logged]  reason on the row
      nothing targets them            → allow            (not logged: most of a
                                                          directory, every ticket)
 f. policyActionOf(policy)  → allow | block | mfa_required
 g. mfa_required AND mode != monitor AND !SuppressMFA → SendMFAChallenge
 h. attach mfa_session_window_ms, mfa_frequency_scope, protected_spns,
    policy_mode, binding_message (rendered)
 i. applyEnforcementMode  — monitor: verdict→allow, real verdict kept in
    would_have_been, challenge_id cleared
 j. LogAuthDecision  → did.auth_logs
```

Step **g** guards on monitor mode *before* sending, not after. `applyEnforcementMode`
runs later and cannot unsend a push notification.

#### 2.3 Inside `GetEffectivePolicy`

```
buildADAuthContext
  ├─ resolveADDomain    — lower(domain_name) OR lower(directory_name)
  ├─ resolveADPrincipal — lower(username) OR lower(logoname)
  │                       OR lower(split_part(logoname,'@',1))
  │                       ambiguous across directories → left unresolved
  ├─ resolveGroupClosure — recursive CTE over did.ad_group_nesting,
  │                        depth-capped, falls back to direct memberships
  └─ resolveOUs         — ad_user_ou_mappings AND the DN on ad_users.cn

loadADCandidates          — ONE query:
    status='Approved'
    AND policy_json ? 'ad'
    AND (lower(ad->>'domain') = :domain OR ad->>'adId' = :adId)
    AND <IsAllowedPolicies tenant filter>

sort: scope specificity (user > group > OU > baseline)
      → priority ASC → created_at ASC

for each candidate: matchADPolicy — first full match wins
```

`matchADPolicy` (`internal/policy/repo/ad_matcher.go`) is pure and DB-free. Its
predicates split in two, and the split is load-bearing:

- **Identity** — does this policy target this principal? (`users` / `groups` /
  `ous` / `matchAll`)
- **Context** — does it cover this login? (`authTypes` / protocol / `sources` /
  `destinations`)

A policy needs both. Keeping them separate is what lets the engine distinguish
*no policy covers this user* (→ allow) from *policies cover this user but not
from here* (→ block). Collapsing them would make every user with any policy
deniable the moment one context predicate missed.

Matching rules worth knowing:

| Dimension | Rule |
|---|---|
| identity | case-insensitive; accepts bare names, `DOMAIN\user`, UPNs, and full DNs |
| `authTypes` | empty means `["ad"]`, not "all providers" |
| protocol | empty `allowed` = all supported; `blocked` wins; ntlm ⇄ smb interchangeable; an event with **no** protocol is not filtered |
| `sources` | empty = any source; exact IP, CIDR, or `*`; a source-scoped policy does not match an event with no source IP |
| `destinations` | **empty = every destination**; `*`, `cifs/*`, `cifs/host01`, or a bare `host01` (any service class on that host) |

### Phase 2 — The challenge

```
SendMFAChallenge(req, promptTemplate)
  ├─ LookupADUserEmail       (domain_name OR directory_name, case-insensitive)
  ├─ renderMfaPrompt         $username $user $domain $source $destination $protocol
  └─ adSvc.InitiateMFAChallenge          (in-process call into internal/ad)
       ├─ GetProviderForOrg → expo | duo | okta
       ├─ expo: DeviceForEmail → push token.  duo/okta: by username
       ├─ INSERT did.ad_mfa_challenges  status='pending', expires_at
       ├─ prov.Initiate(...)            fire-and-forget; a failed push is logged
       │                                and the challenge left to expire
       └─ return challenge id (bigserial)

sensor holds the auth, polls POST /ad/GetMFAChallenge  up to mfa_timeout_seconds

user taps Approve/Deny
  └─ POST /ad/RespondMFAChallenge
      ├─ load challenge, resolve the device it was pushed to
      ├─ VerifyResponse — signature over (challengeId, approved, signedAt)
      │                   against the device public key.  Challenge ids are
      │                   sequential, so without this they are enumerable.
      ├─ UPDATE status = approved|denied, responded_at
      └─ recordMFAOutcomeOnDecision  → auth_logs.mfa_outcome

GetMFAChallenge also resolves two other ways:
  ├─ duo/okta still pending → poll provider, sync status → recordMFAOutcome
  └─ past TTL              → status='expired'            → recordMFAOutcome

sensor: approved → allow the auth
        denied / expired / timeout → apply fallback_action
```

`recordMFAOutcomeOnDecision` is a raw UPDATE inside `internal/ad`, not a call
into the policy repo: `internal/policy` already imports the AD service, so the
reverse would be an import cycle. Both tables live in the same org database —
policy and ad resolve it from the same `organizations` row — so it is a local
write. It only fills an empty `mfa_outcome`, so a late provider poll cannot
overwrite the answer the user gave.

### Phase 3 — Telemetry and response

| Path | Purpose |
|---|---|
| `POST /ad/ingestAuthEvents` | sensor batches raw events → `did.auth_log` |
| `POST /policy/auth/listAuthDecisions` | the decision log |
| `POST /ad/getAuthLog`, `/ad/getUserAuthLog` | raw event views |
| `POST /policy/ad/mfaCoverage` | which policy applies to a page of users — same matcher, never challenges |
| `POST /policy/ad/simulate` | replays `did.auth_log` through the current policy set |
| `POST /ad/blockPrincipal` | → `did.blocked_principals` → next decision blocks at step (c) |

---

## 3. Reference

### Actions

Three, and every one does something real:

| Action | Aliases accepted on read | Effect |
|---|---|---|
| `allow` | — | sensor lets the auth through |
| `block` | `deny` | sensor denies |
| `mfa_required` | `mfa` | challenge issued |

`notify` was removed (migration 008): nothing implemented it, and shipping a
non-allow verdict the sensor might read as a refusal was a lockout risk. Stored
`policyFlow: 'notify'` values are rewritten to `allow` — the same access outcome
notify always produced.

`policyActionOf` resolves the action from three fields, in order — `policyFlow`,
then `mfaConfig.required`, then `permissions.allowed` — because different creation
paths write different ones. It also reports whether the action was genuinely read
or fell back because the policy was unreadable; `EvaluateAuth` logs the second
case rather than recording it as a normal allow.

### Tables

| Table | Role |
|---|---|
| `did.auth_policy_json` | policies (`policy_json` jsonb, `priority`, `is_baseline`, `discovery_source`) |
| `did.auth_logs` | decisions: `decision`, `applied_decision`, `enforcement_mode`, `mfa_outcome`, `ad_challenge_id`, `match_reason` |
| `did.auth_log` | raw sensor events |
| `did.ad_mfa_challenges` | one row per challenge, `status` pending/approved/denied/expired |
| `did.active_directories` | `domain_name` (FQDN), `directory_name` (label), `enforcement_mode`, `fallback_action` |
| `did.ad_users`, `ad_groups`, `ad_user_group_mappings`, `ad_group_nesting`, `ad_ous`, `ad_user_ou_mappings` | directory shadow |
| `did.blocked_principals` | lockouts, checked first on every decision |
| `did.enrolled_set_changes` | add/remove deltas for the agentless gateway |

### Migrations

| # | Adds |
|---|---|
| 001 | `enrolled_set_changes` |
| 002 | `priority`, `is_baseline`, `policy_scope`, `policy_template_type` |
| 003 | decision columns on `auth_logs` |
| 004 | backfill `authTypes`, `policyMode` |
| 005 | AD group discovery columns |
| 006 | `blocked_principals` |
| 007 | `ad_group_nesting`, case-insensitive identity indexes, candidate-query indexes |
| 008 | retire the `notify` action |
| 009 | `enforcement_mode`, `applied_decision`, `ad_challenge_id` on `auth_logs` |
| 010 | suspend baseline policies that cannot match anyone |

---

## 4. Known gaps

Ordered roughly by how much they matter.

**Policy engine**

- **No action-group ordering.** Silverfort evaluates Allow as an exception list
  ahead of Deny and MFA. Here a single winner is picked by scope specificity,
  so a broad allow exception loses to a narrow MFA policy. `priority` is only a
  tiebreaker *within* a scope class, so it cannot express what an admin means by
  dragging a row up the list.
- **No enable/disable toggle.** The only lever is `status`, which entangles
  rollback with the approval workflow.
- **Risk-based policies are not wired, but the scorer exists.**
  `mfaConfig.stepUpOnRisk` and `riskThreshold` are declared and read by nothing.
  A real risk engine does exist in `internal/mfapush/risk.go` — new source IP,
  new country, impossible travel, off-hours, recent denial, push velocity —
  scored over `did.mfa_push_activity`. It ships disabled behind
  `MFA_PUSH_RISK_ENABLED`, and it runs *inside* `InitiateMFAChallenge`, i.e.
  after the policy has already decided. Making risk-based policies real means
  moving the score ahead of the decision and feeding it to the matcher, not
  building a scorer. See
  [AD-MFA-ARCHITECTURE.md](AD-MFA-ARCHITECTURE.md#9-risk-scoring-exists-on-the-wrong-side-of-the-decision).
- **Dead exclusion fields**: `mfaConfig.bypassGroups`, `bypassOus`,
  `ad.excludeServiceAccounts`.
- **Schedule and geolocation** filters are implemented (`TimeBasedFilter`,
  `LocationBasedFilter`) but never populated on the AD path, and
  `TimeBasedFilter` compares start/end for equality — admin-search semantics, not
  runtime semantics.
- **`CreateJSONPolicy` resolves `ad.domain` from `directory_name`** (the admin's
  label) when only `adId` was sent. Harmless today because the candidate query
  also matches on `adId`, but the stored domain is the wrong string. Should select
  `domain_name` with `directory_name` as fallback.

**Data**

- **Nested groups need the sync.** `resolveGroupClosure` walks
  `did.ad_group_nesting` correctly, but nothing populates it yet, so group
  resolution is still direct-membership only. `ad_groups.parent_id` is **not**
  the edge — it holds the DN container (`CN=Users`), and using it would invent
  memberships. The transitive data comes from AD's `tokenGroups`.
- **`ad.sources` has no writer.** The matcher supports it; no UI or API path
  sets it.
- **Identity key inconsistency.** Enforcement matches `ad_users.username`;
  `PreviewImpact` and `DiscoverADPolicies` use `logoname`. The "applies to N
  users" count can disagree with what enforces.

**MFA**

- **Allowed methods are not enforced.** `mfaConfig.methods` is stored and never
  reaches the provider. `mfapush.InitiateRequest` has no factor field and
  `Provider` is a two-method interface; Expo cannot restrict (one device, one
  push) and Duo/Okta need their factor APIs.
- **MFA frequency is enforced client-side.** `mfa_session_window_ms` is handed to
  the sensor, so the cache dies on restart and two DCs in one domain will each
  prompt the same user. Belongs in a server-side grants table keyed by the
  policy's `accordingTo` scope.
- **No per-policy fail-open/fail-closed.** A push provider outage yields a
  pending challenge that expires and lands on the domain's `fallback_action`.
  That decision belongs to the policy author, not to a domain-wide default.
- **No "user cannot be challenged" branch.** `LookupADUserEmail` failing (no
  email on file) fails the whole evaluation.

**Observability**

- **Hit counters.** `policy_invokation_count` is never incremented by
  `EvaluateAuth`, so "applied N times in the last 7 days" has no source. Cheapest
  fix is to derive it from `auth_logs` with an index on `(policy_id, timestamp)`.
- **No policy-set generation counter**, so there is no basis for an
  "All Policies are Synced" indicator.
- **Allows are not logged.** A decision with no matching policy writes nothing to
  `auth_logs`; the raw event still lands in `auth_log`.
- **`match_reason` is one coarse token** (`user-specific` / `group` / `ou` /
  `baseline`). `matchADPolicy` computes a per-predicate `SkipReason` that is
  currently only logged — a dry-run endpoint could return the full trace.
- Logs UI has no export, column config, saved filters, expandable detail, source
  hostname resolution, or source/destination filters.

**Security**

- **`/api/v1/policyService/EvaluateAuth` is unauthenticated.** The sensor has no
  credential: `buildSensorConfig` emits no token and the client sets no
  Authorization header. That endpoint is a policy oracle, a push trigger, and an
  unbounded write into `auth_logs`. Fixing it properly needs a machine identity
  for the gateway plus a matching change in `authnull0/windows-endpoint`.
- ~~**Default-deny is not configurable.**~~ RESOLVED by removing it. The
  `user_enrolled_no_match → block` whitelist is retired: a near miss now allows,
  with the reason recorded on the decision row. A tenant that wants uncovered
  contexts denied authors a matchAll `block` policy on the domain — per-domain,
  visible in the console, and reviewable, which the sentinel never was. See
  `AD-WHITELIST-RETIREMENT.md`.

  A per-domain `default_action` setting is no longer needed for this; the policy
  set expresses it.
- **No break-glass account concept.**
