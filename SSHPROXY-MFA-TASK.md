# SSH proxy MFA — implementation task

Wire the SSH proxy landed by PR #12 (`feature/sshproxy-integration`) to the Authnull push
MFA that already runs in production, so an operator connecting to a privileged account gets
a push on their phone and a recorded session on approval.

**Roughly 2–3 days for Parts 1–6.** Part 7 is review feedback on the same branch and can be
folded in as you go. Each part says which files to touch, what to copy from, and when it is
finished.

The proxy is already complete and already merged-ready in every respect except this one: it
is wired with a `nil` authenticator, which means `DenyAll`, which means **every connection
is currently refused — including one presenting a correctly registered key.** That is
deliberate, not an oversight, and Part 6 is the moment it stops being true.

Read [§0](#0-the-architecture) before writing anything. The risk on this task is a design
misunderstanding about where identity comes from, not a coding mistake.

---

## 0. The architecture

```
ssh oracle@10.0.0.5@proxy:2222
        │  SSH (TCP 2222)
        ▼
   sshproxy listener                    ← in-process, internal/pam/sshproxy
        │
        │  1. publickey  → resolve the offered key's fingerprint
        │                  against did.user_ssh_keys              ← FIRST FACTOR
        │  2. PartialSuccessError → keyboard-interactive
        │  3. authz.Authenticator: grant → lockout → rate limit
        │                  → raise push → poll                    ← SECOND FACTOR
        ▼
   ADService.InitiateChallengeOfKind(KindSSH, …)   ← the push stack you already have
        │  provider lookup, device token, activity row, risk, push
        ▼
   phone approves  →  bridge to the target host, session recorded to .cast
```

### Identity comes from the offered SSH key, and nothing else

This is the part to internalise. The SSH protocol gives the proxy no identity channel: the
username carries the **target** (`account@host`) and whatever a client asserts about itself
there is attacker-chosen. So the anchor is possession of a private key whose public half is
registered in `did.user_ssh_keys` — the SSH counterpart to resolving an AD principal
through `did.ad_users`.

Two consequences that matter to your code:

- **Never derive the principal from the grant row.** On a shared account like `oracle`,
  `did.jump_servers_connections.user_id` is whoever last checked it out. Challenging that
  person's device for a session someone else opened is the exact failure the design exists
  to prevent. `authz.Authenticator` already refuses a request with no `Key` for this reason
  (`ReasonNoKeyIdentity`); do not add a fallback.
- **A key alone can never authenticate.** `VerifiedPublicKeyCallback` returns
  `PartialSuccessError` and never returns permissions, so the only route to a session is
  through the keyboard-interactive callback carried in that error. `KeyboardInteractiveCallback`
  is deliberately absent from the top-level `ssh.ServerConfig` — registering it there would
  let a client select it directly and skip identity entirely.

### Everything fails closed. Keep it that way.

A nil `Authenticator` becomes `DenyAll`, a nil `KeyResolver` becomes `DenyAllKeys`, and
`Authenticator.validate()` refuses to decide when any dependency is missing. Every failure
you can cause in this task therefore denies rather than admits, with one exception — see
[§3c](#3c-ratelimiter), which is the only place in this task where a plausible-looking
implementation can fail open.

**Do not write an approving stub authenticator to "make it work" locally.** A valid key
alone opening a privileged session is the thing this whole design prevents. If you need a
local harness, put it behind a build tag, never on this path.

### The adapter decision, already made

Three routes were considered for reaching the push stack. Use the third.

| | Route | Verdict |
|---|---|---|
| A | Refactor the AD MFA into a shared package first | **Later.** Correct destination, wrong moment — it edits the 41 KB `mfa_push_repository.go` that the RADIUS work is actively changing. See [§9](#9-not-in-this-task). |
| B | Self-contained adapter writing `did.ad_mfa_challenges` directly | **No.** See below. |
| C | Thin adapter over `ADService.InitiateChallengeOfKind` | **Yes.** ~60 lines, no AD behaviour change, every edit outside the proxy additive. |

Route B looks like "a bit of duplicated logic" and is not. Going straight to the table
bypasses per-org provider selection, device push-token **and transport** resolution,
`TouchDevice`, activity-history mirroring, fetch-token minting, risk scoring,
`RecordPushError`, and the `no_device_registered` mark-expired path. That is ~200 lines of
the most correctness-sensitive code in the service, re-implemented — and the symptom is a
challenge row that is created and never pushes, which is invisible in a build and in unit
tests.

Route C already has a seam built for it. `InitiateChallengeOfKind` is exposed on `ADService`
with the comment *"Exposed on the service so other modules do not reach into the
repository"* — it was added for the database flow, which is the same shape as this one.

---

## 1. `mfapush.KindSSH`

**Files:** `internal/mfapush/provider.go`, `internal/mfapush/context.go`,
`internal/ad/src/repository/mfa_push_repository.go`

Follow the `KindDatabase` work exactly — it is the same three-part change, and
[RADIUS-MFA-TASK.md](RADIUS-MFA-TASK.md) §4 describes the same three parts for its own kind.

1. `KindSSH ChallengeKind = "ssh"` beside `KindAD` and `KindDatabase`.
2. `SSHResource(account, host, protocol string) ChallengeContext` in `context.go`, modelled
   on `DatabaseResource`. Resource name falls back host → `"Server"`. Add
   `ResourceTypeServer = "Server"`.
3. A `case mfapush.KindSSH:` in `challengeContextFor`.

**Keep `Flow = FlowAD`.** Read the comment on `ChallengeKind` in `provider.go` before you
are tempted otherwise: `Flow` is a wire contract with the mobile app and the DC sensor, it
is baked into the payload as `data.flow`, the app sends it back on `getChallenge`, and it is
part of the activity lookup key used by respond and status. A `Flow = "ssh"` value would
store the activity row under a flow the app never asks for, and leave every SSH challenge
pending until the daily sweeper reaped it. Neither failure shows up in a build or a unit test.

### Why the `case` matters more than it looks

`correlateFromAuthLog` back-fills any blank context field from that user's most recent **AD**
event, matched on org and email alone. Without a `KindSSH` case, an SSH session by someone
who also logs into Windows inherits that logon's Kerberos SPN, domain, AD username, session
id and source IP — the push would describe an authentication that is not happening, and so
would the activity history.

`challengeContextFor` already zeroes the correlation for any kind that is not `KindAD`, so
adding the case is all that is required.

**Done when:** the push reads *"Approve SSH — oracle on db01 · 10.2.14.7"* and a test proves
no AD context leaks in. Write the SSH twin of `TestDatabaseChallengeDoesNotInheritADContext`
in `internal/ad/src/repository/challenge_kind_test.go`.

---

## 2. The `Challenger` adapter

**Files:** new file satisfying `authz.Challenger` — suggested
`internal/pam/sshproxy/authz/mfa.go`

Two methods over the existing service. The interface is already defined for you in
`internal/pam/sshproxy/authz/authenticator.go`:

```go
Initiate(ctx, ChallengeRequest) (challengeID int, err error)
Poll(ctx, challengeID int) (status string, err error)
```

`Initiate` calls `ADService.InitiateChallengeOfKind(mfapush.KindSSH, …)` and returns
`AdChallengeId`. `Poll` calls `GetMFAChallenge{OrgId, AdChallengeId}` and returns
`ChallengeStatus`. No status translation is needed — `authz` redeclares
`pending / approved / denied / expired` with the same string values as `mfapush`.

### 2a. Field mapping

`dto.InitiateMFAChallengeRequest` is generic enough that no DTO change is needed. Map onto
it the way `KindDatabase` does:

| DTO field | Comes from |
|---|---|
| `OrgId`, `TenantId` | proxy config — `SSHPROXY_ORG_ID`, `SSHPROXY_TENANT_ID` |
| `Email` | `req.Email` — the key-resolved principal, never the grant holder |
| `GatewayId` | target host |
| `Destination` | target account |
| `Protocol` | `"ssh"` |
| `BindingMessage` | `req.BindingMessage`, which the proxy already builds |
| `TtlSec` | `req.TTL` — `Authenticator.challengeTTL()`, 60s by default |
| `SessionId` | `req.SessionID` — the proxy's session id |
| `SourceIp` | `req.SourceIP` |

### 2b. Your DTOs return failures as codes, not errors — this is the part to get right

`InitiateChallengeOfKind` returns `(*InitiateMFAChallengeResponse, error)` where the
interesting cases arrive as `Code` with `err == nil`. Map them:

| Response | Return | Proxy reports |
|---|---|---|
| `Code 200` | `(resp.AdChallengeId, nil)` | proceeds to poll |
| `Code 404`, `"no_device_registered"` | `(0, nil)` | `denied_no_device` |
| any other non-200, or `err != nil` | `(0, err)` | `denied_mfa_rejected`, MFA unavailable |

The proxy already treats `challengeID == 0` as `ReasonNoDevice`, so the middle row needs no
special handling beyond returning zero. **Collapse the third row into `(0, nil)` and a
database blip gets reported to the operator as "this user has no second factor"** — a
different incident with a different response.

**Done when:** a unit test with a fake service covers all three rows.

---

## 3. The four remaining dependencies

**Files:** `internal/pam/sshproxy/authz`

`Authenticator` needs five things and you built one of them in Part 2. All four below are
required — `validate()` refuses to decide if any is nil, because each one absent silently
removes a control.

### 3a. `DeviceChecker`

Wrap `mfapush.RequiresEnrolledDevice(providerName)` for `RequiresEnrolledDevice`, and
`DeviceStore.EnrollmentStatusForEmail` for `EnrollmentStatus`. Map onto
`EnrollActive / EnrollPending / EnrollNone`.

The provider gate is not defensive coding. On a Duo or Okta org the second factor lives in
the vendor and `did.mfa_devices` is empty by design, so an unconditional enrollment
pre-check would report "none" for every user and deny every session on an org where MFA
works fine.

### 3b. `LockoutStore`

Over `did.blocked_principals`, shared with AD.

**Write `domain = "ssh"` and leave the principal as the plain lowercased email.** The table
already has the namespace you need — migration `007_schema_reconciliation.sql` gives it
`UNIQUE (tenant_id, principal, domain)` and an index on `(org_id, domain, principal)`, and
`AuthDecisionRepo.IsUserBlocked` filters on `tenant_id AND principal AND domain`. So an SSH
lockout at `domain='ssh'` is invisible to the AD and policy paths, while a real AD lockout
for the same person at `domain='corp.example.com'` stays a separate row.

Do **not** prefix the principal itself (`ssh:<email>`). It would work, but it breaks the
column's stated convention — principal is "always stored lowercase sAMAccountName" — and it
makes the value unreadable in the console.

The payoff is that the existing admin endpoints work on SSH lockouts unchanged:
`/admin/v1/ad/blockPrincipal`, `unblockPrincipal` and `getBlockedPrincipals` all take a
domain, so no new unblock path is needed. Store the principal lowercased, the way
`IsUserBlocked` compares it.

`tenant_id` is `NOT NULL` and inside the UNIQUE key, so it must carry the real tenant — see
[§4](#4-config-and-the-jump-server-row). A zero puts lockout rows in a namespace the admin
unblock path cannot reach.

### 3c. `RateLimiter`

A fixed-window counter in Redis. `Allow` reports whether the caller may proceed **and
consumes a slot**, so it is called exactly once per attempt. Follow
`claimDiscoveryAttempt` in `internal/deviceapi/discover.go`.

**This is the one place in this task where a plausible implementation fails open.** Two
rules, both non-negotiable:

- **Return the error.** If Redis is unavailable, `Allow` must return `(false, err)` — never
  `(true, nil)`. The caller in `authz` already denies on a non-nil error; the whole risk
  sits in this function returning the wrong value.
- **Not in-memory.** A per-replica counter is not a rate limit. This is the control that
  bounds how many pushes an attacker can send to somebody's phone.

**Done when:** a test asserts that with the store unreachable, `Allow` returns an error and
not `true`.

### 3d. `AuditSink`

Write to `did.auth_log` — **singular**. The plural `did.auth_logs` is the policy-decision
log written by `EvaluateAuth`, which this path does not call.

`AuditRecord` already carries `KeyFingerprint` alongside `Principal`. Persist both: on a
shared account the person and the credential are different facts, and revoking the right
key after an incident depends on having recorded which one authenticated.

**Done when:** `Authenticator.validate()` passes, and removing any single dependency still
produces a denial. `TestDeny_NoAuthenticator_MissingDependency` already covers this shape —
extend it rather than writing a new one.

---

## 4. Config and the jump server row

**Files:** `.env` / the secret store, plus a `did.jump_servers` row

`SSHPROXY_TENANT_ID` and `SSHPROXY_JUMP_SERVER_ID` are read by
`internal/pam/sshproxy/env.go` but are set in **neither** env file today. Wire the
challenger without them and the proxy still denies everything, for a different reason than
before.

Neither value can be discovered by the proxy at runtime, but both are findable by you. Here
is how to get each one.

### 4a. `SSHPROXY_TENANT_ID`

`did.tenants` has no unique constraint on `organization_id` and the product counts tenants
per org, so the mapping is one-to-many by design and you cannot just pick the first row.

Do not guess from `did.tenants`. Copy the tenant that push MFA **already uses** for this
org, so SSH challenges land in the same namespace as the working AD and console ones. In the
org database:

```sql
SELECT DISTINCT tenant_id, count(*)
  FROM did.ad_mfa_challenges
 WHERE org_id = <org>
 GROUP BY tenant_id
 ORDER BY count DESC;
```

One value means you are done. Several means the org genuinely spans tenants, and the correct
one is the tenant the SSH users belong to — confirm with your lead rather than taking the
most common. Cross-check against `SELECT id, tenant_name, status FROM did.tenants WHERE
organization_id = <org>;`.

### 4b. `SSHPROXY_JUMP_SERVER_ID`

The table is `did.jump_server` — **singular**; `did.jump_servers_connections` is the grants
table and a different thing. The proxy host must be registered as a row in it, and there is
a normal API for that, so this is a console operation, not a manual insert:

- `POST /admin/v1/pam/jumpserver/listJumpServer` — find an existing row
- `POST /admin/v1/pam/jumpserver/addJumpServer` — register the proxy host if absent

Then read the id back:

```sql
SELECT id, server_name, public_ip_address, status FROM did.jump_server ORDER BY id;
```

What is *not* discoverable is any of this from inside the proxy: `server_id` and
`private_ip` are never written by any query, `is_default` is never written, and neither
`server_name` nor `public_ip_address` is unique — which is why the id is configuration
rather than something the listener resolves for itself. `validate()` treats
`JumpServerID <= 0` as fatal on purpose: honouring a grant issued for a *different* jump box
escalates access across jump servers.

### 4c. Nothing else needs deciding

The lockout namespace is settled — `domain = "ssh"`, see [§3b](#3b-lockoutstore).

Leave these two alone for now:

- `SSHPROXY_FAIL_POLICY=closed`. A session whose recording cannot be started must be
  refused, not proxied unrecorded.
- `Authenticator.RequireGrant = false`. The checkout flow that populates
  `did.jump_servers_connections.user_id` does not run in production, so `true` denies
  everybody. Flipping it is a config change for later, not part of this task.

---

## 5. `last_used_at` is never written

**Files:** `internal/pam/sqlc/queries/user_ssh_keys.sql`,
`internal/pam/sshproxy/server.go`

The column exists in migration 011, is selected by both queries, and is returned by the
listing API — but **no `UPDATE` statement for it exists anywhere in the branch**, so
stale-key detection silently does not work. The migration comment says the proxy writes it;
nothing does.

Add the query and call it from `verifiedPublicKeyCallback`.

**Not from `publicKeyCallback`.** That one fires speculatively — a client offers every key
its agent holds and asks "would you accept this?" before signing anything, so it runs
several times per connection and only one of those offers is real. It must stay read-only.
`verifiedPublicKeyCallback` runs exactly once, on the key the client actually signed with,
which is why side effects belong there.

**Done when:** connecting stamps the row, and the timestamp survives in `listKeys`.

---

## 6. Wire it up and prove it end to end

### 6a. Replace the `nil`

**Files:** `cmd/authnull-service/main.go`

Assemble the `authz.Authenticator` and pass it to `sshproxy.Start` in place of the current
`nil`. Copy the shape of the existing `sshProxyKeyResolver()` immediately below it: every
failure path returns nil, and nil means `DenyAll` rather than a permissive fallback. Delete
the `TODO step (d)` block and the paragraph explaining why the authenticator is absent.

**Done when:** boot logs the authenticator as wired, and the
`WARNING no authenticator wired; every connection will be denied` line is gone.

### 6b. Seed a key first — nothing works before this

Identity is the offered public key, and there is no console UI for registration. Register
one with an admin session:

```
POST /api/v1/pam/userSshKeys/addKey
{ "userId": <did.users.user_id>, "publicKey": "ssh-ed25519 AAAA…", "label": "laptop" }
```

The user must exist in the caller's org and must have an email address — the proxy refuses a
key that resolves to a user with no email, because there would be nobody to push to.

### 6c. The connection

```
ssh oracle@10.0.0.5@proxy:2222
```

Expected sequence: the instruction text appears (target, source, session id), one push
arrives, approval opens the session, and the session is recorded.

**Done when:** a `.cast` file exists carrying `auth_method: publickey+mfa-push`, an audit
row in `did.auth_log` names both the principal and the key fingerprint, `last_used_at` is
stamped, and denying on the phone refuses the connection with `denied_mfa_rejected` in the
log.

---

## 7. Review findings on the same branch

Not MFA work, but on the branch you are already in. The first two are small; the third and
fourth are decisions for your lead, so raise them rather than resolving them yourself.

### 7a. `listKeys` has no authorization on `userId`

**Files:** `internal/pam/handler/usersshkeys/usersshkeys.go`

It defaults to the caller when `userId <= 0` but never checks it otherwise, so any valid
session in the org can list any user's key fingerprints and labels. `addKey` and `revokeKey`
both require an administrator role. Either require admin for a non-self `userId`, or drop
the parameter.

### 7b. The sqlc `FindSSHGrant` has drifted

**Files:** `internal/pam/sqlc/queries/jump_servers_connections.sql`

The `FindSSHGrant` added to the `.sql` is missing the `jc.user_id = $5` holder predicate
that the executed query in `internal/pam/sshproxy/authz/grant.go` has. It was never
generated to Go, so there is no runtime effect today — but that file is what someone
regenerates from, and the missing predicate is exactly the "returns another person's grant
for a shared account" bug the holder predicate exists to prevent. Sync it.

### 7c. Backend host key is not verified — raise, do not fix

`internal/pam/sshproxy/bridge/bridge.go` uses `ssh.InsecureIgnoreHostKey()` with a `TODO`.
The client leg is a MITM by design; the backend leg being unauthenticated means the
proxy→target hop can be redirected, and a recording then attests to a session with a host
nobody verified. Needs a known-hosts source, which is a deployment decision.

### 7d. Non-session channels still reach the backend — raise, do not fix

Removing `HandleDirectTCPIP` was right, but generic channels still reach
`backClient.OpenChannel` carrying the client's `ExtraData`, which holds the destination, and
the minted certificate grants `permit-port-forwarding`. The target's sshd does the dialling
instead of the proxy. Either reject non-`session` channel types outright or drop that
certificate extension — either way it is a call for your lead.

---

## 8. Make the recordings usable

**Files:** `internal/pam/sshproxy/server.go`, plus the existing
`sessionRecording` service in `internal/pam`

The proxy writes asciicast files to `SSHPROXY_SESSION_DIR` and **stops there**. Three gaps
sit between that and session recording as a product feature. Confirm the scope of this part
with your lead before starting — 8a is certainly needed, 8b and 8c are policy calls.

### 8a. Register each recording with the console

Nothing in the proxy touches `did.jump_server_recordings`, and the existing endpoints
`/sessionRecording/addSessionRecording` and `/sessionRecording/listSessionRecording` go
unused by it — so a completed proxy session is invisible to the console and can only be
found by someone with shell access to the proxy host.

On session close, insert a row: `recording_url`, `recording_mime_type`
(`application/x-asciicast`), `session_recording_time`, `username`, `recording_length`,
`endpoint`, `user_id`.

**One wrinkle to raise rather than guess at.** `jump_server_connection_id` is
`NOT NULL DEFAULT 0` and means the grant this session ran under — but with
`RequireGrant = false` ([§4](#4-config-and-the-jump-server-row)) there is no grant, so the
honest value is `0`. Check whether the console's listing filters on that column; if it does,
proxy recordings will not appear until grants exist, and the listing needs a path for
grantless sessions.

### 8b. Turn on the HMAC sidecar

`SSHPROXY_HMAC_KEY` is empty in both env files, so `writeHMAC` never runs and no `.hmac`
file is produced. Until it is set, the proxy host can rewrite its own evidence and nothing
detects it. Set a hex key if these recordings are meant to be audit evidence — the code path
already exists and is validated at config load.

### 8c. Decide whether `scp` and `git` payloads are recorded

`SSHPROXY_RECORD_EXEC_IO` defaults to **false**, so exec and subsystem channels record the
command marker and metadata but **not the data stream**. That means an `scp` of a file, a
`git push`, and an `sftp` transfer all appear in the recording as "this command ran", with no
content.

That default is deliberate — the stream is wire-protocol data, not terminal activity, and it
is large. But if "we can see what was copied off the box" is part of what this feature is
sold as, the default is wrong for you. It is a config flag, not code.

### 8d. Two limits of the recording to state to whoever consumes it

Neither is a bug to fix here; both belong in whatever describes this feature to a customer.

- **Secret redaction is a heuristic.** `prompt.go` matches English keywords on the last line
  of output. A prompt it does not recognise — different wording, another language — has its
  input recorded verbatim. It over-redacts rather than under-redacts by design, but it
  cannot promise a recording is free of secrets.
- **Command arguments are recorded in full.** `mysql -pHunter2` is captured as typed.
  Redacting arguments is a different problem and is not attempted.

**Done when:** a completed session appears in `listSessionRecording`, a `.hmac` sidecar
exists beside its `.cast`, and the `RECORD_EXEC_IO` decision is written down.

---

## 9. Not in this task

- **The `.env` credentials.** The branch commits `.env` with live-looking secrets. Rotation
  and history purge are being handled separately. **Do not carry those two files forward
  into any rebase or new branch.** The `.gitignore` fix belongs with that work too — the
  ignore list currently reads `env` and `env.prod`, without the leading dot, which is why
  the files were never ignored.
- **Extracting the push stack into a shared package.** The right destination, and blocked
  until RADIUS lands — it edits the same `mfa_push_repository.go`. When it happens, Part 2's
  adapter changes by one import line, which is the point of keeping it in a single file.
- **`RequireGrant = true`.** Waits on the checkout flow populating
  `jump_servers_connections.user_id`. Config change, not code.

---

## 10. Gotchas, collected

- **Go 1.25.8 is required** by `go.mod`. The branch has not been compiled or its ~6,000
  lines of new tests executed during review, so **run the suite before you change
  anything** and treat a failure as pre-existing until proven otherwise.
- **Keep `Flow = FlowAD` for `KindSSH`.** §1. The failure is total and invisible in tests.
- **`Allow` must return an error, never `true`, when its store is down.** §3c.
- **`did.auth_log` singular, not `did.auth_logs`.** §3d.
- **`last_used_at` goes in `verifiedPublicKeyCallback`, not `publicKeyCallback`.** §5.
- **The principal is the key-resolved person, never the grant's `user_id`.** §0.
- **Challenge TTL is coupled to client timeouts.** The proxy's `AuthTimeout` defaults to 90s
  against a 60s challenge TTL, which is correct headroom. If anyone raises
  `MFA_PUSH_CHALLENGE_TTL_SEC` above 60 they must also raise the DC sensor's
  `mfa_timeout_seconds` and the gateway's `mfa_timeout` — the approve-then-fail trap
  documented in `mfapush.ChallengeTTL()`.
- **The compound username carries no port.** `ensurePort` supplies the configured backend
  port; that bug was found by a local end-to-end run and not by any unit test, because every
  fixture passes `host:port`. Expect the same class of gap elsewhere in Part 6.
- **Recordings are invisible to the console until §8a.** They exist only as files on the
  proxy host.
- **No permissive stub authenticator, ever.** §0.

---

## 11. Files at a glance

| Part | Files |
|---|---|
| 1 | `internal/mfapush/provider.go`, `internal/mfapush/context.go`, `internal/ad/src/repository/mfa_push_repository.go`, `.../challenge_kind_test.go` |
| 2 | `internal/pam/sshproxy/authz/mfa.go` *(create)* |
| 3 | `internal/pam/sshproxy/authz/` — lockout, limiter, audit, devices *(create)* |
| 4 | `.env` / secret store, `did.jump_servers` row |
| 5 | `internal/pam/sqlc/queries/user_ssh_keys.sql`, `internal/pam/sshproxy/server.go` |
| 6 | `cmd/authnull-service/main.go` |
| 7 | `internal/pam/handler/usersshkeys/usersshkeys.go`, `internal/pam/sqlc/queries/jump_servers_connections.sql`, `internal/pam/sshproxy/bridge/bridge.go` |
| 8 | `internal/pam/sshproxy/server.go`, `internal/pam/handler/sessionrecording/`, `.env` / secret store |

Related reading: [DATABASE-MFA-FLOW.md](DATABASE-MFA-FLOW.md) for the `KindDatabase` work
this mirrors most closely, [RADIUS-MFA-TASK.md](RADIUS-MFA-TASK.md) §4 for the same
three-part kind change written up for RADIUS, and the package comments in
`internal/pam/sshproxy/` — they are unusually complete and explain most of the design
decisions you will want to question.
