# UI handoff — per-user MFA: login shows only enrolled factors, Settings → MFA → Add/Update

Backend is **implemented and tested, not yet deployed**. Lands on the next `authnull-service`
deploy together with migration `011_user_mfa_config_unique.sql` (applied automatically on boot).
Approved plan: [MFA-SELF-SERVICE-PLAN.md](MFA-SELF-SERVICE-PLAN.md).

**No new endpoints.** One existing response gained three fields; everything else you already call.

---

## 1. What the backend fixes (so you know what stops happening)

`did.user_mfa_config` had no unique index and the enrol path did a blind INSERT, so every
re-registration appended another row. A user with one passkey therefore got `Passkey` in the
factor list **twice** — which is why "use another method" appeared to offer nothing but Passkey
again, and why re-adding a removed factor left a dead row behind.

Enrolment is now an upsert on `(user_id, tenant_id, mfa_type)`: **one row per user per factor,
always.** Duplicates already in the database are collapsed by the migration.

---

## 2. CHANGED: `POST /api/v1/mfa/status` now says what the *user* enrolled

(also reachable at `POST /authentication/mfa/status` — either is fine)

Request is unchanged — session header plus:

```json
{ "email": "satyam@authnull.com", "url": "tenantname.orgname.authnull.com" }
```

Response — new fields marked:

```json
{
  "user_id": 42,
  "email": "satyam@authnull.com",
  "mfa_enabled": true,
  "mfa_default_method": "Passkey",
  "configured_methods": [
    {
      "tenant_id": 1,
      "name": "TOTP",
      "display_name": "Authenticator App (TOTP)",
      "description": "TOTP",
      "status": "Active",
      "is_default": false,
      "factor_id": 1,          // NEW - did.mfa_config.id, stable per factor
      "enrolled": false        // NEW - has THIS user registered it
    },
    {
      "tenant_id": 1,
      "name": "Passkey",
      "display_name": "Biometric/Passkey Authentication",
      "description": "Passkey",
      "status": "Active",
      "is_default": true,
      "factor_id": 9,
      "enrolled": true,
      "enrolled_at": "2026-08-18T10:00:00Z"   // NEW - only when enrolled
    }
  ],
  "total_methods": 2,
  "enrolled_methods": 1        // NEW - how many of the above have enrolled = true
}
```

Read the three fields carefully — they answer different questions:

| Field | Means |
|---|---|
| `status` | the **tenant** offers this factor (unchanged meaning) |
| `enrolled` | **this user** has registered it |
| `mfa_enabled` | the **tenant** has ≥1 second factor configured (unchanged — do **not** repurpose it) |
| `enrolled_methods` | count of `enrolled == true` |

`is_default` / `mfa_default_method` now prefer an **enrolled** factor, falling back to the
tenant's first factor when the user has enrolled nothing. Previously it could preselect a factor
the user had never set up.

`configured_methods` order is the tenant's factor order and is unchanged.

Dispatch on `name` (`"Passkey"`, `"TOTP"`), as the console already does — not on `display_name`.

---

## 3. Login screen

1. Call `mfa/status` as today.
2. `enrolled_methods == 0` → **first-time enrolment step**: offer every entry in
   `configured_methods`, user picks one, run the setup flow in §4. This is the only screen that
   shows unenrolled factors.
3. `enrolled_methods >= 1` → render **only** entries with `enrolled == true`, preselecting
   `is_default`.
4. **"Use another method" link: render it only when `enrolled_methods > 1`.** With exactly one
   enrolled factor the link must be absent — today it renders and re-lists the same single
   factor, which is the bug users are reporting.

`POST /api/v1/mfa/auth/verifyUser` still returns the same enrolled list if you prefer it for the
login path; it no longer returns duplicates either. It just has no `factor_id` / tenant-catalog
context, so §4 needs `mfa/status`.

---

## 4. Settings → MFA → Add/Update

One row per entry in `configured_methods`, with a single action button:

- `enrolled == false` → **Add**
- `enrolled == true` → **Update**, plus show `enrolled_at`

Both open the **same existing setup dialog** for that factor — Add and Update are the same call.
The upsert is what keeps Update from duplicating the enrolment. What "Update" *means* differs per
factor, so word the buttons accordingly:

**TOTP — Update replaces the secret** ("Re-scan QR")

```
POST /api/v1/mfa/totp/beginSetup    { "email", "url" }
   -> { "secret", "qr_code", "manual_entry", "issuer", "account", "otpauth_url" }
POST /api/v1/mfa/totp/confirmSetup  { "email", "url", "secret", "code" }
   -> { "success": true, "message", "backup_codes": ["ABCD-EFGH", ...] }
```

Warn before starting: the old authenticator entry **stops working** once confirmSetup succeeds,
and it issues a **fresh set of backup codes** that invalidates the previous set. Show the new
codes once, on Update as well as Add.

**Passkey — Update adds another device** ("Add another device")

```
POST /api/v1/mfa/beginAuthRegistration  { "email", "url" }
   -> { "publicKey": { ... } }        // pass straight to navigator.credentials.create()
POST /api/v1/mfa/finishRegistration     { "email", "url", "credential": <attestation response> }
   -> { "success": true, "message", "credential_id" }
```

Unchanged from the flow the first-time enrolment screen already uses. Two things about Update
here: existing passkeys **keep working** (credentials accumulate; the row in the factor list is
just "this user has Passkey"), and `beginAuthRegistration` sends the user's existing credentials
as `excludeCredentials`, so re-registering the **same** authenticator fails in the browser with
`InvalidStateError` before any request is sent. Catch that name and show "this device is already
registered" rather than a generic failure — it means the user needs a *different* device.

After either flow succeeds, re-fetch `mfa/status` to repaint the page — the new factor is live at
the next login with no further action.

### Not in this scope

- **No Remove / un-enrol button.** `totp/delete` and `deletePasskey` exist but stay unused here;
  ship Add/Update only. (Consequence: no last-factor lockout case to design for.)
- No per-user "make this my default" control — `user_mfa_config` has no such column yet;
  the default is derived as described in §2.
- SMS and Push are not offered on this page even if the tenant enables them.

---

## 5. Test after deploy

- Fresh user, enrol Passkey → login shows Passkey only, **no** "use another method" link.
- Settings → MFA → Add TOTP → next login shows both factors, link present.
- Same starting from TOTP.
- Update an already-enrolled factor → still exactly one row in the list; the new
  passkey/secret is the one that works, the old one does not.
- Existing user who had duplicated rows → the duplicate entry is gone after the deploy.

## 6. One thing to flag back

`mfa/status` takes the email from the request body (session-gated, but not session-*bound*), so it
will report another user's enrolled factors if you send their email. Pre-existing behaviour, not
touched here — worth a follow-up ticket, not a blocker for these screens.
