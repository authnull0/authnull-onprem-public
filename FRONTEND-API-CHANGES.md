# Frontend API changes — login, password reset, users list

Backend changes are done and building. This is what the console (`self-service-console`)
needs to change, and one page it needs to add.

Base URL below is `SYSTEM_URL`, e.g. `https://onprem.dev.authnull.com`.

**Three things changed:**

1. Login now **requires a password**. The wallet-pairing step is gone.
2. Password reset works, but is **missing its frontend page** — needs building.
3. There's a **new endpoint** for listing platform users (the Users page).

---

## 1. Login — password is now mandatory

### What changed and why

Previously the tenant's primary factor was seeded as `Passwordless`, so
`getTenantAuthFactor` returned `nextaction` pointing straight at the second factor and
the console never collected a password. `Passwordless` meant *wallet-credential login*;
with the wallet removed from signup and logon there is nothing behind it, so the primary
factor is now `Username and Password`.

Separately, `normalLogin` used to skip password verification entirely unless
`factor === "PASSWORD"`. It no longer does — **verification runs on every request that
can return a session**, whatever `factor` says. A request with an empty password now gets
`401`, where before it returned a valid session token.

### The sequence

**Step 1 — resolve the tenant's factors** (unauthenticated)

```
POST /api/v1/tenants/getTenantAuthFactor
{ "url": "default.alpha.dev.authnull.com", "requestId": "<uuid>" }
```

```json
{ "code": 200, "status": "success",
  "factors": [
    { "name": "Username and Password", "type": "PRIMARY",   "order": 1 },
    { "name": "TOTP",                  "type": "SECONDARY", "order": 2 },
    { "name": "Passkey",               "type": "SECONDARY", "order": 3 }
  ],
  "nextaction": "PASSWORD" }
```

`nextaction` will now be **`"PASSWORD"`**, not a factor name. Drive off this.

**Step 2 — validate the username** (optional, unauthenticated)

```
POST /authentication/okta/normalLogin
{ "username": "user@example.com", "url": "default.alpha.dev.authnull.com",
  "password": "", "factor": "PASSWORD" }
```

```json
{ "code": 200, "status": "ok", "message": "Username validated",
  "username": "user@example.com", "first_login": "0" }
```

Confirms the address exists before showing the password field. Returns **no session** —
`access_token` is absent. Only `factor: "PASSWORD"` with an empty password behaves this
way; any other combination is treated as a real login attempt.

**Step 3 — verify the password** (unauthenticated)

```
POST /authentication/okta/normalLogin
{ "username": "user@example.com", "password": "<password>",
  "url": "default.alpha.dev.authnull.com", "factor": "PASSWORD" }
```

```json
{ "code": 200, "status": "ok", "first_login": "0",
  "access_token": "<session id>", "sso_mfa": false,
  "url": "...", "wallet_status": "Registered" }
```

`access_token` is the session id. **Send it as `X-Authorization` on every authenticated
call from here on** — including the MFA endpoints in step 4.

Error responses (all now correct status codes; they used to be `500`):

| condition | HTTP | `message` |
|---|---|---|
| unknown username | **401** | `Invalid Username` |
| wrong password | **401** | `Invalid Password` |
| no password sent | **401** | `Password is required` |
| user has no password set | **401** | `Password not set for user` |

`401` on `Invalid Username` and `Invalid Password` is intentionally indistinguishable —
please surface a single "invalid email or password" message rather than revealing which.

> `wallet_status` is still returned and still reads `"Registered"`. That is a deliberate
> stub so the current bundle skips `<AppInstall/>`. Once the wizard gate is removed from
> `authFlow.jsx`, tell us and we'll stop sending it. **Do not build new logic on it.**

**Step 4 — second factor.** Unchanged; you already call these. `X-Authorization` required.

```
POST /authentication/mfa/status              → which factors this tenant offers / user has
POST /authentication/auth/verifyUser         → the user's enrolled factors
POST /authentication/mfa/totp/beginSetup     { email, url }
POST /authentication/mfa/totp/confirmSetup   { email, url, secret, code }
POST /authentication/mfa/totp/verify         { email, url, code }
POST /authentication/mfa/beginAuthRegistration   (passkey enrol begin)
POST /authentication/mfa/finishRegistration      (passkey enrol finish)
POST /authentication/mfa/beginAuthentication     (passkey login begin)
POST /authentication/mfa/finishAuthentication    (passkey login finish)
```

One naming note: the factor is now called **`Passkey`** everywhere (it used to be seeded
as `webauthn`, which never matched the `selectedMFA === "Passkey"` check). `mfa/status`
returns `"Passkey"` in `configured_methods[].name` and `getTenantAuthFactor` returns
`"Passkey"` in `factors[].name`. Passkey enrolment was completely broken before and now
works, so it is worth re-testing.

---

## 2. Password reset — needs a new page

