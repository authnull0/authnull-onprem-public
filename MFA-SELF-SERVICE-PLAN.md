# Plan — per-user MFA enrolment (login shows only enrolled methods, Settings → MFA → Add/Update)

## Goal
1. First login: user is offered every tenant-enabled second factor (Passkey, TOTP), picks one, enrols.
2. Later logins: user sees **only the factors they actually enrolled**.
3. Platform → Settings → MFA → **Add/Update**: user sees all tenant-enabled factors with enrolled/not-enrolled state, and can **Add** a factor they don't have yet, or **Update** one they do (register a new passkey device / re-scan a new TOTP secret). Newly added factor shows up at next login.

## What already exists (no new endpoints needed for add/update)

| Action | Endpoint |
|---|---|
| tenant-enabled factor list | `POST /ssc/v1/mfa/status` (`GetMFAStatus`) |
| user's enrolled factor list | `POST /ssc/v1/mfa/auth/verifyUser` (`VerifyUser`) |
| TOTP add / update | `totp/beginSetup` → `totp/confirmSetup` |
| Passkey add / update | `beginAuthRegistration` → `finishRegistration` |

Add and Update hit the same two endpoints — Update is just re-running setup for a factor the user already has, which the upsert below turns into an in-place refresh instead of a duplicate row.

All of these are already behind `AuthnzMiddleware`, so Settings can call them as-is. Enrolment source of truth = `did.user_mfa_config` (one row per user per factor).

## Root cause of the current bug
`MFARepository.AddUserMFAConfig` ([mfa_repository.go:28](internal/mfa/repo/mfa_repository.go#L28)) does a blind `Create` — the duplicate check is commented out and `did.user_mfa_config` has **no primary key and no unique index** ([01_schema.sql:4979](db-init/01_schema.sql#L4979)). Every re-registration inserts another row, so `VerifyUser` returns the same factor N times → login shows "Passkey" and, under "other options", Passkey again.

## Backend changes (3 small ones)
1. **Migration** — dedupe existing rows, then
   `CREATE UNIQUE INDEX ON did.user_mfa_config (user_id, tenant_id, mfa_type);`
2. **`AddUserMFAConfig` → upsert** on `(user_id, tenant_id, mfa_type)`, setting `status='Active'`, `mfa_detail`, `updated_at`. This is what makes **Update** work: re-running setup refreshes the existing row instead of adding a second one. Both paths (`FinishRegistration`, `ConfirmTOTPSetup`) already call it — one fix covers both.
3. **`GetMFAStatus` → add `enrolled` + `enrolledAt` per method**, by joining the user's Active `user_mfa_config` rows onto the tenant factor list it already builds. One call then drives both screens: Settings renders the full list with state, login renders `enrolled == true` only. No new route, no change for `VerifyUser` callers.

## Frontend changes (console repo)
- **Login**: render factors from `mfa/status` where `enrolled == true`. If zero enrolled → existing first-time enrolment screen, listing all tenant factors.
- **Login, "Use another method" link**: show it only when `enrolled` count > 1. With exactly one enrolled factor the link is hidden entirely (today it renders and re-lists the same factor, which is what looks broken).
- **Settings → MFA → Add/Update**: one page listing each tenant factor with its state and a single button — **Add** when not enrolled, **Update** when enrolled — both opening the existing setup dialog for that factor.

## Out of scope
Removing / un-enrolling a factor from Settings (`totp/delete` and `deletePasskey` exist but stay unused by this page — no Remove button, so no last-factor lockout risk to handle), per-user default factor ordering (`user_mfa_config` has no `is_default` column), SMS and Push enrolment from Settings, admin-forced MFA policy.

## Test

- Enrol Passkey → login shows Passkey only, no "use another method" link. Add TOTP in Settings → next login shows both, link visible.
- Same starting from TOTP.
- Update an already-enrolled factor → still exactly one row and one login option; the new passkey/secret is the one that works.
