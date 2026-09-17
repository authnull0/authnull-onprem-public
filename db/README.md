# Database bootstrap

`docker-compose.yml` mounts `./db-init` into the postgres container at
`/docker-entrypoint-initdb.d`, so every `*.sql` there runs once, in filename
order, on first boot of an empty data volume.

## The schema

[`../db-init/01_schema.sql`](../db-init/01_schema.sql) is a `pg_dump
--schema-only --schema=did` taken from the **live reference deployment**
(`web-vm-01`, database `authnull_dev`, PostgreSQL 16.1):

- 164 tables, 16 indexes, 134 sequences
- includes `CREATE SCHEMA did`, so it bootstraps an empty database unaided

Regenerate it from a running environment with:

```sh
docker exec <postgres-container> bash -c \
  'PGPASSWORD=$POSTGRESQL_PASSWORD pg_dump --schema-only --schema=did \
     --no-owner --no-privileges -U kloudone -d authnull_dev' > db-init/01_schema.sql
```

### History

This replaced two earlier files, both now deleted:

- `db/01_schema.sql` — an index/FK tail with no `CREATE TABLE`. It turned out to
  be byte-for-byte the reference deployment's `db-init/index.sql`; the
  consolidation copied that companion file and lost the `did.sql` that actually
  created the tables, which is why 65 of 142 referenced tables had no DDL.
- `db/draft_schema_from_models.sql` — 55 tables reverse-engineered from the GORM
  structs as a stopgap. Superseded by the real dump; the generator
  (`scripts/gen_schema_draft.py`) is kept only for reference.

## Two databases are required

The reference deployment seeds **two**: the master `authnull_dev` *and* an org
database (`kloudone`), because org provisioning connects via
`GetConnectiontoDatabaseDynamically(<orgName>)`. Mounting `db-init/` only seeds
the master. See §2 and §4 step 3 of [../DEPLOYMENT.md](../DEPLOYMENT.md) for the
one-shot init service that creates the org DB and installs the
`fix_tenant_url()` trigger.

## Postgres version

The dump is from 16.1 and the reference runs `bitnamilegacy/postgresql:16.1.0`.
`docker-compose.yml` currently pins `postgres:15-alpine` — align it to 16 before
restoring.

## Two migration directories — only one is applied

This is the thing most people get wrong, so it is worth stating plainly:

| Directory | Applied automatically? |
|---|---|
| `db-init/migrations/*.sql` | **Yes** — by the `did-schema-init` service on every `up` |
| `internal/*/db/migrations/*.sql` | **No** — reference/provenance only, applied by nothing |

### `db-init/migrations/` (runtime migrations)

`did-schema-init` replays every file here against the master **and every org
database** on each `docker compose up`, unguarded and in filename order. That is
deliberate: the other two branches in that service only fire on a fresh volume or a
schema-less master, so on an existing deployment neither runs and new DDL would never
land anywhere.

Because it replays unconditionally, **every file must be idempotent** — use
`CREATE ... IF NOT EXISTS`, and guard `UPDATE`/`ALTER` on the target existing (e.g.
`IF to_regclass('did.foo') IS NOT NULL`). A bare statement against a missing table
aborts the whole run under `ON_ERROR_STOP=1`. Databases without a `did` schema are
skipped. There is no ledger table, and none is needed.

Do **not** add DDL to `01_schema.sql`: it is a verbatim `pg_dump` with a documented
regeneration command, so anything hand-added there is silently lost the next time it is
regenerated. Do not name a file `db-init/02_*.sql` either — the postgres entrypoint
glob only covers a first-boot empty volume, which is the one path that already works.

| Migration | Purpose |
|---|---|
| `001_mfa_credentials.sql` | Creates `did.credentials` (WebAuthn/passkey records, missing from the dump) and renames the seeded `mfa_config` row `webauthn` → `Passkey` |

### `internal/*/db/migrations/` (reference only)

Applied by **nothing**. These post-date the schema dump in some cases and exist as
provenance:

| Module | Migrations |
|---|---|
| `internal/ad` | 001–009 (gateway, MFA push, auth log) |
| `internal/policy` | 001–006 |
| `internal/database` | 001_multi_host_support |
| `internal/pam` | 001_machine_uuid |

Some of these tables (`blocked_principals`, `enrolled_set_changes`,
`gateway_domain_mappings`) are **absent from the live dump** — the reference database
predates those features. Apply the relevant migrations after restoring the schema if you
need them.

`did.passkey_credentials`, `did.credentials` and `did.clients` were previously listed
here as having migrations. They did not: no `.sql` in this repo created any of them.
`did.credentials` is now created by `db-init/migrations/001_mfa_credentials.sql`.
`did.passkey_credentials` and `did.clients` still have no DDL anywhere — the handlers
that use them are unreachable from the UI and their routes are commented out.
