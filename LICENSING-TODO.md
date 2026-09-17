# Licensing — what is left

The mechanism works and has been run end to end. What remains is mostly other people's
halves: a key only the CEO can generate, an image only release engineering can publish, and
two console screens. Nothing below is a redesign — the design is in
[LICENSING-PLAN.md](LICENSING-PLAN.md) and has not changed.

Written 24 August 2026, after the lifecycle was verified live for the first time.

---

## Where it stands

**Done and verified against a real enforcing binary and a real PostgreSQL:**

| | |
|---|---|
| `keygen` → `sign` → `show` | real CLI, private key written 0600 |
| build with `-ldflags` | public key confirmed present in the binary |
| fresh install | trial row written and HMAC-signed |
| day 31 | **402** on every gated path |
| licence at `LICENSE_FILE` | unblocked, and overrode an exhausted trial |
| AD-only licence in the database | beat the file; database path → `feature not licensed` |
| throughout | `dbSync` and `EvaluateAuth` never gated, console reads never gated |

**Not verified, and each has its own item below:** the upload endpoint's own auth path, the
`docker build`, a clean-VM install, and anything a browser touches.

Three bugs came out of that first run and are fixed: the trial signature could never verify
(nanoseconds vs microseconds), the trial never reports a warning state before it expires, and
log lines named a file path when the licence had come from the database.

---

## 1. Generate the signing key — CEO — BLOCKS EVERYTHING ELSE

Until this exists there is no `-onprem` image, so no customer can be sold anything. It is
about ten minutes of work and it is the critical path.

The procedure is written out in [LICENSE-KEY-CUSTODY.md](LICENSE-KEY-CUSTODY.md) §2. In short:

```
authnull-license keygen -out .
# produces license.key (PRIVATE, never leaves this machine)
#          license.pub (PUBLIC, send to engineering)
```

What engineering needs back is **`license.pub` only** — 44 characters of base64. Send it by any
means; it is not a secret. Also read out the fingerprint that `build-image.sh --check` prints,
so we can confirm we compiled the right key before a release rather than after a customer
cannot install their licence.

**`license.key` must never be sent to engineering, committed, put in a build argument, or
copied to a shared drive.** §7 of the custody doc covers what to do if it leaks; the short
version is that every licence ever issued has to be reissued, so it is worth being careful once.

> The signing tool is not published anywhere yet. Either build it from this repo
> (`go build ./cmd/authnull-license`) or hand the CEO a compiled binary — decide which, because
> "build it from the repo" means the CEO needs Go installed.

---

## 2. Build and publish the `-onprem` image — release engineering

`onprem/docker-compose.yml` points at `docker-repo-public.authnull.com/authnull-service:1.0.0-onprem`
and **nothing has ever built it**. There is no CI in this repository at all.

Use the script rather than a hand-typed `docker build`:

```sh
./onprem/build-image.sh --key license.pub --version 1.0.0          # build only
./onprem/build-image.sh --key license.pub --version 1.0.0 --push   # build and push
```

It refuses a missing key, a malformed key, and a private key handed over by mistake, then
greps the finished image to prove the key really made it in. The reasoning for each guard is
at the top of the script.

**Why not a plain `docker build`:** leaving the build argument out still succeeds and produces
a working image that never asks for a licence. Push that as `-onprem` and every customer who
pulls it has the product free, permanently, with nothing in the console or the logs to say so.
Nobody would notice until someone asked why no licence had ever been sold.

Needed to finish this item:

- [ ] `license.pub` from item 1.
- [ ] Push credentials for `docker-repo-public.authnull.com`. Nobody has confirmed who holds
      these or whether the registry is actually public-readable — check before release day.
- [ ] **Run the script on a machine with Docker.** Its argument handling is tested; the
      `docker build` and the image-grep step have never executed, because the sandbox this was
      written in has no Docker. Expect to fix something small the first time.
- [ ] Decide whether this becomes CI. A GitHub Actions workflow holding the public key as a
      repository variable would remove the hand-typed step entirely, and the key is not secret
      so there is nothing to protect. Worth it if we expect to cut more than a couple of releases.

---

## 3. Prove the upload endpoint's auth path — backend, ~1 hour

`POST /api/v1/license/upload` requires a session and an ADMIN or SUPERADMIN role before it will
accept anything. **That check has never run.** What has been proven is everything after it:
verify, save, reload, and the licence taking effect without a restart.

The risk is low — it is the same `SessionPrincipal` + `RoleForIdentity` pattern as `adminInvite`
and the database-MFA console routes — but "low risk" is not "tested", and this is the endpoint a
paying customer uses.

It cannot be tested on the current deployment, because that build has no public key and the
handler correctly answers *"this build does not use licences, so there is nothing to install"*.
So it needs the enforcing image from item 2 and then, as an administrator:

