# Installing Authnull on-premise

Self-hosted Active Directory MFA. One Linux host, seven containers, about fifteen
minutes.

## Before you start

| | |
|---|---|
| OS | Any Linux with Docker Engine 20.10+ and the Compose **v2** plugin |
| CPU / RAM | 2 vCPU, 6 GB minimum; 4 vCPU / 8 GB comfortable |
| Disk | 20 GB free |
| Network | Outbound HTTPS to pull images. Nothing inbound from the internet is required. |

The Compose **v2** plugin specifically (`docker compose`, not `docker-compose`). The v1
binary ignores the startup ordering this package relies on, so services come up in the
wrong order and fail in ways that look random.

Have ready:

- **The URL browsers will use** — e.g. `https://authnull.acme.internal`. Put TLS in front
  of port 8080 with your own reverse proxy; the package does not terminate TLS.
- **The email address of your first administrator.**
- **A short organisation name**, lowercase, no spaces.

## Install

```sh
tar xzf authnull-onprem.tar.gz && cd authnull-onprem
./install.sh --check      # prerequisites only, changes nothing
./install.sh
```

`install.sh` asks three questions, generates every secret, starts the stack and waits
until it reports healthy. It is safe to re-run: an existing `.env` is never overwritten,
because rotating `JWT_SECRET` would invalidate every session and rotating
`ENCRYPTION_KEY` would make already-encrypted data unreadable.

Success looks like:

```
Healthy.
Licence: 30-day trial started.

Authnull is running
  Console:  https://authnull.acme.internal
```

## Verifying the install

Nine checks. Run them in order; each one isolates a different layer.

```sh
# 1. every container up, none restarting
docker compose ps

# 2. the service is serving and the schema matches
curl -s http://localhost:8080/system/v1/health | jq
#    expect  "schema": { "ok": true }
#    and     "license": { "state": "trial", "licensed": true }

# 3. the console is reachable
curl -sI http://localhost:5173 | head -1        # expect 200

# 4. Postgres and Redis are NOT reachable from outside
curl -s --max-time 3 http://localhost:5432 ; echo "exit=$?"   # expect non-zero
#    They are internal to the compose network on purpose: Redis holds live session tokens.

# 5. the database was created with the credentials from .env
docker compose exec postgres psql -U "$(grep ^DB_USER= .env | cut -d= -f2)" \
    -d "$(grep ^DB_NAME= .env | cut -d= -f2)" -c '\dn'      # expect the did schema

# 6. every migration replayed cleanly
docker compose logs did-schema-init | grep -iE "error|fatal" ; echo "exit=$?"   # expect no matches

# 7. sign in to the console as your administrator address

# 8. add your directory  (Identity Provider -> Add), then install the DC sensor

# 9. create an MFA policy and authenticate once against the domain
```

Checks 2 and 4 are the ones worth doing every time. Check 2 proves the schema is
complete rather than merely present; check 4 proves you have not published a session
store to the network.

## Licence state

The deployment runs free for 30 days from first boot, with every feature enabled.
`/system/v1/health` reports the days remaining throughout:

```json
"license": { "state": "trial", "licensed": true, "daysRemaining": 12 }
```

The trial reports `"state": "trial"` on every one of those days and `"state": "expired"` on
the thirty-first — it never passes through an intermediate warning state, so watch
`daysRemaining` rather than `state` if you are scripting an alert. A purchased licence does
report `"state": "expiring"` for its last 14 days.

When you buy, you receive a licence file. Upload it in **Settings → Licence**; it takes
effect immediately, with no restart. Air-gapped installs can instead drop it at
`./license/authnull.lic` before first boot.

**Expiry never blocks authentication.** MFA keeps working, pushes keep arriving, the
sensor keeps enforcing. What stops is administration: the console goes read-only until a
licence is installed. A lapsed invoice cannot take your domain controllers offline.

If `/system/v1/health` reports `"state": "not_enforced"`, this image was built without a
licence key — you have the wrong image and should ask for the `-onprem` tag.

## When it does not work

Licence problems are in this table too — `state: not_enforced`, an upload that is refused, a
console that has gone read-only.


| Symptom | Cause |
|---|---|
| `./install.sh --check` reports a port in use | Something already listens on 8080, 6066, 5173 or 3000. Stop it, or change the published port in `docker-compose.yml`. |
| `cannot talk to the Docker daemon` | Not running, or your user is not in the `docker` group. `sudo systemctl start docker`, then `newgrp docker`. |
| `did-schema-init` logs `role does not exist` | `.env` was edited after the first start. Postgres initialises its user *once*, on an empty data directory; changing `DB_USER` afterwards does not rename it. Either restore the old value or `docker compose down -v` and start over — **that destroys all data**. |
| Health never becomes ready | `docker compose logs authnull-service --tail=50`. Usually the database is unreachable or `.env` is incomplete. |
| Console loads but sign-in fails | `SYSTEM_URL` and `CLIENT_URL` must be the addresses a **browser** uses, not container names. |
| Enrollment emails never arrive | `SMTP_*` is unset. The console works without it; only outbound mail is affected. |

Collect `docker compose ps`, `docker compose logs --tail=100`, and the output of
`/system/v1/health` before contacting support. Those three answer most questions without
a second round trip.

## What is not in this package

- **The AuthNull Authenticator app.** Its push transport is tied to Authnull's own
  Firebase project, so a self-hosted deployment cannot use it. Use Okta, Duo, TOTP or
  WebAuthn — all supported, none requiring an Authnull-hosted component.
- **Database MFA.** Licensable, but not part of this release.

**RADIUS MFA is included**, as `radius-bridge/`. It installs on the customer's
FreeRADIUS host rather than in this compose stack, so it is a separate step and not
part of `install.sh` — see [RADIUS.md](RADIUS.md). Two prerequisites decide whether it
can work at all: `authn-service` must have `ENCRYPTION_KEY`, `TOTP_ENCRYPTION_KEY` and
`INTERNAL_API_KEY` set with its `TENANT_*` URLs pointing at `authnull-service:8080`, and
the RADIUS users must be synced from a directory. Both fail closed, on every login.
