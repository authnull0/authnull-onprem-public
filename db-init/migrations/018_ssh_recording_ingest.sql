-- Makes a recording ingestible: identified by the session that produced it, deduplicated
-- on replay, and checkable against the bytes we actually received.
--
-- 017 gave a recording somewhere to put its facts -- target host, target account, storage
-- backend and key, hmac, size. What it did not give it was a NAME. Everything there
-- describes the recording; nothing identifies the session, and so nothing joins a
-- recording to the rest of the evidence.
--
-- WHY session_id
--
-- The session id is already the join key everywhere else, and it was not invented for this
-- table. The proxy stamps it into the asciicast header, sends it as requestId on the
-- decision so authn-service's audit row carries it, and puts it in the certificate's
-- KeyId -- where the TARGET's own sshd writes it to auth.log as
--
--     Accepted publickey for ubuntu ... ID authnull-sshproxy:d7bbae886dcfe00d:ubuntu
--
-- That last one is the reason this is a column and not a substring of storage_key. A
-- customer asking "your console says this happened; prove it from MY logs" is answered by
-- grepping their auth.log for the id, and an id you cannot query is an id you cannot
-- answer with. Correlating on a timestamp instead is not evidence, it is a coincidence.
--
-- Nullable, because every Guacamole row predates the concept.
--
-- WHY content_sha256 WHEN THERE IS ALREADY AN hmac
--
-- They answer different questions and neither substitutes for the other.
--
-- The hmac is the PROXY's claim, computed with SSHPROXY_HMAC_KEY, which lives on the jump
-- box and deliberately never reaches this service. It is what proves a recording was
-- produced by that proxy and not altered afterwards -- and only someone holding the key
-- can check it. That is the property worth having, and it is why the key stays there.
--
-- But it leaves this service unable to say anything at all about its own copy. A recording
-- truncated in transit, or altered in the database later, is invisible here: we would hand
-- back bytes and repeat a digest we cannot evaluate.
--
-- content_sha256 is this service's own record of what it received. It proves nothing about
-- the proxy and is not meant to -- it catches corruption between ingest and playback, which
-- is the failure this side can actually detect. Console shows both: "matches what was
-- received" from this column, "verifiable with the proxy key" from the hmac.
--
-- WHY THE UNIQUE INDEX
--
-- Ingest retries. The proxy reports after a session closes, the report is fire-and-forget
-- so that a console outage cannot fail a session, and anything fire-and-forget that is
-- worth doing at all is retried -- which means the same recording arrives twice whenever a
-- response is lost after the write. Without a constraint that is two rows for one session
-- and an audit trail that double-counts.
--
-- On (jump_server_id, storage_key) rather than session_id alone, deliberately: one SSH
-- connection can carry several channels and each is its own recording, so session ids are
-- NOT unique here. storage_key already ends in the channel number.

ALTER TABLE did.jump_server_recordings
    ADD COLUMN IF NOT EXISTS session_id     varchar(64) NULL,
    ADD COLUMN IF NOT EXISTS content_sha256 varchar(64) NULL;

-- "Show me that session", from an id someone read out of their own auth.log.
CREATE INDEX IF NOT EXISTS jump_server_recordings_session_idx
    ON did.jump_server_recordings (session_id)
    WHERE session_id IS NOT NULL;

-- Partial, so the Guacamole rows -- which have no storage_key -- are not forced into it.
CREATE UNIQUE INDEX IF NOT EXISTS jump_server_recordings_storage_idx
    ON did.jump_server_recordings (jump_server_id, storage_key)
    WHERE storage_key IS NOT NULL AND jump_server_id IS NOT NULL;
