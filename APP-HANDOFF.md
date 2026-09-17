# App handoff — everything you asked for, and one bug in your notes

Reference: [AUTHENTICATOR-BACKEND-CONTRACT.md](AUTHENTICATOR-BACKEND-CONTRACT.md) (full wire
contract) and [AUTHENTICATOR-TEST-VECTORS.md](AUTHENTICATOR-TEST-VECTORS.md) (byte-reproducible
signatures). This document is the delta and the answers — read it first, use those two as lookup.

**Status: migrations APPLIED to alpha; the code is not deployed yet.**

The schema on the alpha org database is now complete — migrations 001–008 applied and verified, so
`did.mfa_devices`, `did.mfa_device_identities` and `did.mfa_push_activity` all exist with every
column the device API needs. What is still pending is the **service binary**, so the new endpoints
(`/api/v1/device/*`, `selfEnroll`, the `requireBiometric` field, idempotent `/respond`) do not answer
yet. Existing endpoints are unaffected.

Applying the migrations turned up one thing worth knowing: `did.mfa_devices` was missing
`public_key` and `public_key_alg` — the columns that hold your signing key — because the migration
declaring them used `CREATE TABLE IF NOT EXISTS` against a table that already existed in an older
shape, so the declaration had been inert. Without those columns enrollment cannot store a key and no
signature can verify: the whole flow would have failed on a database where everything else looked
correct. Fixed in migration 008 and applied.

---

## 0. Read this first — a bug in your `data` key list

**The push `data` keys are `snake_case`, not camelCase.** You listed `challengeId`, `orgId`,
`tenantId`. The wire sends:

| key | present on | notes |
|---|---|---|
| `challenge_id` | both flows | pass to `getChallenge` / `respond` |
| `flow` | both | `ad` \| `platform` — selects the respond endpoint |
| `org_id` | both | **required** by `getChallenge` |
| `tenant_id` | both | |
| `fetch_token` | both | the credential for `getChallenge` |
| `expires_at` | both | RFC3339 |
| `base_url` | both | the deployment that issued this challenge |
| `type` | both | `ad_mfa` \| `platform_mfa` |
| `user_email`, `binding_message` | AD only | |
| `email` | platform only | |

Every value is a string — FCM rejects the whole send otherwise.

**And checking your list found a server bug.** The platform push carried `tenant_id` but **no
`org_id`**, while `getChallenge` requires `orgId` and answers 401 without it — so a platform
challenge was receivable and then permanently unresolvable. The AD push had the mirror-image gap:
`org_id` but no `tenant_id`. Neither shows up in a single-flow test, because each flow looks
self-consistent on its own. Both now carry the same identifying set, pinned by a test.

Thank you for the list — it's the only reason this was found before you hit it.

---

## 1. Your seven questions

**1 — Device key scoping. Your assumption is correct, and it is load-bearing exactly as you
described.** Use **one keypair per deployment (`baseUrl`)**, reused for every org and both flows on
that server.

The row is per **(deployment, org)** — device rows live in per-org databases and the merge is
`WHERE org_id = ? AND key_id = ?`. Your feared cross-org overwrite cannot happen, because those are
physically separate databases. But the hazard is real one level down: within a single org, if the
key does **not** match, enrollment falls through to an upsert on
`(org_id, push_transport, push_token)` — and your push token *is* the same — which overwrites
`public_key` on the existing row. So a *different* key per (deployment, org) is precisely what
breaks the first enrollment. Same key throughout: the merge matches and it's a no-op.

**2 — `base_url` in the push. Done.** Route on it, not on `org_id`. Your most-recently-enrolled
heuristic can go. Your instinct not to broadcast `getChallenge` across candidates was right and is
now a documented rule — that fetch token is a live credential and must never reach a server that
did not issue it.

**3 — `requireBiometric` on `getChallenge`. Done.**

```json
{ "status": "pending", "ttlSeconds": 60, "secondsRemaining": 47,
  "requireBiometric": true, "…": "…" }
```

Resolved with the same lookup the respond path enforces with, so you are never told one thing and
held to another. Prompt for user verification only when it's true.

**4 — `/respond` is now idempotent per `(challengeId, approved)`.**

| case | response |
|---|---|
| same decision repeated | **200** with `status` + `message` naming the recorded outcome |
| contradicting decision | **409** — first answer wins, a device cannot flip a verdict |
| challenge expired first | **400** `"challenge expired"` |

`409` is new — handle it as "already resolved", not a generic failure. Retrying a lost reply is now
safe.

**5 — `/accounts/list` is scoped to `X-Authnull-Device-Org`.** One call per (deployment, org). The
`device` block repeats with the same key id across orgs, which is expected. I added `orgId` to each
account row so a merged screen stays unambiguous:

```json
{ "device": { "deviceName": "Pixel 8", "hasBiometricKey": true, "…": "…" },
  "accounts": [ { "id": 7, "orgId": 2, "email": "…", "identityKind": "ad_user",
                  "displayName": "Work", "pushEnabled": true, "requireBiometric": false } ] }
```

