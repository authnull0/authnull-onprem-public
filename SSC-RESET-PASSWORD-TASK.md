# Task: add `/ssc/reset-password` to self-service-console

**Why:** the backend reset flow is complete and the email goes out with a valid link — but
that link points at `/ssc/reset-password`, which has no route yet, so it renders a **blank
page**. This page is the last missing piece; until it exists, password reset cannot be
completed by a user.

**This is blocking**, not a tidy-up. Passwords are now mandatory at login, so this is the
only self-service recovery path.

**Backend is ready and already points at this page.** The emailed link is
`/ssc/reset-password` today, so the moment your route exists it starts working — no backend
change, no env var, no coordination needed.

---

## What the user arrives with

```
https://onprem.dev.authnull.com/ssc/reset-password
  ?token=77534b1d-d3bd-436a-b55a-510464af6671
  &user_name=guptasatyam1807%40gmail.com
  &url=default.alpha.dev.authnull.com
```

Note the host is the **console** host, not the tenant's. The SSC is served on both, so either
works and no nginx or CORS change is needed — but it does mean the page cannot infer the
tenant from its own hostname. Use the `url` param (and the `url` in the reset response) for
that, which you need for the redirect anyway.

| param | use |
|---|---|
| `token` | send it back verbatim. **Required.** |
| `user_name` | display / prefill only. Not trusted, not needed by the API. |
| `url` | the tenant domain — use it to seed `domainUrl` so the redirect to signin works. |

---

## Steps

### 1. `src/api/clients/tenantClient.js` — add the path

```js
const path = {
  tenantAuthFactor: "/getTenantAuthFactor",
  resetPassword: "/checkUserandSendMail",
  forgotPassword: "/forgotPassword",        // add
};

const TenantNetworkManager = {
  // ...
  forgotPassword: async (params) => {       // add
    return await requests.post(path.forgotPassword, params);
  },
};
```

Same `TENANTS_BASE_URL` instance as the existing calls.

### 2. `src/api/redux/slices/tenantSlice.js` + `sagas/tenantSaga.js`

Add a `submitNewPassword` action alongside `resetPasswordLink`, and a saga watcher next to
the existing one:

```js
yield takeLatest(submitNewPassword.type, fetchSubmitNewPassword);
```

Mirror `fetchResetPassword` in `tenantSaga.js`. The saga needs to surface success and
failure distinctly — see step 5.

### 3. `src/pages/resetPassword.jsx` — new page

Use the same building blocks as `pages/factors/signin.jsx`: `SplitShell`, `ANField`,
`ANButton`, `AN_COLORS`, and `showCustomError` / `showSuccessAlert` from
`utils/alertService`. `useSearchParams` for the query params.

Fields: **New password**, **Confirm password**. Prefill/show the email from `user_name`
(read-only is fine).

### 4. `src/router/routes.js` — register it

```js
const routes = [
  { path: "signin", element: <AuthFlow /> },
  { path: "reset-password", element: <ResetPassword /> },   // add
  { path: "logout", element: <Logout /> },
];
```

Put it in the `routes` array (not as a sibling of `service-maintenance`) so it inherits
`LayoutView` and the `AlertProvider` / `TenantProvider` / `AuthProvider` wrappers.

> Note: `/ssc/reset-password` currently renders **blank** rather than redirecting, because
> it matches the parent `/ssc/*` route and then finds no child, so `<Outlet/>` renders
> nothing. Adding the child route is the whole fix.

### 5. The submit

```
POST {TENANTS_BASE_URL}/forgotPassword
{ "token": "<from query>", "newpassword": "<p1>", "confirmpassword": "<p2>" }
```

**Do not send `email` or `url`** — the backend ignores both and identifies the account from
the token. Sending them is harmless but misleading.

Responses:

| HTTP | `message` | UI |
|---|---|---|
| **200** | `Password is reset successfully` | success → redirect (step 6) |
| **401** | `Reset link is invalid or has expired` | "This link has expired or was already used — request a new one", with a link back to signin |
| **400** | `Passwords do not match` | field-level error |
| **400** | `Password is required` | field-level error |

Validate the match client-side too, but keep the 400 handling — the backend checks as well.

The **401 is expected in normal use**: tokens are single-use and last 15 minutes, so a
refresh or double-submit legitimately produces it. Don't treat it as a bug.

### 6. On success — redirect

The 200 response also carries the tenant domain:

```json
{ "code": 200, "status": "success",
  "message": "Password is reset successfully",
  "url": "default.alpha.dev.authnull.com" }
```

Prefer `response.url`; fall back to the `url` query param. Then:

```js
setLocalStorageItem("URL", domain);          // or whatever key getDomainUrl() reads
navigate(`/ssc/signin?url=${encodeURIComponent(domain)}`);
```

Seeding the domain matters: without it the signin page hangs on *"Resolving authentication
factors"*, because `getTenantAuthFactor` needs the tenant URL. Using the response value
means it works even if the query string was mangled by a mail client.

Show a brief "Password updated" confirmation before redirecting.

---

## Reference implementation

did-react's `src/components/unauthorized/tenant/ForgotPassword.js` (branch
`production-az`) already does all of this — read `token`/`user_name` from the query,
prefill, POST, redirect. Worth copying the shape from; just don't copy its `url` payload
field (unnecessary now) or its `/tenant/login` redirect target.

## Testing

The emailed link already points at this route, so once it exists you can test with a real
reset email. To test before that, or to iterate quickly:

1. Trigger a reset from `/ssc/signin` → **Forgot password?** (or via the API).
2. Get the token — ask backend, or from Redis (needs the password):
   ```
   sudo docker exec authnull-service-redis-1 redis-cli -a <REDIS_PASSWORD> \
     --no-auth-warning --scan --pattern 'tenant:pwreset:*'
   ```
   `GET tenant:pwreset:<uuid>` shows the bound email + org, useful for confirming which
   account you are resetting.
3. Open `https://default.alpha.dev.authnull.com/ssc/reset-password?token=<token>&user_name=<email>&url=default.alpha.dev.authnull.com`
4. Submit; confirm the redirect and that the new password works at `/ssc/signin`.

Each token is single-use — get a fresh one per attempt.

## Done when

- [ ] `/ssc/reset-password` renders (no blank page)
- [ ] Valid token → password changes → redirected to `/ssc/signin` with factors resolving
- [ ] Reused/expired token → clear "expired" message, not a crash or blank screen
- [ ] Mismatched passwords → field error
- [ ] New password works at `/ssc/signin`

Nothing needed from backend when you're done — the link already targets this route.

One thing to be aware of: `did-react`'s `/tenant/forgot-password` will then be half-live —
its "enter your email" step still works, but its set-password form will no longer receive
links. Worth deciding separately whether to point its "Forgot password?" at this page.
