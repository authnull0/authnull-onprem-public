-- An Entra login source signs users in with the tenant's Entra connection.
--
-- 057 had each 'entra' login source name a console SSO provider
-- (did.sso_providers) to perform the Entra sign-in, so an administrator typed
-- the same Entra app's client id and secret twice: once in Identity Sources
-- for the directory sync, once as a sign-in provider. The sign-in now uses the
-- sync's own connection (did.entra_config), and the console's SSO is no
-- longer involved. 057 no longer creates the column; this removes it, with
-- the CHECK that required it, where 057 already did.
--
-- Numbered 058, following 057_app_idp.sql. Safe to run repeatedly.

ALTER TABLE did.idp_login_sources DROP COLUMN IF EXISTS sso_provider_id;