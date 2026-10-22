-- Rename the app identity provider's client table to did.app_clients.
--
-- did.idp_oidc_clients (migration 057) holds every application's client id
-- and hashed secret: OpenID Connect sign-in apps and MFA API apps (059) alike,
-- so it is named for what it holds. Columns, indexes, constraints and the
-- foreign key to did.idp_apps are kept; only the table's name changes. See
-- internal/idp/apps.go.
--
-- Numbered 062, following 061_idp_saml.sql. Safe to run repeatedly: it renames
-- only while the old table exists and the new one does not.

DO $$
BEGIN
    IF to_regclass('did.idp_oidc_clients') IS NOT NULL AND to_regclass('did.app_clients') IS NULL THEN
        ALTER TABLE did.idp_oidc_clients RENAME TO app_clients;
    END IF;
END
$$;