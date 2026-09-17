-- One row per (user, tenant, factor) in did.user_mfa_config.
--
-- WHY: THE LOGIN SCREEN LISTS THE SAME FACTOR TWICE AND "ADD ANOTHER METHOD" NEVER WORKS
--
-- did.user_mfa_config is the enrolment record the login screen reads (VerifyUser, and now
-- GetMFAStatus). The table was created with no primary key and no unique index, and
-- MFARepository.AddUserMFAConfig did a blind INSERT -- its duplicate check was commented
-- out. So every re-registration of a factor appended another row:
--
--   user_id | tenant_id | mfa_type | mfa_detail | status
--   ------- + --------- + -------- + ---------- + --------
--        42 |         1 |        9 | Passkey    | Active
--        42 |         1 |        9 | Passkey    | Active   <- second registration
--
-- which is why a user with one passkey sees "Passkey" and then, under "use another method",
-- Passkey again -- and why removing a factor and re-adding it left an Inactive row shadowed
-- by an Active one.
--
-- With this index the enrol path can UPSERT instead, which is also what makes Settings ->
-- MFA -> Update work: re-running setup for a factor the user already has refreshes the row
-- in place rather than adding a second one.
--
-- Numbered 011: 001-010 are taken. Safe to run repeatedly -- this directory is replayed
-- against the master and every org database on every boot.

-- 1. Collapse existing duplicates, keeping one row per (user_id, tenant_id, mfa_type).
--
-- Matched on ctid because the table has no key of its own -- that is the whole problem.
-- Preference order picks the row a login would have honoured anyway: Active first (status
-- casing is inconsistent across writers, hence lower()), then most recently touched.
DELETE FROM did.user_mfa_config d
 WHERE d.ctid <> (
       SELECT k.ctid
         FROM did.user_mfa_config k
        WHERE k.user_id   = d.user_id
          AND k.tenant_id = d.tenant_id
          AND k.mfa_type  = d.mfa_type
        ORDER BY (lower(k.status) = 'active') DESC,
                 k.updated_at DESC NULLS LAST,
                 k.created_at DESC NULLS LAST,
                 k.ctid DESC
        LIMIT 1);

-- 2. Keep it that way. AddUserMFAConfig's ON CONFLICT clause targets exactly these columns,
-- so this index is a hard dependency of the enrol path, not just hygiene.
CREATE UNIQUE INDEX IF NOT EXISTS user_mfa_config_user_tenant_factor_key
    ON did.user_mfa_config (user_id, tenant_id, mfa_type);
