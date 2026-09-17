# AD MFA — architecture

Components, boundaries, and who decides what. The sequences live in
[AD-MFA-FLOW.md](AD-MFA-FLOW.md); this is the shape underneath them.

---

## 1. The shape in one paragraph

A C# sensor on every domain controller intercepts Kerberos, NTLM and LDAP
authentication and asks a Go monolith what to do about each one. The monolith
resolves the principal against a per-tenant shadow copy of the directory, picks a
policy, and answers `allow` / `block` / `mfa_required`. When the answer is a
challenge it hands off to a shared push subsystem — the same one the console
login uses — which reaches the user's phone through one of several providers and
waits for a signed response. **Every call is inbound to the monolith:** nothing
reaches back into the domain controller, and nothing but the sensor and the phone
initiate anything.

---

## 2. Components

| Component | Runs on | Repo | Responsibility |
|---|---|---|---|
| **DC Sensor** | every domain controller | `authnull0/windows-endpoint` (C#) | WFP interception, calls `EvaluateAuth`, polls for the challenge verdict, applies it, batches raw events back |
| **authnull-service** | server / container | this repo (Go) | everything below |
| ├ `internal/policy` | — | — | the decision engine: matcher, policy CRUD, decision log |
| ├ `internal/ad` | — | — | directory registry, user sync, challenge lifecycle, raw auth-log ingest, lockouts |
| ├ `internal/mfapush` | — | — | shared push subsystem: devices, signing, providers, activity, risk |
| └ `internal/deviceapi` | — | — | authenticator self-service (enrol, list, revoke) |
| **Authenticator app** | user's phone | mobile repo | enrolment, receives push, returns a **signed** approve/deny |
| **Admin console** | browser | React repo | policy authoring, logs, directory management |
| **Postgres** | — | — | one common DB plus one database per organisation |
| **Redis** | — | — | admin session store |
| **Push providers** | external | — | Expo, FCM, AuthNull, Duo, Okta, Azure AD |

`internal/policy` and `internal/ad` are separate modules inside **one binary**,
not separate services. They communicate by in-process function call and by
sharing the same org database. `internal/policy` imports `internal/ad`; the
reverse would be an import cycle, which is why the MFA-outcome write-back is a
raw SQL statement on the AD side rather than a call into the policy repo.

---

## 3. Topology

```
   ┌──────────────────────┐        ┌───────────────────────┐
   │  Domain Controller   │        │  User's phone         │
   │  ┌────────────────┐  │        │  ┌─────────────────┐  │
   │  │  DC Sensor     │  │        │  │ Authenticator   │  │
   │  └───────┬────────┘  │        │  └────────┬────────┘  │
   └──────────┼───────────┘        └───────────┼───────────┘
              │                                │
              │ EvaluateAuth                   │ RegisterDevice
              │ GetMFAChallenge                │ RespondMFAChallenge
              │ UserSync                       │ (signed)
              │ IngestAuthEvents               │
              ▼                                ▼
   ┌───────────────────────────────────────────────────────┐
   │                   authnull-service                    │
   │   policy ── ad ── mfapush ── deviceapi ── (others)    │
   └───────┬─────────────────────────────┬─────────────────┘
           │                             │
           ▼                             ▼
   ┌───────────────┐            ┌──────────────────┐
   │ Postgres      │            │ Push providers   │
   │ common + org  │            │ Expo/FCM/Duo/... │
   └───────────────┘            └──────────────────┘
                    ▲
                    │ X-Authorization
           ┌────────┴────────┐
           │  Admin console  │
           └─────────────────┘
```

Direction matters: the backend **never** connects to a domain controller. The
sensor polls. That is what makes the deployment survivable behind a firewall, and
it is also why the enforcement switch has to live server-side (§6) — there is no
channel to push a config change down.

---

## 4. Storage

**Two tiers.** A common database named by `DB_NAME` holds `did.organizations`,
which maps an org id to its own database name. Every tenant-specific table lives
in that per-org database, under schema `did`. Both `internal/policy` and
`internal/ad` resolve the same org database from the same `organizations` row, so
they share one physical database and can write across module boundaries.

### Table ownership

| Table | Written by | Notes |
|---|---|---|
| `auth_policy_json` | policy | the policies themselves |
| `auth_logs` | policy | **decisions** — one row per `EvaluateAuth` verdict |
| `auth_log` | ad | **raw events** — batched from the sensor |
| `active_directories` | ad | `domain_name` = FQDN, `directory_name` = admin's label, `enforcement_mode`, `fallback_action` |
| `ad_users`, `ad_groups`, `ad_user_group_mappings`, `ad_ous`, `ad_user_ou_mappings` | ad | directory shadow, refreshed every 10 min |
| `ad_group_nesting` | *nobody yet* | transitive group edges; the matcher reads it, the sync does not fill it |
| `ad_mfa_challenges` | ad | one row per challenge |
| `blocked_principals` | ad | lockouts, checked first on every decision |
| `enrolled_set_changes` | policy | add/remove deltas for the agentless gateway |
| `mfa_devices`, `mfa_device_identities`, `mfa_device_enrollments` | mfapush | shared with console login |
| `mfa_push_activity` | mfapush | activity mirror; risk scoring reads it |
| `ad_mfa_provider_config` | mfapush | per-org provider selection |

**`auth_log` and `auth_logs` are different tables.** Singular is raw sensor
traffic and is what `SimulateADPolicy` replays; plural is decisions and is what
the logs screen reads. Neither derives from the other. This is the easiest
mistake to make in the subsystem.

---

## 5. The decision path

The hot path, once per authentication:

```
EvaluateAuth
  ├─ resolveTenantDB(orgId)                        common DB → org DB
  ├─ domainEnforcementMode(domain)                 1 query
  ├─ IsUserBlocked(principal, domain)              1 query
  └─ GetEffectivePolicy
       ├─ resolveADDomain                          1 query
       ├─ resolveADPrincipal                       1 query
       ├─ resolveGroupClosure  (recursive CTE)     1 query
       ├─ resolveOUs                               1 query
       └─ loadADCandidates                         1 query
            └─ matchADPolicy per candidate         in memory, no I/O
  └─ LogAuthDecision                               1 insert
```

Roughly **seven queries and one insert** per decision. Nothing is cached: no
policy set, no group membership, no tenant config. The matching itself is pure Go
over decoded structs, so the cost is entirely round trips.

The budget is set by the sensor, not the backend: `mfa_timeout_seconds: 60` for a
challenge, and a circuit breaker that opens after **5** consecutive API failures
and sends every subsequent authentication to `fallback_action`.

**Selection is a two-stage predicate.** Identity predicates (`users`, `groups`,
`ous`, `matchAll`) ask whether a policy targets this principal; context
predicates (`authTypes`, protocol, `sources`, `destinations`) ask whether it
covers this login. A policy needs both. The split is what lets the engine tell
*no policy covers this user* (allow) from *policies cover this user, but not from
here* (block) — and since the second answer locks someone out, it must never be
reachable by a policy that was never about that user.

Candidate order is scope specificity → priority → age. **Not** Silverfort's
action-group order (Allow evaluated as an exception list ahead of Deny and MFA);
that is the next planned change and is what the console's policy list will
eventually reflect.

---

## 6. Four things decide whether anyone is challenged

This is the part most worth understanding, because the layers are easy to confuse.

| Layer | Where it lives | What it controls | Changes take effect |
|---|---|---|---|
| `mode` in `sensor.yml` | file on each DC | whether the sensor asks at all. Always `"enforce"`, meaning *ask and apply*. Setting `monitor` is a local kill switch that allows everything | file edit + restart |
| `enforcement_mode` | `active_directories` row | whether the domain actually challenges or blocks. `monitor` evaluates and logs, returns allow | next authentication |
| `fallback_action` | `sensor.yml` | what happens when the backend is **unreachable** | file edit + restart |
| policy action | `auth_policy_json` | what a matching policy does | next authentication |

The critical one: **`mode: "enforce"` in sensor.yml does not mean "block"**. It
means "ask the backend". The real monitor/enforce switch is the domain row, which
is read fresh on every decision — that is deliberate, because there is no channel
to push config to a DC (§3), so the toggle has to be somewhere the sensor already
looks.

`policy_json.policyMode` (`online`/`monitor`/`offline`) is returned to the sensor
but **acted on by nothing in this repo**. The console currently offers it as a
per-policy control; that is the subject of a UI ticket.

---

## 7. Trust boundaries

| Surface | Authentication |
|---|---|
| Admin console → `/api/v1/**` | `X-Authorization` header, Redis session or the Authnz service |
| Sensor → `/api/v1/policyService/EvaluateAuth` | **none** |
| Sensor → `/ad/**` (UserSync, challenges, ingest) | **none** |
| Phone → `RespondMFAChallenge` | request signed with the device's private key, verified against the enrolled public key |
| Backend → push providers | provider credentials from `ad_mfa_provider_config` |

**The sensor surface is unauthenticated.** `buildSensorConfig` emits no token, API
key or client secret, and the sensor sets no `Authorization` header — so every
route it uses is mounted without middleware. `EvaluateAuth` in particular is a
policy oracle (enumerate any principal's coverage), a push trigger, and an
unbounded write into `auth_logs`.

The one place that *is* properly authenticated is the phone's response: challenge
ids are sequential and would otherwise be trivially enumerable, so
`RespondMFAChallenge` requires a signature over `(challengeId, approved,
signedAt)` verified against the device's enrolled key.

Closing the sensor gap needs a machine identity for the gateway plus a matching
change in `authnull0/windows-endpoint`.

---

## 8. The push subsystem is shared

`internal/mfapush` serves **two flows**, distinguished by a `Flow` value:

- `FlowAD` — domain authentication (this feature)
- `FlowPlatform` — console and self-service login

They share the device registry, so a phone enrolled for console login is reused
for AD challenges: one device row, one push token, one revocation. They also
share signing, the activity mirror, geo lookup, provider config and the
enrolment-email path.

Providers behind one two-method interface (`Initiate`, `Status`): Expo, FCM,
AuthNull, Duo, Okta, Azure AD. Expo-family providers return `pending` and are
resolved by the app calling `RespondMFAChallenge`; Duo and Okta are resolved by
polling the provider from `GetMFAChallenge`.

---

## 9. Risk scoring exists, on the wrong side of the decision

**Correcting something I said earlier in this work:** there *is* a risk engine —
`internal/mfapush/risk.go` — with real rules scored over `mfa_push_activity`:
first activity, new source IP, new country, impossible travel, off-hours, recent
denial, push velocity, geo unavailable. It returns `low` / `medium` / `high` plus
the reasons that fired.

Two things about it:

1. **It ships disabled**, behind `MFA_PUSH_RISK_ENABLED`, because every rule is
   relative to a user's own history and the scores are noise on an empty table.
2. **It runs after the decision.** Scoring happens inside `InitiateMFAChallenge`
   — the policy has already resolved to `mfa_required` — and the verdict is
   attached to the activity record for the app to display. `EvaluateAuth` never
   sees it, and `mfaConfig.stepUpOnRisk` / `riskThreshold` are still read by
   nothing.

So risk-based policies are **not** blocked on building a risk engine, as I said
earlier. They are blocked on moving the score to before the decision and feeding
it into the matcher — a smaller job than starting from nothing, though it needs
the activity table warm first.

---

## 10. Failure modes

| What fails | Result |
|---|---|
| Backend unreachable | sensor circuit breaker opens after 5 failures → every auth takes `fallback_action` |
| Org DB unreachable | `EvaluateAuth` 500s → counts toward the breaker |
| Domain lookup fails / unknown domain | defaults to **monitor** — a lookup problem costs visibility, never availability |
| Policy JSON unreadable | treated as **allow**, logged as a distinct event so it is not mistaken for a policy that says allow |
| `ad_group_nesting` absent | group closure falls back to direct memberships, latched per org so it costs one failed query, not one per auth |
| Push provider down | `Initiate` is fire-and-forget; the challenge expires at TTL → sensor applies `fallback_action` |
| User has no enrolled device | challenge creation returns `no_device_registered`; the evaluation errors |
| User has no email on file | `LookupADUserEmail` fails → the whole evaluation errors |

The last two are the weakest links: a user who cannot be challenged fails the
*decision* rather than taking an explicit "cannot challenge" branch, which means
one unenrolled user produces a 500 that counts toward the circuit breaker.

---

## 11. Background work

| Job | Trigger | Notes |
|---|---|---|
| Directory sync | sensor, every 10 min | pushes users/groups/OUs to `UserSync` |
| Activity sweeper | cron in `main`, `MFA_PUSH_SWEEP_ENABLED` | retention on `mfa_push_activity`, default 90 days |
| Org provisioning | cron in `main` | tenant database creation |
| Enrolled-set delta | polled by the agentless gateway | cursor-based, collapses add/remove |

**No leader election.** The sweeper is gated off by default precisely because
every replica would otherwise run it. The jobs are idempotent, so a double-run is
wasted work rather than corruption — but it is work against a table that live
authentication also writes to.

---

## 12. Extension points

- **New protocol** — add to `supportedProtocols` in `ad_matcher.go`; add an
  equivalence in `protocolEquivalents` if the sensor reports it under another name.
- **New auth type** — `authTypes` is already a live predicate; what is missing is
  an event source that routes non-AD authentications into `EvaluateAuth`.
- **New action** — one canonical name in `canonicalPolicyAction`, one case in the
  decision switch. A test asserts every value the first can produce is handled by
  the second.
- **New push provider** — implement `Initiate` / `Status`, register in
  `NewProvider`, add the config shape.
- **New policy template** — add to `ad_baseline_templates.go`; a test walks every
  template and fails if it produces a policy that can never match.

---

## 13. Architectural debt

Roughly by consequence:

1. **The sensor surface is unauthenticated.** Needs a gateway machine identity and
   a coordinated sensor change.
2. **No caching on the decision path.** Seven queries per authentication, no
   policy-set cache, no group cache, no tenant-config cache. The natural design is
   a per-tenant compiled policy set invalidated by a generation counter.
3. **`ad_group_nesting` has no writer.** The engine resolves transitively; the sync
   supplies only direct memberships, so nested groups silently under-match. The
   edge is available on each group's own `memberOf`.
4. **Two creation paths for one object.** Templates create `Pending` and go through
   approval; discovery creates `Approved` directly, with a different priority
   scheme. Most of the inconsistencies found in this work were on that seam.
5. **Silverfort-style action ordering is not implemented.** Specificity outranks
   priority, so a broad exception cannot override a narrow rule. Unreachable today
   only because the console cannot set `sources`; reachable the day it can.
6. **`policy_scope` and `policy_template_type` hold the same value.** One is
   redundant, and `is_baseline` is a third way to record provenance alongside
   `generated_by` and `discovery_source`.
7. **Identity keys disagree.** Enforcement matches `ad_users.username`;
   `PreviewImpact` and discovery use `logoname`. The impact count can disagree with
   what enforces.
8. ~~**Default-deny is not configurable.**~~ RESOLVED by removing it. The
   `user_enrolled_no_match → block` whitelist is retired — a near miss allows, with
   the reason recorded on the decision row. A tenant wanting uncovered contexts
   denied authors a matchAll `block` policy, which is per-domain and visible.
   See `AD-WHITELIST-RETIREMENT.md`.
9. **No break-glass concept.** Nothing exempts an emergency account from every
   policy by construction.
