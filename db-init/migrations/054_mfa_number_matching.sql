-- Authenticator: number matching on console sign-in pushes.
--
-- Idempotent: replayed against the master and every org database on every boot
-- (see docker-compose.yml).

-- When the sign-in screen shows a number the user must pick on the phone: 'off' (default),
-- 'high_risk' (only when the sign-in scores high risk) or 'always'. Only console sign-in
-- pushes carry one; AD, VPN and database prompts have no screen to show it on.
ALTER TABLE did.mfa_device_settings
    ADD COLUMN IF NOT EXISTS number_matching varchar(16) NOT NULL DEFAULT 'off';