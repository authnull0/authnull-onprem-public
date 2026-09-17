# Deploying authnull-service on a Linux VM with Docker Compose

This plan is written against the **live reference deployment** on `web-vm-01`
(`192.168.122.72`, a libvirt guest on `vmhost-01` / `49.12.150.218`), which runs
the pre-consolidation stack as 32 compose services out of `/home/ubuntu/onprem`.
Everything below either mirrors that deployment or calls out where the
consolidated service deliberately differs.

---

## 1. What the reference deployment actually looks like

**Topology.** nginx terminates TLS on the *host* (`vmhost-01`) for
`onprem.prod.authnull.com` and proxies per-path to published ports on the guest
(`192.168.122.72`). The guest runs only Docker; it is not internet-facing.

```
internet ──► vmhost-01 (nginx, certbot, :443)
                 │  per-path upstreams → 192.168.122.72:<port>
                 ▼
             web-vm-01 (docker compose project "onprem", 32 services)
```

**The 32 services split into four groups:**

| Group | Services |
|---|---|
| Consolidated into `authnull-service` | ad, dashboard, database, dbconsole, entra, issuer, mfa, pam, policy, service-accounts, user, verifier, wallet, okta-login |
| Stay separate (by design) | authnz `:6066`, ssi-service (no published port), authn-service `:2882`, did-react UI `:5173`, self-service-console `:3000` |
| Infra | postgres `:5432`, redis `:6379`, minio `:9000/:9595`, temporal `:7233`, cassandra `:9042`, elasticsearch `:9200` |
| **Not in the consolidation** | **secret-management-service `:9291`, log-service `:9255`, logworkflows `:8086`, transaction-log-daemon `:8087`, blockchain-ipfs-logging `:6065`** |

That last row matters — see §7.

**Registry is `docker-repo-public.authnull.com`** (self-hosted, proxied by nginx
on vmhost-01 alongside Jenkins and Nexus). Not `-v2`.

**Postgres is `bitnamilegacy/postgresql:16.1.0`**, user `kloudone`, database
`authnull_dev`, data volume at `/bitnami/postgresql`. Network
`authnull-prod-net`.

---

## 2. The schema — resolved

This was the one hard blocker and it is now closed.

The reference deployment bootstraps the `did` schema from two hand-maintained
files in `./db-init`:

- `did.sql` — 2424 lines, `DROP TABLE IF EXISTS` + `CREATE TABLE` per table
- `index.sql` — 19 lines of `CREATE INDEX` / `ALTER TABLE ADD CONSTRAINT`

**`index.sql` is byte-for-byte the fragment that had been sitting in this repo as
`db/01_schema.sql`.** The consolidation copied the index tail and lost `did.sql`,
which is why 65 of 142 referenced tables had no DDL.

Rather than re-import the hand-maintained pair, I took a real dump of the running
database — it is the authoritative current state, including drift from migrations
applied ad hoc since `did.sql` was last edited:

```sh
docker exec onprem-postgres-1 bash -c \
  'PGPASSWORD=$POSTGRESQL_PASSWORD pg_dump --schema-only --schema=did \
     --no-owner --no-privileges -U kloudone -d authnull_dev'
```

That is now committed as **`db-init/01_schema.sql`**: 7701 lines, **164 tables**,
16 indexes, 134 sequences. It supersedes both `did.sql` and `index.sql`, so the
old fragment and the GORM-derived draft have been deleted.

### Two databases, not one

The reference deployment runs a one-shot `did-schema-init` service that does more
than seed `authnull_dev`. It also:

1. creates a **second database `kloudone`** (the org database — org provisioning
   calls `GetConnectiontoDatabaseDynamically(<orgName>)`) and imports the same
   schema into it;
2. installs a `fix_tenant_url()` trigger on `did.tenants` in `kloudone` that
   rewrites `site_url` to `http://${SYSTEM_IP}/<subdomain>` on insert — this is
   what makes tenant links resolve to the VM instead of to `*.authnull.com`.

Mounting `db-init/` into `/docker-entrypoint-initdb.d` only seeds
`authnull_dev`, so without an equivalent the first org you provision lands in a
database with no tables. **A `did-schema-init` service is now in our compose too**
— see §4 step 3.

### Postgres version

The dump came from **16.1**, and our compose previously pinned
`postgres:15-alpine` — a 16 dump can fail to restore into 15. **Now
`postgres:16-alpine`.**

