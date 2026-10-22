-- AuthNull as an identity provider for applications (OpenID Connect now, SAML
-- later), in each ORGANISATION database. See docs/APP-IDP-PLAN.md.
--
-- An application is registered per tenant. Its users sign in on AuthNull's
-- hosted pages: first with their directory (Entra now, AD later -- the
-- password is never checked by AuthNull itself), then with an AuthNull push,
-- and the application receives a signed ID token. Nothing here creates users:
-- they are the directory users the existing syncs bring into did.ad_users.
--
--   idp_signing_keys     RS256 keys that sign ID tokens, per tenant. The
--                        private key is a vault secret (kind idp_signing_key,
--                        organisation level, account idp-key-<kid>); the row
--                        keeps the public half, published at the tenant's JWKS.
--                        At most one active key per tenant; a 'next' key is
--                        published before it is used, so relying parties have
--                        cached it by the time it signs.
--   idp_apps             one registered application.
--   idp_oidc_clients     its OpenID Connect client. The client secret is
--                        random (256 bits) and kept only as a SHA-256 hash:
--                        AuthNull verifies it and never sends it anywhere.
--                        A public client (token_endpoint_auth_method 'none')
--                        has no secret and must use PKCE.
--   idp_app_assignments  who may sign in to an application: a directory user
--                        (did.ad_users.id) or a directory group, by name.
--   idp_login_sources    the directories a tenant's users sign in from. An
--                        'entra' source signs users in with the tenant's Entra
--                        connection (did.entra_config, from Identity Sources);
--                        'ad' is reserved for AD sign-in.
--
-- vault_secrets_kind_check is owned by 042_admin_account.sql; the new kind is
-- added there.
--
-- Numbered 057, following 056_ad_fallback_deny_default.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.idp_signing_keys (
    kid             text        PRIMARY KEY,
    org_id          integer     NOT NULL,
    tenant_id       integer     NOT NULL,
    alg             text        NOT NULL DEFAULT 'RS256' CHECK (alg IN ('RS256')),
    public_key_pem  text        NOT NULL,
    cert_pem        text        NOT NULL,
    status          text        NOT NULL CHECK (status IN ('next', 'active', 'retired')),
    vault_secret_id uuid        NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    activated_at    timestamptz,
    retired_at      timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS idp_signing_keys_one_active
    ON did.idp_signing_keys (org_id, tenant_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idp_signing_keys_by_tenant ON did.idp_signing_keys (org_id, tenant_id);

CREATE TABLE IF NOT EXISTS did.idp_apps (
    id          uuid        PRIMARY KEY,
    org_id      integer     NOT NULL,
    tenant_id   integer     NOT NULL,
    name        text        NOT NULL,
    protocol    text        NOT NULL CHECK (protocol IN ('oidc', 'saml')),
    enabled     boolean     NOT NULL DEFAULT true,
    logo_url    text        NOT NULL DEFAULT '',
    mfa_mode    text        NOT NULL DEFAULT 'always' CHECK (mfa_mode IN ('always')),
    created_by  integer,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idp_apps_by_tenant ON did.idp_apps (org_id, tenant_id);

CREATE TABLE IF NOT EXISTS did.idp_oidc_clients (
    app_id                     uuid        PRIMARY KEY REFERENCES did.idp_apps (id) ON DELETE CASCADE,
    org_id                     integer     NOT NULL,
    tenant_id                  integer     NOT NULL,
    client_id                  text        NOT NULL UNIQUE,
    client_secret_hash         text,
    token_endpoint_auth_method text        NOT NULL
        CHECK (token_endpoint_auth_method IN ('client_secret_basic', 'client_secret_post', 'none')),
    redirect_uris              jsonb       NOT NULL DEFAULT '[]'::jsonb,
    post_logout_redirect_uris  jsonb       NOT NULL DEFAULT '[]'::jsonb,
    allowed_scopes             jsonb       NOT NULL DEFAULT '["openid", "profile", "email"]'::jsonb,
    require_pkce               boolean     NOT NULL DEFAULT true,
    secret_rotated_at          timestamptz,
    CHECK ((token_endpoint_auth_method = 'none') = (client_secret_hash IS NULL)),
    CHECK (token_endpoint_auth_method <> 'none' OR require_pkce)
);

CREATE TABLE IF NOT EXISTS did.idp_app_assignments (
    app_id         uuid        NOT NULL REFERENCES did.idp_apps (id) ON DELETE CASCADE,
    org_id         integer     NOT NULL,
    principal_type text        NOT NULL CHECK (principal_type IN ('user', 'group')),
    principal      text        NOT NULL,
    created_by     integer,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idp_app_assignments_unique
    ON did.idp_app_assignments (app_id, principal_type, lower(principal));

CREATE TABLE IF NOT EXISTS did.idp_login_sources (
    id                 uuid        PRIMARY KEY,
    org_id             integer     NOT NULL,
    tenant_id          integer     NOT NULL,
    kind               text        NOT NULL CHECK (kind IN ('entra', 'ad')),
    identity_source_id integer     NOT NULL,
    priority           integer     NOT NULL DEFAULT 100,
    domain_suffixes    jsonb       NOT NULL DEFAULT '[]'::jsonb,
    enabled            boolean     NOT NULL DEFAULT true,
    ldap_urls          jsonb       NOT NULL DEFAULT '[]'::jsonb,
    ldap_ca_cert       text        NOT NULL DEFAULT '',
    bind_format        text        NOT NULL DEFAULT 'upn' CHECK (bind_format IN ('upn', 'down_level')),
    created_by         integer,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idp_login_sources_one_per_directory
    ON did.idp_login_sources (org_id, tenant_id, identity_source_id);