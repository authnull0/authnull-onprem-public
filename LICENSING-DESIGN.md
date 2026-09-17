# Licensing — design document

How Authnull licenses a deployment it cannot see, reach, or switch off.

Status: **implemented, not enabled.** Everything described here is built and tested;
enforcement is dormant until an on-premise build is produced with a signing key
(§10.1). Companion documents: [LICENSING-PLAN.md](LICENSING-PLAN.md) for delivery
status and the decisions still owed by the business,
[ONPREM-PACKAGING-PLAN.md](ONPREM-PACKAGING-PLAN.md) for the package this ships in.

---

## 1. Problem

Authnull is becoming a self-hosted product. A customer signs up on the website,
downloads the package from a public Git repository, and installs it on their own
infrastructure. From that moment we have no visibility and no control: we cannot see
the deployment, cannot reach it, and cannot revoke anything remotely.

We need it to be free for 30 days and paid after, without any of the levers a SaaS
product would use.

Three properties of the environment shape every decision below:

- **It may be air-gapped.** On-premise identity infrastructure is frequently placed on
  networks with no outbound access. A licence check that needs the internet is a licence
  check that fails.
- **The customer owns everything.** The disk, the database, the system clock. Anything
  we store locally, they can read and edit.
- **We sit in the authentication path of their domain controllers.** This is the
  constraint that dominates the design. If licensing misbehaves, people cannot log in to
  their computers.

## 2. Goals

1. A deployment runs free for 30 days from first boot, with no action required from
   Authnull and none possible by the customer.
2. After that, continued *administration* requires a licence we issued.
3. Verification works with no network access.
4. A customer cannot forge or extend a licence without our private key.
5. AD, Database and RADIUS are separately licensable, in any combination.
6. **Licensing can never interrupt authentication.**

## 3. Non-goals

Stated explicitly because each one is a thing somebody will eventually ask for, and the
answer should be a decision on record rather than an omission.

- **Preventing trial reset.** See §9.2.
- **Preventing clock rollback.** See §9.3.
- **Per-seat metering.** See §9.4.
- **Remote revocation.** Impossible without a callback, which §1 rules out. A licence
  expires; it is not withdrawn.
- **Usage telemetry.** No phone-home exists in this design, for licensing or anything
  else.

---

## 4. The decision that shapes everything: what expiry does

A licence gates the **control plane**. It never gates the **data plane**.

| Licence state | Console (control plane) | Enforcement (data plane) |
|---|---|---|
| `valid` | full | normal |
| `expiring` (≤14 days) | full, with banner | normal |
| `expired` | **read-only** | **unchanged** |
| `invalid` (bad signature) | **read-only** | **unchanged** |
| `trial` | full | normal |
| `not_enforced` (no key in build) | full | normal |

### Why

Two obvious designs, both unacceptable:

**Fail closed** — expiry blocks authentication. A late invoice becomes a domain-wide
outage on the customer's most critical path, caused by us. No security vendor survives
doing that twice.

**Fail open** — expiry is advisory. The customer keeps full use of a product they have
stopped paying for, and there is no commercial mechanism at all.

Gating administration keeps the commercial lever — you cannot grow or change your
deployment without paying — while the customer loses neither availability nor security.
The failure mode is *boring*, which is the property we want from a billing state.

### What this means concretely

`EvaluateAuth`, `InitiateMFAChallenge`, `GetMFAChallenge`, the sensor's sync endpoints,
the phone's `push/*` routes, the database agent's endpoints, and the health endpoints
have **no licence check at all** — not a permissive one. A check that could be made
strict by a later edit is a latent outage.

37 such paths are asserted ungated by `TestDataPlaneIsNeverGated` and its siblings.

---

## 5. Architecture

```
                 Authnull (internal)
  ┌──────────────────────────────────────────┐
  │  authnull-license CLI                    │
  │    keygen → license.key  (private)       │
  │             license.pub  (public)        │
  │    sign   → acme.lic     (per customer)  │
  └──────────────┬───────────────────────────┘
                 │ license.pub compiled into the on-prem build
                 │ acme.lic emailed to the customer
                 ▼
  ┌──────────────────────────────────────────┐
  │  Customer deployment (offline)            │
  │                                           │
  │  pkg/license                              │
  │   ├─ Verify()    Ed25519 over payload     │
  │   ├─ Evaluate()  → Status (state machine) │
  │   ├─ Loader      atomic cache, 5 min      │
  │   ├─ Gate()      middleware, 34 paths     │
  │   ├─ TrialStore  did.license_state        │
  │   └─ DocumentStore did.license_documents  │
  │                                           │
  │  console → GET /api/v1/license            │
  │          → POST /api/v1/license/upload    │
  └──────────────────────────────────────────┘
```

