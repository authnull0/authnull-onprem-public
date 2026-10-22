-- SAML 2.0 service providers for the app identity provider.
--
-- An application with protocol 'saml' (did.idp_apps) has one row here instead
-- of an OpenID Connect client: the service provider's entity id, the URLs it
-- receives assertions at (ACS, HTTP-POST binding), which NameID it gets, and
-- what the attributes it receives are called. AuthNull signs the response and
-- the assertion with the tenant's key (did.idp_signing_keys); its metadata is
-- at <issuer>/saml/metadata. See internal/idp/saml.go.
--
--   nameid_format  emailAddress | unspecified | persistent
--   nameid_source  email | upn | user_id (user_id is AuthNull's stable "ad:<id>")
--   attribute_map  {"email": "<name>", "name": "<name>", "username": "<name>", "groups": "<name>"}:
--                  which attributes are sent, under which names; an empty
--                  name leaves that attribute out
--
-- Numbered 061, following 060_directory_totp.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.idp_saml_sps (
    app_id        uuid  PRIMARY KEY REFERENCES did.idp_apps (id) ON DELETE CASCADE,
    org_id        integer NOT NULL,
    tenant_id     integer NOT NULL,
    entity_id     text  NOT NULL,
    acs_urls      jsonb NOT NULL DEFAULT '[]'::jsonb,
    nameid_format text  NOT NULL DEFAULT 'emailAddress'
        CHECK (nameid_format IN ('emailAddress', 'unspecified', 'persistent')),
    nameid_source text  NOT NULL DEFAULT 'email' CHECK (nameid_source IN ('email', 'upn', 'user_id')),
    attribute_map jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE UNIQUE INDEX IF NOT EXISTS idp_saml_sps_entity
    ON did.idp_saml_sps (org_id, tenant_id, entity_id);