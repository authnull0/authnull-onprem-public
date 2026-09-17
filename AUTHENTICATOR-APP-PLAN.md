# AuthNull Authenticator (Flutter) — build plan

> **Superseded for the wire contract.** WP1–WP8 are implemented; the current, verified endpoint
> and payload reference is [AUTHENTICATOR-BACKEND-CONTRACT.md](AUTHENTICATOR-BACKEND-CONTRACT.md).
> Section 4 below records the original design and no longer matches the shipped shapes —
> notably the respond signature is flat with `signatureVersion` / `userVerified`, invites are
> v2 and carry a base URL, and `getChallenge` requires a fetch token.

Plan for the new push-MFA authenticator app and the backend work it requires.
Written against the code as of the `on-prem` branch, after the push-MFA
consolidation into [internal/mfapush](internal/mfapush).

The app serves two login surfaces that already exist server-side:

| Surface | Trigger | Server endpoints |
|---|---|---|
| AD / Windows domain login | AD sensor / gateway | `/api/v1/ad/InitiateMFAChallenge`, `GetMFAChallenge`, `RespondMFAChallenge` |
| Platform (console / SSC) login | browser session | `/api/v1/mfa/push/{challenge,respond,status}` |

---

## 1. Decisions

**Transport: FCM HTTP v1. Expo Push is not an option.**

`ExponentPushToken[...]` is issued only by `expo-notifications` inside an
Expo-managed React Native app, and `exp.host/--/api/v2/push/send` accepts only
those tokens. A Flutter app cannot obtain one. Firebase Cloud Messaging covers
Android natively and iOS via APNs (upload an APNs auth key to Firebase), and is
what `firebase_messaging` speaks.

HTTP v1 over the legacy server-key API: legacy is deprecated and closed to new
projects, and v1 is the only one still gaining features. Cost is an OAuth2
service-account credential instead of a static key.

**Responses are signed by the device.** See §2 — this is not optional.

---

## 2. Blocking security fix — RESOLVED

Today the approve/deny endpoints accept a challenge id and a boolean, with
nothing tying the call to the enrolled phone:

- `POST /api/v1/ad/RespondMFAChallenge` — `internal/ad/routes.go` applies no
  middleware, and [the handler](internal/ad/src/controller/mfa_push_controller.go)
  performs no secret check. Body is `{orgId, adChallengeId, approved}`.
- `POST /authentication/push/respond` — registered by `RegisterSscAuthRoutes`,
  which calls no `rg.Use(...)`, so the bare alias is unauthenticated. (The
  `/api/v1/mfa/push/respond` path *is* behind `AuthnzMiddleware`, which a phone
  cannot satisfy — so the app would have to use the unauthenticated alias.)

**`AdMfaChallenge.Id` is a sequential `autoIncrement` integer** returned to the
caller as `adChallengeId`. So within the 90-second window an attacker who can
reach the server can enumerate ids and approve a victim's pending domain login.
The platform flow is better — the challenge id is a UUID delivered only in the
push payload — but it is still a bearer secret with no device binding.

**Implemented** in [internal/mfapush/signing.go](internal/mfapush/signing.go) and
wired into both respond paths. The endpoints stay open at the middleware layer —
they must, the phone has no session — and the signature is the authentication
instead. Enumerating challenge ids is now useless without the private key.

This is why the app needs crypto rather than just a REST client:

1. **At enrollment** the app generates a P-256 keypair in hardware
   (iOS Secure Enclave / Android Keystore — P-256 is the portable choice that
   both back in hardware) and sends the **public key** with `confirmSetup` /
   `RegisterDevice`. The private key never leaves the device.
2. **At respond** the app signs a canonical string over the challenge id, the
   decision and a timestamp, and sends the signature.
3. **The server** resolves the challenge → its identity → that identity's linked
   device → the stored public key, verifies the signature, rejects timestamps
   outside a small window, and rejects a challenge whose identity is not linked
   to that device.

The request does not need to name the device: the challenge already knows which
identity it was raised for. This closes enumeration and unauthorised approval in
one step, and gives the AD audit trail non-repudiation it currently lacks.

