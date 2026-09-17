# Database MFA — replace the wallet with push

Today a database login blocks while the user approves a **verifiable presentation in a
mobile wallet**. This replaces that with the same push MFA the AD flow uses, and removes
the credential machinery entirely.

**Roughly 5–7 days**, plus a per-VM ProxySQL rollout. Read
[DATABASE-MFA-FLOW.md](DATABASE-MFA-FLOW.md) first — it is the traced description of how
the current flow works and where it is broken. This document is what to do about it.

---

## 0. The one idea that makes this small

**The verifiable credential is a courier, not a source of truth.**

Everything ProxySQL reads out of it — `databaseName`, `privilege[]`, `tables[]`,
`fieldMasking{}` — the policy already holds, and the agent already fetches through
`getPolicyDetails`. The `password` inside it is an out-of-band echo of a value ProxySQL
already has in its own `pgsql_users` table: it is decrypted, compared against that stored
value, and discarded.

So this is not "port the credential to push". It is **read from the policy, push instead of
poll, and stop issuing credentials.** No new data has to be invented.

The second thing to know: for database logins the **wallet tap *is* the MFA**. There is no
challenge row, no provider, no push. `authn-service` blocks while `verifier-service` waits
for a presentation. That is the whole mechanism being replaced.

---

## 0b. DECIDED: a database policy names IAM users, and nothing else

Settled 24 August 2026. Recorded here because it narrows the design and the obvious instinct
is to add the scopes back.

A database policy names **individual IAM users by email address**. Not AD users, not AD
groups, not OUs, not IAM groups. Implemented in `internal/database/dbmfa/matcher.go`, whose
package comment carries the full reasoning; the short version:

- **Provisioning is per-IAM-user and cannot be otherwise today.** Approval queues one
  `did.database_job_queue` row per IAM user named, and that job creates the database role and
  writes its password into ProxySQL's `pgsql_users`. An AD-group-scoped policy named no IAM
  users, so it queued nothing — it would have matched at connection time and granted access to
  a role that had never been created. Matching and provisioning must agree about who a policy
  names, and provisioning is the half that cannot be hand-waved.
- **The AD-to-platform link was a string match on email.** `did.users` has no
  `sAMAccountName`, `did.ad_users` has no platform user id, so the directory identity of a
  connection came from matching `did.ad_users.email_id` against `did.users.email_address` and
  hoping. Not a foundation for deciding who may open a database.
- **It cost five queries on a blocked connection.** Now one.

**IAM groups are out for a simpler reason: they never worked.** `BuildAuthContext` passed
`nil` for the group list, so an IAM-group scope could never match; and `GetUserDetails` accepts
an `iam_groups` argument and ignores it, so such a policy provisioned nothing either.

The cost, stated plainly: a customer with five hundred DBAs in a directory adds five hundred
IAM users rather than pointing at one group. They are ordinary `did.users` rows, so a directory
sync could create them without any of this needing AD scoping again — the two are separable,
and only the POLICY is IAM-only. If a large customer is close, a bulk add matters more than it
looks.

A policy carrying the old AD fields is not rejected — it simply matches nobody, with a skip
reason that says the shape is wrong and names the fix. Adding emails to such a policy makes it
work; the stale fields are ignored, not poisonous.
`TestRemovedScopesMatchNobodyAndExplainThemselves` pins both halves.

**Still to do, and it is the real lesson of PR #16:** refuse a database policy at CREATION
when it names no IAM user. Today such a policy is accepted, approved, queues nothing, and
refuses every connection. It should be impossible to write.

---

## 1. Already done — do not rebuild

The push-side seam exists and is merged. This is the part that would have been fiddly.

| In place | Where |
|---|---|
| `mfapush.KindDatabase` | `internal/mfapush/provider.go` |
| `mfapush.DatabaseResource(dbName, host, protocol)` | `internal/mfapush/context.go` |
| the `KindDatabase` arm of `challengeContextFor` | `internal/ad/src/repository/mfa_push_repository.go:210` |
| `InitiateChallengeOfKind(kind, req)` on repo **and** service | `mfa_push_repository.go:275`, `mfa_push_service.go:36` |
| `FeatureDatabase` licence gating, any combination | `pkg/license` |
| `getPolicyDetails` reachable by the agent | `RegisterAgentRoutes` |

**`KindDatabase` has no production caller yet.** It was built alongside the RADIUS work and
tested, but nothing invokes it. Wiring that caller is task 3.

### Why correlation must stay gated

`challengeContextFor` zeroes the correlated AD context for any kind that is not `KindAD`.
Do not undo that. `correlateFromAuthLog` matches on **org + email alone**, so a Postgres
login by someone who also signs into Windows would inherit that logon's Kerberos SPN,
domain, AD username and source IP — the prompt would describe an authentication that is not
happening. `TestDatabaseChallengeDoesNotInheritADContext` asserts it.

