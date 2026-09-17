# Database MFA — end-to-end flow

What happens when a user connects to a Postgres or MySQL database through
Authnull, from the admin creating a policy to ProxySQL letting the session open.

Referenced by function name rather than line number where possible, because line
numbers rot and function names don't. Line numbers appear only where the finding
*is* a specific statement, and each is stamped with the commit it was read at.

Companion document: [AD-MFA-FLOW.md](AD-MFA-FLOW.md) — the same treatment for AD.
The two flows share the push-MFA engine but almost nothing else.

> **Do not add this file to `TestHandoffPathsAreReal`.** That test asserts every
> backticked `METHOD /path` in a handoff document is registered. This document
> deliberately quotes paths that are **not** registered — that is finding 2 — so
> including it would fail the test by design.

## Sources read

Four repositories, at these commits:

| repo | branch | commit |
|---|---|---|
| `authnull-service` | `on-prem` | working tree |
| `proxysql-v3-alpha` | `authsql-postgres` | `37aec8fc` |
| `database-agent` | `checkout_postgres` | `6e22d1c` |
| `authn-service` | `production-az` | `a158432` |

`proxysql-v3` (without `-alpha`) is superseded — `-alpha` is the branch carrying
the Postgres work. `verifier-service` and `ssi-service` participate but were read
only far enough to establish where the blocking happens.

---

## 0. The one thing to understand first

**The verifiable credential is a courier, not a source of truth.**

Everything ProxySQL reads out of it — `databaseName`, `privilege[]`, `tables[]`,
`fieldMasking{}` — the policy already holds, and the agent already fetches via
`FetchPolicyDetails`. The `password` inside it is an out-of-band echo of a value
ProxySQL already has in its own `pgsql_users` table; it is decrypted, compared
against that stored value, and discarded.

This matters because it means removing the wallet does not require inventing any
new data. It requires reading from the policy instead of from a credential.

The second thing to understand: **for database logins the wallet tap *is* the
MFA.** There is no push, no challenge row, no provider. A connection blocks while
verifier-service waits for the user to approve a presentation in the mobile
wallet.

---

## 1. Provisioning — database-agent

The agent runs as a service on a VM that can reach both the database and
ProxySQL. On a timer (`timeInterval` minutes) it calls `FetchDatabaseDetails` per
configured host, which does directory sync (`dbSync`, `dbUser`, `dbTable`,
`FetchTablePrivileges`, `FetchTables`) and then, per database, `PollCheckoutJob`.

`PollCheckoutJob` (`src/pkg/checkout.go`) is the provisioning path:

1. `POST /api/v1/databaseService/getJobQueue` — jobs queued by policy approval.
2. Per job: `FetchPolicyDetails` → `POST /api/v1/policyService/getPolicyDetails`,
   for the policy's `tables`, `fieldMasking` and `privilege`.
3. `GenerateCredentials`:
   - reuse the existing `pgsql_users` password if the row exists and is non-empty,
     otherwise generate a new one;
   - `CREATE ROLE <user> WITH LOGIN PASSWORD '<pw>'`, or `ALTER ROLE … WITH
     PASSWORD` when the password is newly generated;
   - `INSERT`/`UPDATE` the `pgsql_users` row in ProxySQL, then `LOAD PGSQL USERS
     TO RUNTIME` and `SAVE PGSQL USERS TO DISK`;
   - AES-encrypt the password and `POST /api/v1/credential/createDatabaseCredential`;
   - `POST /api/v1/policyService/updatePolicyCredentialMapping`.
4. On success: `POST /api/v1/databaseService/updateQueue` marks the job complete.

The password's only real home is `pgsql_users` on the customer's own VM. The
platform never needs it — which is why the credential copy is redundant.

> **This path does not currently complete.** See finding 2.

---

## 2. The user gets a connection string

Console → `listConnections` → `DbService.GetAllDatabaseConnections`
(`internal/database/service/database_service.go`):

- mint a UUID, store `MFAState{UserId}` in Redis under that UUID for **180
  seconds** (key becomes `<uuid>&&pgAdmin` when `Mode == "pgAdmin"`);