---

## 3. Backend work packages

### B1 — transport-agnostic device registry — **DONE**

Folded into [002_mfa_devices.sql](db-init/migrations/002_mfa_devices.sql) rather
than left as a follow-up migration, since it had not run yet:

```sql
push_transport  text not null default 'expo'   -- 'expo' | 'fcm'
push_token      text not null
public_key      text                            -- base64 DER SPKI
public_key_alg  text                            -- 'ecdsa-p256'
UNIQUE (org_id, push_transport, push_token)
```

`Device` in [devices.go](internal/mfapush/devices.go) matches, enrollment takes a
`Registration` struct, and `DeactivateToken(orgID, transport, token)` is
transport-scoped. Both backfills tag existing rows `'expo'`.

The transport column is what makes the rollout survivable: during the transition
some users are on the old Expo app and some on the new Flutter app, and the
server must push to whichever each device registered with.

### B2 — signed responses — **DONE**

- `CompleteEnrollment` stores `publicKey` / `publicKeyAlg`, validated at
  enrollment so a device can never register an unverifiable key. A legacy
  re-enrollment that sends no key cannot strip a key already on record.
- `VerifyResponse` in [signing.go](internal/mfapush/signing.go): P-256 ECDSA over
  SHA-256 of the canonical payload, with a ±2 minute skew window.
- Wired into both respond paths, each resolving the device from the challenge
  (AD by the challenge's email, platform by the challenge's identity).
- **Signatures are required by default.** The device registry starts empty — no
  install has a single legacy Expo enrollment — so there is no keyless fleet to
  protect and a permissive default would only leave the respond endpoints open.
  `MFA_PUSH_ALLOW_UNSIGNED=true` is an escape hatch for debugging a device that
  cannot sign; an unparseable value fails secure. A signature that is *present*
  but wrong is rejected either way, so the hatch is never a forgery bypass.

### B3 — FCM sender

- `internal/mfapush/fcm.go` implementing the existing `Provider` interface —
  `NewProvider` gains an `fcm` case alongside `expo`.
- OAuth2 via service account: `FCM_SERVICE_ACCOUNT_JSON` (path or inline),
  `FCM_PROJECT_ID`. Cache the bearer token; it lasts an hour.
- Map the payload equivalents:

| Concept | Expo | FCM HTTP v1 |
|---|---|---|
| Actionable buttons | `categoryId: "auth_request"` | `apns.payload.aps.category`; Android actions are declared app-side on the channel |
| Mutable content | `mutableContent: true` | `apns.payload.aps["mutable-content"]: 1` |
| High priority | `priority: "high"` | `android.priority: "HIGH"`, `apns-priority: 10` |
| Dead token | ticket `DeviceNotRegistered` | `UNREGISTERED` / `INVALID_ARGUMENT` → `DeactivateToken` |
| Data | `data` (strings) | `data` (**string values only** — FCM rejects non-strings) |

Note the last row: `PlatformChallengeMessage` currently sends `tenant_id` as an
int. FCM requires all `data` values to be strings, so the platform payload needs
`"tenant_id": "1"`.

- Replace the single `expoTokenRegex` in
  [push_handler.go](internal/mfa/handler/push_handler.go) with transport-aware
  validation (FCM tokens have no fixed shape — length/charset check only).

### B4 — make the platform push visible

`PlatformChallengeMessage` sends a data-only payload with no title or body. On
iOS a silent data push is throttled and will not reliably wake a killed app, and
nothing is displayed. The AD payload already gets this right (title, body,
category). Give the platform push the same treatment, or approvals will simply
not arrive on iOS.

### B5 — wallet — **DROPPED**

`internal/wallet` had a third Expo copy, but it is being removed wholesale by the
DID-removal work (`/api/v1/wallet/registerDevice` and
`/api/v1/wallet/updatePushToken` are already gone from the route table). Nothing
to do.

---

## 4. Wire contract for the app

Base URL is the tenant's server. Endpoints the **phone** calls are marked ☎.

