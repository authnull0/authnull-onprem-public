# On-premise packaging and licensing — plan

Package Authnull so a customer can sign up on the website, download from a public
Git repo, install it themselves, run free for 30 days, and then buy a licence to
carry on.

Scope named by the business: **AD MFA, Database MFA, RADIUS MFA.**

Companion documents: [DEPLOYMENT.md](DEPLOYMENT.md) is the *internal* runbook for
Authnull's own reference deployment — it names internal hosts and is not customer
documentation. [DATABASE-MFA-FLOW.md](DATABASE-MFA-FLOW.md) covers why database
MFA is not yet shippable.

---

## 1. Feature readiness against the advertised scope

Assessed by reading the code, not by trusting the roadmap.

| Feature | Logic | Packaged today | Verdict |
|---|---|---|---|
| **AD MFA** | Works. Verified live: policy matched, challenge raised, sensor enforced. | Yes | **Shippable** |
| **RADIUS MFA** | Clean and fail-closed on every path — API error, unknown decision, poll timeout all `AccessReject`. `EvaluateAuth` returns the challenge id, so no separate initiate. | **No.** Absent from `docker-compose.yml`, and the source is **not in version control at all** (local directory only). | **Packaging work only** |
| **Database MFA** | Provisioning never completes (`getPolicyDetails` 404). MySQL enforcement is a no-op. Postgres denies only by accident. Still gated on the **mobile wallet**, which is being removed. | Agent and ProxySQL ship per-VM, outside compose | **Not shippable** |

**Consequence for the plan.** AD and RADIUS can be packaged and sold now. Database
MFA cannot be advertised until the push swap lands — a trial customer who enables
it today gets a database that either never provisions or never enforces. Options
are (a) ship AD + RADIUS first and add database in the next release, or (b) hold
the whole package until database MFA is finished. (a) is strongly preferable: it
gets the trial funnel running months earlier.

---

## 2. Two blockers that must be settled before any packaging is written

### 2.1 The `.env` cannot ship as it stands

107 keys, roughly 40 of them secret, and three different kinds are currently mixed
in one file:

