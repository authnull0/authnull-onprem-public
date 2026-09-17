-- Per-domain enforcement settings for the AD Shield DC sensor.
--
-- WHY THESE LIVE ON active_directories AND NOT ad_gateways:
-- The DC sensor never identifies itself by gateway. sensor.yml carries tenant_id, org_id and
-- ad_sync_domain_id (= active_directories.id) and nothing else; SensorConfig.cs has no
-- GatewayId property at all, so the gateway_id key present in the sensor.yml template is
-- silently dropped by its YAML deserialiser (IgnoreUnmatchedProperties). ad_gateways and
-- gateway_domain_mappings belong to the RADIUS bridge / proxy deployment, which is a
-- different install path with a different config file (buildGatewayConfigs).
--
-- Enforcement mode is therefore a property of the AD domain being protected, exactly as the
-- sync scope is -- see the comment on ActiveDirectory.SyncFilterGroups in
-- internal/ad/models/models.go: "stored here because the scope is a property of the
-- directory, not the gateway". Same reasoning, same table.
--
-- Before this, buildSensorConfig hardcoded mode and fallback_action, so an admin could only
-- move a domain from monitor to enforce by hand-editing sensor.yml on every DC.
--
-- Safe to run repeatedly: every statement is IF NOT EXISTS.

ALTER TABLE did.active_directories
    -- 'monitor' logs auth events and never blocks; 'enforce' applies the MFA verdict.
    -- Defaults to monitor so a newly registered domain cannot block logins before the admin
    -- has explicitly opted in. This is the monitor-first rollout Silverfort also uses.
    ADD COLUMN IF NOT EXISTS enforcement_mode text NOT NULL DEFAULT 'monitor',

    -- What the sensor does when it cannot reach this backend: 'allow' fails open (logins
    -- continue, MFA is skipped), 'deny' fails closed (authentication is refused).
    --
    -- Defaults to 'allow'. The sensor's own default is also allow, and SensorConfig.cs
    -- documents it as "availability-first, recommended for DCs" -- a fail-closed default
    -- means one backend outage refuses authentication for an entire Active Directory
    -- domain. Note this changes the effective default: the old hardcoded generator emitted
    -- fallback_action: "deny".
    ADD COLUMN IF NOT EXISTS fallback_action  text NOT NULL DEFAULT 'allow';

-- Reject anything the sensor cannot parse. SensorConfig.cs compares these as plain strings
-- with no validation, so a typo ("Monitor", "block") silently reads as not-monitor /
-- not-allow and flips the domain to enforcing and failing closed -- the exact opposite of
-- what was intended, with no error anywhere.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'active_directories_enforcement_mode_check') THEN
        ALTER TABLE did.active_directories
            ADD CONSTRAINT active_directories_enforcement_mode_check
            CHECK (enforcement_mode IN ('monitor', 'enforce'));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'active_directories_fallback_action_check') THEN
        ALTER TABLE did.active_directories
            ADD CONSTRAINT active_directories_fallback_action_check
            CHECK (fallback_action IN ('allow', 'deny'));
    END IF;
END $$;