- look up the user's permitted connections and each host's type/port from
  `did.db_synchronization` (defaulting to `6033` for MySQL, `6133` for Postgres);
- return a ready-to-paste command:

```
psql postgresql://<dbUser>,<uuid>:'<uuid>'@<proxy-host>:6133/<database>
mysql -u<dbUser>,<uuid> -p<uuid> -h<proxy-host> -P6033 -D<database> -A
```

The token appears **twice**: as a suffix on the username, and as the password.
Only the username copy is ever used (finding 4).

---

## 3. The intercept — ProxySQL

### Postgres (`lib/PgSQL_Protocol.cpp`)

In the handshake-response handler, before any authentication method runs:

- split the startup-packet username on the **first comma** →
  `clean_user` + `extra_data` (the token), stashed in
  `session_extra_data_map[clean_user + "_" + thread_session_id]`;
- **no comma → the connection is closed immediately.** This check precedes the
  `admin` exemption further down, so even `admin` must connect as `admin,<x>`;
- `GloPgAuth->lookup()` fetches the stored `pgsql_users` password.

Then in the `CLEAR_TEXT_PASSWORD` branch, for any user other than `admin`:
`loadAuthNullConfig2()` reads `[authnull] org_id / tenant_id / api_url` from
`proxysql.cnf`, and a `curl` POST goes out:

```json
{ "credentialType": "DATABASE", "requestId": "", "userIp": "<ipify result>",
  "orgId": 0, "tenantId": 0, "dbUser": "<clean_user>",
  "database_host": "<listener addr>", "hostname": "<db>",
  "databaseType": "postgres", "databaseName": "<db>",
  "token": "<extra_data>", "timestamp": <epoch> }
```

120s timeout, 10s connect timeout, `SSL_VERIFYPEER`/`SSL_VERIFYHOST` **disabled**,
and `getPublicIP3()` calls an external service on every single login.

### MySQL (`lib/MySQL_Session.cpp`)

`performMFA()` sends the equivalent payload with `databaseType: "mysql"` and
returns a clean boolean — `true` only when the response carries
`isValid == true`; `false` on rejection, non-2xx, CURL error or parse error. The
function itself is fail-closed. Its *caller* is not (finding 1).

There is also an `mfa_status_map` keyed on `rand_session_id`, so the check is
skipped for a session already seen.

---

## 4. The decision — authn-service

`api_url` points at authn-service, **not** authnull-service. `internal/dbconsole`
here declares `AuthRequest`/`AuthResponse` types matching this payload, but they
are referenced nowhere — `dbconsole` only serves the web-terminal websocket. Do
not mistake those types for a live handler.

`RiskBasedRepository.DoAuthenticationDatabase` (684 lines,
`src/repository/risk_based_repository.go`):

1. `GetUserFromRedis` resolves the token → wallet email + user id.
2. `LookupPolicy` with `Database{DatabaseName, DatabaseType, DatabaseUser}` and
   `IamLogging{IAMUsers: [email]}`.
3. `LookUpWalletDetailsV2` fetches the user's wallet credentials, filtered to the
   wallets that actually belong to that user.
4. Presentation requests are issued per credential, then
   `VerifyPresentationSubmissionRequestV4` → verifier-service, which is where the
   request **blocks** waiting for the wallet tap.
5. Returns `isValid` plus `credential.credentialSubject{databaseName, privilege,
   tables, fieldMasking, password}`.

**The policy's action is never consulted** — there is no `mfa_required` / `allow`
/ `deny` branch anywhere in this function (finding 5).

---

## 5. Applying the result — ProxySQL again

On `isValid == true`, reading `credential.credentialSubject`:

- `user_database_access2[user+db+session] = {databaseName}`
- `user_database_privileges2[user][db+session] = privilege[]`
- `usertype_masking_policies2[key] = fieldMasking` per table in `tables[]`
- `password` → `DecryptFromGoOpenSSL2()` → `pass2`

Then, outside the credential block:

```cpp
if (pass) free(pass);                 // the client's password, discarded
pass = strdup(pass2.c_str());         // replaced with the API's
pass_len = pass2.length();
if (strlen(password) == pass_len && strcmp(password, pass) == 0)
        ret = EXECUTION_STATE::SUCCESSFUL;
```

