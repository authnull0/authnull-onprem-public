# Authnull on-prem

The whole product as Docker containers on one Linux host, behind the host's nginx.

## Needs

- Docker with the compose plugin, `openssl`, and nginx on the host.
- An SMTP server. Sign-up emails a verification link, and setting up a new
  organisation emails its admin; without SMTP neither finishes.
- For a domain install over HTTPS: nginx 1.19.4 or newer (`nginx/nginx.conf`
  uses `ssl_reject_handshake`) and a certificate for the domain.

## Install

1. Create `.env` and the ssi-service config. Every secret is generated for this
   install; nothing is shared with any other install.

   ```bash
   ./setup.sh --address 10.0.0.5 --org acme
   ```

   Use `--address pam.example.com --https` for a domain. Run with no options to
   be asked instead. It never overwrites an existing `.env`.

2. **Back up `.env`.** It holds this install's secrets, and `ENCRYPTION_KEY` is
   the only way to read the vault. Lose it and stored passwords are gone.

3. Fill in `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM` and `SMTP_PASSWORD` in `.env`.

4. Start it:

   ```bash
   docker compose up -d
   ```

   The first start loads the database schema from `db-init/` and takes a few
   minutes.

5. Put nginx in front. The files in `nginx/` are whole `nginx.conf` files. Remove
   Ubuntu's default site too, or nginx refuses to start with "duplicate default
   server":

   ```bash
   sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
   sudo cp nginx/nginx-ip.conf /etc/nginx/nginx.conf
   sudo rm /etc/nginx/sites-enabled/default
   sudo nginx -t && sudo systemctl reload nginx
   ```

   For a domain, use `nginx/nginx.conf` instead and set the domain and
   certificate paths in it.

6. Open `http://<address>/org/signup` and register the organisation's admin.
   Confirm from the email, then sign in at `/org/login`. Within five minutes the
   organisation's database and its Default tenant are created.

## Keeping secrets in your Vault

By default the secrets Authnull manages (rotated passwords, admin credentials, SSO, SIEM
and storage credentials) are kept in its database, encrypted with `ENCRYPTION_KEY`. To
keep them in your HashiCorp Vault or OpenBao instead:

1. In Vault: a KV version 2 mount, a policy, and an AppRole for Authnull.

   ```bash
   vault policy write authnull - <<'EOF'
   path "secret/data/authnull/*"     { capabilities = ["create", "read", "update"] }
   path "secret/metadata/authnull/*" { capabilities = ["delete"] }
   EOF
   vault auth enable approle
   vault write auth/approle/role/authnull token_policies=authnull token_ttl=1h token_max_ttl=4h
   vault read -field=role_id auth/approle/role/authnull/role-id
   vault write -f -field=secret_id auth/approle/role/authnull/secret-id
   ```

2. In `.env`: `VAULT_BACKEND=hashicorp`, `VAULT_ADDR`, `VAULT_APPROLE_ROLE_ID`, and the
   secret ID, either in `VAULT_APPROLE_SECRET_ID` or in `secrets/vault/secret-id` with
   `VAULT_APPROLE_SECRET_ID_FILE=/run/secrets/vault/secret-id`. For a private CA, put
   it at `secrets/vault/ca.pem` and set `VAULT_CACERT=/run/secrets/vault/ca.pem`.

3. `docker compose up -d authnull-service`. The log says
   `vault: secrets are kept in HashiCorp Vault`. Secrets already in the database are
   moved to Vault on that start.

Vault must be reachable for anything that uses a secret. Keep `ENCRYPTION_KEY` as it
is until the log shows nothing left to move.

## Notes

- On an IP install the tenant URL (`default.<org>.<ip>`) is not a real DNS name.
  The organisation console works on the IP; to use the tenant URL, add it to DNS
  or to the hosts file of the machines that use it.
- Audit events go to Fluent Bit (`fluent-bit` service). SIEM outputs configured
  in the console are written to the `authnull-siem-outputs` volume and loaded by
  Fluent Bit without a restart.
- Phone pushes through Firebase are off until you put the service account key at
  `secrets/fcm-service-account.json` and set `FCM_SERVICE_ACCOUNT_JSON` in `.env`.
