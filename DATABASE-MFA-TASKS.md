# Database MFA — remaining tasks

Updated 24 August 2026, after two decisions narrowed the work: **a database policy names IAM
users and nothing else** (see [DATABASE-MFA-TASK.md](DATABASE-MFA-TASK.md) §0b), and a policy
that can never work is now **refused at creation** rather than failing silently later.

Sizes assume someone new to the codebase: **XS** under an hour, **S** half a day, **M** one to
two days, **L** longer.

## Where it stands

`internal/database/dbmfa/` is built and passes 23 tests. Identity is one field — the person's
email — resolved in one query. Policy matching, the verdict, the push and the endpoint ProxySQL
calls all exist.

**Nothing has been tested end to end.** No push has ever been raised for a database login. Two
things in this repo are in the way, and they are D1 and D2.

## Read this first

**A licence gates the control plane, never the data plane.** An expired licence makes the
console read-only; it must never stop a database login. `/database/mfa/authorize` is the
endpoint ProxySQL calls on every connection — it is never gated, never authenticated, and both
of those are deliberate.

**ProxySQL has already discarded the client's password** by the time it asks us. Our answer is
the only thing between a token and an open database session, so every path that is not an
explicit approval must refuse. That is why a refusal is HTTP 200 with `isValid:false` and never
a non-200 — ProxySQL treats a non-200 as an exception, and its handling of that is what made
the Postgres path fail-closed by accident rather than by design.

## Environment

```sh
export GOTOOLCHAIN=local
GO=~/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.25.8.linux-amd64/bin/go
$GO build ./... && $GO test -vet=off ./...
```

Many files here are **CRLF with a UTF-8 BOM**. Check `git diff --stat` before committing: a
one-line change showing as a whole-file rewrite means your editor stripped the line endings.

---

## D1 · Queue the provisioning job even with no credential issuer