### Enrollment

The invite arrives by email as a deep link. Two schemes exist today and both stay
valid — they resolve to the same token store:

```
authnull://ad-enroll?token=<t>&orgId=<o>              (AD invite)
authnull://mfa-push-enroll?token=<t>&tenantId=<t>&orgId=<o>&email=<e>
```

The app should register both and branch only on which confirm endpoint to call.

☎ **AD** — resolve the invite, then register:
```
GET  /api/v1/ad/GetEnrollmentDetails?token=<t>&orgId=<o>
  → {email, orgId, tenantId, userId}
POST /api/v1/ad/RegisterDevice
  {orgId, enrollmentToken, expoPushToken, platform, deviceName}
```

☎ **Platform**:
```
POST /api/v1/mfa/push/confirmSetup
  {email, tenantId, orgId, userId, enrollmentToken,
   expoPushToken, platform, deviceName}
```

Both now accept, alongside the legacy fields:

```json
{ "pushToken": "<fcm registration token>",
  "pushTransport": "fcm",
  "publicKey": "<base64 DER SPKI, P-256>",
  "publicKeyAlg": "ecdsa-p256" }
```

`expoPushToken` still works — the server takes `pushToken` when present and falls
back to it — so the legacy app needs no change. Token format is validated per
transport: the Expo wrapper for `expo`, a length/charset sanity check for `fcm`.

Invites are valid **7 days** (`EnrollmentTokenTTL`). Re-sending supersedes the
previous unused invite.

**One phone, both surfaces:** enrollment keys on `(org_id, push_transport,
push_token)`, so when the same device redeems the second invite the existing
device row is reused and only an identity link is added. One token, one push, and
one deactivation covering both. It still takes **two invites**, because nothing
links an AD user to a platform user — see §7.

### Challenge

Raised server-side, delivered as a push. Payload the app must parse:

| Field | AD | Platform |
|---|---|---|
| `data.type` | `ad_mfa` | `platform_mfa` |
| `data.challenge_id` | `AdMfaChallenge.Id` (int as string) | UUID |
| `data.user_email` / `data.email` | `user_email` | `email` |
| `data.org_id` | string | — |
| `data.tenant_id` | — | string (after B3) |
| `data.binding_message` | free text — **display it** | not sent |

Challenges live **90 seconds** (`DefaultChallengeTTL`). The binding message is
what lets the user tell a legitimate prompt from an attacker-triggered one; it
must be shown, not swallowed.

### Respond ☎

```
POST /api/v1/ad/RespondMFAChallenge      {orgId, adChallengeId, approved}
POST /authentication/push/respond        {challengeId, approved}
```

Plus `signature` and `signedAt`:

```json
{ "challengeId": "…", "approved": true,
  "signature": "<base64 ASN.1 DER ECDSA>",
  "signedAt": "2026-08-05T12:00:00Z" }
```

Signed bytes are SHA-256 of:

```
authnull-mfa-response-v1|<challengeId>|approve|<signedAt RFC3339 UTC>
```

`approve` becomes `deny` when declining. For AD, `<challengeId>` is the decimal
`adChallengeId`. The decision is inside the payload, so a captured approval
cannot be replayed as a denial, and a signature for one challenge will not verify
against another.

The platform path must use the bare `/authentication/...` alias — the
`/api/v1/mfa/...` one requires a session cookie the phone does not have.

### Status (not the app)

`/api/v1/ad/GetMFAChallenge` and `/api/v1/mfa/push/status` are polled by the
sensor and the browser respectively. The app never calls them.

---

## 5. Flutter app

**Packages:** `firebase_core`, `firebase_messaging`,
`flutter_local_notifications` (foreground display + Android actions),
`flutter_secure_storage` (invite state), plus platform channels or a Keystore/
Secure Enclave plugin for the P-256 key. `app_links` / `uni_links` for the deep
links.

**Screens:** enrollment (from deep link, confirm + name the device), account list
(one row per enrolled identity, showing which surface it covers), approval sheet
(who / what / where + binding message, Approve / Deny, live countdown), settings
(remove account, re-register token).