### How a database challenge maps onto the request

No DTO change. The caller puts its own fields on the existing generic ones:

```
GatewayId      -> the database host        (already NOT NULL on the challenge row)
Destination    -> the database name
Protocol       -> "postgres" | "mysql"
BindingMessage -> the sentence the user reads, including the DB role
```

---

## 2. Fix enforcement first — independent of the push work

Add to this section: **the provisioning job is never queued** when `default_issuer` is unset.
See the correction in §4 — it is listed there because that is where it was wrongly filed, but
it is an enforcement blocker and should be fixed alongside 2a–2c.

These are live defects. Do them before anything else; they are small and they stand alone.

### 2a. MySQL database MFA refuses only as a side effect, and reports the wrong reason

> **Corrected 24 August 2026.** This section originally said MySQL MFA was not enforced at all.
> It is not a bypass: the `break` skips the connection accounting, so `free_users` stays 0 and
> the connection is refused anyway — surfacing as **"Too many connections"**. Accidentally
> fail-closed, exactly like the Postgres path in 2b. The fix and the priority are unchanged: the
> error message misdirects whoever is debugging it, and enforcement resting on a resource counter
> it was never meant to rest on becomes a real bypass the moment that counter is refactored.

`proxysql-v3-alpha`, branch `authsql-postgres`, `lib/MySQL_Session.cpp`:

```cpp
client_authenticated=true;                          // :7044 — BEFORE the check
switch (session_type) {
  case PROXYSQL_SESSION_MYSQL:
    if (!performMFA(...)) {
        syslog(LOG_ERR, "MFA Failed");              // :7063
        break;                                      // breaks the switch, not the auth
    }
```

`client_authenticated` is set before the call, and failure `break`s out of the switch
without emitting an error packet. **A denied push, an Authnull outage and a TLS failure are
all indistinguishable from success.** The database-access check immediately below it builds
a proper `1045 Access denied` packet, so copy that: error packet, `RequestEnd`, and do not
leave `client_authenticated` true.

### 2b. Postgres denies only by accident

`lib/PgSQL_Protocol.cpp`: the whole Authnull block sits inside
`catch (const std::exception&)`, which swallows the `"Authentication rejected by API"` throw.
Control then reaches the password substitution where `pass2` is a default-constructed
`std::string`, so the connection is refused *because* `strlen(password) != 0`. Any
`pgsql_users` row with an empty password inverts it, and the client gets a generic failure
rather than a reason.

Make the denial explicit: generate an error packet and return `FAILED`.

### 2c. Passwords from `math/rand`

`database-agent`, `src/pkg/checkout.go`, `GenerateRandomPassword` uses
`rand.New(rand.NewSource(time.Now().UnixNano()))` — predictable seed, non-crypto generator,
for credentials that grant database access. Use `crypto/rand`.

---

## 3. The decision endpoint — the core of the work

### 3a. Where it goes

**`internal/database`, in authnull-service.** Not `authn-service`.

`authn-service` is a pulled image (`docker-compose.yml`), so leaving the decision there
means a separate release path for every change, and it has no access to the policy engine
except over HTTP. Moving it here puts the decision next to the policy it reads. Once
ProxySQL is repointed, `authn-service`'s `DATABASE` branch is unreachable and needs no
change or republish at all.

### 3b. What ProxySQL sends

Do not change the request shape. ProxySQL already posts this, and it runs on customer VMs:

```json
{ "credentialType": "DATABASE", "requestId": "", "userIp": "...",
  "orgId": 0, "tenantId": 0, "dbUser": "readonly_app",
  "database_host": "...", "hostname": "salesdb",
  "databaseType": "postgres", "databaseName": "salesdb",
  "token": "<uuid>", "timestamp": 1234567890 }
```

`internal/dbconsole/model/model.go` already declares `AuthRequest`/`AuthResponse` matching
it — **but they are referenced nowhere**; `dbconsole` only serves the web terminal. Use them
as a starting shape, not as a live handler.

### 3c. The flow

1. **Token → user.** `GET <token>` from Redis → `MFAState.UserId` → email from `did.users`.
   The producer (`GetAllDatabaseConnections`, `internal/database/service/database_service.go:207`)
   is unchanged. Mind the **pgAdmin key mismatch** in §6.
2. **Policy.** `SearchDatabasePolicy` for the `database` block, `permissions.iam_users`, and
   the action.
3. **Act on the action** — and this is new, because today it is ignored:
   - `allow` → return valid immediately, no push. **This is what makes service accounts
     work**; a daemon cannot approve anything.
   - `deny` → refuse.
   - `mfa_required` → push.