We deliberately did *not* adopt `bitnamilegacy/postgresql`: it uses a different
data path (`/bitnami/postgresql`) and `POSTGRESQL_*` env names instead of
`POSTGRES_*`. Our compose keeps the official image with standard names and
`/var/lib/postgresql/data`. Either is fine — just don't mix them, and note the
volume paths are not interchangeable if you ever migrate a volume between the two.

---

## 3. VM prerequisites

Sized from the reference guest, which carries 32 services including Cassandra,
Elasticsearch and Temporal. The consolidated stack drops ~14 Go services into
one process, so it needs less:

| | Reference (32 svc) | Consolidated (8 svc) |
|---|---|---|
| vCPU | 8 | 4 |
| RAM | 24–32 GB | 8 GB (12 if you add the logging stack) |
| Disk | 200 GB SSD | 80 GB SSD |

Elasticsearch needs `vm.max_map_count=262144` if you deploy the logging group.

```sh
# Ubuntu 22.04/24.04
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER   # log out/in; avoids the sudo-for-every-command
                                # pattern the reference guest currently needs
```

Registry login — the images are on a private self-hosted registry:

```sh
docker login docker-repo-public.authnull.com
```

---

## 4. Deployment steps

### Step 1 — registry hostname — DONE

`docker-compose.yml` pinned `docker-repo-public-v2.authnull.com` for all six
authnull images while Jenkins pushes to `docker-repo-public.authnull.com` (the
`Jenkinsfile` changed in `05f2ab3`; compose did not), so every
`docker compose pull` fetched stale images. **Applied — all six now point at
`docker-repo-public.authnull.com`.** Nothing to do.

### Step 2 — configure `.env`

```sh
cp .env.prod .env
```

Then set, at minimum:

- the 7 `CHANGE_ME` placeholders: `DB_PASSWORD`, `REDIS_PASSWORD`,
  `ENCRYPTION_KEY` (32 chars), `TOTP_ENCRYPTION_KEY` (64 hex),
  `JWT_SECRET`, `SMTP_PASSWORD`, `POSTGRES_PASSWORD`
- `DOMAIN` — `deploy.sh` requires it. **It exists in `.env.prod` but not in the
  dev `.env`**, so `./deploy.sh` fails immediately if you skip the copy.
- `SYSTEM_URL` — this deployment's externally reachable base URL. Compose derives
  `API_BASE_URL`, `AD_SERVICE_URL` and `POLICY_SERVICE_URL` from it, and those
  are **baked into downloadable AD agent config files**. Left at `localhost:8080`
  every enrolled agent gets an unreachable server.
- `ORG_NAME` — the organisation name used at signup. `did-schema-init` creates a
  database with this name; if it differs from what you sign up with, provisioning
  creates a second, empty one.
- `SYSTEM_IP` / `FIX_TENANT_URL` — only needed for the tenant-URL rewrite (§2).
  Both now present in `.env`, `.env.prod` and `.env.example`, defaulting to
  unset / `false`.

Generate the crypto material rather than inventing it:

```sh
openssl rand -hex 16   # ENCRYPTION_KEY (32 chars)
openssl rand -hex 32   # TOTP_ENCRYPTION_KEY (64 hex)
openssl rand -hex 32   # JWT_SECRET
```

`TOTP_ENCRYPTION_KEY` now degrades to a generated key on a malformed value rather
than exiting, but that key is **regenerated on every restart** — existing TOTP
enrolments stop verifying. Set it properly.

### Step 3 — org database + trigger — DONE

**A `did-schema-init` service is now in `docker-compose.yml`**, mirroring the
reference. It is idempotent, and `authnull-service` gained
`depends_on: did-schema-init: condition: service_completed_successfully`, so the
backend cannot start against a missing or half-applied schema.

It does three things:

1. creates the org database (`${ORG_NAME}`, default `kloudone`) and imports
   `db-init/01_schema.sql` into it, if absent;
2. seeds the **master** database too if `did.organizations` is missing — postgres
   only runs `/docker-entrypoint-initdb.d` on a first-boot *empty volume*, so an
   existing volume can otherwise be left schema-less;
3. optionally installs the `fix_tenant_url()` trigger, gated behind
   `FIX_TENANT_URL=true` (off by default — only wanted when no real domain fronts
   the deployment).

