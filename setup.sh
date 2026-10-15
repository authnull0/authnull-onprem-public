#!/bin/sh
# authnull on-prem: first-time setup.
#
# Creates .env from .env.example, once: every secret is generated here, at
# random, for this install only, and the address settings are derived from one
# address (an IP or a domain). It never overwrites an existing .env, because
# changing ENCRYPTION_KEY on a running install makes the vault unreadable.
#
#   ./setup.sh                                   asks for the address and org name
#   ./setup.sh --address 10.0.0.5 --org acme     no questions
#   ./setup.sh --address pam.example.com --org acme --https
#   ./setup.sh --address 10.0.0.5:8088 --org acme     console on a non-standard port
#
# Then:  docker compose up -d
set -eu

cd "$(dirname "$0")"

ADDRESS="" ORG="" HTTPS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --address) ADDRESS=${2:-}; shift 2 ;;
    --org)     ORG=${2:-}; shift 2 ;;
    --https)   HTTPS=yes; shift ;;
    --http)    HTTPS=no; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "setup.sh: unknown option $1 (see --help)" >&2; exit 2 ;;
  esac
done

if [ -e .env ] || [ -e ssi-config/config.toml ]; then
  echo "setup.sh: .env or ssi-config/config.toml already exists; leaving them alone."
  echo "  It holds this install's secrets. To start over on a NEW install only:"
  echo "  move it away, then run setup.sh again."
  exit 0
fi
[ -f .env.example ] || { echo "setup.sh: .env.example is missing" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "setup.sh: openssl is needed to generate secrets" >&2; exit 1; }

# --- questions ----------------------------------------------------------------
default_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$ADDRESS" ]; then
  printf "Address people use to reach this install (IP or domain) [%s]: " "$default_ip"
  read -r ADDRESS
  ADDRESS=${ADDRESS:-$default_ip}
fi
case "$ADDRESS" in
  ''|*/*|*' '*) echo "setup.sh: give an IP or domain, optionally with :port, without http://" >&2; exit 2 ;;
esac
# HOST is ADDRESS without a port: what cookies, WebAuthn and tenant names use.
HOST=${ADDRESS%%:*}
case "$ADDRESS" in
  *:*) port=${ADDRESS#*:}; case "$port" in ''|*[!0-9]*) echo "setup.sh: bad port in $ADDRESS" >&2; exit 2 ;; esac ;;
esac
is_ip=no
if printf '%s' "$HOST" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then is_ip=yes; fi

if [ -z "$ORG" ]; then
  printf "Organisation name (lower-case letters, digits, _) [acme]: "
  read -r ORG
  ORG=${ORG:-acme}
fi
case "$ORG" in
  ''|*[!a-z0-9_]*|[0-9]*) echo "setup.sh: the organisation name must be lower-case letters, digits or _, not starting with a digit" >&2; exit 2 ;;
esac

if [ -z "$HTTPS" ]; then
  if [ "$is_ip" = yes ]; then HTTPS=no; else
    printf "Will %s be served over HTTPS? [Y/n]: " "$ADDRESS"
    read -r yn
    case "$yn" in n|N|no) HTTPS=no ;; *) HTTPS=yes ;; esac
  fi
fi
scheme=http; [ "$HTTPS" = yes ] && scheme=https
url="$scheme://$ADDRESS"

# --- secrets ------------------------------------------------------------------
# Hex only: safe in URLs, YAML and shell. ENCRYPTION_KEY is used as an AES-256
# key directly, so it must be exactly 32 characters.
db_password=$(openssl rand -hex 24)

umask 077
tmp=.env.tmp.$$
trap 'rm -f "$tmp"' EXIT
cp .env.example "$tmp"

# set KEY VALUE: replace the KEY= line (keeping nothing after it), or add it.
set_kv() {
  awk -v k="$1" -v v="$2" '
    BEGIN { done = 0 }
    $0 ~ "^" k "=" { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
}

set_kv JWT_SECRET          "$(openssl rand -hex 32)"
set_kv INTERNAL_API_KEY    "$(openssl rand -hex 32)"
set_kv ENCRYPTION_KEY      "$(openssl rand -hex 16)"
set_kv TOTP_ENCRYPTION_KEY "$(openssl rand -hex 32)"
set_kv REDIS_PASSWORD      "$(openssl rand -hex 24)"
set_kv POSTGRES_PASSWORD   "$db_password"
set_kv DB_PASSWORD         "$db_password"
set_kv DB_USER             authnull
set_kv POSTGRES_USER       authnull
set_kv ORG_NAME            "$ORG"

# --- address --------------------------------------------------------------------
set_kv SYSTEM_URL          "$url"
set_kv ROOT_URL            "$url"
set_kv CLIENT_URL          "$url"
set_kv API_BASE_URL        "$url"
set_kv SSC_BASE_URL        "$url"
set_kv SSC_SIGNIN_URL      "$url/ssc/signin"
set_kv SSC_URL             "$url/ssc/signin"
set_kv AUTHNULL_LOGOUT_URL "$url/ssc/signin"
set_kv TENANT_BASE_DOMAIN  "$HOST"
set_kv DOMAIN_URL          "default.$ORG.$HOST"
set_kv WEBAUTHN_RP_ID      "$HOST"
set_kv WEBAUTHN_ORIGIN     "$url"
set_kv SSO_CALLBACK_URL    "$url/authentication/sso/callback"
set_kv SSO_CONSOLE_DOMAIN  "$HOST"
if [ "$is_ip" = yes ]; then set_kv SYSTEM_IP "$HOST"; fi

# ssi-service reads its passwords from a config file, not the environment.
redis_password=$(awk -F= '/^REDIS_PASSWORD=/{print $2; exit}' "$tmp")
keystore_password=$(openssl rand -hex 24)
[ -f ssi-config/config.toml.example ] || { echo "setup.sh: ssi-config/config.toml.example is missing" >&2; exit 1; }
sed -e "s/@@REDIS_PASSWORD@@/$redis_password/" -e "s/@@SSI_KEYSTORE_PASSWORD@@/$keystore_password/" \
  ssi-config/config.toml.example > ssi-config/config.toml.tmp
chmod 644 ssi-config/config.toml.tmp   # the container reads it as a non-root user
mv ssi-config/config.toml.tmp ssi-config/config.toml

# Firebase key for phone pushes (optional). The compose file bind-mounts this
# path; if it does not exist Docker creates a root-owned DIRECTORY there. An empty
# file is harmless: pushes through Firebase stay off until you put the key here
# and set FCM_SERVICE_ACCOUNT_JSON=/run/secrets/fcm-service-account.json.
mkdir -p secrets/vault
chmod 700 secrets
[ -e secrets/fcm-service-account.json ] || : > secrets/fcm-service-account.json
chmod 644 secrets/fcm-service-account.json

mv "$tmp" .env
chmod 600 .env
trap - EXIT

echo "Created .env for $url (organisation \"$ORG\")."
echo
echo "Next:"
echo "  1. Back up .env somewhere safe. It holds this install's secrets, and"
echo "     ENCRYPTION_KEY is the only way to read the vault."
echo "  2. Fill in your SMTP settings in .env (SMTP_HOST, SMTP_PORT, SMTP_FROM,"
echo "     SMTP_PASSWORD) if the console should send email."
echo "  3. docker compose up -d"
