-- Gateway jobs wait between attempts, in each ORGANISATION database.
--
-- A failed job went straight back to the queue, so its three attempts were spent
-- within seconds -- before an administrator had finished running an endpoint's
-- setup script, say. not_before holds a failed job back (30s, 1m, 2m, 4m, then
-- every 5m) and lets a job be queued to start a little later.
--
-- Additive: code that does not know the column ignores it, and the default
-- makes every existing and newly inserted row claimable at once.
--
-- Numbered 026, following 025_ssh_decisions.sql. Safe to run repeatedly.

ALTER TABLE did.gateway_jobs ADD COLUMN IF NOT EXISTS not_before timestamptz NOT NULL DEFAULT now();