**Flows to get right:**

1. *Enrollment* — deep link → generate keypair → obtain FCM token → POST confirm
   → store which identity this account represents. Handle the app not being
   installed when the link is tapped (store-redirect then re-open).
2. *Approval, three app states* — foreground (show in-app sheet),
   background (notification with actions), **terminated** (this is the one that
   breaks; needs a visible notification, not data-only — see B4). Tapping an
   action must work without a full app start where possible.
3. *Expiry* — a 90s countdown, and a clean "this request expired" state. Do not
   let a stale notification sit there looking actionable.
4. *Token rotation* — FCM rotates tokens on reinstall, restore, and sometimes
   spontaneously. Implement `onTokenRefresh` → re-POST the new token for **every**
   enrolled identity, or the user silently stops receiving prompts. This is the
   single most common cause of "push MFA stopped working".
5. *Multi-account* — one phone can hold AD and platform identities across several
   orgs. Key local state on `(orgId, identityKind, identityId)`.

**Do not** put the private key in `flutter_secure_storage` — use the hardware
keystore so it is non-exportable.

---

## 6. Rollout

**There is nothing to migrate.** Verified against a live database: zero rows in
`did.ad_user_devices`, zero push rows in `did.mfa_methods`, zero rows in
`did.mfa_devices`. Push MFA has never been enrolled anywhere, so the coexistence
problem this section originally planned around does not exist. That removes three
things:

- **No signature grace period.** Enforcement is on by default (see B2).
- **No re-enrollment campaign.** Every user enrolls fresh on the Flutter app.
- **No dual-transport period in practice.** `push_transport` still selects the
  sender and is worth keeping, but only `'fcm'` will ever be written.

Consequently the Expo sender ([expo.go](internal/mfapush/expo.go)) and the two
backfill blocks in
[002_mfa_devices.sql](db-init/migrations/002_mfa_devices.sql) are dead code.
Both are harmless — the backfills are `to_regclass`-guarded and no-op on empty
inputs — and worth deleting once it is confirmed the legacy React Native app is
not published anywhere.

---

## 7. Open decisions

1. **FCM HTTP v1 confirmed?** Assumed yes. Needs a Firebase project and, for
   iOS, an APNs auth key.
3. **AD ↔ platform identity link.** Until one exists, a user with both a domain
   account and a console account needs two invites. Linking them is a product
   decision (are these the same person? matched how — manual, UPN rule, directory
   attribute?), not a refactor.
4. **Is the legacy React Native app published anywhere?** If not, the Expo
   sender and the migration backfills can be deleted outright.
5. **Offline fallback.** Duo/Okta Verify support TOTP when push cannot be
   delivered. TOTP already exists server-side (`/mfa/totp/*`); reusing it in the
   app would cover dead-network cases.

---

## 8. Phasing

| Phase | Work | Status |
|---|---|---|
| 0 | B1 registry: transport + key columns | **done** |
| 1 | B2 signed responses (log-only) | **done** |
| 2 | B3 FCM sender + transport-aware token validation | validation **done**; sender outstanding — blocks the app |
| 3 | B4 visible platform push | outstanding — blocks iOS |
| 4 | App: enrollment + approve/deny | ready once phase 2 lands |
| 5 | ~~Re-enrollment campaign, then enforce~~ | **not needed** — no legacy devices; enforcement already on |
| 6 | §7.3 AD ↔ platform identity link | product decision |
| 7 | Delete the Expo sender + migration backfills | once the legacy app is confirmed unpublished |

What remains before app work can start is the **FCM sender** (B3) and the
**visible platform push** (B4). Everything the app needs to *enroll* and *sign*
is in place.

**Caveat carried from the consolidation:** the device registry's SQL paths
(`CompleteEnrollment`'s upsert-and-link transaction, and the backfill in
`002_mfa_devices.sql`) have never executed against Postgres — no test DB driver
is vendored. Bring the stack up and verify the backfill populated
`did.mfa_devices` from both old stores before building on top of it.
