# authnull-service — Developer Setup

## Prerequisites

- Docker Desktop (Windows/Mac) or Docker Engine (Linux)
- Go 1.25+ (for local development without Docker)
- PostgreSQL running locally with the `did` schema seeded
- WSL2 (Windows only)

## Quick start

```bash
# Clone all repos into the same parent directory
git clone git@github.com:authnull0/authnull-service
git clone git@github.com:authnull0/Authnz
git clone git@github.com:authnull0/authn-service
git clone git@github.com:authnull0/ssi-service
git clone git@github.com:authnull0/did-react

# From authnull-service/
make dev
```

That starts: **redis + authnz + authnull-service** using your local postgres.

---

## Environment

Copy and fill in your values:

```bash
cp env_local_win.ps1 .env.local    # Windows
# or use env_local_win.ps1 directly in PowerShell
```

Key variables to configure for your machine:

| Variable | Default | Notes |
|---|---|---|
| `DB_HOST` | `localhost` | Your local postgres host |
| `DB_USER` | `postgres` | Your local postgres user |
| `DB_PASSWORD` | `postgres` | Your local postgres password |
| `DB_NAME` | `development` | Database name |
| `REDIS_PASSWORD` | `PrA6zPWF7b` | Redis password |
| `AUTHNZ_URL` | `http://localhost:6066/authnz/authenticate` | Authnz endpoint |

---

## Available commands

```bash
make help           # see all commands
make dev            # start backend (host postgres)
make dev-full       # start all services including UI
make test           # run test suite
make logs           # tail authnull-service logs
make rebuild-backend # rebuild only the backend after code change
make stop           # stop everything
make clean          # stop + delete volumes
```

---

## Adding / changing Go dependencies

After modifying `go.mod`:

```bash
# Configure GitHub access for private modules (one-time)
git config --global url."https://<YOUR_GITHUB_TOKEN>@github.com/authnull0/".insteadOf "https://github.com/authnull0/"

make vendor         # re-vendors all dependencies
git add vendor/
git commit -m "chore: update vendor"
```

---

## Running without Docker (local Go)

```bash
# Windows PowerShell
. .\env_local_win.ps1
$env:GOTOOLCHAIN = "auto"
go run ./cmd/authnull-service/...

# WSL / Linux
source env_local_win.ps1   # or export vars manually
export GOTOOLCHAIN=auto
go run ./cmd/authnull-service/...
```

---

## Repo structure

```
internal/
  ad/            Active Directory
  policy/        Policy engine
  pam/           Privileged access management
  mfa/           Multi-factor authentication
  issuer/        Credential issuance
  wallet/        Wallet service
  verifier/      Verifier service
  user/          User / org / tenant management
  entra/         Azure Entra sync
  database/      Database access management
  dbconsole/     Web terminal
  endpoint/      Endpoint management
  serviceaccounts/ Service accounts
  dashboard/     Dashboard analytics
pkg/
  db/            Shared DB connection
  middleware/    Auth + CORS middleware
  email/         Email utilities
cmd/
  authnull-service/  Entry point
config/
  config.yaml    PAM configuration
vendor/          Vendored Go dependencies
```
