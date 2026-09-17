# Task: Authenticator enrollment — get users onto the app

**Backend:** done and verified. Needs deploy.
**Related:** [UI-HANDOFF.md](UI-HANDOFF.md) (what changed overall),
[AD-IDENTITY-PROVIDERS-UI-TASK.md](AD-IDENTITY-PROVIDERS-UI-TASK.md) (the Identity Providers row
work, still current).

## Why

There is currently no screen that answers *"has this rollout actually happened?"* An admin can
configure a provider, create a policy, and have no way to see that four of nine users are getting in
without MFA because they never enrolled. There is also no way to enrol an AD user whose `mail`
attribute is empty or routes nowhere — which on the reference deployment is **every user**, since all
nine have `@authnull.lab` addresses that deliver to nothing.

Three pieces, in build order. Piece 1 is a guard that makes the other two safe to show.

---

## 1. Provider awareness — build this first

`POST /api/v1/ad/GetEnrollmentSummary`

```json
{ "orgId": 2, "tenantId": 16, "domain": "authnull.lab", "days": 7 }
```

```json
{ "message": "ok", "code": 200, "status": "Success",
  "provider": "authnull", "enrollmentApplies": true,
  "totalUsers": 9, "enrolled": 3, "pendingInvites": 2, "notEnrolled": 6,
  "usersWithoutEmail": 4,
  "windowDays": 7, "bypassEvents": 18, "bypassUsers": 4,
  "topBypass": [ { "adUser": "administrator", "events": 9, "lastSeen": "2026-08-12T09:14:22Z" } ] }
```

**`enrollmentApplies: false` must hide every enrollment control on the screen.** Not disable —
hide, and show `MFA managed by {provider}` instead.

This is the whole reason the field exists. For `okta`, `duo` and `azure_ad` the second factor is
enrolled *in the vendor*, not with us, so `enrolled` will read **0 forever** while MFA works
perfectly. A screen that renders those numbers anyway tells an Okta admin their working deployment
is broken, and they will open a ticket about it.

| `provider` | `enrollmentApplies` | show |
|---|---|---|
| `authnull`, `fcm`, `expo`, `""` | `true` | the enrollment panel |
| `okta`, `duo`, `azure_ad` | `false` | "MFA managed by Okta" — nothing else |

Treat `enrollmentApplies` as authoritative and don't re-derive it from `provider`; the mapping lives
in the backend so a new provider doesn't need a frontend release.

`404 "unknown domain"` means the domain string didn't resolve. Both the AD FQDN (`authnull.lab`) and
the directory label the admin typed (`test01`) work, so send whichever the row already has.

### The MFA Provider screen is currently lying — fix this too

`POST /api/v1/ad/GetMFAProvider` — `{ "orgId": 2 }`

```json
{ "provider": "okta", "source": "env-default", "configuredForOrg": false,
  "domain": "", "host": "" }
```

Two new fields, and they matter more than they look.

`source` is `"org"` (an explicit choice saved for this organisation) or `"env-default"` (no row
exists, so `MFA_PROVIDER` from the deployment was inherited). `configuredForOrg` is true only when a
row exists **and** carries the credentials that provider needs.

On the current deployment, every org — alpha included — returns `source: "env-default"`,
`configuredForOrg: false`. The screen today shows **"Active provider: Okta Verify"** next to an
**"Encrypted per org"** badge, and **"Okta org URL: —"** below it. The empty URL is the truthful part:
there is no per-org config. Okta works because `okta.go` falls back to `OKTA_DOMAIN` /
`OKTA_API_TOKEN` from the deployment env.

That badge is asserting a security property that does not hold, and it hides a real multi-tenant
problem: on `env-default` a vendor provider inherits the *deployment's* credentials, so a second
customer onboarded onto the same box has their users looked up in the first customer's Okta org —
not found, every challenge reports not-enrolled, and nothing on screen says so.

| state | show |
|---|---|
| `source: "org"`, `configuredForOrg: true` | "Okta Verify — configured for this organisation" + the encrypted badge |
| `source: "org"`, `configuredForOrg: false` | "Okta Verify — **incomplete configuration**", and say which field is missing |
| `source: "env-default"` | "Okta Verify — **deployment default, not configured for this organisation**". **No encrypted badge.** |

Three more things in that screenshot to correct:

- **"AuthNull Authenticator — DEFAULT"** while Okta is active. The card claims default; the env makes
  Okta the actual default. Both cannot be shown. Drive the label from `source`.
- **"REMOVE ACTIVE PROVIDER TO SWITCH"** on the Duo card implies you must clear the active provider
  first — but on `env-default` there is nothing to clear. Verify that selecting **AuthNull
  Authenticator** and saving actually works today; that is precisely the path a new tenant needs, and
  if that rule blocks it, a new tenant cannot choose the app at all.
- The provider list must **include the AuthNull Authenticator**. `ValidateConfig` has always accepted
  `authnull` with no credentials, but the endpoint's own error message used to read *"supported
  providers: expo, duo, okta"* and omit it. That string is fixed; check the dropdown wasn't built
  from it.