**Size S · blocker · this repo · [PR #16](https://github.com/authnull0/authnull-service/pull/16) is open for this**

### Why

Approving a database policy does nothing on any deployment without `did.tenants.default_issuer`
set — every fresh on-premise install, and ours.

[`ApproveDatabasePolicy`](internal/policy/repo/policyjson_repository.go#L2356) reads the issuer
at **:2370** and returns at **:2375**. The provisioning job is created **57 lines later at
:2432**, and that insert is the only place a `did.database_job_queue` row is written anywhere.
The queue is the only signal the agent gets. So: no database role, no `pgsql_users` row, and
nothing queued so nothing retries.

The issuer only ever existed to mint a wallet credential, and the wallet is being removed.

### Do

PR #16 already does this — review and merge it rather than starting again. If you are picking it
up fresh: remove the early return, set `IssuerID` to `defaultIssuer` when `issuerOK` and `0`
otherwise (`issuer_id` is `DEFAULT 0 NOT NULL`), leave `WalletUserID` alone, and comment why so
the guard is not re-added as "defensive".

### Verify

- [ ] On a tenant with **no** issuer: approve a database policy, then
      `SELECT * FROM did.database_job_queue ORDER BY id DESC LIMIT 5` — a `QUEUED` row appears.
      Before the change there is none.
- [ ] On a tenant **with** an issuer the row still carries that id, not 0.
- [ ] The log no longer stops after `Successfully Unmarshalled Policy JSON`.

### Don't

Don't delete `defaultIssuerID` or its four other call sites — three are AD paths handled
separately. That is D6.

### Note on what this no longer needs

The follow-up I originally flagged on PR #16 — that `GetUserDetails` ignores `iam_groups` — is
**closed by the IAM-only decision**, since a policy can no longer be scoped to a group. What
remains is that `GetUserDetails` returns `(nil, nil)` for an empty user list, which
`ValidateDatabase` now prevents from ever happening through the API. Nothing further needed here.

---

## D2 · ~~Licence-gate the two console routes~~ — WITHDRAWN

**No longer applicable.** The two endpoints this was about, `AddLocalUser` and
`DeactivateLocalUser`, have been deleted — people are created by `onboardUser` and named in a
database policy by email. There is nothing left in `internal/database/dbmfa` that changes
configuration, so nothing to gate.

`/api/v1/database/mfa/authorize` is the only route the package still serves, and it must stay
ungated: ProxySQL calls it on every database login, and a lapsed licence must not stop database
logins. Adding it to `controlPlaneWrites` would cause the exact outage the licence design exists
to prevent.

That is already pinned — both spellings of the path are in `dataPlanePaths` in
`pkg/license/license_test.go`, so `TestDataPlaneIsNeverGated` fails if anyone adds them to the
gate. **Nothing to do on this card at all.**

---

## D3 · Exercise the decision endpoint by hand

**Size S · needs D1 · this repo · do this before touching any C++**

### Why

The whole decision path is unit-tested and has never run against a real database, a real policy
or a real push. Do it with `curl` first, so a failure is unambiguous.

### Do

Post what ProxySQL posts, to `/api/v1/database/mfa/authorize` (unauthenticated by design):

```json
{ "orgId": 1, "tenantId": 1, "token": "<one-time token>",
  "databaseName": "salesdb", "dbUser": "readonly_app",
  "databaseType": "postgres", "sourceIp": "203.0.113.44" }
```

Get the token from `listConnections`. The policy must name the person's **email** in
`iam_users`.

### Verify — each must be a distinct, correct outcome

- [ ] **MFA Required**, enrolled user → push arrives naming the role, database and source IP →
      approve → `isValid:true`
- [ ] Deny the push → `isValid:false`
- [ ] Ignore it for 60s → `isValid:false`
- [ ] **Allow** → `isValid:true`, no push (the service-account path)
- [ ] **Deny** → `isValid:false`
- [ ] **No policy** → `isValid:false`, not a silent allow
- [ ] Expired or garbage token → `isValid:false`
- [ ] User with no enrolled device → `isValid:false` by default
- [ ] A policy still carrying only AD groups → `isValid:false`, and the log names the shape
      problem rather than "does not cover this user"
- [ ] **Every** response is HTTP 200, including every refusal

---

## D4 · ProxySQL: actually enforce, and read the new response

**Size L · repo `proxysql-v3-alpha`, branch `authsql-postgres` · C++ · senior review before merge**

> **Line numbers and behaviour below were verified against the branch on 24 August 2026**, at
> `37aec8fc`. Two claims in the earlier version of this section were wrong and are corrected in
> place — see "Corrections" at the end.

### Why

**MySQL** (`lib/MySQL_Session.cpp:7062`) does `break` on MFA failure. That `break` leaves the
`switch (session_type)`, skipping the `free_users` assignment at `:7086`. `free_users` was
initialised to 0 at `:7036`, so the check at `:7109` (`free_users<=0`) refuses the connection.
So it is **not** a bypass — it is accidentally fail-closed through a resource counter, and the
user is told **"User 'x' has exceeded the 'max_user_connections' resource (current value: 0)"**
(error 1226). Not "Too many connections" — that is the neighbouring branch at `:7119`, which
needs `max_connections_reached==true`.

**Postgres** has a real `isValid:false` check: `PgSQL_Protocol.cpp:1132-1138` throws on it. What
is accidental is everything else — an absent `isValid`, an HTTP error, a malformed body — none of
which denies explicitly. They fall through to `:1239`, where the client's typed password is
compared against `pass2` extracted from the credential. With no credential, `pass2` is empty, the
comparison fails, and the connection is refused. Fail-closed by a string comparison that exists
for another purpose.

**This is why the response-shape change is dangerous.** The flat response has no `credential`, so
`pass2` is never set and `:1239` can never succeed — the new build must bypass that comparison or
nothing authenticates at all. **Once it is bypassed, `databaseName` in the response is the only
remaining constraint on what the grant covers.** Treat it accordingly: see "The fallback question"
below.

### Do

**Response shape** — `lib/PgSQL_Protocol.cpp`

- `:1149-1152` read the four fields from the **top level**, not `jsonResponse["credential"]["credentialSubject"]`
- `:730` delete `KEY_STRING2` (the hardcoded AES key), `:802` delete `DecryptFromGoOpenSSL2`,
  `:1201` delete its call site
- Skip the client-password comparison at `:1239` when `isValid` is true — but see below

**The fallback question — DENY, do not grant.**

An `isValid:true` response with no top-level `databaseName` must be **refused**, not granted
against the database the client asked for.

`databaseName` is a scope, not a label: it is what pins the grant to the database the *policy*
named. And once the password comparison at `:1239` is bypassed, it is the **last** check standing
— so falling back to the client's request does not make one path "looser than fail-closed", it
removes the check entirely. Concretely: policy grants `readonly_app` on `salesdb`, client asks
for `hrdb`, response omits `databaseName`, proxy grants `hrdb`.

The compatibility argument does not hold either. The backend **always** populates `databaseName`
on `isValid:true` — `dbmfa.MatchPolicy` refuses to match unless the policy names both a database
and a role, so a granted verdict always carries both. That branch can therefore only fire against
a backend that is not the new one, which is a misconfiguration, which is exactly when to refuse.
For rollout: repointing `api_url` and installing the new binary are both per-VM operations, so do
them as one step. Rollback is old binary plus old `api_url`.

**Enforcement**

- `MySQL_Session.cpp:7062-7064` — deny explicitly instead of `break`, with an error that names
  MFA. The current behaviour refuses but blames connection limits, which sends whoever is
  debugging to the wrong place entirely
- Apply the same response-shape and gate changes to the MySQL path

**Two memory bugs on the deny path — IN THIS PR, not a follow-up**

Both were found by whoever is doing this work, and both belong here rather than in a separate
change, because this task is what makes the deny path load-bearing. Today deny barely runs; after
this it runs on every refusal. A latent fault there becomes reachable by anyone who can fail MFA.

- **Double free of `pkt`.** `l_free(pkt->size, pkt->ptr)` runs unconditionally before the switch —
  `PgSQL_Session.cpp:5760` and `MySQL_Session.cpp:7023` — and then **again** on the
  "does not have access to this database" deny path at `PgSQL_Session.cpp:5798` and
  `MySQL_Session.cpp:7073`. **Both files**, and the MySQL one is easy to miss because the work so
  far has been Postgres. Reachable by any legitimate user who passes MFA and then requests a
  database not on their list.
- **`exit(1)` inside a `catch`.** `PgSQL_Session.cpp:5807` and `MySQL_Session.cpp:7082`. An
  exception anywhere in that block kills the **entire proxy process**, not the session — every
  other database connection on that VM dies with it. The MySQL one wraps the `performMFA` call, so
  anything that makes the auth call throw is a remote denial of service against every user of that
  proxy.

**Housekeeping**

- `PgSQL_Protocol.cpp:1108-1109` re-enable TLS verification. Note the most recent commit on the
  branch is *"fix: disable SSL peer verification for auth API curl call in PgSQL"* — it was turned
  off deliberately, so re-enabling it needs a CA path in the `[authnull]` stanza, or it will
  simply break again
- `MySQL_Session.cpp:723` — `CURLOPT_TIMEOUT` is 30s and a push can take 60. The Postgres side is
  **already 120s** (`PgSQL_Protocol.cpp:1104`); only MySQL needs changing
- Stop calling `api.ipify.org` on every login — `PgSQL_Protocol.cpp:761` **and**
  `MySQL_Session.cpp:818`. Both, not just the Postgres one
- `PgSQL_Session.cpp:5789` is `if (true) {`

### Verify

Nothing here is provable by reading. Real database, real proxy, real phone, **both engines**:
approve → session opens; deny → refused; time out → refused; backend unreachable → refused. Plus
the two memory bugs: pass MFA and request a database you are not granted, on both engines, and
confirm the proxy refuses and **stays up**.

Note the ordering: "approve → session opens" cannot be tested until **D1** is merged, because
without it no database role is provisioned and there is nothing to open.

### Corrections to the earlier version of this section

- It said **"MySQL database MFA is not enforced at all"**. Wrong — it refuses, via the
  `free_users` accounting, with a misleading error. Same fix, same priority, different reason.
- It said **"the Postgres path is fail-closed only by accident"** without qualification. Half
  wrong: `isValid:false` is checked explicitly at `:1132-1138`. It is the absent-field and error
  cases that fall through to the password comparison.
- It omitted the MySQL `api.ipify.org` call and the MySQL half of both memory bugs.
- It said to raise `CURLOPT_TIMEOUT` without noting Postgres was already done.

---

## D5 · `database-agent`: drop the credential calls

**Size M · other repo · Go, mechanical · after D1**

In `src/pkg/checkout.go`:

- [ ] Delete `createDatabaseCredential` (~:546, body :572–607) and its call site
- [ ] Delete `updatePolicyCredentialMapping` (~:553, body :612–648) and its call site — both
      already 404, which is part of why jobs never complete
- [ ] Delete `EncryptAES` and the hardcoded AES key (:316–339, used :523)
- [ ] **Replace the `math/rand` password generation at :562–571 with `crypto/rand`** —
      predictably seeded, and currently generating database passwords

### Verify

- [ ] A provisioning job runs to completion: role created or altered, `pgsql_users` row written
- [ ] No 404s in the agent log
- [ ] `grep -rn "84sF#v7Fpt"` finds nothing
- [ ] Two passwords generated in the same second differ, and are not reproducible from a seed

---

## D6 · Delete the credential machinery

**Size S · this repo · only after D3 and D4 pass**

Once nothing depends on it: in `ApproveDatabasePolicy`, drop the `default_issuer` read, the
`IssuerID`/`WalletUserID` job fields, and the commented-out `user_credential_mapping` /
`policy_credential_mapping` lookups.

**Leave the columns.** `wallet_user_id`, `issuer_id` and `credential_id` on
`did.database_job_queue` are `NOT NULL` and the agent still sends them. Stop giving them
meaning; drop them in a later migration.

Low-priority tidy in the same area: `CreateDatabaseCredential` still exists at
`internal/issuer/handler/credential_controller.go:734`, but its route is **already unmounted**
(`issuer.RegisterRoutes` is commented out in `cmd/authnull-service/routes.go`), so it is
unreachable — dead code, not a live path.

---

## D7 · Console screens

**Size M · UI team · can start now; the API is finished and will not move**

### Adding people — nothing new to build

There is no database-MFA-specific "add a user" screen. People are created by the **existing user
onboarding flow** (`POST /pam/api/v1/users/onboardUser`), which now emails an invitation and lets
them set their own password.

That is all a database policy needs: it matches on `did.users.email_address`, and a push is
addressed to that email. Neither requires console access, a role, or anything database-specific.

This card previously specified a separate `POST /api/v1/database/mfa/users` endpoint for "a person
who is in no directory". It has been deleted. Worth knowing why, because the reasoning applies to
the next feature that wants its own user table: it distinguished its cohort by "has no password",
which stopped being a discriminator the moment onboarding started leaving the password empty until
the invitation was accepted. Two paths creating `did.users` rows, told apart by a field neither
owned, meant the list showed pending administrators and the deactivate endpoint could delete one.
One way in is worth more than the property it was protecting.

### The database policy form

Pick a database and a database role, then **the people, by email address**, then the action:
**Allow**, **MFA Required** or **Deny**.

Three things the form must get right. All three are now enforced by the API, so getting them
wrong shows up as a 400 rather than as a policy that quietly does nothing — but the form should
prevent the 400 rather than relay it.

1. **People are individual email addresses.** There is no AD user, AD group, OU or IAM group
   picker on a database policy. Anything that offers one produces a policy the API refuses. See
   [DATABASE-MFA-TASK.md](DATABASE-MFA-TASK.md) §0b for why.
2. **Database and role are mandatory**, and at least one email is mandatory. An empty resource
   matches nothing on purpose — a blank field must never mean "every database".
3. **Surface Allow prominently, with an explanation.** A connection pool or a scheduled job
   cannot approve a push. Those need an Allow policy, and someone who sets MFA Required on an
   application account will break it at 3am.

If a customer has an existing policy scoped to AD groups, the API's error names the fields being
ignored and tells them to populate `iam_users`. Show it verbatim — it is written for an
administrator.

---

## D8 · Bulk add of IAM users

**Size M · this repo + UI · not blocking, but it becomes urgent with the first large customer**

The cost of the IAM-only decision: a customer with five hundred DBAs adds five hundred IAM users
rather than pointing at one AD group.

`onboardUser` takes one person at a time, and now emails each of them an invitation — so five
hundred DBAs is five hundred invitations as well as five hundred calls. Two ways to close this,
and they are not exclusive:

- **CSV or paste-a-list import** driving `onboardUser`. Small, and enough for most cases. Decide
  deliberately whether it sends five hundred invitations or defers them, because the invitation is
  the only way an onboarded user ever gets a password.
- **Populate `did.users` from a directory sync**, so the people arrive automatically. Note this
  does not reintroduce AD scoping — the directory would create the *users*, and the *policy*
  still names them by email. The two are separable, which is what makes the IAM-only decision
  affordable. It also sidesteps the invitation problem entirely for anyone who will never sign in
  to the console.

Worth deciding which before a customer with a large DBA population, not after.

---

## Order

1. ~~**D2**~~ — withdrawn entirely; the endpoints it gated are gone, and `/authorize` is already
   pinned as data-plane. Nothing to do.
2. **D1** — review and merge PR #16.
3. **D3** — the first genuine proof that any of this works.
4. **D5**, then **D4**. D4 wants a senior reviewer.
5. **D6** once D3 and D4 pass.
6. **D7** any time, in parallel. **D8** before the first large customer.