Set `ORG_NAME` to the organisation name used at signup. If they differ,
provisioning creates a second, empty database.

Verified by extracting the entrypoint, running `sh -n`, and executing it against
a stubbed `psql` for all three paths: fresh install, idempotent re-run, and a
failing schema import (which exits 1 and correctly blocks the backend).

<details>
<summary>Reference version, for comparison</summary>


```yaml
  did-schema-init:
    image: postgres:16-alpine          # match your postgres image
    restart: "no"
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      PGPASSWORD: ${DB_PASSWORD}
      SYSTEM_IP: ${SYSTEM_IP}
      ORG_DB: ${ORG_NAME:-kloudone}
    volumes:
      - ./db-init:/db-init:ro
    networks: [authnull-network]
    entrypoint:
      - bash
      - -c
      - |
        set -e
        psql -h postgres -U ${DB_USER} -d postgres -tc \
          "SELECT 1 FROM pg_database WHERE datname='$$ORG_DB'" | grep -q 1 || {
            psql -h postgres -U ${DB_USER} -d postgres -c "CREATE DATABASE \"$$ORG_DB\";"
            psql -h postgres -U ${DB_USER} -d "$$ORG_DB" -f /db-init/01_schema.sql
          }
        psql -h postgres -U ${DB_USER} -d "$$ORG_DB" -c "
          CREATE OR REPLACE FUNCTION fix_tenant_url() RETURNS TRIGGER AS \$\$
          BEGIN
            NEW.site_url := 'http://$$SYSTEM_IP/' || split_part(NEW.site_url, '.', 2);
            RETURN NEW;
          END; \$\$ LANGUAGE plpgsql;
          DROP TRIGGER IF EXISTS trigger_fix_tenant_url ON did.tenants;
          CREATE TRIGGER trigger_fix_tenant_url BEFORE INSERT ON did.tenants
            FOR EACH ROW EXECUTE FUNCTION fix_tenant_url();"
```

</details>

Only apply the trigger if you want the reference's IP-rewriting behaviour; skip
it if you front the deployment with a real domain.

### Step 4 — bring the stack up

```sh
./deploy.sh          # validates .env, pulls, starts, waits for health
# or, without the guardrails:
docker compose up -d --build
```

`authnull-service` is the only service with a `build:` context — the Dockerfile
now compiles from source in a builder stage, so the build needs registry access
for the private `github.com/authnull0/did-proto` module. Pass the token:

```sh
docker compose build --build-arg GITHUB_TOKEN=<pat> authnull-service
```

Verify:

```sh
docker compose ps
curl -fsS http://localhost:8080/system/v1/health
docker compose exec postgres psql -U kloudone -d authnull_dev -c '\dt did.*' | wc -l   # ~164
```

### Step 5 — nginx and TLS on the host

Copy `nginx/authnull.conf`, replace `yourdomain.com`, then certbot:

```sh
sudo cp nginx/authnull.conf /etc/nginx/sites-available/authnull.conf
sudo sed -i "s/yourdomain.com/$YOUR_DOMAIN/g" /etc/nginx/sites-available/authnull.conf
sudo ln -sf /etc/nginx/sites-available/authnull.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d "$YOUR_DOMAIN"
```

Our vhost is far simpler than the reference because one backend replaces 14
upstreams — `/api/`, `/authentication/`, `/authnz/`, `/ad/`, `/pam/`, `/system/`
all go to `:8080`; `/ssc/` to `:3000`; `/` to the UI on `:5173`.

**`/console/` websocket block — DONE.** The DB console (`/console/ws`,
`/console/init`) is served by the backend, but `location /` was sending it to the
UI on `:5173`. A dedicated block with `Upgrade`/`Connection` headers,
`proxy_buffering off` and a 3600s timeout is now in `nginx/authnull.conf`.

**Still to check: `proxy_pass` targets `127.0.0.1`.** Correct only if nginx runs
on the same host as the containers. In the reference, nginx is on `vmhost-01` and
points at the guest IP. If you split them, replace `127.0.0.1` with the VM
address.

---

## 5. What to smoke-test