**Why this is in the enrollment task:** selecting the Authenticator must write a row. If the
selection never reaches `POST /ad/SetMFAProvider` with `provider: "authnull"`, the tenant keeps
inheriting Okta — users enrol phones, the QR scans, the panel reports "3 of 9 enrolled", and no push
ever arrives, because every challenge is going to an Okta org those users do not exist in. Enrollment
count and *who actually gets asked* are separate facts.

---

## 2. Enrollment panel — on the Identity Provider / domain screen

Four numbers and one list. Suggested shape:

```
Authenticator enrollment                                    ⟳ last 7 days

  ●●●○○○○○○   3 of 9 enrolled          2 invites pending
              ⚠ 4 users have no email address  → they need a QR code
              ⚠ 4 users signed in without MFA (18 times)  → view

  [ Send invites to unenrolled users ]
```

**`usersWithoutEmail` is the number that silently caps an email-only rollout.** If it's non-zero,
say so and link to the per-user QR flow (piece 3) — otherwise an admin sends invites, sees nothing
happen, and has no idea why.

**`bypassUsers` / `bypassEvents` is the important one.** These are logins the sensor *allowed*
because the user has no second factor. A policy saying "MFA required" does **not** mean everyone
covered is protected, and this is the only place that fact is visible.

- Phrase it as an action, not an error: "4 users signed in without MFA" → a list of who, from
  `topBypass` (capped at 20, ordered by `events` desc).
- **Do not** offer a "block these users" button. There is deliberately no enforcement switch: the
  answer is to enrol them, and denying them locks out anyone AD synced into a covered group
  before they've had a phone — including a brand-new employee who then can't log in *to* enrol.
- `windowDays` is echoed back; label the number with it. `days` accepts 1–90, defaults to 7.

`bypassEvents: 0` with `notEnrolled > 0` is normal and not a contradiction — it means those users
simply haven't tried to log in yet. Don't render it as "all clear".

---

## 3. Per-user panel — status and the QR

On the AD user (and console user) detail panel.

### Status

`POST /api/v1/ad/GetEnrollmentStatus` — `{ orgId, tenantId, userId, email }`

```json
{ "enrollmentStatus": "active", "deviceName": "Pixel 8", "platform": "android",
  "lastUsedAt": "2026-08-12T09:14:22Z" }
```

`enrollmentStatus` is `active` | `pending` | `none`. Show the device name and a relative
`lastUsedAt` when active — "Pixel 8, last used 2 hours ago" is what tells an admin the enrollment is
real rather than a stale row.

### Where it lives

On the Users row's **⋯ menu** → **"Register device"**. That opens a small dialog with **two ways to
deliver the same invite**, both available for every user regardless of whether they have an email:

```
Register device — aman.prasad@authnull.lab

  ( ) Send by email          aman.prasad@authnull.lab
  (•) Show invite            copy the link or the QR and send it yourself

      ┌──────────────┐   Invite link
      │  ▛▀▙ QR ▛▀▙  │   https://…/enroll?d=eyJ2Ijoy…      [ Copy ]
      │  ▙▄▟    ▙▄▟  │
      └──────────────┘   [ Download QR ]

  Anyone who opens this can register a device as aman.prasad@authnull.lab.
  Expires 19 Aug 2026 · works once · re-issuing replaces it.
```

**Both artifacts come from the one `adminInvite` call.** `inviteUrl` is the clickable https link —
that is the only thing meant to travel. `qrPngBase64` is the image. `deepLink` (`authnull://…`) is
what the QR *encodes*; do not surface it as a link, because a mail client will not linkify an unknown
scheme and it is inert text in a desktop chat.

**Copy and Download are required here** — the admin is expected to paste the link or send the QR
picture over whatever channel they actually have. (An earlier draft of this doc said not to offer
them; that was wrong for this workflow.)

**`inviteUrl` can be empty** when no console URL is configured. Show the QR and say the link is
unavailable rather than rendering a broken one.

### Two actions

**Send invite by email** — `POST /api/v1/ad/SendEnrollmentEmail` with `{ orgId, tenantId, userId, email }`.
Returns `207 Partial` when the token was created but SMTP failed: say *"invite created but the email
could not be sent"* and offer the QR instead. Don't report that as success.

**Show enrollment QR** — `POST /api/v1/mfa/push/adminInvite`

```json
{ "email": "aman.prasad@authnull.lab" }
```

```json
{ "payload": "…", "deepLink": "authnull://enroll?v=2&d=…", "qrPngBase64": "iVBORw0K…",
  "email": "aman.prasad@authnull.lab", "identityKind": "ad_user",
  "orgName": "Acme Corp", "orgHost": "acme.authnull.com",
  "expiresAt": "2026-08-19T09:14:22Z" }
```

**The body is only `{"email"}`. There is no `orgId` to send** — the org comes from your session, and
accepting one from the body would let any admin mint an invite for any account in any other tenant.
Please don't add it "to be explicit".

**This is a credential, and the modal should say so.** The QR contains a single-use token that
registers a device as that user. Treat the modal accordingly:

