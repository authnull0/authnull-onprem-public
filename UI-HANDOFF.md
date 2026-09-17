# UI handoff — backend changes to build against

Everything here is **implemented and tested but not yet deployed**. It lands on the next deploy
of `authnull-service`. Nothing in this document is speculative; every endpoint and field was
read off the code, not a plan.

Read section 1 first — it is the only thing that can break a screen you already have.

---

## 1. BREAKING: `listConnections` now requires authentication

`POST /api/v1/databaseService/listConnections`
`POST /api/v1/database/listConnections`

Both now sit behind the session middleware. **Send `X-Authorization` with the session token**, the
same header you already send to `listDatabase` / `listUser` / `listUserPrivilege` in that module.

Without it: **`401 {"error":"Unauthorized"}`**.

### Also: the `userId` header is no longer trusted

This endpoint used to read `userId` from a request header and mint a database access token bound
to whatever user id you named. It now derives the user **from the session**. If you still send the
header:

- session resolves → the header is **ignored** (and a mismatch is logged server-side)
- session cannot resolve → the header is used, and a deprecation warning is logged

You can stop sending it. Nothing else changes about the request or response body.

**Why it changed:** the endpoint was reachable from the internet with no credentials, and the token
it creates is what the database proxy resolves to authorise a login. That made it a
credential-minting endpoint for any named user.

**What to test after deploy:** open the database connections screen. If it 401s, the session header
isn't being attached on that call.

---

## 2. NEW: self-enrollment QR for the Authenticator app

`POST /api/v1/mfa/push/selfEnroll` — session-authenticated, **empty body**.
(also reachable at `POST /authentication/mfa/push/selfEnroll`; either is fine)

```json
{
  "payload":     "<compact base64url>",
  "deepLink":    "authnull://enroll?v=2&d=…",
  "qrPngBase64": "iVBORw0K…",
  "orgName":     "Acme Corp",
  "orgHost":     "acme.authnull.com",
  "email":       "satyam@authnull.com",
  "role":        "Org Admin",
  "roleSource":  "role",
  "expiresAt":   "2026-08-18T09:14:22Z"
}
```

This replaces "wait for an invite email" for a signed-in admin setting up their own device.

**Render `qrPngBase64` directly** — `<img src="data:image/png;base64,…">`. Don't generate the QR
client-side from `payload`; the server's encoding is tuned to keep the QR version low so it scans
off a laptop screen, and re-encoding loses that.

**There is deliberately no `orgId`, `email` or `userId` field to send.** The identity comes only
from the session. Please don't add body fields "to be explicit" — accepting them would make this
endpoint able to mint an invite for someone else's account.

Suggested placement: Profile / Security → "Set up AuthNull Authenticator". Show `orgName`,
`email`, and a countdown from `expiresAt` (7 days). `roleSource` tells you what `role` means:
`"role"` = a real product role, `"job_title"` = an AD job title. **Label them differently** — don't
print a job title under a heading that says Role.

---

## 3. Identity Providers / AD screens

The detailed spec is in **[AD-IDENTITY-PROVIDERS-UI-TASK.md](AD-IDENTITY-PROVIDERS-UI-TASK.md)** —
mode as a control rather than a badge, per-DC sensor rows, the "Not Protected" explanation, last
sync. That document is still current. Two additions since it was written:

### 3a. The "Protected" badge has a real data source now

`POST /api/v1/policy/ad/mfaCoverage`

```json
{ "orgId": 2, "tenantId": 16, "domain": "authnull.lab",
  "adUsers": ["administrator", "jdoe"], "protocol": "kerberos" }
```

```json
{ "message": "ok", "code": 200, "status": "Success",
  "enforcementMode": "monitor",
  "coverage": [
    { "adUser": "administrator", "mfaRequired": false,
      "action": "mfa_required", "appliedAction": "allow", "targetedByPolicy": true,
      "policyId": "…", "policyName": "Admins need MFA", "matchReason": "group:Domain Admins" }
  ] }
```

- **Send only the page of usernames currently on screen.** Coverage is evaluated per user; this is
  not an endpoint to hand a 50,000-user directory.
- **Render `appliedAction`, not `action`.** `action` is what the *policy* says; `appliedAction` is
  what would *actually happen right now*. They differ whenever `enforcementMode` is `"monitor"`,
  where every denying action becomes `allow` because a monitored domain challenges nobody. The
  example above is exactly that case: the policy requires MFA, and nobody is being prompted.
  (Same distinction, same names, as `did.auth_logs.decision` / `applied_decision`.)
- `mfaRequired` follows `appliedAction`, so it is a straight answer to "will this person be
  prompted?" and is safe to bind a badge to directly.
