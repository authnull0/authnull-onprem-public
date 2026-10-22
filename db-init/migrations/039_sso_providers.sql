-- Single sign-on to the console with OpenID Connect or GitHub, in each
-- ORGANISATION database.
--
-- A provider belongs to one tenant: its sign-in button is shown on that
-- tenant's login page. Signing in maps the identity provider's VERIFIED email
-- to an existing, active user of that tenant -- never creates one -- and issues
-- the same session a password sign-in does.
--
--   kind 'oidc'   -- any OpenID Connect provider (Google, Okta, Entra ID,
--                    Keycloak, ...): issuer, client id and secret. The ID token
--                    is verified against the issuer's published keys.
--   kind 'github' -- GitHub OAuth: the account's primary, verified email;
--                    optionally membership of github_org.
--
-- The client secret is in the vault (kind sso_client_secret, organisation
-- level, account sso-<provider id>), never in this table.
--
-- Numbered 039, following 038_password_ssh_exceptions.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.sso_providers (
    id                     uuid        PRIMARY KEY,
    org_id                 integer     NOT NULL,
    tenant_id              integer     NOT NULL,
    kind                   text        NOT NULL CHECK (kind IN ('oidc', 'github')),
    name                   text        NOT NULL,
    issuer                 text,
    client_id              text        NOT NULL,
    scopes                 text        NOT NULL DEFAULT '',
    email_claim            text        NOT NULL DEFAULT 'email',
    require_email_verified boolean     NOT NULL DEFAULT true,
    allowed_domains        jsonb       NOT NULL DEFAULT '[]'::jsonb,
    github_org             text,
    enabled                boolean     NOT NULL DEFAULT true,
    created_by             integer,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    CHECK (kind <> 'oidc' OR coalesce(issuer, '') <> '')
);
CREATE INDEX IF NOT EXISTS sso_providers_by_tenant ON did.sso_providers (org_id, tenant_id) WHERE enabled;

-- vault_secrets_kind_check is owned by 042_admin_account.sql; see the note there.