- [ ] Upload a valid licence → 200, and `GET /api/v1/license` reports `state: valid` **with no restart**.
- [ ] Upload the same file again → 200, and `history` gains a row rather than replacing one.
- [ ] Upload a file with one character of the expiry date changed → **400**, and the message
      names the signature rather than saying "expired".
- [ ] Upload a licence signed by a different key → **400**.
- [ ] Upload as a non-administrator → **403**.
- [ ] Upload with no session → **401**.
- [ ] Upload a 5 MB file → **413**, and nothing is written.
- [ ] Upload an empty file → **400**.

The first four are already covered by unit and integration tests; it is the last four —
everything in front of `license.Verify` — that has never executed.

---

## 4. The console's two licence surfaces — UI team

Nothing browser-facing exists. The API is finished and needs no changes, so this is purely UI.

### 4a. The banner

`GET /api/v1/license` returns, for any signed-in user:

```json
{
  "state": "trial",
  "licensed": true,
  "daysRemaining": 12,
  "reason": "trial: 12 days remaining",
  "enforced": true,
  "enforcementUnaffected": true,
  "customer": "Acme Corp",
  "tier": "enterprise",
  "expiresAt": "2027-08-24T00:00:00Z",
  "features": ["ad", "database"],
  "history": [{ "licenseId": "lic-…", "customer": "Acme Corp",
                "expiresAt": "2027-08-24T00:00:00Z", "uploadedAt": "2026-08-24T09:12:00Z" }]
}
```

`state` is one of `trial`, `valid`, `expiring`, `expired`, `invalid`, `not_enforced`. Only
`customer`, `tier`, `expiresAt`, `features`, `reason` and `history` are optional — the rest are
always present.

**Read this bit before writing the banner logic.** The obvious rule is wrong:

```js
state === "expiring" ? warn() : ok()      // ← shows nothing for 29 days, then a read-only console
```

A purchased licence spends its last 14 days in `expiring`. **A trial never does** — it is
`trial` on every one of its 29 days and `expired` on the thirtieth. So warn on
`daysRemaining`, which is populated for both:

```js
if (!licensed)              → blocking banner, offer the upload
else if (daysRemaining<=14) → warning banner, days remaining, offer to buy
else                        → nothing
```

`enforced: false` means the build carries no licence key (Authnull's own SaaS and every
reference deployment). **Show nothing at all in that case** — no banner, no licence page. A
trial countdown on a SaaS console is a support call. `TestTrialNeverReportsExpiring` pins this
behaviour, so it will not change under you.

`reason` is written to be displayed verbatim; it already ends with *"Existing policies continue
to be enforced; only changes are blocked."* where that applies. Do not paraphrase it — the
second sentence is the part that stops a panicked escalation when an admin cannot save a policy.

### 4b. Settings → Licence

- Current state, customer, expiry, and which modules are included.
- A file picker that `POST`s the raw file body to `/api/v1/license/upload` — **not multipart**,
  just the bytes, `Content-Type: application/json`.
- Errors come back as `{"error": "...", "state": "..."}`. Show `error` verbatim; it is written
  for an administrator and distinguishes an edited file from an expired one.
- `history` renders the upload log. Bodies are deliberately not included.
- Administrators only (403 otherwise), though the banner in 4a is for everyone.

### 4c. What a 402 looks like mid-session

Any gated write returns **402** with:

```json
{ "error": "license required", "state": "expired", "licensed": false,
  "message": "trial period has ended — install a licence to make further changes. Existing policies continue to be enforced; only changes are blocked." }
```

or, when the licence is valid but the module was not bought:

```json
{ "error": "feature not licensed", "state": "valid", "licensed": true,
  "feature": "database",
  "message": "your licence does not include Database MFA. …" }
```

- [ ] Handle 402 globally, not per-screen — there are 36 gated paths — 24 shared policy paths, 6 AD, 6 database.
- [ ] Show `message`, and route to Settings → Licence.
- [ ] On `feature not licensed`, `feature` tells you which module to offer. This is the upsell
      path and the only place the console can ask for money.
- [ ] **Do not treat 402 as a session error.** It is not a logout, and logging the user out here
      would be the single most confusing possible response.

---

## 5. Renewal reminders — undecided, needs a product call

There is no notification of any kind. A customer's trial ends, or their licence lapses, and the
first they know is a console that will not save. That is a poor experience and it is also a
missed renewal.

Nothing has been built because the answer depends on decisions nobody has made:

- Does an on-premise deployment email its own administrator, or do we notify from our side?
  On-prem SMTP is the customer's, may not be configured, and may not reach the internet.
- If we notify, we need to know a licence exists and when it expires — which means we know when
  a deployment was installed. **That is a phone-home, and `pkg/license` currently has none by
  design** (the package doc says so explicitly: a licence check that needs the network is a
  licence check that fails when the network does). Anything here must stay outside that package
  and must never gate a decision.
