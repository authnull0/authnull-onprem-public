#!/usr/bin/env bash
#
# Authnull on-premise installer.
#
# Usage:
#   ./install.sh              install, prompting for what cannot be guessed
#   ./install.sh --check      preflight only, change nothing
#   ./install.sh --help
#
# Idempotent. Running it twice does not rotate secrets and does not touch data: an
# existing .env is never overwritten, because rotating JWT_SECRET invalidates every
# session and rotating ENCRYPTION_KEY makes already-encrypted columns unreadable.

set -euo pipefail

readonly ENV_FILE=".env"
readonly ENV_EXAMPLE=".env.example"
readonly COMPOSE_FILE="docker-compose.yml"

# Secrets generated here, never shipped. A fixed value in the public repository would mean
# every deployment shared one JWT signing key, so a session minted on one customer's system
# would validate on another's.
# Secret name -> required format. NOT all of these are free-form strings, and getting the
# format wrong fails at runtime rather than at install:
#
#   ENCRYPTION_KEY       passed straight to aes.NewCipher (internal/ad/src/utils/encryption.go),
#                        so it must be EXACTLY 16, 24 or 32 bytes. 32 hex characters gives
#                        AES-256. A 40-character random string returns KeySizeError and every
#                        AD credential encryption fails.
#   TOTP_ENCRYPTION_KEY  hex-decoded and checked for exactly 32 bytes
#                        (internal/mfa/utils/crypto.go). Anything else and the code generates a
#                        RANDOM key at boot -- so TOTP secrets stop decrypting after a restart,
#                        which looks like data corruption rather than a config error.
#
# The rest are opaque strings where only length matters.
readonly GENERATED_KEYS=(
  "DB_PASSWORD:alnum"
  "REDIS_PASSWORD:alnum"
  "JWT_SECRET:alnum"
  "INTERNAL_API_KEY:alnum"
  "ENCRYPTION_KEY:hex32"
  "TOTP_ENCRYPTION_KEY:hex64"
)

# Ports the package publishes. Postgres and Redis are deliberately absent: they are internal
# to the compose network, and Redis holds live session bearer tokens.
readonly REQUIRED_PORTS=(8080 6066 5173 3000)

readonly MIN_DISK_GB=20
readonly MIN_RAM_GB=6

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn()  { printf '\033[33m%s\033[0m\n' "$*"; }

fail() { red "ERROR: $*"; exit 1; }

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Preflight
#
# Every check reports what to do about it. "docker: not found" without a next step is a
# support ticket; "install Docker Engine 20.10 or newer" is not.
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
  bold "Checking prerequisites"
  local problems=0

  if ! command -v docker >/dev/null 2>&1; then
    red "  ✗ docker not found — install Docker Engine 20.10 or newer"
    problems=$((problems+1))
  else
    green "  ✓ docker $(docker --version | sed 's/Docker version //; s/,.*//')"
  fi

  # Compose v2 (`docker compose`) rather than the standalone v1 binary: the package uses
  # depends_on conditions, which v1 ignores, so services would start in the wrong order and
  # fail in ways that look random.
  if docker compose version >/dev/null 2>&1; then
    green "  ✓ docker compose $(docker compose version --short 2>/dev/null || echo v2)"
  else
    red "  ✗ 'docker compose' (v2) not available — the v1 'docker-compose' binary ignores"
    red "    the startup ordering this package relies on. Install the Compose v2 plugin."
    problems=$((problems+1))
  fi

  if ! docker info >/dev/null 2>&1; then
    red "  ✗ cannot talk to the Docker daemon — is it running, and is your user in the"
    red "    'docker' group? (newgrp docker, or log out and back in)"
    problems=$((problems+1))
  fi

  local disk_gb
  disk_gb=$(df -BG --output=avail . 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
  if [ "${disk_gb:-0}" -lt "$MIN_DISK_GB" ]; then
    red "  ✗ ${disk_gb}GB free here, need ${MIN_DISK_GB}GB — Postgres data and images"
    problems=$((problems+1))
  else
    green "  ✓ ${disk_gb}GB disk free"
  fi

  local ram_gb
  ram_gb=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0) / 1024 / 1024 ))
  if [ "$ram_gb" -lt "$MIN_RAM_GB" ]; then
    warn "  ! ${ram_gb}GB RAM, ${MIN_RAM_GB}GB recommended — it will start, but expect it to be slow"
  else
    green "  ✓ ${ram_gb}GB RAM"
  fi

  # Counted separately from the running total: keyed on `problems` this line vanished
  # whenever any EARLIER check failed, so a clean port scan silently reported nothing.
  local port_problems=0
  for port in "${REQUIRED_PORTS[@]}"; do
    if (command -v ss >/dev/null && ss -ltn 2>/dev/null | grep -q ":${port} ") ||
       (command -v netstat >/dev/null && netstat -ltn 2>/dev/null | grep -q ":${port} "); then
      red "  ✗ port ${port} is already in use — stop whatever holds it, or change the"
      red "    published port in ${COMPOSE_FILE}"
      port_problems=$((port_problems+1))
      problems=$((problems+1))
    fi
  done
  [ "$port_problems" -eq 0 ] && green "  ✓ ports ${REQUIRED_PORTS[*]} free"

  for f in "$ENV_EXAMPLE" "$COMPOSE_FILE"; do
    [ -f "$f" ] || { red "  ✗ $f missing — run this from inside the unpacked package"; problems=$((problems+1)); }
  done

  if [ "$problems" -gt 0 ]; then
    echo; fail "$problems problem(s) above. Nothing has been changed."
  fi
  echo
}

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
gen_secret() {
  case "$1" in
    # 32 hex characters = 32 bytes as consumed = AES-256.
    hex32) openssl rand -hex 16 ;;
    # 64 hex characters = 32 bytes once decoded.
    hex64) openssl rand -hex 32 ;;
    # Opaque. Base64 with the characters that need shell or YAML quoting removed, then padded
    # from a second draw so stripping can never shorten it below 40.
    alnum) { openssl rand -base64 48; openssl rand -base64 48; } | tr -d '/+=\n' | cut -c1-40 ;;
    *)     fail "gen_secret: unknown format '$1'" ;;
  esac
}