| Kind | Examples | What packaging must do |
|---|---|---|
| **Authnull-owned** | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AZURE_OPENAI_API_KEY`, `CLOUDFLARE_AUTH_KEY`, `GIT_TOKEN`, `EXPO_ACCESS_TOKEN`, `IPINFO_TOKEN`, `AI_SERVICE_API_KEY`, `FCM_SERVICE_ACCOUNT_JSON` | **Never ship.** Either remove the dependency or make the feature optional and off by default. |
| **Per-deployment crypto** | `JWT_SECRET`, `ENCRYPTION_KEY`, `TOTP_ENCRYPTION_KEY`, `INTERNAL_API_KEY`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `DB_PASSWORD`, `MINIO_ROOT_PASSWORD` | **Generate per install.** |
| **Customer-owned** | `DUO_*`, `OKTA_*`, `SMTP_*`, `TWILIO_*` | Document; customer fills in. |

The second row is the dangerous one. If the public repo carries fixed values, then
**every customer shares one JWT signing key**, and a token minted on one
deployment validates on another. That is a cross-deployment authentication break
created by packaging rather than by code, and a public repo makes the key public.

The installer must therefore generate that row with `openssl rand` at install
time and never read it from a committed default. A committed `.env.example` must
carry empty values, not working ones.

Features depending on the first row need an explicit posture. `IPINFO_TOKEN`
(geolocation in the push prompt) and the AI risk service should degrade quietly
when unset — the code already treats risk scoring as optional.

### 2.2 The AuthNull Authenticator cannot ship on-prem — decided

The app's push transport is FCM against Authnull's own Firebase project, and the
app bundle contains `google-services.json` for it. A self-hosted deployment cannot
use that without Authnull sitting in the customer's authentication path.

**Decision: on-prem uses Okta, Duo, TOTP or WebAuthn.** The AuthNull
Authenticator is a SaaS-only feature for now.

This costs nothing architecturally — `GetProviderForOrg` already selects per org
and `RequiresEnrolledDevice(provider)` is already false for vendor providers, so
the enrolment machinery correctly reports "not applicable". It does need to be
stated plainly in the customer documentation, and the console should not offer
`authnull` as a provider in an on-prem build.

---

## 3. What gets shipped, and where

A **new public repository**, `authnull0/authnull-onprem`, containing no source and
no secrets:

```
authnull-onprem/
├── README.md                  quickstart: 5 commands to a running system
├── docker-compose.yml         pinned image tags, no Authnull secrets
├── .env.example               every key, all secret values EMPTY
├── install.sh                 preflight → generate secrets → pull → up → verify
├── db-init/                   schema + migrations (replayed on every boot)
├── docs/
│   ├── INSTALL.md             prerequisites, sizing, TLS, firewall
│   ├── CONFIGURE.md           identity provider, SMTP, first admin
│   ├── AD-SETUP.md            DC sensor install, domain registration, first policy
│   ├── RADIUS-SETUP.md        NAS shared secret, client config
│   ├── LICENSING.md           trial, activation, renewal, what expiry does
│   ├── UPGRADE.md             pull new tags, migrations replay, rollback
│   └── TROUBLESHOOT.md        health endpoint, log locations, common failures
└── LICENSE                    commercial terms
```

Images stay on `docker-repo-public.authnull.com`. Anonymous pull must be verified
— today's deployments may be using credentials nobody has tested removing.

**Air-gapped variant.** A `docker save` tarball of the pinned images plus the same
repo contents, so an isolated customer can install without registry access. Cheap
to produce and expected by anyone who wants on-prem in the first place.

**Version control for RADIUS.** `radius-server` is not in git. That must be fixed
before it can be packaged at all — it cannot be built reproducibly today.

### `install.sh` responsibilities

1. **Preflight** — Docker and Compose versions, free disk, free RAM, required
   ports unused, kernel `vm.max_map_count` for Elasticsearch.
2. **Generate** — write `.env` from `.env.example` with fresh `openssl rand`
   values for every per-deployment secret. Refuse to overwrite an existing `.env`.
3. **Collect** — prompt for the handful of things only the customer knows: base
   URL / hostname, first admin email, SMTP, identity provider.
4. **Pull and start** — pinned tags only, never `latest`, so two installs on
   different days produce the same system.
5. **Verify** — poll `/system/v1/health` until schema and dependency checks pass,
   then print the console URL. The existing health endpoint already reports schema
   drift; the installer should surface that rather than declare success blindly.

Idempotent throughout: running it twice must not rotate secrets or reset data.

---

## 4. Licensing

### 4.1 The rule that matters most

**A licence gates the control plane. It never gates the data plane.**

This product sits in the authentication path of domain controllers, databases and
RADIUS clients. So:

| Licence state | Console (control plane) | Enforcement (data plane) |
|---|---|---|
| Valid | full | normal |
| Expiring (≤14 days) | full, with banner | normal |
| **Expired** | **read-only** — no new policies, directories, or users | **unchanged** |
| Missing / invalid signature | read-only | **unchanged** |

Rationale, stated plainly because it will be challenged: if expiry failed
**closed**, a billing lapse would stop authentication across a customer's domain —
a self-inflicted outage on the customer's most critical path. If it failed
**open**, MFA would silently stop being enforced and the customer would be less
secure without being told. Neither is acceptable. Gating administration keeps the
commercial lever (you cannot grow or change your deployment) while making the
failure mode boring.

`EvaluateAuth`, `InitiateMFAChallenge`, `GetMFAChallenge` and the RADIUS path must
have **no licence check at all** — not a permissive one. A check that could be
made strict by a later edit is a latent outage.

### 4.2 Offline by design

On-prem installations are frequently air-gapped, so validation must be local:

- **Format** — a signed file: a JSON payload plus an Ed25519 signature over it.
- **Payload** — licence id, customer name, issue date, expiry date, tier, feature
  flags (`ad`, `database`, `radius`), optional limits, and a nonce.
- **Verification** — Ed25519 public key compiled into the binary. The private key
  never leaves Authnull.
- **Storage** — the licence file mounted read-only into the container, with a copy
  in the database so the console can display it.

Ed25519 rather than a bespoke key format: signature verification is 30 lines using
`crypto/ed25519` from the standard library, and a forged licence requires the
private key rather than merely reading our validation code.

**No phone-home for validation.** Optional phone-home only for renewal
convenience, and never blocking.

### 4.3 The trial

The package is public, so the trial must self-start with no input from Authnull.

- First boot with no licence writes a trial record: start timestamp, 30-day
  expiry.
- The trial grants **all in-scope features**, so evaluation is not crippled.
- At expiry the licence state becomes `expired` and §4.1 applies.

**A self-starting trial on a public package is resettable** — a customer can
delete the volume and reinstall. Do not attempt to prevent this: the mitigations
(hardware fingerprints, hidden state, filesystem markers) are defeatable, annoy
honest customers, and break legitimate restores and migrations. The trial is a
lead-generation mechanism, not a security control. Store the trial start signed by
the deployment's own key so casual editing is visible, and stop there.

Clock rollback has the same character. It cannot be prevented when the customer
owns the clock. Record the highest timestamp ever seen and warn when time moves
backwards; do not attempt to enforce.

### 4.4 Trial to paid — recommendation

You did not have a view on this, so: **offline signed licence, manually issued,
for v1.**

1. Customer signs up on the website; the download link and a trial id are emailed.
2. They install; the trial self-starts. Nothing is required from Authnull.
3. At day 16 and day 25 the console shows a renewal banner with a **licence
   request code** — a short string identifying the deployment.
4. They buy through sales. Authnull generates a signed licence against that code
   and emails the file.
5. They upload it in the console. Validation is instant and local.

Why this first: it works air-gapped, needs no payment integration, needs no
Authnull-side licence service beyond a signing CLI, and does not block the trial
funnel — which is the part with revenue attached. Online activation (short key
exchanged once for a signed licence) is the natural second step, and self-serve
checkout the third. The file format does not change between them, so nothing is
wasted.

### 4.5 What to meter

Start with **expiry plus the three feature flags**. Add seat counting only when
there is a reason to.

Feature flags are needed anyway to sell AD, database and RADIUS separately, and
they are cheap: one gate at each module's route registration. Seat counting needs
a decision about overage, and the honest answer for this product is that a hard
block during an AD sync is indistinguishable from an outage — so it would have to
be soft, which makes it a reporting feature rather than an enforcement one. That
can wait.

---

## 5. Sequence

Each phase is independently shippable.

**Phase 0 — correctness that packaging would otherwise expose** *(small, do first)*
- Register the `/api/v1/policyService/getPolicyDetails` alias — one line, unblocks
  database provisioning ([DATABASE-MFA-FLOW.md](DATABASE-MFA-FLOW.md) finding 2).
- Fix the MySQL MFA `break` so a denial denies (finding 1).
- Put `radius-server` in git.
- Verify anonymous pull from the registry actually works.

**Phase 1 — packaging** *(the trial funnel)*
- Create `authnull0/authnull-onprem`; audit `.env` into the three categories.
- Write `install.sh` with generated secrets and a real preflight.
- Pin every image tag; remove `latest`.
- Add `radius-server` to compose.
- Write the seven customer documents.
- Prove it: install from the public repo on a clean VM, following only the docs.

**Phase 2 — licensing core**
- `pkg/license`: Ed25519 verification, payload schema, state machine
  (`trial` / `valid` / `expiring` / `expired` / `invalid`).
- Boot-time load and a periodic re-check, following the existing
  `verifySchema` / `schemaProblems` pattern in `cmd/authnull-service/schema.go`
  (`atomic.Value`, surfaced through the health endpoint).
- Middleware for control-plane writes only, with an explicit allow-list of paths
  that must never be gated.
- Console: licence page, banners, upload.
- Signing CLI for Authnull-internal use.

**Phase 3 — commerce**
- Renewal reminders by email; licence request codes.
- Online activation, then self-serve checkout.

**Phase 4 — database MFA on-prem**
- Finish the push swap, then add `database` to the advertised feature set.

---

## 6. Risks

| Risk | Consequence | Mitigation |
|---|---|---|
| A per-deployment secret ships with a fixed value in a public repo | Cross-deployment token forgery | `install.sh` generates them; a test asserts `.env.example` has no non-empty secret values |
| Database MFA advertised before the push swap | Trial customer enables it and it silently does nothing | Do not list it until Phase 4 |
| Licence check reaches the data plane | Billing lapse becomes an authentication outage | Explicit allow-list plus a test asserting the enforcement routes are unlicensed |
| `radius-server` not in git | Cannot be built reproducibly, so cannot be shipped | Phase 0 |
| Registry needs credentials nobody has tested | Install fails at step one for every customer | Verify anonymous pull in Phase 0 |
| 16 services on one VM | Bad first impression from an under-resourced trial | Preflight enforces minimum RAM/disk and says what is needed |