- Simplest honest option: send the reminders from our own records at sale time, since we already
  know the expiry date of every licence we sign. No product change at all.

**Recommendation:** do the last one first. It costs nothing and covers the commercial risk. Only
revisit in-product notification if customers actually ask.

---

## 6. Install it once on a clean VM — nobody has done this

`onprem/install.sh` has never run on a fresh machine. It is 343 lines of shell that generates
secrets, writes `.env`, brings up seven containers and polls for health. The secret formats are
unit-tested against the real `aes.NewCipher` and `hex.DecodeString`, and the health parsing is
verified against real response bodies from all four licence states — but the script as a whole
has never executed.

Expect to find something. Do it before any customer does.

- [ ] Fresh Ubuntu VM, Docker installed, nothing else.
- [ ] `./install.sh --check`, then `./install.sh`.
- [ ] It should end with `Licence: 30-day trial started.` If it says
      **`Licence: not enforced`**, the key did not make it into the image and the customer would
      never be asked to pay. That is the one line to watch for.
- [ ] `/system/v1/health` reports `"schema": {"ok": true}` and `"license": {"state": "trial"}`.
- [ ] Re-run `./install.sh` and confirm `.env` is not overwritten — rotating `JWT_SECRET` would
      invalidate every session and rotating `ENCRYPTION_KEY` would make stored data unreadable.
- [ ] Upload a licence through the console (item 3) and confirm the state changes with no restart.

---

## 7. The package's missing documents — low priority

`onprem/docs/` contains only `INSTALL.md`. The installer used to print paths to
`docs/CONFIGURE.md` and `docs/TROUBLESHOOT.md`, neither of which was ever written; it now points
at sections of `INSTALL.md` that exist, and `TestOnpremDocPathsExist` keeps every path it prints
real. So nothing is broken — these are just thin.

Write them when there is a real customer to write them for, and split `INSTALL.md` at that
point. Writing them now would mean guessing at the questions.

- [ ] `CONFIGURE.md` — after installing: add a directory, install the DC sensor, first policy.
- [ ] `TROUBLESHOOT.md` — expand `INSTALL.md`'s table, with the licence cases from §"Licence state".
- [ ] `UPGRADE.md` — pulling a new image, and what happens to the licence (nothing: it is in the
      database, which is the whole reason it lives there).

---

## 8. Commercial decisions — not engineering

Listed only because the code has placeholders waiting on them.

- [ ] **Price, per module.** `pkg/license` supports `ad`, `database` and `radius` in any
      combination and `TestFeatureCombinationsAreEnforced` covers all of them, so any bundling
      works. Nothing is priced.
- [ ] **Licence term.** `--days` is free-form; 365 is the assumed default and nothing enforces it.
- [ ] **`tier` is a label only**, for support and reporting. Gates read `features`. If tiers are
      meant to gate anything, say so now — it is a small change today and a licence-format change
      later.
- [ ] **Trial length.** 30 days, `TrialDuration` in `pkg/license/license.go`. Changing it later
      only affects new installs, since the start date is recorded per deployment.
- [ ] **What happens at renewal time on a lapsed deployment.** Currently: upload the new licence
      and everything resumes, with no penalty and no gap. That is deliberate and probably right,
      but it means there is no cost to lapsing for a month.

---

## Two rules not to break

Both are enforced by tests, and both exist because getting them wrong would be worse than having
no licensing at all.

**A licence gates the control plane, never the data plane.** This product sits in the
authentication path of customers' domain controllers. An expired licence makes the console
read-only; it must never stop an authentication, a push, a database login or an agent sync. If
expiry failed closed, a late invoice would take a customer's domain offline — an outage we
caused, on their most critical path. `TestDataPlaneIsNeverGated`,
`TestDatabaseAgentPathsAreNeverGated` and `TestReadsAreNeverGated` hold this.

**A build with no public key must behave as though licensing did not exist.** Every build except
the on-premise one has no key, and every one of those consoles would go read-only if that
defaulted the other way. This has already been broken once — `Status.Has()` returned false for
`not_enforced`, which would have 402'd every feature-scoped path on our own SaaS the moment the
gate was wired in. `TestNotEnforcedGrantsEveryFeature` and
`TestSaaSBuildIsUnaffectedByAnyOfThis` hold it now.

---

## Suggested order

1. **Item 1** (CEO, ten minutes) — everything else is blocked on it.
2. **Item 2** (release engineering) — the image, on a machine with Docker.
3. **Item 6** (clean-VM install) — before any customer.
4. **Item 3** (upload auth path) — needs the image from 2.
5. **Item 4** (console) — can start now in parallel; the API is finished and will not move.
6. **Items 5, 7, 8** — as they become real.