- Show it only on explicit click, never eagerly on panel load — every call **invalidates the
  previous invite** for that user, so a panel that fetches on render silently breaks an invite the
  user is already holding.
- Say what it is: *"Anyone who scans this can register a device as {email}. It expires
  {expiresAt} and works once."*
- Show the countdown from `expiresAt` (7 days).
- No "copy link" or "download PNG" button. Scanning off the screen is the intended path; a token in
  a clipboard or a Downloads folder is a token in a backup.
- Close-on-blur, and don't keep it in component state after close.

**Responses to handle:**

| code | meaning | UI |
|---|---|---|
| 200 | ok | the modal |
| **403** | `"administrator role required"` | **hide the button entirely for non-admins**, and treat a 403 as a bug rather than a message to render |
| 404 | no user with that email in this org | "This user isn't in this organisation" |
| 401 | no session | re-auth |

**Render `qrPngBase64` directly** — `<img src="data:image/png;base64,…">`. Do not regenerate the QR
client-side from `payload`: the server tunes the encoding to keep the QR version low so it scans off
a laptop screen at arm's length, and re-encoding loses that.

Only `ADMIN` and `SUPERADMIN` see this button. Every use is recorded server-side against the
admin's user id, so it is not anonymous — worth mentioning in the modal copy if you can do it
without alarming people.

### Self-enrollment, for comparison

`POST /api/v1/mfa/push/selfEnroll` — **empty body**, no fields at all. For a signed-in user setting
up their *own* device: Profile / Security → "Set up AuthNull Authenticator". Same rendering rules as
the admin QR, minus the warnings — there's no third party involved. Console users only; AD users
have no console session, which is exactly why piece 3 exists.

---

## The rollout this enables

Worth knowing, because it explains why the numbers are shaped this way:

1. Admin enrols their own device (`selfEnroll`) — proves push delivery before touching anyone else
2. Pick a scope, send invites, hand QR codes to the users without mail
3. Create the policy — unenrolled users are **allowed through and counted**, not blocked
4. Watch `bypassUsers` fall to zero
5. There is no step 5. No enforcement switch, by design.

---

## The `/enroll` page — a console route you own

`inviteUrl` points at **`{console}/enroll?d=<compact payload>`**. That route does not exist yet and
is yours to build. It is the piece that makes the link clickable everywhere.

**Public and unauthenticated** — the recipient has no session; the token in `d` is the credential.

Decode `d` (unpadded base64url JSON) to render without a network call. Fields: `n` orgName,
`e` email, `x` expiry (unix seconds), `o` orgId, `tk` token, `k` kind, `b` API base.

The page needs three things:

1. **"Open in AuthNull Authenticator"** → navigates to `authnull://enroll?v=2&d=<the same d>`. This
   is where the custom scheme belongs: a button press, not a link in an email.
2. **Store links** for when the app is not installed — otherwise pressing the button appears to do
   nothing at all, with no explanation.
3. **The QR**, re-rendered from `d`, so someone opening the link on a laptop can scan it with their
   phone. This is the one place regenerating the QR client-side is correct, because the server is not
   in the loop.

Also: `Referrer-Policy: no-referrer` and `noindex`, because the URL contains a live token.

Expiry can be checked from `x` with no request. "Already used" cannot — that needs
`GET /ad/getEnrollmentDetails?token=<tk>&orgId=<o>`, which returns `reason` as
`ok` / `used` / `expired` / `unknown`. Worth calling: "already used on another phone" and "expired,
ask for a new one" are different instructions, and showing one message for both is how someone
re-requests an invite they already redeemed.

A later improvement, needing the app dev: **App Links / Universal Links** association files
(`assetlinks.json`, `apple-app-site-association`) so the https URL opens the app directly instead of
via the button. Needs the bundle id and signing fingerprint.

## Don't

- Send `orgId`, `email` or `userId` to `selfEnroll`, or `orgId` to `adminInvite`
- Surface `deepLink` as a clickable link anywhere — it only works as QR content or a button target
- Regenerate either QR client-side from `payload`
- Fetch `adminInvite` on panel render — it invalidates the user's existing invite
- Render enrollment counts when `enrollmentApplies` is `false`
- Offer any "enforce / block unenrolled" control
- Show the QR button to non-admins and rely on the 403

## Done when

- [ ] An Okta or Duo org sees "MFA managed by {provider}" and **no** enrollment numbers
- [ ] `usersWithoutEmail > 0` visibly routes the admin to the QR flow
- [ ] The bypass count is shown as "N users signed in without MFA", with the list of who
- [ ] `bypassEvents: 0` with `notEnrolled > 0` does not read as "all clear"
- [ ] Per-user panel shows active / pending / none, with device name and relative last-used
- [ ] QR modal opens only on click, warns what the code grants, and shows the expiry countdown
- [ ] No copy-link or download-PNG affordance on either QR
- [ ] The QR button is absent for non-admin roles, not merely erroring
- [ ] `207` from the email invite reads as "created but not sent", not success
- [ ] `404 unknown domain` and `401` are handled distinctly