No component of this talks to Authnull at runtime. The only channel is a file a human
carries.

### Package layout

| File | Lines | Responsibility |
|---|---|---|
| `pkg/license/license.go` | 334 | payload schema, `Verify`, `Sign`, the state machine |
| `pkg/license/gate.go` | 219 | the gated-path table and the middleware |
| `pkg/license/loader.go` | 205 | source selection, caching, re-check |
| `pkg/license/store.go` | 109 | uploaded documents in the master DB |
| `pkg/license/trial.go` | 139 | first-boot record |
| `cmd/authnull-service/license.go` | 94 | boot wiring |
| `cmd/authnull-service/license_handler.go` | 206 | the two HTTP endpoints |
| `cmd/authnull-license/main.go` | 286 | Authnull-internal issuing tool |

1,592 lines of implementation — 1,006 in `pkg/license`, 300 wiring the service, 286 in
the issuing CLI — against 694 lines of test in `pkg/license`, covering 23 tests.

---

## 6. The licence file

### Format

```json
{
  "payload": {
    "id": "lic-7b99cf1a81423de8",
    "customer": "Acme Ltd",
    "issuedAt": "2026-08-17T00:00:00Z",
    "expiresAt": "2027-08-17T00:00:00Z",
    "tier": "enterprise",
    "features": ["ad", "database"],
    "nonce": "40c683941fcc6983"
  },
  "signature": "<base64 Ed25519 over the canonicalised payload>"
}
```

Field names are part of the format. Changing one invalidates every licence already
issued, so **add, never rename**.

### Why Ed25519

Verification is ~30 lines of `crypto/ed25519` from the standard library. Forging a
licence requires the private key rather than merely reading how we validate — which
rules out the entire class of "someone decompiled the binary and worked out the check".

Alternatives rejected:

- **HMAC / shared secret.** The verifying key would have to ship in the customer's
  binary, and it is the same key that signs. Anyone who extracts it can issue licences.
- **RSA.** Works, but larger keys, larger signatures, more parameters to get wrong, and
  no benefit here.
- **A bespoke obfuscated format.** Security by obscurity, and unmaintainable.

### Why the signature covers a *canonicalised* payload

The signature is computed over the payload with insignificant whitespace removed
(`json.Compact`), not over the literal bytes on disk.

A licence is a JSON file that people open in editors, paste into tickets and mail to
each other, and plenty of tools reformat JSON on save. Signing literal bytes would mean
a customer could invalidate a genuine licence by looking at it — and be told the file
had been tampered with.

**This was not theoretical.** The first version of the signing CLI wrote the document
with `json.MarshalIndent`, which re-indented the embedded payload, and *every licence it
produced failed to verify against its own signature*. Only running the tool end to end
caught it. `Sign` is now exported from `pkg/license` and the CLI calls it, so signer and
verifier cannot drift.

**Known limit:** this forgives whitespace, not key reordering. A tool that parses the
payload and re-serialises with sorted keys will invalidate the licence. Full RFC 8785
canonicalisation would fix that and is deliberately not attempted — it drags in number
formatting and unicode escaping rules that are easy to get subtly wrong, and a
canonicaliser that disagrees with the signer by one byte fails exactly like tampering.
The supported answer is to request a reissue rather than repair the file.

### Verify and Evaluate are separate

`Verify` answers *did Authnull issue this, and is it intact*. `Evaluate` answers *what
does it entitle you to right now*. Keeping them apart means an expired licence can still
be displayed accurately — customer, dates, features — instead of being indistinguishable
from a forgery. An admin who uploads last year's file is told it lapsed in March, not
that it is invalid.

### An empty feature list grants nothing

Not "grants everything". A truncated or half-written file must not silently unlock the
product.

---

## 7. Where the licence lives

Two sources, tried in order.

**1. The master database** (`did.license_documents`) — primary, and what the console
upload writes.

**2. A file** at `LICENSE_FILE` — the bootstrap path, for an air-gapped operator who
wants to drop a licence beside the compose file before first boot.

### Why the database is primary

A file is a poor upload target for reasons that all bite in production:

- container filesystems are recreated on every image upgrade, so a licence written
  inside one disappears and the deployment looks unlicensed again;
