-- Liveness for a jump server, so the console can say whether its proxy is running.
--
-- WHY
--
-- did.jump_server describes a jump box an administrator registered: its name, its
-- addresses, which domain it serves. Nothing in it says whether the SSH proxy on that
-- box is actually up. The proxy never announced itself, so "is my proxy running?" could
-- only be answered by logging into the machine -- which is the one question a customer
-- asks about a component they deployed and cannot see.
--
-- The proxy now announces at startup and heartbeats while it runs, and these columns are
-- where that lands.
--
-- WHY last_seen_at RATHER THAN A STATUS COLUMN
--
-- status already exists on this table and means something else: it is the administrative
-- state of the jump server record, set by a person through the console. Liveness is
-- observed, not declared, and overloading one column with both would make "disabled" and
-- "not running" indistinguishable -- two conditions with completely different remedies.
--
-- A timestamp rather than a boolean for the same reason a heartbeat is not a flag:
-- whoever is looking needs to know HOW STALE the answer is. "Last seen 4 seconds ago"
-- and "last seen on Tuesday" are both "not right now", and only one of them is an
-- incident. The staleness threshold is a display decision and deliberately not encoded
-- here.
--
-- WHY THE VERSION IS RECORDED
--
-- A proxy that is running an old binary is the failure that looks like a configuration
-- problem: it connects, it authenticates, and a capability added since its build simply
-- does nothing. The RADIUS bridge has exactly this failure mode documented in its own
-- build script, where an older build sends none of the five context fields and policies
-- scoped by them silently stop applying. Recording the version makes that a question
-- somebody can answer from the console rather than by SSH-ing to the jump box.
--
-- Every column is NULLABLE, and that is deliberate: a jump server registered before this
-- migration, or one whose proxy has never started, has no honest value to put here, and
-- a default would assert something untrue. NULL last_seen_at means "never seen", which
-- is exactly right for a jump box nobody has installed the proxy on yet.

ALTER TABLE did.jump_server
    ADD COLUMN IF NOT EXISTS last_seen_at    timestamptz  NULL,
    ADD COLUMN IF NOT EXISTS proxy_version   varchar(64)  NULL,
    ADD COLUMN IF NOT EXISTS proxy_listen    varchar(128) NULL,
    ADD COLUMN IF NOT EXISTS last_seen_ip    varchar(64)  NULL;

-- Serves the console's "which proxies are live" listing, which orders by staleness.
CREATE INDEX IF NOT EXISTS jump_server_last_seen_idx
    ON did.jump_server (last_seen_at DESC NULLS LAST);
