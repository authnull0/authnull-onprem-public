-- A hint of each application's client secret, for the console.
--
-- The secret itself is never stored, only its SHA-256 (client_secret_hash), so
-- the console cannot show it again after it is issued. secret_hint keeps its
-- first characters -- the "ancs_" prefix and four more, 24 of its 256 random
-- bits -- so the console can show "ancs_Wad4••••" and the admin can tell which
-- secret an app has, as Azure does. Set when a secret is made or rotated; NULL
-- for public clients and for secrets made before this migration.
--
-- Numbered 063, following 062_app_clients.sql. Safe to run repeatedly.

ALTER TABLE did.app_clients ADD COLUMN IF NOT EXISTS secret_hint text;