4. **Push, in process:**
   ```go
   adSvc.InitiateChallengeOfKind(mfapush.KindDatabase, addto.InitiateMFAChallengeRequest{
       OrgId: …, TenantId: …, Email: email,
       GatewayId:   databaseHost,   // -> DatabaseResource host
       Destination: databaseName,   // -> resource name
       Protocol:    databaseType,   // "postgres" | "mysql"
       BindingMessage: fmt.Sprintf("Approve database login — %s on %s from %s",
           dbUser, databaseName, sourceIP),
       TtlSec: 60,
   })
   ```
   **The push goes to the human, not the database role.** `readonly_app` has no phone;
   the IAM user does.
5. **Poll** `GetMFAChallenge` every 2s to a 60s deadline, mirroring the DC sensor.
6. **Respond flat — no credential, no password:**
   ```json
   { "isValid": true, "databaseName": "...", "privilege": [], "tables": [],
     "fieldMasking": {}, "host": "...", "schema": "..." }
   ```
7. **Cache** the verdict keyed on the token itself, so reconnects inside the window do not
   re-prompt. pgAdmin and DBeaver open several connections per session.

### 3d. Two decisions to make, not code

**Unenrolled users.** With Okta this cannot arise — `InitiateMFAChallenge` targets by email.
With the AuthNull Authenticator (FCM, device-based) it will. `ErrNotEnrolled` already
surfaces as a 404 from the push layer. **Deny is the right default for a database**, but
mirror the AD sensor's switch rather than inventing a second convention.

**Provider scope.** `GetProviderForOrg` is exclusive per org, so database MFA inherits
whatever AD uses. Accept it or make it per-feature — but decide, do not discover.

---

## 4. Delete the credential machinery

Only after §3 works.

**`internal/policy` — `ApproveDatabasePolicy`:** drop the `tenant.default_issuer` read, the
`IssuerID`/`WalletUserID` job fields, and the commented-out
`user_credential_mapping` / `policy_credential_mapping` lookups. Delete rather than leave
dangling.

> **CORRECTION — this section previously said the issuer read was "inert today, so removing it
> is tidying, not behaviour change". That was wrong, and in the direction that matters. It is a
> BLOCKER, and it belongs in §2 with the other enforcement fixes rather than here.**
>
> The read is at `policyjson_repository.go:2370` and it is followed at **:2375 by
> `return nil`** — fifty-seven lines *before* the provisioning job is created at **:2432**. So
> when `default_issuer` is not set, `ApproveDatabasePolicy` returns before queueing anything,
> and `did.database_job_queue` is the only thing that tells the agent to act. The consequence
> is not a missing credential; it is that **no database role is ever created or altered and no
> `pgsql_users` row is ever written.** Approving a database policy silently does nothing.
>
> This is a step EARLIER than "Postgres provisioning never completes" in
> DATABASE-MFA-FLOW.md, which blamed the agent's `getPolicyDetails` 404 (since fixed). Two
> blockers in series, and only the second was known. On the deployment we have, `default_issuer`
> is the same value that already fails for AD with "failed to fetch default issuer ID" — so the
> early return fires today, and it fires on every fresh on-premise install by definition, since
> nothing sets `default_issuer` there and nothing ever will.
>
> The fix is small but it is not a deletion: remove the early return, and pass `0` for
> `IssuerID`. `issuer_id` is `DEFAULT 0 NOT NULL` so zero is accepted; `wallet_user_id` is
> `NOT NULL` with no default, and `user.UserId` is already to hand at the insert. Verify by
> approving a database policy on a tenant with no issuer and confirming a `QUEUED` row appears.
>
> Found 24 August 2026 while auditing what was actually finished. Nothing had exercised this
> path, which is why an early return sitting between an approval and its only side effect went
> unnoticed in both documents.

**Keep and make load-bearing:** the policy JSON's `database` block and
`permissions.iam_users`. They stop being inputs to credential minting and become the direct
source of the auth decision.

**`database-agent`:** delete `createDatabaseCredential` and `updatePolicyCredentialMapping`
(both already 404, which is why jobs never complete), `EncryptAES`, and the hardcoded key.

**Leave the columns.** `wallet_user_id`, `issuer_id`, `credential_id` on
`did.database_job_queue` are `NOT NULL` and the agent still sends them. Stop giving them
meaning; drop them in a later migration.

**`grep -rn "84sF#v7Fpt"` must return nothing** across authnull-service, database-agent and
proxysql-v3-alpha when this is done.

---

## 5. ProxySQL and cutover

### The dual-shape cutover does NOT work, and this is why