# Assert what was written is actually usable, because both cipher keys fail at RUNTIME rather
# than at install, and a 40-character ENCRYPTION_KEY would look like a working install until
# the first credential was encrypted.
verify_secrets() {
  local key len value
  for spec in "${GENERATED_KEYS[@]}"; do
    key="${spec%%:*}"
    value="$(grep -E "^${key}=" "$ENV_FILE" | cut -d= -f2-)"
    len="${#value}"
    case "${spec##*:}" in
      hex32) [ "$len" -eq 32 ] || fail "$key is $len chars, must be exactly 32 (AES key)" ;;
      hex64) [ "$len" -eq 64 ] || fail "$key is $len chars, must be exactly 64 (32 bytes hex)" ;;
      alnum) [ "$len" -ge 32 ] || fail "$key is only $len chars" ;;
    esac
  done
  green "  ✓ all generated secrets are the right length and format"
}

set_env() {
  # Replace KEY=... in place, whether or not it already has a value.
  local key="$1" value="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    # | as the delimiter: URLs contain /
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

ask() {
  local prompt="$1" default="${2:-}" answer
  if [ -n "$default" ]; then
    read -r -p "  ${prompt} [${default}]: " answer
    printf '%s' "${answer:-$default}"
  else
    while :; do
      read -r -p "  ${prompt}: " answer
      [ -n "$answer" ] && { printf '%s' "$answer"; return; }
      echo "    required"
    done
  fi
}

configure() {
  if [ -f "$ENV_FILE" ]; then
    warn "$ENV_FILE already exists — keeping it."
    warn "Secrets are NOT regenerated: rotating JWT_SECRET would invalidate every session,"
    warn "and rotating ENCRYPTION_KEY would make already-encrypted data unreadable."
    echo
    return
  fi

  bold "Configuration"
  echo "  Answer four questions. Everything else has a working default, and optional"
  echo "  features (SMTP, Okta, Duo) can be filled in later by editing $ENV_FILE."
  echo

  local base_url admin_email org_name
  base_url=$(ask   "Base URL browsers will use (https://authnull.example.com)")
  admin_email=$(ask "Email address of the first administrator")
  org_name=$(ask   "Short organisation name, lowercase, no spaces" "acme")

  base_url="${base_url%/}"          # a trailing slash produces "//api/v1" everywhere
  local host="${base_url#*://}"

  cp "$ENV_EXAMPLE" "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  bold "Generating secrets"
  local key fmt
  for spec in "${GENERATED_KEYS[@]}"; do
    key="${spec%%:*}"; fmt="${spec##*:}"
    set_env "$key" "$(gen_secret "$fmt")"
    green "  ✓ $key ($fmt)"
  done
  verify_secrets

  # URLs. SYSTEM_URL is the API base; CLIENT_URL is the console root. Enrollment links are
  # built from CLIENT_URL, so pointing it at the API host makes every invite 404 in a browser.
  set_env SYSTEM_URL          "$base_url"
  set_env CLIENT_URL          "$base_url"
  set_env SSC_URL             "$base_url"
  set_env SSC_BASE_URL        "$base_url"
  set_env SSC_SIGNIN_URL      "$base_url/ssc/signin"
  set_env AUTHNULL_LOGOUT_URL "$base_url"
  set_env DOMAIN_URL          "$host"
  set_env ROOT_URL            "$base_url"

  # Database. DB_NAME stays authnull_dev: it is the only value exercised end to end, and a
  # first customer install is the worst place to discover a novel database name breaks
  # something. DB_USER is free -- Postgres is initialised from these same variables.
  set_env DB_HOST   "postgres"
  set_env DB_PORT   "5432"
  set_env DB_USER   "authnull"
  set_env DB_NAME   "authnull_dev"
  set_env DB_SCHEMA "did"

  set_env ORG_NAME  "$org_name"
  set_env TENANT_ID "1"
  set_env ADMIN_EMAIL "$admin_email"

  mkdir -p license
  echo
  green "Wrote $ENV_FILE (mode 600)."
  echo
}

# ─────────────────────────────────────────────────────────────────────────────
# Start and verify
# ─────────────────────────────────────────────────────────────────────────────
start() {
  bold "Pulling images"
  docker compose pull --quiet 2>/dev/null || docker compose pull

  bold "Starting"
  docker compose up -d

  bold "Waiting for the service to report healthy"
  local url health=""
  url="$(grep -E '^SYSTEM_URL=' "$ENV_FILE" | cut -d= -f2-)"

  for _ in $(seq 1 60); do
    # localhost, not SYSTEM_URL: DNS and TLS for the public name may not be in place yet,
    # and this check is about the container, not the ingress.
    if health=$(curl -fsS http://localhost:8080/system/v1/health 2>/dev/null); then
      break
    fi
    sleep 5
  done

  echo
  if [ -z "$health" ]; then
    red "The service did not become healthy within five minutes."
    echo "  docker compose ps"
    echo "  docker compose logs authnull-service --tail=50"
    exit 1
  fi

  # Schema drift is reported in the body rather than as a bad status, because the process IS
  # serving. Surface it here instead of declaring success over a degraded install.
  if printf '%s' "$health" | grep -q '"ok":false'; then
    warn "Started, but the schema check reports problems:"
    printf '%s\n' "$health"
    warn "The console will work; some features may not. Send this output to support."
  else
    green "Healthy."
  fi

  local lic
  lic=$(printf '%s' "$health" | grep -o '"state":"[a-z_]*"' | head -1 | cut -d'"' -f4 || true)
  case "${lic:-}" in
    trial)        green "Licence: 30-day trial started." ;;
    valid)        green "Licence: valid." ;;
    not_enforced) warn  "Licence: not enforced — this image was built without a licence key."
                  warn  "         If you are a customer, you have the wrong image; ask for the -onprem tag." ;;
    "")           : ;;
    *)            warn "Licence state: $lic" ;;
  esac

  echo
  bold "Authnull is running"
  echo "  Console:  ${url}"
  echo "  Sign in as the administrator address you gave, then add your directory."
  echo
  # Both of these must exist in the package. They pointed at docs/CONFIGURE.md and
  # docs/TROUBLESHOOT.md, which were never written -- so the last thing every customer read
  # after a successful install was a path to a missing file. TestOnpremDocPathsExist keeps
  # every path printed here real.
  echo "  Next steps:      docs/INSTALL.md  (\"Verifying the install\")"
  echo "  Licence:         docs/INSTALL.md  (\"Licence state\")"
  echo "  Something wrong: docs/INSTALL.md  (\"When it does not work\")"
}

main() {
  case "${1:-}" in
    -h|--help) usage ;;
    --check)   preflight; green "Preflight passed. Nothing was changed."; exit 0 ;;
    "")        ;;
    *)         fail "unknown option: $1 (try --help)" ;;
  esac

  bold "Authnull on-premise installer"
  echo
  preflight
  configure
  start
}

main "$@"