**6 — Activity endpoint. Done.** `POST /api/v1/device/activity` (signed, like every other device
route).

```json
{ "before": "2026-08-11T09:02:14Z", "limit": 50, "statuses": ["denied"] }
```

```json
{ "items": [ { "flow": "ad", "challengeId": "1841", "email": "…", "status": "denied",
               "resolutionSource": "device",
               "resource": {…}, "location": {…}, "risk": {…},
               "bindingMessage": "…", "createdAt": "…", "respondedAt": "…" } ],
  "nextCursor": "2026-08-11T09:02:14Z" }
```

- Scoped to the **signed device** — there is no device id to send, deliberately: the table holds the
  whole organisation's challenges.
- `resource`, `location` and `risk` are the **same shapes** `getChallenge` returns, so one model
  parses both.
- Page with the previous `nextCursor` as `before`. **Absent `nextCursor` = last page.**
- `limit` defaults 50, caps 200. `statuses` is optional; unknown values are dropped.
- `resolutionSource` is `device` | `provider_poll` | `ttl` — the difference between "the user denied
  it" and "nobody answered", which is what makes the Activity screen worth showing.

Unhide the tab.

**7 — One Firebase project per deployment: `authnull-one`.** Build against it, or your registration
tokens belong to a different project and every send returns `INVALID_ARGUMENT`. Two orgs *within
one* deployment cannot use different projects; and since tokens are minted against whatever project
the binary is built with, per-customer FCM projects would mean per-customer app builds. **Say now if
that's on the roadmap** — it's cheap to know, expensive to retrofit.

---

## 2. Your confirmation list

| | |
|---|---|
| `FCM_SERVICE_ACCOUNT_JSON` | Set. Mounted read-only at `/run/secrets/…`. Verified with a real OAuth token exchange **from the deployment host**, not just locally. |
| Project id `authnull-one` | Matches the JSON. `FCM_PROJECT_ID` left empty so it derives from the file — one place to change on rotation. |
| `API_BASE_URL` | **Was missing from `.env` entirely.** It fell back to `SYSTEM_URL`, which is set, so invites were right *by luck of the fallback*. Now explicit. |
| `APP_IOS_URL` / `APP_ANDROID_URL` | Set, but to **placeholder** store paths. Send me the real ones. |
| `MFA_PUSH_CHALLENGE_TTL_SEC` | **60** ✓ |
| `MFA_PUSH_ALLOW_UNSIGNED` | Unset = **enforced** ✓. It was absent from `.env`; now present-but-empty with a comment, because an absent variable can't be confirmed by reading the file. |
| Notification + data, not data-only | ✓ A `notification` block with title/body alongside `data`, plus `aps.alert` on iOS. |
| Android channel `authnull_mfa` | ✓ `android.notification.channel_id`. Keep `default_notification_channel_id` in your manifest so background messages use it. |
| Migrations 005 + 006 applied | **YES on alpha**, along with 001–004, 007 and 008. Applied in one transaction, verified column-by-column against the code's requirements, row counts unchanged. The master database gets them from the boot loop at deploy. |

---

## 3. Also settled since you last read the contract

- **Deny is never blocked by `requireBiometric`.** A denial is accepted from the ordinary key with
  `userVerified: false`, even on a require-biometric account, and even from a v1 client. Refusing
  access is fail-safe; holding denials to the strict bar would leave a user whose biometric key was
  invalidated unable to refuse anything while an attacker keeps retrying. A denial still has to be
  **signed** — only the choice of key is relaxed.
- **The nonce rule that isn't in your notes:** `X-Authnull-Device-Nonce` must be **16–128
  characters** of `[A-Za-z0-9-_]` only. Shorter fails as the same blanket `401` as everything else,
  which is undiagnosable from the client. 32 hex chars, or base64url of 16 random bytes, both fine.
  (My own first test vector used an 11-character nonce and the server rejected it.)
- **`signedAt`** is RFC3339 in **UTC** — `2026-08-12T09:14:31Z` — and must be the same string you
  signed, byte for byte, within 5 minutes of server time.

---

## 4. On you before we can test end to end

1. **Upload an APNs auth key to the `authnull-one` Firebase project.** Without it iOS pushes fail
   *silently* — FCM accepts the send and drops it. This is the most likely cause of "works on
   Android, nothing on iPhone", and it cannot be diagnosed from the server side.
2. **Real store URLs** for `APP_IOS_URL` / `APP_ANDROID_URL`.
3. **Confirm the app is built against `authnull-one`.**
4. **Create the `authnull_mfa` channel at first run** with max importance, before any push can
   arrive.

## 5. On us

1. Deploy — migrations 005/006/007 plus the code.
2. Confirm the schema guard reports clean afterwards (dry-run says it will, on both databases).

Once (1) lands, the full flow is testable: invite → scan → enroll → challenge → approve/deny →
activity.
