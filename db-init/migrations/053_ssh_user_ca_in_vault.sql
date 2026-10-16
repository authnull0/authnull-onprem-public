-- The SSH user CA private key moves into the vault.
--
-- did.ssh_user_ca kept the CA's private key in private_key_enc, sealed under
-- ENCRYPTION_KEY: the one secret that signs every user and web-terminal
-- certificate, and the only one the vault did not hold. It is now a vault
-- secret of kind 'ssh_user_ca' (the kind is added to vault_secrets_kind_check
-- in 042, which owns that list), so it is kept wherever the install keeps its
-- secrets -- including the customer's HashiCorp Vault -- and every use of it is
-- in the vault access log.
--
-- The row keeps the CA's identity and public key; vault_secret_id names its
-- private key. A row still holding private_key_enc is moved by the service on
-- start and on first use (internal/pam/sshcerts), which then clears the column.
--
-- Idempotent: replayed against the master and every org database on every boot.

ALTER TABLE did.ssh_user_ca ADD COLUMN IF NOT EXISTS vault_secret_id uuid;
ALTER TABLE did.ssh_user_ca ALTER COLUMN private_key_enc DROP NOT NULL;

ALTER TABLE did.ssh_user_ca DROP CONSTRAINT IF EXISTS ssh_user_ca_key_check;
ALTER TABLE did.ssh_user_ca ADD CONSTRAINT ssh_user_ca_key_check
    CHECK (private_key_enc IS NOT NULL OR vault_secret_id IS NOT NULL);
