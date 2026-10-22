-- An application can be an MFA API client (protocol 'mfa_api').
--
-- Some applications keep their own login -- an in-house ERP checks its own
-- passwords -- and want only a second factor from AuthNull. Such an app is
-- registered like any other (did.idp_apps, with its client id and secret in
-- did.idp_oidc_clients), gets an access token with the client credentials
-- grant, and asks for a push for one of its users through
-- /api/v1/idp/mfa/challenges. It has no redirect URIs and never uses the
-- sign-in pages. See internal/idp/mfaapi.go.
--
-- Numbered 059, following 058_idp_login_source_no_sso_provider.sql. Safe to run repeatedly.

ALTER TABLE did.idp_apps DROP CONSTRAINT IF EXISTS idp_apps_protocol_check;
ALTER TABLE did.idp_apps ADD CONSTRAINT idp_apps_protocol_check CHECK (protocol IN ('oidc', 'saml', 'mfa_api'));