- the packaged compose mounts the licence path **read-only**, which is correct for a
  file an operator drops in and unwritable by an upload handler;
- with more than one replica, an upload only ever reaches the container that served the
  request.

The database has none of those problems and is already what customers back up.

### A database read error does not fall through to the file

Only `ErrNoLicense` — "nothing uploaded yet" — falls through. Any other error is
reported.

The two sources can hold different licences. Silently preferring a stale file because
the database blipped would change what the deployment is entitled to for a reason nobody
could see.

### Documents are append-only

Every upload inserts; the newest wins, ordered `uploaded_at DESC, id DESC`.

Deliberately **not** an `active` boolean: two rows both marked active is a state somebody
eventually reaches, and then which licence applies depends on query order. "Most recent"
cannot be ambiguous. The tiebreak on `id` matters because two uploads inside one clock
tick are possible.

History also makes the obvious renewal mistake recoverable — uploading last year's file,
or another deployment's, no longer destroys a good licence.

`customer`, `license_id` and `expires_at` are denormalised copies written *after*
verification, for display and support only. Every decision re-verifies the document, so
the database is never trusted on its own.

---

## 8. Enforcement

### The gated-path table runs in the safe direction

There are two ways to build this:

| | Behaviour for a route added later | Cost of forgetting |
|---|---|---|
| Gate everything, exempt a list | gated **by default** | a licence lapse stops authentication — an **outage** |
| Gate only a list | free **by default** | an expired customer changes one setting — **revenue** |

The second, without hesitation. A mistake must cost money rather than availability, and
in a product sitting in the authentication path that is not a close call.

*(The original plan specified the first. This is a deliberate reversal, recorded in
`gate.go`.)*

### Exact paths, never prefixes

A prefix is how the safe direction quietly becomes the unsafe one.
`/api/v1/policy/json/` looks like it means "policy writes", but it also matches
`listPolicy`, `getEffectivePolicy` and `simulatePolicy` — all reads. Gating those would
make an expired console *unusable* when the entire point is that it stays **read-only**.

34 exact paths, no prefix matching. Nine console reads are asserted ungated by
`TestReadsAreNeverGated`.

### Two checks, because features are sold separately

```
      ┌─ not gated ────────────────────────────► allow
path ─┤
      └─ gated ─┬─ !Licensed ──────────────────► 402 "license required"
                ├─ feature not in licence ─────► 402 "feature not licensed"
                └─ otherwise ──────────────────► allow
```

The two refusals are deliberately different. A feature refusal reports
`"licensed": true`, because the licence *is* valid — they simply did not buy that
module. An admin seeing "license required" would go hunting for a billing problem;
"your licence does not include Database MFA" tells them to call sales.

`402 Payment Required`, not `403`. The caller's permissions are fine; the deployment's
licence is not. A console showing "forbidden" sends an admin through the roles screen
for no reason.

Every refusal ends with *"Existing policies continue to be enforced; only changes are
blocked."* Without that sentence, a 402 on "create policy" reads like a total outage and
gets escalated as one.

### Path-level and type-level checks

| Distribution | Count | Why |
|---|---|---|
| `FeatureAny` | 23 | policy authoring — shared by all three products |
| `FeatureAD` | 5 | AD discovery, group jobs, enrolment invites |
| `FeatureDatabase` | 6 | database host registration |
| `FeatureRADIUS` | 0 | no RADIUS-specific screens exist yet |

AD, database and RADIUS policies are all created through the **same** endpoints with the
type in the request body, so a URL cannot tell them apart. `FeatureForPolicyType` exists
for the place that does know the type.

**Open gap:** that function is built and tested but not yet called from the policy save
path. Until it is, a customer with an AD-only licence could create a database policy —
which does nothing for them, since the database screens are refused. Tracked in
[LICENSING-PLAN.md](LICENSING-PLAN.md) §5.

### The renewal deadlock, and why it cannot happen

An expired deployment must be able to install a licence. If `POST /license/upload` were
gated, a lapsed customer could never renew without somebody editing their database.

It is safe *by construction*: the gate consults an include-list, and the licence
endpoints are not on it. `TestLicenseEndpointsAreNeverGated` asserts it anyway —
"safe by construction" holds only until somebody adds an entry to that list.

---

## 9. Accepted limitations

### 9.1 An absent build key means licensing is not enforced