| Check | Why |
|---|---|
| `GET /system/v1/health` | process up |
| Admin UI login → dashboard tiles | authnz + dashboard + user paths |
| Provision a new org, then confirm its DB has 164 tables | §2 org-DB init actually ran |
| New org has a `webauthn` MFA factor | the provisioning seed restored this round |
| AD agent config download | `API_BASE_URL` is external, not localhost |
| Postgres DB console session | `/console/` nginx block + the `psql`/`PGPASSWORD` exec path |
| RADIUS device list | `network_device` endpoints restored this round |
| Policy update on a multi-version policy | the version-chain walk and nil-`Version` guard |

---

## 6. Rollback

```sh
docker compose down                     # keeps volumes
docker compose down -v                  # DESTROYS postgres/redis data
git checkout <previous-tag> && docker compose up -d --build
```

Back the database up before any upgrade — the volume is the only stateful thing:

```sh
docker compose exec -T postgres pg_dumpall -U kloudone > backup-$(date +%F).sql
```

---

## 7. Services the consolidation does not cover

The reference runs five services with **no equivalent in `authnull-service`**.
Decide explicitly whether each is required, because nothing in the consolidated
stack replaces them:

| Service | Port | Consolidated status |
|---|---|---|
| `secret-management-service` | 9291 | `/api/v1/secretservice/*` is a **hardcoded stub** in `cmd/authnull-service/routes.go` returning `connectionMode: 0` / "vault not configured". PAM credential-vaulting is a no-op. |
| `log-service` | 9255 | absent |
| `logworkflows` | 8086 | absent — `LOGGING_URL` is documented as unset, so issuer audit-log POSTs are skipped |
| `transaction-log-daemon` | 8087 | absent |
| `blockchain-ipfs-logging` | 6065 | absent |

They also imply infra our compose omits: **temporal**, **cassandra**,
**elasticsearch**, **minio**. If you need the logging/audit pipeline or real
vaulting, those services and their backing stores have to be added back — that is
a scope decision, not a deployment detail.

Also note `ssi-service` publishes **no port** in the reference (container-internal
`:5000` only), yet our compose sets `DID_SERVICE_ADDR: ssi-service:50051`. I could
not confirm ssi-service listens on 50051 at all; the issuer/serviceaccounts gRPC
DID clients will fail if it does not. Verify before relying on DID creation.

---

## 8. Known deltas from the reference, at a glance

| # | Item | Status |
|---|---|---|
| 1 | compose pinned `-v2` registry | **fixed** — all six images repointed |
| 2 | `postgres:15-alpine` vs 16.1 dump | **fixed** — now `postgres:16-alpine` |
| 3 | org DB + tenant-URL trigger not created | **fixed** — `did-schema-init` added and gated |
| 4 | `SYSTEM_IP` / `FIX_TENANT_URL` missing | **fixed** — added to `.env`, `.env.prod`, `.env.example` |
| 5 | nginx has no `/console/` block | **fixed** |
| 6 | 5 logging/vault services absent | **open** — §7, scope call |
| 7 | `DID_SERVICE_ADDR` port unverified | **open** — §7, verify against ssi-service |
| 8 | compose header claims `--profile ssi --profile authn` | **open** — stale text; no service declares `profiles` |
| 9 | nothing has been run against a live Postgres/Redis | **open** — see §9 |

---

## 9. Staging run — what was actually verified

Executed on `web-vm-03` (`192.168.122.15`), 2026-07-30. That VM already runs
proxysql (6032/6033/6132/6133) and a **native postgresql@14 on 5432**, so the
staging stack used a `docker-compose.override.yml` remapping the container's
published port to `15432`. Note compose *merges* sequence fields — the override
needs `ports: !override` or the base `5432:5432` mapping is kept and still
collides.

| Check | Result |
|---|---|
| `db-init/01_schema.sql` applies to real Postgres 16 | **164 tables, zero errors** |
| `did-schema-init` creates the org DB | **`kloudone`, 164 tables, exit 0** |
| Idempotent re-run | **no-ops correctly, exit 0** |
| `FIX_TENANT_URL=true` path | trigger created; verified and dropped again |
| `docker build` of the consolidated service | **succeeds, 96.6 MB image** |
| Service starts against live Postgres + Redis | **yes** — Redis PONG, cron started, WebAuthn configured |
| Graceful degradation on unreachable Okta | **yes** — SAML disabled, process continued |
| `GET /system/v1/health` | 200 `{"status":"ok"}` |
| Unregistered path | 404 (routing sane) |
| `policyService/listLinuxCommands` | **200, returned seeded row** |
| `policyService/changeStatus` | **200** |
| `policyService/addEndpoint` | **200, `machine_id: 1`** |
| `policyService/storeSudoers` | **200** |
| `network_device` Create → List → Delete | **201 / 200 / 200, real UUID round-tripped** |
| `tenant/getTenantDetail` (converted loopback) | **200 with real tenant data** |
| `policy/json/listPolicy` | 200 |
| dashboard `listAuthRequest` period=1 | **200 — and the process survived** (this is the path that used to `log.Fatalf`) |
| Container restarts / OOM | **0 / false** |