So the session opens when the API-supplied password matches the one ProxySQL
already had. The MySQL path applies the same maps and additionally rejects with a
proper `1045` packet if the requested database is not in the returned list.

---

## Findings

Ranked by consequence.

### 1. MySQL database MFA refuses only by accident — CRITICAL

> **Corrected 24 August 2026:** not a bypass. The `break` skips the connection accounting, so
> `free_users` stays 0 and the connection is refused as "Too many connections". Accidentally
> fail-closed, like finding 3. Still critical: the reported reason is wrong, and the refusal
> depends on a counter nobody intended to be load-bearing.

`lib/MySQL_Session.cpp` (`37aec8fc`):

```cpp
client_authenticated=true;                                  // :7044, before the check
switch (session_type) {
  case PROXYSQL_SESSION_MYSQL:
    …
    if (!performMFA(user_ip, connection_ip, user, db_name, authtoken, thread_session_id)) {
        syslog(LOG_ERR, "MFA Failed");                      // :7063
        break;                                              // breaks the switch only
    }
```

`client_authenticated` is set **before** the MFA call, and failure `break`s out of
the switch without emitting an error packet or clearing that flag. A denied
approval, an Authnull outage, a TLS failure and a malformed response are all
indistinguishable from success at the connection level.

The database-access check immediately below it *does* build a
`generate_pkt_ERR(… 1045 … "Access denied")` before breaking — so the mechanism
was understood and simply not applied to the MFA branch.

**Fix:** mirror that block — error packet, `RequestEnd`, and do not leave
`client_authenticated` true.

### 2. Postgres provisioning never completes — CRITICAL

The agent calls `POST /api/v1/policyService/getPolicyDetails`. That path is **not
registered**. The handler exists, at `/api/v1/policy/json/getPolicyDetails`
(`internal/policy/routes.go`).

`FetchPolicyDetails` returns an error on any non-200, and `PollCheckoutJob` does
`continue` on that error — *before* `GenerateCredentials` runs. Consequently:

- no DB role is created or altered,
- no `pgsql_users` row is written,
- the job is never marked complete, so it is re-attempted on every sync tick
  indefinitely.

Three of the agent's ten backend calls 404. The other two —
`createDatabaseCredential` and `updatePolicyCredentialMapping` — are the wallet
path and are *expected* to be gone. This one is required.

**Fix:** register `/api/v1/policyService/getPolicyDetails` in the policyService
alias table. One line, and it unblocks provisioning without touching the agent.

### 3. Postgres is fail-closed only by accident — HIGH

The entire Authnull block is wrapped in `catch (const std::exception& e)` which
logs and swallows — including the `throw std::runtime_error("Authentication
rejected by API")` raised when `isValid` is false, and the non-200 throw. Control
then reaches the password substitution, where `pass2` is a default-constructed
`std::string`.

The connection is refused because `strlen(password)` (the stored password) does
not equal `0`. That is the only thing standing between a rejected MFA and an open
session. Any `pgsql_users` row with an empty password inverts it.

The client also receives a generic authentication failure rather than a reason.

**Fix:** make denial explicit — generate an error packet and return `FAILED`
rather than relying on an empty-string comparison.

### 4. The client's password is never verified — HIGH (by design, worth stating)

The password the user supplies is `free()`d and replaced. Authentication rests
entirely on the token in the username. The token is therefore a bearer credential
for a database session — and because the connection string also places it in the
password position, it lands in shell history and pgAdmin's saved-connection
config, where a 180-second TTL is the only mitigation.

### 5. The policy action is ignored — HIGH

No `mfa_required` / `allow` / `deny` handling in `DoAuthenticationDatabase`. Every
covered login requires a wallet tap, so an **Allow** policy cannot be expressed.
Service accounts, connection pools and scheduled jobs cannot approve anything —
setting a policy on an application account breaks it, and there is no way to
exempt it.

### 6. Database passwords come from `math/rand` — HIGH

`GenerateRandomPassword` (`src/pkg/checkout.go`) uses
`rand.New(rand.NewSource(time.Now().UnixNano()))`. Predictable seed, non-crypto
generator, for credentials that grant database access.