`PublicKeyBase64` is injected at build time via `-ldflags`. Empty means **licensing does
not apply**, and that is the correct default.

The same binary serves Authnull's own SaaS and reference deployments, which have no
licence and never will. If an absent key meant "nothing verifies", wiring this package in
would have put every one of those consoles into read-only — an outage we shipped to
ourselves.

A malformed build key logs loudly and degrades to unenforced rather than bricking a
customer's console. That is a release-engineering error, not a customer's problem.

### 9.2 The trial can be reset

Wipe the volume, reinstall, get another 30 days.

Every defence — hardware fingerprints, hidden filesystem markers, refusing to start when
state is missing — is defeatable by anyone determined, while breaking legitimate
restores, migrations and VM snapshots for honest customers. The support cost exceeds the
recovered revenue.

The trial is a **lead-generation mechanism, not a security control.** The trial row is
HMAC'd with the deployment's own `ENCRYPTION_KEY` so a casual `UPDATE` is *visible* — a
support engineer can tell "somebody edited this" from "this install really is 12 days
old" — and we stop there. A mismatched signature is logged and the stored value honoured,
because a restored backup is far more likely than fraud.

What *is* prevented, because it needs no intent: `Ensure()` is idempotent, so restarting
the container cannot push the trial start forward.

### 9.3 The clock can be turned back

They own the server, so they own its date. Detectable, not preventable. Recording the
highest timestamp ever seen and warning on regression is possible future work; enforcing
is not.

### 9.4 No per-seat metering

Expiry plus three feature flags is the whole enforcement surface.

Feature flags are needed anyway to sell the modules separately, and cost one gate each.
Seat counting needs an overage decision, and the honest answer for this product is that a
hard block partway through an AD sync is indistinguishable from an outage — so it would
have to be soft, which makes it a reporting feature rather than a licence one. Deferred
until there is a commercial reason.

---

## 10. Operations

### 10.1 Enabling it

```sh
# once, ever — the private key must outlive several employees
authnull-license keygen -out ./keys

# the on-premise build, with the public half compiled in
go build -ldflags \
  "-X github.com/authnull0/authnull-service/pkg/license.PublicKeyBase64=$(cat keys/license.pub)" \
  ./cmd/authnull-service
```

`keygen` refuses to overwrite an existing key. Regenerating it invalidates every licence
ever issued, and there is no way to detect that has happened until customers start
reporting failures.

### 10.2 Issuing a licence

```sh
authnull-license sign -key keys/license.key \
  -customer "Acme Ltd" -days 365 -features ad,database -out acme.lic

authnull-license show -pub keys/license.pub -in acme.lic   # what they will see
```

Unknown feature names are rejected at issue time. A typo like `radiusx` would otherwise
produce a licence that verifies perfectly and grants nothing, and the customer would be
the one to discover it.

### 10.3 Key custody

The private key is the entire security model. Anyone holding it can issue unlimited
licences; losing it means no customer can ever renew. **This needs a named owner and a
documented location before the real key is generated** — it is the one open item that
blocks enabling licensing at all.

### 10.4 Observability

Licence state appears in `GET /system/v1/health` alongside the schema check, and in
`GET /api/v1/license` for the console. Health stays **200** when unlicensed: the process
is serving and enforcement is running, so a 503 would pull the container out of rotation
over a billing state.

Boot logs one line: `license: state=… licensed=… days_remaining=… customer=…`.

---

## 11. Data model

### `did.license_state` — the trial (migration 011)

| Column | Notes |
|---|---|
| `id` | `smallint`, `CHECK (id = 1)` — one trial per deployment, enforced |
| `trial_started_at` | `timestamptz`, first boot |
| `signature` | HMAC-SHA256 over the timestamp, keyed on `ENCRYPTION_KEY` |

The `CHECK` constraint exists because two containers booting simultaneously could
otherwise insert two rows, and the trial length would depend on which one a later read
returned.

### `did.license_documents` — uploads (migration 012)

| Column | Notes |
|---|---|
| `id` | `bigserial` |
| `document` | the signed licence as uploaded; re-verified on every read |
| `license_id`, `customer`, `expires_at` | denormalised, display only |
| `uploaded_by_user_id` | audit |
| `uploaded_at` | ordering; indexed `DESC` |

Both live in the **master** database. A licence covers the deployment, not an
organisation. The migration directory is replayed against every org database too, so the
tables exist there as well and are simply unread — harmless, and better than a migration
that must know which database it is running against.

---

## 12. API

