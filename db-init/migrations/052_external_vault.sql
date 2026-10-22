-- External vault: a secret's value can live in the customer's HashiCorp Vault
-- (or OpenBao) instead of in this row.
--
-- The row stays either way. It is the secret's identity -- id, kind, endpoint,
-- account, version -- and what the access log refers to; only the value moves.
--
--   store = 'builtin'    ciphertext and wrapped_key hold the value, as before.
--   store = 'hashicorp'  external_version is the live KV version of
--                        <mount>/data/<prefix>/org-<org>/<id>; ciphertext and
--                        wrapped_key are NULL.
--
-- VAULT_BACKEND picks where new values go (internal/pam/vault/store.go). Rows
-- written before an install switched are moved on start, and logged as 'move'.
--
-- Idempotent: replayed against the master and every org database on every boot.

ALTER TABLE did.vault_secrets
    ADD COLUMN IF NOT EXISTS store            text NOT NULL DEFAULT 'builtin',
    ADD COLUMN IF NOT EXISTS external_version integer;

ALTER TABLE did.vault_secrets ALTER COLUMN ciphertext  DROP NOT NULL;
ALTER TABLE did.vault_secrets ALTER COLUMN wrapped_key DROP NOT NULL;

ALTER TABLE did.vault_secrets DROP CONSTRAINT IF EXISTS vault_secrets_store_check;
ALTER TABLE did.vault_secrets ADD CONSTRAINT vault_secrets_store_check CHECK (
    (store = 'builtin'   AND ciphertext IS NOT NULL AND wrapped_key IS NOT NULL) OR
    (store = 'hashicorp' AND external_version IS NOT NULL AND ciphertext IS NULL AND wrapped_key IS NULL)
);

-- 'move': a value moved from the built-in store to the external vault.
ALTER TABLE did.vault_access_log DROP CONSTRAINT IF EXISTS vault_access_log_action_check;
ALTER TABLE did.vault_access_log ADD CONSTRAINT vault_access_log_action_check
    CHECK (action IN ('put', 'rotate', 'release', 'refuse', 'retire', 'move'));