An earlier version of this plan said: serve both the flat response and the legacy
`credential.credentialSubject` wrapper, repoint proxies one at a time, then drop the wrapper.
**That is not possible**, and it is worth understanding why before designing around it.

The legacy shape carries an encrypted `password`. authnull-service has never had that
password and cannot obtain it: the **agent** generates it locally, writes it into ProxySQL's
own `pgsql_users`, and encrypts a copy into the credential. Stop issuing credentials and
there is nothing to put in the wrapper. Backwards compatibility would mean keeping the whole
credential pipeline alive purely to populate a field — which is the thing being removed.

So the order is **proxy first, backend second**:

1. Build the new ProxySQL, reading the flat response. It can be deployed while still pointed
   at the old backend — the old backend keeps sending the wrapper, and a build that reads the
   flat shape must tolerate its absence, so make "no credential object" a normal case rather
   than an error.
2. Repoint `[authnull] api_url` at `/api/v1/database/mfa/authorize` per VM, restart ProxySQL
   only. **Rollback is pointing it back**, which still works because the old backend is
   untouched.
3. When no proxy points at the old endpoint, delete the credential pipeline (§4).

### The ProxySQL change is bigger than "read different fields"

Today ProxySQL **discards the client's password** and substitutes the one from the credential,
then compares that against `pgsql_users`. With no password in the response there is nothing to
substitute, so the comparison cannot be the gate any more.

The new behaviour on `isValid: true` is to **skip client-password verification entirely**. The
API verdict *is* the authentication: the token proved which person, the policy said they may,
and the push proved they were present. ProxySQL still uses its own `pgsql_users` entry to open
the backend connection to the real database, which is unaffected — that is its own stored
credential, not the user's.

On `isValid: false`, refuse explicitly (§2a, §2b). Do not fall through to stock authentication:
the user typed a token, not a password, so stock auth would fail anyway and the failure would
report the wrong cause.

Also in the same build: delete `DecryptFromGoOpenSSL2` and `KEY_STRING2`, re-enable TLS
verification, stop calling `api.ipify.org` on every login, and raise `CURLOPT_TIMEOUT` to 120s
in `MySQL_Session.cpp` so a 60-second push fits.

## 6. Gotchas

- **The pgAdmin Redis key mismatch.** `GetAllDatabaseConnections` stores under
  `<uuid>&&pgAdmin` when `Mode == "pgAdmin"`, but the connection string embeds the bare
  `<uuid>`. The token ProxySQL sends cannot find the suffixed entry. Fix the key or the
  lookup, and pick one deliberately.
- **The client's password is never verified** (Postgres): it is `free()`d and replaced by
  the API's credential password. So the token alone authenticates, and it also appears *as*
  the password in the connection string — shell history, saved connections. Preserve or
  change that consciously; do not let it change by accident.
- **180s token TTL vs a 10-minute approved window.** Long-lived pools and saved connections
  hit this. Surface a countdown or lengthen it.
- **`listConnections` is unauthenticated and mints the token**, reading `userId` from a raw
  header (`internal/database/routes.go`, `database_controller.go:250`). Out of scope here,
  but it is the credential-minting endpoint and should not stay that way.
- **Do not licence-gate the decision path.** `pkg/license` gates the control plane only, and
  `listConnections` / `dbSync` / `getJobQueue` are explicitly asserted ungated in
  `TestDatabaseAgentPathsAreNeverGated`. A licence lapse must not stop database logins.

---

## 7. Verification

1. Policy **MFA Required** for an IAM user on a DB role; approve it; the agent provisions the
   role and **no credential call appears in its log**.
2. Old proxy + new backend → behaviour unchanged.
3. New proxy, Postgres: connect → **push arrives on the IAM user's device**, naming the
   database, role and source IP → approve → session opens, privileges and column masking
   still applied.
4. New proxy, MySQL: same, and a **denied** push is actually refused (§2a).
5. Deny → prompt refusal. Reconnect inside the window → **no second push**.
6. Policy **Allow** → connects with no push (the service-account path).
7. Stop authnull-service → refused, not allowed.
8. Expire the licence → **database logins keep working**; only the console goes read-only.
9. `grep -rn "84sF#v7Fpt"` returns nothing in any of the four repos.
10. No traffic to `authn-service`, `verifier-service` or `ssi-service` during a database
    login; no rows added to `did.issuer_credentials`.

Steps 4, 7 and 8 are the ones that matter most: 4 proves MySQL now enforces, 7 proves we
fail closed, 8 proves licensing never touches the data plane.

---

Related: [DATABASE-MFA-FLOW.md](DATABASE-MFA-FLOW.md) for how it works today,
[RADIUS-MFA-TASK.md](RADIUS-MFA-TASK.md) for the same treatment applied to RADIUS —
the push-side pattern there is the one to copy.