### `GET /api/v1/license`

Any authenticated session. The expiry banner is shown to whoever is logged in, and hiding
"your trial ends in 3 days" from the person who would chase it serves nobody.

Returns state, `licensed`, `daysRemaining`, customer, tier, features, `expiresAt`,
`enforced`, `enforcementUnaffected: true`, and the last 10 uploads. **Not** the document
bodies — no reason to ship kilobytes of signed blobs to a browser to render a table of
dates.

### `POST /api/v1/license/upload`

`ADMIN` or `SUPERADMIN`, resolved from the caller's org database via
`mfapush.RoleForIdentity` — the same way `adminInvite` does it, so there is one answer to
"who counts as an administrator here". `middleware.Principal` carries only identity, so a
role check has to go and look.

Raw file as the body, not multipart: it is a kilobyte of JSON, and a raw body is simpler
for both a browser `fetch` and a support engineer's `curl`.

Sequence: 64 KiB cap → build must be enforcing → **verify** → save → `Reload()` → return
the new status.

| Response | Meaning |
|---|---|
| `200` | installed; body carries the new state |
| `400` | bad signature, malformed, empty, or a non-licensing build |
| `403` | not an administrator |
| `413` | far larger than a licence |
| `503` | valid, but the master database is unavailable to save it |

---

## 13. Failure modes

| Situation | Behaviour | Rationale |
|---|---|---|
| No licence, inside 30 days | `trial`, everything permitted | evaluation must not be crippled |
| No licence, past 30 days | `expired`, console read-only | §4 |
| Signature fails | `invalid`, console read-only, reason names the cause | not conflated with expiry |
| File unreadable (permissions) | trial applies; reason notes the file was ignored | not an accusation of tampering |
| Empty file | treated as *no licence* | what a truncated mount or half-finished upload looks like |
| Master DB unreachable at boot | trial treated as starting now; logged | refusing to serve over licence bookkeeping would be the outage this design avoids |
| Trial row HMAC mismatch | logged; stored value honoured | a restored backup is likelier than fraud |
| Build key malformed | licensing unenforced; logged loudly | our error, not the customer's |
| Licence expires mid-session | next gated write refused | `Gate` reads current state, not a snapshot |
| Licence uploaded | effective immediately | `Reload()` on the upload path |

---

## 14. Testing

23 tests in `pkg/license`. The ones that carry weight:

- **`TestDataPlaneIsNeverGated`** — 18 authentication paths must stay ungated. If this
  fails, a licence lapse would break live authentication.
- **`TestDatabaseAgentPathsAreNeverGated`** — the agent's sync and job endpoints, plus
  `listConnections`, which is how a user obtains database credentials.
- **`TestReadsAreNeverGated`** — nine console reads, so "read-only" is not a euphemism
  for "broken".
- **`TestFeatureCombinationsAreEnforced`** — AD only, Database only, two of three, all
  three.
- **`TestNoBuildKeyMeansNotEnforced`** — a non-enforcing build stays usable even when
  handed a forged file.
- **`TestSignedLicenceSurvivesReformattingButNotEditing`** — the regression test for
  §6, written after the CLI failed to verify its own output.
- **`TestVerifyRejectsEditedExpiry`** — editing a date must fail as a *signature* error,
  so the console can say "this file was modified" rather than "something went wrong".

The invariants worth restating: **licensing never blocks authentication**, and **an
expired console can still read its own state**. Both are properties CI checks, not
promises in a document.

---

## 15. Open items

| Item | Owner | Blocking |
|---|---|---|
| Key custody: named owner and location | business | enabling licensing at all |
| Call `FeatureForPolicyType` from the policy save path | engineering | per-product policy enforcement |
| Console: licence page, upload, day-16/25 banners | UI team | customer-visible licensing |
| Apply migrations 011 and 012 | engineering | trial and upload storage |
| Product pricing and bundles | business | step 7 of the plan |
| Renewal reminders by email | business + engineering | renewal conversion |

## 16. Future work, explicitly deferred

- **Online activation** — a short key exchanged once for a signed licence, then offline.
  The file format does not change, so nothing here is wasted.
- **Self-serve checkout** — Stripe in the console. Needs an Authnull-side licence
  service.
- **Clock-regression detection** — record the highest timestamp seen, warn on regression.
- **Seat reporting** — count without enforcing (§9.4).
- **RFC 8785 canonicalisation** — only if key-reordering by customer tooling turns out to
  happen in practice (§6).
