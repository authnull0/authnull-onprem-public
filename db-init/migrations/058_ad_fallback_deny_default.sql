-- 056_ad_fallback_deny_default.sql
--
-- New AD directories fail CLOSED by default: when the DC sensor cannot reach Authnull, sign-ins
-- are refused rather than let in without MFA. Fail-open stays available, but as an explicit
-- choice (fallback_action = 'allow'); SanitiseFallbackAction now also maps anything that is not
-- an explicit "allow" to "deny".
--
-- Existing rows are not changed: each keeps the fallback an admin chose (or was defaulted to).
--
-- Numbered 056, following 055_mfa_user_default.sql. Safe to run repeatedly.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'did' AND table_name = 'active_directories'
                  AND column_name = 'fallback_action') THEN
        ALTER TABLE did.active_directories ALTER COLUMN fallback_action SET DEFAULT 'deny';
    END IF;
END
$$;