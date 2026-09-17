-- Who minted each enrollment invite, and how.
--
-- WHY
--
-- Admin-assisted enrollment lets an org admin generate another user's QR code and hand it over --
-- the only workable path for AD users whose `mail` attribute is empty or routes nowhere, which is
-- common enough to block a rollout on its own.
--
-- But the admin necessarily SEES the token, and an enrollment token is the credential that lets a
-- device register as that user. So the admin could enroll their own phone as someone else and
-- thereafter approve that person's MFA. That is a smaller escalation than it sounds -- an org admin
-- can already trigger an invite to that user's mailbox, and can already change policy -- but it is
-- the kind of thing that must leave a record rather than being merely unlikely.
--
-- The record lives on the enrollment row itself rather than in a separate audit table, because
-- that is where the artifact is: BeginEnrollment supersedes prior invites by setting used = true
-- and never deletes them, so every invite ever minted persists with its provenance attached. A
-- separate table would need its own retention, its own join, and could drift from the thing it
-- describes.
--
-- Numbered 009: 001-008 are taken. Safe to run repeatedly.

ALTER TABLE did.mfa_device_enrollments
    -- did.users.user_id of the person who caused this invite to exist. 0 for invites minted before
    -- this column existed, and for any path with no session behind it.
    ADD COLUMN IF NOT EXISTS invited_by_user_id integer NOT NULL DEFAULT 0,

    -- How it was minted:
    --   'self'      the user generated their own QR while signed in     (no escalation possible)
    --   'admin_qr'  an admin generated it for someone else              (the case worth auditing)
    --   'email'     mailed to the user's own address                    (the token never leaves the mailbox)
    --   ''          minted before this column existed
    --
    -- Text rather than an enum: a new delivery channel should not need a type migration, and the
    -- set is validated in Go where the vocabulary already lives.
    ADD COLUMN IF NOT EXISTS invite_method text NOT NULL DEFAULT '';

-- "Show me every invite an admin generated on someone else's behalf" -- the query an auditor
-- actually runs. Partial, because admin_qr is the rare case and indexing the whole table to find
-- it would be mostly dead weight.
CREATE INDEX IF NOT EXISTS mfa_device_enrollments_admin_minted_idx
    ON did.mfa_device_enrollments (org_id, invited_by_user_id, created_at DESC)
    WHERE invite_method = 'admin_qr';
