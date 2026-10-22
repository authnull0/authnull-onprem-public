-- RADIUS server registry (RADIUS MFA plan, WS1.1).
--
-- One row per server that sends logins to AuthNull: a FreeRADIUS VM running the AuthNull
-- bridge, or a customer's Microsoft NPS, Cisco ISE or Aruba ClearPass that forwards its
-- logins to that FreeRADIUS for the second factor. Until now the console had no idea a
-- RADIUS server existed, so a FreeRADIUS VM that went down told nobody.
--
-- The bridge's heartbeat (WS2) and every login (WS3) name the server by id, which reaches
-- the bridge as RADIUS_SERVER_ID in its app.env. A uuid rather than a counter: the
-- heartbeat and login calls are not authenticated yet (that is deferred to the central,
-- per-feature API auth), so the id must not be guessable from the next one along.
--
-- The liveness columns follow 016_jump_server_liveness.sql: every one is NULLABLE, because
-- a server registered but never started has no honest value for them. NULL last_seen_at
-- means "never connected". Status (Healthy / Degraded / Down) is derived from last_seen_at
-- and last_health when read (WS2.4), not stored.
--
-- Safe to replay: every statement is IF NOT EXISTS.

CREATE TABLE IF NOT EXISTS did.radius_servers (
    id             uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id         integer      NOT NULL,
    tenant_id      integer      NOT NULL,
    name           varchar(128) NOT NULL,
    type           varchar(16)  NOT NULL
                   CHECK (type IN ('freeradius', 'nps', 'ise', 'clearpass')),
    -- The address logins and heartbeats arrive from. For NPS, ISE and ClearPass this is
    -- what tells a forwarded login apart from a device's own (WS5.3).
    source_ip      varchar(64)  NULL,
    last_seen_at   timestamptz  NULL,
    last_health    jsonb        NULL,
    bridge_version varchar(64)  NULL,
    created_at     timestamptz  NOT NULL DEFAULT now()
);

-- One name per tenant, case-insensitively: the name is how an admin tells servers apart.
CREATE UNIQUE INDEX IF NOT EXISTS radius_servers_tenant_name_uniq
    ON did.radius_servers (org_id, tenant_id, lower(name));

-- "Sends logins to" on a network device (WS4.2). Added here so the registry can refuse to
-- delete a server that devices still point at (WS1.2). NULL: not linked to a server.
ALTER TABLE did.network_devices
    ADD COLUMN IF NOT EXISTS radius_server_id uuid NULL;

-- The status an admin was last emailed about ('down' or 'up'), so a server that stays down
-- sends one email, not one per minute (WS2.5). NULL: never alerted.
ALTER TABLE did.radius_servers
    ADD COLUMN IF NOT EXISTS notified_status varchar(8) NULL;

-- Which RADIUS server handled a login, from the bridge's RADIUS_SERVER_ID (WS3.3), and the
-- address the RADIUS packet came from (WS5.4): for a login an NPS, ISE or ClearPass forwarded,
-- that is the forwarding server, which is how its row shows a last login and a count. Both
-- NULL on rows written before this, or by a bridge whose app.env has no server id.
ALTER TABLE did.auth_log
    ADD COLUMN IF NOT EXISTS radius_server_id  uuid        NULL,
    ADD COLUMN IF NOT EXISTS radius_packet_src varchar(64) NULL;

-- CONCURRENTLY: auth_log is the busiest table, and a plain CREATE INDEX blocks every login's log
-- row while it builds. The migration runner applies files with `psql -f` (one statement per
-- transaction), which CONCURRENTLY needs. If a build is interrupted it leaves an INVALID index that
-- IF NOT EXISTS would then skip, so such a leftover is dropped first (review of #132).
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
             JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'did' AND NOT i.indisvalid
               AND c.relname IN ('auth_log_radius_server_idx', 'auth_log_radius_packet_src_idx',
                                 'auth_log_radius_gateway_idx', 'auth_log_radius_nas_id_idx')
    LOOP
        EXECUTE format('DROP INDEX did.%I', r.relname);
    END LOOP;
END $$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS auth_log_radius_server_idx
    ON did.auth_log (radius_server_id, ts_unix_ms DESC) WHERE radius_server_id IS NOT NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS auth_log_radius_packet_src_idx
    ON did.auth_log (radius_packet_src, ts_unix_ms DESC) WHERE radius_packet_src IS NOT NULL;

-- A device's last login (WS4.3): RADIUS rows by device address and by NAS-Identifier.
CREATE INDEX CONCURRENTLY IF NOT EXISTS auth_log_radius_gateway_idx
    ON did.auth_log (gateway_id, ts_unix_ms DESC) WHERE protocol = 'radius';
CREATE INDEX CONCURRENTLY IF NOT EXISTS auth_log_radius_nas_id_idx
    ON did.auth_log (lower(service_spn), ts_unix_ms DESC) WHERE protocol = 'radius';

-- "Sends logins to" points at a real server, and a server devices still use cannot be deleted --
-- enforced by the database too, so a device linked while a delete runs cannot slip between the
-- registry's check and its DELETE (review of #132). NOT VALID: existing rows are all NULL, so there
-- is nothing to check, and it takes no long lock on network_devices.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'network_devices_radius_server_fk') THEN
        ALTER TABLE did.network_devices
            ADD CONSTRAINT network_devices_radius_server_fk FOREIGN KEY (radius_server_id)
            REFERENCES did.radius_servers (id) ON DELETE RESTRICT NOT VALID;
    END IF;
END $$;