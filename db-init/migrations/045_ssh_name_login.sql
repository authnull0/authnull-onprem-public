-- 045_ssh_name_login.sql
--
-- Name logins: `ssh -p 2222 PERSON@ACCOUNT@HOST@GATEWAY`, with no Authnull
-- certificate and no CLI. The typed person is a claim, so the push to their
-- phone is the only factor; authn-service always challenges a name login and
-- limits how many pushes one person can be sent (3 in 5 minutes, and none for
-- 15 minutes after 3 denied or unanswered in a row), counting from this table.
--
-- login is 'name' for those decisions, NULL for certificate logins, so only
-- name logins are counted.
--
-- Numbered 045, following 044_policy_sudo.sql. Safe to run repeatedly.

ALTER TABLE did.ssh_decisions ADD COLUMN IF NOT EXISTS login text;
CREATE INDEX IF NOT EXISTS ssh_decisions_name_pushes
    ON did.ssh_decisions (org_id, lower(email), decided_at DESC) WHERE login = 'name';