**Fix:** `crypto/rand`.

### 7. Hardcoded AES key — HIGH

`84sF#v7Fpt!L#PesYb^AezXrUn2kE%5v` is embedded in `GenerateCredentials`, with the
matching `DecryptFromGoOpenSSL2` compiled into ProxySQL. It is in the source of
two repositories. Once the credential path is removed, both the key and
`EncryptAES` become dead and should go with it.

### 8. Smaller, but real — MEDIUM

- **SQL by string formatting.** `CREATE ROLE %s`, `ALTER ROLE %s`, and the
  `pgsql_users` statements are built with `fmt.Sprintf` on values the server
  supplies. The generated password charset happens to exclude `'`, so this does
  not break today — it is one charset change from doing so.
- **pgAdmin key mismatch.** The Redis key is `<uuid>&&pgAdmin`, but the
  connection string embeds the bare `<uuid>`, so the suffixed entry cannot be
  found by the token ProxySQL sends.
- **`getPublicIP` per login** — an external HTTP call on the authentication hot
  path, and a dependency on `api.ipify.org` being reachable.
- **TLS verification disabled** for the auth call (`37aec8fc` did this
  deliberately). If the endpoint's certificate is self-signed, add a CA path to
  `[authnull]` instead.
- **180s TTL** is tight for an interactive paste and awkward for a saved
  connection. Either surface a countdown or lengthen it.
- **No `[authnull]` stanza in the repo's `etc/proxysql.cnf`** and nothing
  templates it — so the agent should write it as part of provisioning.

---

## Remediation sequence

Ordered so that each step is independently shippable and the risky one is last.

**Step 1 — unblock what is broken now.** Register the
`/api/v1/policyService/getPolicyDetails` alias (finding 2). Backend only, no
agent or proxy release. Provisioning starts working.

**Step 2 — make denial mean denial.** Fix the MySQL `break` (finding 1) and the
Postgres implicit deny (finding 3). ProxySQL release, per-VM. These are pure
enforcement fixes and do not depend on the push work.

**Step 3 — agent hygiene.** `crypto/rand` (6); delete the credential calls, the
hardcoded key and `EncryptAES` once step 4 lands (7); parameterise the SQL (8).

**Step 4 — replace the wallet gate with push MFA.** In authn-service (or,
better, move the decision into authnull-service alongside the policy engine):
resolve token → user, read the policy, and call
`InitiateChallengeOfKind(KindDatabase, …)` then poll `GetMFAChallenge`. Most of
`DoAuthenticationDatabase`'s 684 lines disappear, because the credential was only
a courier.

Two things this step must decide, neither of which is code:

- **Unenrolled users.** With Okta as the org's provider this cannot arise. With
  the AuthNull Authenticator (device-based) it will. Deny is the right default for
  a database; mirror the AD sensor's switch rather than inventing a second one.
- **Provider scope.** `GetProviderForOrg` is exclusive per org, so database MFA
  inherits whatever AD uses. Accept that, or make it per-feature.

**Step 5 — response shape and cutover.** ProxySQL still reads
`credential.credentialSubject` and still decrypts `password`, so it cannot consume
a flat response. Because it runs on customer VMs:

1. serve **both** shapes — flat *and* the legacy wrapper. Old proxies behave
   exactly as today.
2. repoint `[authnull] api_url` per VM and restart ProxySQL only. Rollback is
   pointing it back.
3. roll the new ProxySQL build per VM.
4. drop the legacy wrapper when no old proxies remain.

---

## Confidence

Read directly and quoted above: the ProxySQL Postgres and MySQL paths, the agent's
poll/provision path, `DoAuthenticationDatabase`'s structure, and the token mint.

Verified mechanically: the agent's ten backend paths were diffed against the live
Gin route table (`ROUTE_DUMP=… go test -run TestDumpRoutes`), which is what
established the three 404s.

**Not** verified against a running database login — no Postgres or MySQL session
was traced end to end on a live deployment. Findings 1, 2 and 3 are read from
control flow, and each is worth reproducing before it is quoted as an incident.
The likeliest way to be wrong about finding 2 is if some deployment points the
agent's `Config.API` at a different backend that does serve the legacy path.