The backend flow is complete. **There is currently no console page to land on**, so the
emailed link 404s. This is the main piece of frontend work.

**Step 1 — request the email** (unauthenticated)

```
POST /api/v1/tenants/checkUserandSendMail
{ "email": "user@example.com", "url": "default.alpha.dev.authnull.com",
  "orgId": 2, "tenantId": 1 }
```

```json
{ "code": 200, "status": "success",
  "message": "If that account exists, a password reset email has been sent" }
```

**Always 200, even for an unknown address** — that is deliberate, so the endpoint cannot
be used to discover which accounts exist. Show the same confirmation regardless; do not
try to detect whether the user exists. (`orgId`/`tenantId` are accepted but unused; the
org comes from `url`.)

**Step 2 — the page you need to build**

The email links to:

```
{PASSWORD_RESET_URL}?token=<token>&user_name=<email>
```

defaulting to `{CLIENT_URL}/ssc/reset-password`. Tell us the route you want and we'll set
`PASSWORD_RESET_URL` to match.

The page should read `token` from the query string, collect the new password twice, and
POST:

```
POST /api/v1/tenants/forgotPassword
{ "token": "<token from the query string>",
  "newpassword": "<new>", "confirmpassword": "<new>" }
```

```json
{ "code": 200, "status": "success", "message": "..." }
```

| condition | HTTP | `message` |
|---|---|---|
| invalid / expired / already-used token | **401** | `Reset link is invalid or has expired` |
| passwords differ | **400** | `Passwords do not match` |
| password empty | **400** | `Password is required` |

Important details:

- **`email` and `url` in the body are ignored.** The account is identified by the token
  alone. Previously the reset applied to whatever email was in the body, which let any
  valid token change any user's password — that is fixed, so don't rely on those fields.
  You may display `user_name` from the query string, but it is not trusted input.
- **The token is single-use and valid for 15 minutes.** After a successful reset it is
  consumed; a second submit returns `401`. Handle that (show "request a new link").
- After a successful reset, send the user to login. The password is written to the same
  store login reads, so it works immediately.

---

## 3. Users page — new endpoint

For the platform/console identities: the tenant's **ADMIN** and **ENDUSER** accounts.
These are a different population from the two lists already on that page — AD users
(`did.ad_users`) and wallet users — and had no endpoint before.

```
POST /api/v1/tenants/listPlatformUsers        (X-Authorization required)
{ "url": "default.alpha.dev.authnull.com",
  "roles": ["ADMIN", "ENDUSER"],
  "status": "all",
  "search": "",
  "page": 1, "pageSize": 25 }
```

```json
{ "code": 200, "status": "success", "message": "Users fetched successfully",
  "counts": { "total": 4, "active": 4, "inactive": 0, "pending": 0 },
  "page": 1, "pageSize": 25,
  "data": [
    { "userId": 2, "email": "saffran@authnull.com",
      "firstName": "saffran", "lastName": "s",
      "role": "ADMIN", "roleId": 1, "status": "active",
      "tenantId": 1, "firstLogin": 1, "mfaEnrolled": ["Passkey"] }
  ] }
```

Field notes:

- `counts` is for the TOTAL / ACTIVE / PENDING tiles. It **ignores the `status` filter**,
  so the tiles keep showing the full breakdown while a status tab is selected.
- `status` accepts `active` / `inactive` / `pending` / `all` (or omit), case-insensitive.
- `roles` may be omitted → both ADMIN and ENDUSER. Requesting `"SUPERADMIN"` returns
  **400**: that is an organisation-level role stored in a different database and is out of
  scope for this endpoint.
- `search` matches email, first name or last name, case-insensitively.
- `pageSize` defaults to 25, capped at 200. `page` is 1-based.
- `mfaEnrolled` lists factors the user has actually set up, e.g. `["TOTP"]`,
  `["Passkey"]`, or `[]`.

Everything in `data` is safe to render. (Note: **do not** use the older
`/api/v1/user/userlist` — it returns the full user row including the password hash.)

---

## Summary of frontend work

| # | Work | Notes |
|---|---|---|
| 1 | Collect and send the password on login | `nextaction` is now `"PASSWORD"` |
| 2 | Map 401s to a single "invalid email or password" | don't leak which was wrong |
| 3 | **Build the reset-password page** | reads `token` from query, POSTs `forgotPassword` |
| 4 | Handle single-use/expired reset tokens | 401 → "request a new link" |
| 5 | Point the Users page at `listPlatformUsers` | remove the Wallet Users tab |
| 6 | Re-test passkey enrol/login | was broken before, now works; factor is `Passkey` |
| 7 | *(follow-up)* drop `digitalWalletRegistered` from `authFlow.jsx` | lets us remove the `wallet_status` stub |

Tell us the reset-page route and we'll set `PASSWORD_RESET_URL`.