- **`action` can be `"unknown"`**, alongside `allow` | `block` | `mfa_required`. It means the
  policy could not be evaluated or could not be read — *not* that the user is unrestricted. Show
  it as a warning, never as a green tick: enforcement refuses what it cannot determine, so a
  reassuring cell here would be the screen disagreeing with the login path about the one user
  whose policy is broken.
- **`targetedByPolicy` splits the two kinds of `allow`.** `false` means no rule mentions this
  person. `true` with no `policyId` means a policy *does* target them but does not cover the
  protocol being displayed — `matchReason` says which predicate missed. Worth distinguishing in
  the UI: an admin who has just written a policy and sees a bare "no policy" concludes it did not
  save.
- `matchReason` is worth surfacing in a tooltip: it says *why* ("group:Domain Admins", "user
  match", "policy does not cover protocol \"ntlm\""), which is the difference between a badge and
  an explanation.
- `protocol` defaults to `kerberos`. Policies can be protocol-scoped, so **state which protocol
  the screen is showing** — a user can be covered for one and not another.

This is answered by the same matcher the DC sensor's real decision goes through, and
`appliedAction` runs through the same monitor-mode predicate the live login path uses, so the
badge cannot disagree with what happens at login. It is deliberately **not** read from
`ad_users.mfa_flag`, which goes stale for any user synced after a policy was approved.

### 3b. ~~"What happens if I turn enforcement on"~~ — WITHDRAWN

`POST /api/v1/policy/ad/simulate` — WITHDRAWN, and no longer registered. Nothing was built
against it, so there is nothing for the UI to change; this note exists so anyone who read the
earlier handoff knows it was removed rather than renamed.

It replayed `did.auth_log` through the policy set to forecast "12 users would be challenged, 2
would be denied". The AD decision is moving to `authn-service`, and a forecast that evaluates
policies with a second, separate copy of the matcher is exactly the divergence the shared matcher
exists to prevent — the forecast and enforcement can disagree, and the forecast is the one an
admin trusts before flipping to enforce. If the confidence step comes back it has to ask the
service that actually decides, in a dry-run mode.

The enforcement-mode toggle (3a's neighbour) is unaffected.

---

## 4. Health endpoint now reports schema drift

`GET /system/v1/health` (also `/readiness`, `/liveness`)

```json
{ "status": "ok", "schema": { "ok": true } }
```

or

```json
{ "status": "ok",
  "schema": { "ok": false,
              "problems": ["alpha: did.auth_logs is missing decision — policy LogAuthDecision …"] } }
```

Still **HTTP 200 either way** — the service is serving; drift degrades one feature, it does not
mean unhealthy. Don't treat `schema.ok === false` as a service outage.

If there's an admin diagnostics or system-status view, this is worth surfacing: each problem
string already names the database, the missing column, and **what stops working**. If there isn't
such a view, ignore this section — it's for operators, not end users.

---

## 5. Things that did *not* change

Called out because it's easy to assume otherwise from the release notes:

- No changes to login, MFA setup (TOTP / SMS / WebAuthn), tenant, user, PAM or dashboard endpoints.
- No changes to any request or response shape you already consume, **except** the two
  `listConnections` paths in section 1 — and there only the auth requirement, not the body.
- The database module's other endpoints are untouched.
- `GET /ad/getEnrollmentDetails` gained fields (`reason`, `orgName`, `orgHost`, `role`,
  `roleSource`, `baseUrl`, `kind`, `expiresAt`) but kept every existing one. Additive only. It is
  primarily consumed by the mobile app; if the console renders an invite page, `reason` is the
  field to branch on — it is populated on the 404s too, and distinguishes
  `used` / `expired` / `unknown`.

---

## 6. Not for the UI

New endpoints under `/api/v1/device/*` and the push respond/getChallenge paths are for the mobile
app. They authenticate with an **ECDSA request signature**, not a session, so they are not callable
from the browser and are not CORS-usable. Their contract is
[AUTHENTICATOR-BACKEND-CONTRACT.md](AUTHENTICATOR-BACKEND-CONTRACT.md).

One exception worth knowing: `POST /api/v1/device/discover` is unsigned, but it is **off by
default** and returns 404 unless an operator enables it. Don't build against it.

---

## Questions

For anything ambiguous here, the authoritative source is the route registration in
`cmd/authnull-service/routes.go` plus the DTOs in each module's `dto` package — both are current.
Ask rather than infer a field; several shapes in this repo have a near-identical sibling
(`did.auth_log` vs `did.auth_logs`, `dashboard/models` vs `dashboard/models/dto`) and guessing
between them wastes a day.