The build used a `Dockerfile.staging` that compiles from `vendor/` because the VM
has no `GIT_TOKEN` for the private `did-proto` module. Same source, same compiler,
same flags — only the module source differs. CI has the token and uses `-mod=mod`.

### Two bugs the run found, both now fixed

**1. `/console/` did not resolve.** The consolidated service registers the DB
console under `/api/v1/dbconsole/{ws,init}`, but the UI and the reference
deployment both call `/console/{ws,init}`. The nginx block added earlier proxied
`/console/` straight through and 404'd. Fixed by rewriting in `proxy_pass`:
`http://127.0.0.1:8080/api/v1/dbconsole/`.

That rewrite fixed the path but not the method, so `/console/init` kept 404ing
until later: `init` was registered as `GET` while the UI posts a JSON body, and
gin's `HandleMethodNotAllowed` is off by default, so it surfaced as a 404 rather
than a 405. It is now `POST /api/v1/dbconsole/init`; `ws` stays `GET` because it
is a websocket upgrade. The staging run below listed a real Postgres console
session as uncovered, which is why the method half went unnoticed.

**2. Nil-pointer panic on any unknown `orgId`.**
`getTenantDBConnection` used `Find()`, which — unlike `First()` — does **not**
return `ErrRecordNotFound`. An unknown org therefore left the struct zero-valued,
slipped past the error check, resolved to an empty database name, and returned
`(nil, nil)`. All ~60 callers then dereferenced nil. Gin recovered it into a 500
so the process survived, but every one of those endpoints was one bad `orgId` away
from a panic. Fixed at the single source: it now returns an explicit error.
Verified — unknown org returns
`{"error":"organization 99999 not found or has no database name"}`, valid org
still returns data, zero panics in the run.

### What the staging run did *not* cover

- **The five separate services** (`authnz`, `ssi-service`, `authn-service`, `ui`,
  `self-service-console`) — their images are on the private registry and no
  credentials were available. The backend ran with `AUTH_DISABLED=true`, so the
  **authnz middleware path is unverified**.
- End-to-end UI login, org signup through the provisioning cron, AD agent
  enrolment, and a real Postgres DB-console session.
- `DID_SERVICE_ADDR: ssi-service:50051` — still unconfirmed (§7).

### Staging artefacts left on web-vm-03

`/opt/authnull-staging` with volumes `authnull-staging_postgres-data` and
`authnull-staging_redis-data`, plus container `authnull-svc-test` and images
`authnull-service:staging{,2}`. Docker was installed on that VM (proxysql and the
native Postgres were left untouched and confirmed still active). Teardown:

```sh
cd /opt/authnull-staging && docker compose down -v
docker rm -f authnull-svc-test
docker rmi authnull-service:staging authnull-service:staging2
```

---

## 10. Remaining gate before production

Items 1–5 are closed, and the schema blocker is closed. What remains is not
configuration but **verification**:

The schema, the init service, the build, startup against live Postgres/Redis, and
every endpoint restored in this work are now verified (§9). What remains unproven
is the part that needs the private registry:

- **authnz middleware** — the staging run used `AUTH_DISABLED=true`
- UI login end to end, org signup via the provisioning cron
- AD agent enrolment against a real agent
- a live Postgres DB-console session through nginx
- `DID_SERVICE_ADDR` / ssi-service gRPC

Do that with registry credentials on a fresh volume, `docker compose logs -f`
attached. Bring up `postgres redis authnz authnull-service` first, confirm health
**and one real login**, then add the UI and SSC.

Do not treat this as a drop-in replacement for the 32-service stack on day one.
The five absent services and the `secretservice` stub mean feature parity is not
there. Run both side by side, point a test tenant at the consolidated stack, and
cut over per feature.
