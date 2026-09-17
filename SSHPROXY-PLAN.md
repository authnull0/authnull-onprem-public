# Authnull SSH Proxy — build plan and status

**Repositories:** `authnull-sshproxy` (new, the proxy) · `authnull-service` @ `sshproxy-phase1` (control plane) · `authn-service` @ `ssh-channel` (the decision)
**Companion document:** the PRD + LLD draft v2, 14 Sep 2026. This file is the delivery
plan: what is built, what is left, what is decided, and where the spec and the code
currently disagree.

---

## 1. What we are building

An SSH jump proxy that puts identity and MFA in front of privileged accounts.

Today an operator reaches a privileged Linux account by SSH-ing to it with a shared key.
Nobody is challenged, nothing is recorded, and the audit trail says only that `oracle`
logged in — not which person was holding the key.

With the proxy: the operator connects to the proxy instead of the target, the proxy
identifies the *person* from the public key they offer, authn-service decides whether that
person may open that account on that host, a push lands on their phone, and only then is
the session bridged — recorded to an asciicast file with an HMAC sidecar and listed in the
console.

SSH is not a fourth decision pipeline. It is a fifth `credentialType` on the
`DoAuthenticationV4` flow that already decides AD, Database, RADIUS and Console.

---

## 2. Architecture

Three components. The proxy enforces, authn-service decides, authnull-service stores and
displays.

| Component | Runs | Owns |
|---|---|---|
| `authnull-sshproxy` | Its own repository and image, in the DMZ | TCP listener, SSH handshake, the two-factor auth chain, backend dial with known-hosts verification, channel bridging, session recording |
| `authn-service` | Existing service | The decision. Resolves the person from the key fingerprint, fetches policy, applies the action, raises the push, writes the audit row |
| `authnull-service` | Existing service | Key table and admin CRUD, policy storage and authoring, recording metadata and playback, MFA activity |

**The proxy makes exactly one blocking call to decide a session.** Everything else it does
is bookkeeping that can fail without opening or closing anything wrongly.

**The proxy holds no database credentials.** It cannot resolve a key to a person; that
happens on the other side of the `Authenticator` interface. This is the property that lets
it sit in a DMZ, and it is enforced structurally — the whole repository depends on
`golang.org/x/crypto` and nothing else, and its image ships no database client.

That property is also why the proxy lives in its own repository. It was built inside
authnull-service as `internal/pam/sshproxy` while D1 still assumed an in-process proxy;
once D1 settled, a package that accepts TCP connections and forwards bytes was the one
thing in `internal/pam` that neither answers HTTP nor talks to Postgres. Moving it was a
deletion rather than a disentangling, because nothing imported it and it imported nothing.

Recordings cannot go "through" authnull-service: the proxy is the only thing that ever
sees the bytes. It writes the `.cast` locally and registers the metadata with
authnull-service so the console can list and play it.

### Connection flow

1. Operator runs `ssh oracle@10.0.0.5@proxy:2222`. SSH sends everything before the last
   `@` as the username, so the proxy receives `oracle@10.0.0.5` and splits it into target
   account and target host.
2. The client offers a public key. The proxy computes its SHA256 fingerprint and returns
   `PartialSuccessError` — never permissions. A key alone can never open a session.
3. The client falls through to the keyboard-interactive callback carried in that error.
   Zero prompts: one line of instruction text naming target, source and session id, then
   it blocks.
4. Proxy → authn-service: `POST /api/v1/authn/DoAuthenticationV4` with
   `credentialType: "SSH"`, the fingerprint, target account and host, org, tenant, source
   IP and request id. The request holds open for the length of the challenge.
5. authn-service resolves fingerprint → `did.user_ssh_keys` → the person and their email.
   Refuses on no match, revoked row, ambiguous duplicate, or a user with no email.
6. Policy lookup, then `PolicyActionOf` reads the action from inside the policy body.
   `block` refuses here, before any push.
7. `ChallengeMFA` builds the prompt and blocks until approved, refused, or the window
   closes.
8. Audit row written; response returns `isValid` and the backend account to use.
9. Proxy dials the backend — host key verified against known-hosts, credentials per §6.
10. Recorder opens before the first byte moves. If recording cannot start and
    `fail_policy=closed`, the session is refused rather than proxied unrecorded.
11. Channels bridged bidirectionally, teeing into the per-channel `.cast`.
12. On close, HMAC sidecar finalised and the recording registered with authnull-service.

---

## 3. Status

Phases 1–6, 8 and 9 are built. The proxy is **233 tests, race-clean**, in its own
repository (`sshproxy`, branch `v2`) and packaged as a systemd host binary; authn-service
carries the channel arm on `ssh-channel`; authnull-service keeps the control-plane half and
now also the admin API over the key registry. `go test ./...` is green here across all 27
packages.

**Nothing is left to build for a first end-to-end run.** What remains is environment: the
four configuration values in §6, a key registered through the new API, and a push provider
on the chosen tenant.

| Commit | Lands | State |
|---|---|---|
| `20cdec1` | Listener skeleton — config, env loading, compound-username routing, bounded concurrency, drain on shutdown | Done |
| `47ed9eb` | Key registry — migration `015_user_ssh_keys.sql`, `internal/pam/sshkeys`, schemacheck entry | Done |
| `012aecc` | Allowlist hardening | Done |
| `b212f23` | The auth chain — SSH handshake, publickey → `PartialSuccessError` → keyboard-interactive | Done |
| `de97b79` | Backend leg — known-hosts verification, per-session certificates | Done |
| `503182a` | Channel bridge — session relay, pivot paths refused | Done |
| `051db27` | Recorder — asciicast, HMAC sidecar, echo-tracking redaction | Done |
| `7aad6d6` | Decision client — the call to `DoAuthenticationV4` | Done |
| `96c87e6` | Proxy moved out to `authnull-sshproxy`; control-plane half stays | Done |
| `e65680b` | authn-service: the SSH channel arm (four edits) | Done, `ssh-channel` |
| `1ebe712` | authn-service: `resolvedUser` on the response | Done, `ssh-channel` |
| `001e9f7` | Deployment — systemd unit, idempotent installer, driver-linkage guard in `build.sh` | Done, `sshproxy` `v2` |
| `9693552` | `v2` replaces the proof of concept, both histories kept | Done, `sshproxy` `v2` |
| — | authnull-service: admin API over the key registry (`sshKeys/{addKey,listKeys,revokeKey}`) | Done |
| — | authnull-service: the three vet-failing packages cleared | Done |

### What each one actually does

**Listener (`20cdec1`).** `Listen` binds synchronously so a taken port surfaces at boot
rather than in a goroutine nobody reads. `MaxConcurrent` is acquired before any
per-connection work, because what is being bounded is how many connections can sit parked
waiting on a human to reach for their phone; over the cap a client is closed immediately
rather than queued. Every connection goroutine recovers — written when this ran in-process
with authentication, and kept now that it does not, because a panic still costs every live
session on the proxy. `Shutdown` drains rather than severing, because a live connection is a
session being recorded and cutting it mid-write leaves a truncated `.cast` the player
cannot open.

Two bugs from the prior implementations are encoded as tests, not comments: a username
with no `@` carries no target and must deny (the PoC fell back to `127.0.0.1:22` and
silently proxied such connections to the proxy host's own sshd), and `ensurePort` supplies
the backend port for the bare host the documented client shape actually produces — every
PoC fixture passed `host:port`, which is how "missing port in address" survived its whole
unit suite and only appeared *after* a fully successful authentication.

**Key registry (`47ed9eb`).** The migration's schema decisions are load-bearing and worth
reading before anyone changes them: the unique index is partial on `revoked_at IS NULL` so
revocation is not permanent (a key can be re-registered to the same person after a laptop
rebuild); `revoked_at` rather than `DELETE` because a revoked key is the evidence for every
session it ever authenticated; `domain_id` is `integer` to match the epm-side columns while
`did.users.domain_id` is `VARCHAR(255)`; and there is deliberately no FK on `user_id`
because this directory replays against every org database on every boot under
`ON_ERROR_STOP=1`, so one database missing `did.users` would abort the migration for every
tenant.

**Allowlist (`012aecc`).** An empty allowlist allowed `Backend.Host`, and `Backend.Host`
defaulted to `127.0.0.1` — so a proxy brought up without one would bridge to its own host's
sshd. That is the PoC's `127.0.0.1:22` fallback again, arriving through configuration
instead of through a missing `@`, and it matters more with the proxy running in a DMZ. Now
an empty allowlist denies every target, `Backend.Host` neither defaults nor grants itself,
and matching is what an operator would assume: an entry without a port matches any port on
that host, an entry with a port must match exactly, hosts compare case-insensitively. The
old exact-string match would have denied `10.0.0.5:22` against an entry of `10.0.0.5` —
and since `ensurePort` appends a port to every target, that denied every list written the
obvious way.

**Auth chain (`b212f23`).** See §5 — the shape is dictated by x/crypto and is not what the
spec described.

### Verification standard

Every phase so far: `go test -race` clean, `go vet` clean, `gofmt` clean, plus mutation
testing — each contract is deliberately broken to confirm a test fails. Running totals:
18/18 killed in the listener, 6/6 in the allowlist, 12/13 in the auth chain. The one
survivor is an equivalent mutant, documented in §5.

---

## 4. Decisions

| # | Question | Status |
|---|---|---|
| D1 | In-process or its own binary? | **Settled — own binary, and its own repository** (`authnull-sshproxy`). Matches the other three enforcement points; keeps an authnull-service deploy from having to drain or truncate live SSH sessions; the DMZ component holds no database credentials. |
| D2 | How does authn-service know the fingerprint is real? | **Settled — leave as is.** See below. |
| D3 | Does v1 ship with an `ssh` policy block, or on key + MFA alone? | **Open.** Blocks Phase 7. |
| D4 | Is the jump server part of the entitlement check? | **Open.** Recommendation: carry it in the request and the audit row from day one, decide whether it gates when the policy block lands. Cheap now, expensive to backfill. |
| D5 | Which branch continues? | **Settled — `sshproxy-phase1`**, porting bodies from `origin/feature/sshproxy-integration` where they are sound. |

### D2, stated plainly for the record

`DoAuthenticationV4` has no caller authentication today. The route is registered at
`app/service.go:112` inside the `/api/v1/authn` group, and that group carries no auth
middleware — the only `r.Use` in the entire app is `middleware.AuditLogger`, and nothing in
`src/middleware/` handles jwt, tokens, api keys or `Authorization`. `orgId` and `tenantId`
come off the request body.

So over the wire the fingerprint is an input: anything that can reach authn-service can
name one and raise a push as that person. **This is the same exposure the AD and RADIUS
channels already carry** — a DC sensor names a logon name — and the decision is to keep the
existing posture rather than introduce mTLS for SSH alone. Recorded here so it is a known,
accepted property rather than an oversight. If it is ever revisited, mTLS with the client
certificate checked against a registered enforcement point fixes all four channels at once.

---

## 5. Where the spec and the code disagree

These are corrections to the PRD v2, found while building. The code is right in each case
unless noted.

**1. The callback shape. (Spec §9 step 2, and the older plan's Phase 3.)**
Both describe `PublicKeyCallback` returning the `PartialSuccessError`. x/crypto forbids
that: `PublicKeyCallback must not return partial success when VerifiedPublicKeyCallback is
defined` (`ssh/server.go:754`), and permissions accompanying a partial success are
discarded (`ssh/server.go:326`). Verified in x/crypto v0.52.0. The working shape:

- `PublicKeyCallback` fires speculatively, once per key the agent offers, and judges
  nothing. It computes the fingerprint and stashes it in `Permissions.Extensions`, which is
  what x/crypto's own documentation prescribes for anything derived from an offered key.
- `VerifiedPublicKeyCallback` fires once, on the key actually signed with, confirms it is
  the key we described, and returns `PartialSuccessError` carrying the second factor. Never
  permissions — this is what makes a key alone incapable of opening a session.
- `KeyboardInteractiveCallback` is reachable *only* through that error, and is absent from
  `ServerConfig`. Registering it there advertises it as a standalone method, and a client
  could then authenticate having offered no key at all — with the SSH username carrying
  only the target, that is no identity whatsoever.

Both bypasses are tests: a client offering only a key is refused, and a client offering
only keyboard-interactive is refused without the authenticator being consulted.

**2. All refusals must be raised from one place.** Not in the spec, and it is a real leak.
The target and allowlist checks read like they belong in `PublicKeyCallback`, and that is
where they were until the test caught it: a refusal there leaves the client reporting
`attempted methods [none publickey]`, while one raised after partial success reports
`[none publickey keyboard-interactive]`. So anyone holding any key at all could map the
backend allowlist by reading its own error messages. Deferring the checks costs nothing —
no push is raised and the decision service is never called for a target that fails.

Note for reviewers: the opaque error constant is hygiene, not the control. x/crypto never
forwards a callback's error text to the client. What is observable is the method list.

**3. Config table (spec §16) does not match the code.**

| Spec says | Code does | Which is right |
|---|---|---|
| `SSHPROXY_FAIL_POLICY` defaults to `open` | Defaults to `closed` | Code. Recording a privileged session is the point of the feature; an operator should have to ask for unrecorded sessions. |
| `SSHPROXY_BACKEND_ALLOWLIST` | Was `SSHPROXY_ALLOW_LIST` | Spec. Renamed in `012aecc` — free now, not after deployment. |
| Empty allowlist "denies every target" | Used to allow the default backend | Spec. Fixed in `012aecc`. |
| No known-hosts variable listed | `SSHPROXY_KNOWN_HOSTS_PATH`, required at validate when enabled | Code. Add it to the table. |

**4. The timeout budget is off by exactly zero seconds. (Spec §9 vs §16.)** §9 nests login
grace 120s > HTTP timeout 90s > handler > challenge TTL 60s, but §16 sets
`SSHPROXY_AUTH_TIMEOUT_SEC` to 90 — and that variable is the raw-connection deadline
covering handshake *and* auth, which contains the HTTP call. At 90 and 90 they expire
together, and whichever wins decides whether the operator sees "the approval timed out" or
an unexplained dropped connection. Fixed in code: the challenge deadline is derived
strictly shorter than the socket deadline.

**5. Identity is resolved twice, in two repos.** Spec §8 lists
`internal/pam/sshkeys/registry.go` as built under authnull-service; §11 arm 2 reimplements
the same lookup in authn-service's `utils/identity.go` — fingerprint → key row → user →
email, refusing on no-match, revoked, duplicate and no-email. That is the same
security-critical judgement ("when is an identity undecidable") in two places, against a
table whose DDL ships in a third, with nothing making them agree.

**Decide which is authoritative.** Under the v2 design it is authn-service; the registry
should then keep `Add`/`List`/`Revoke`/`MarkUsed` and either lose `Resolve` or carry a
comment marking it admin-side only.

**6. The admin CRUD is not built.** Spec §8 says it is. `47ed9eb` built the migration, the
registry and the schemacheck entry — there is no `internal/pam/handler/usersshkeys/`. Which
means the `listKeys` finding in §10 is a note about code that does not exist yet, and is
cheap to get right the first time: `listKeys` must require admin for any non-self `userId`,
or drop the parameter.

**7. Phase 4 cannot be cherry-picked as-is.** Spec §19 says phases 3–5 should be
cherry-picked from `origin/feature/sshproxy-integration`. That branch's
`internal/pam/sshproxy/bridge/bridge.go:143` is `ssh.InsecureIgnoreHostKey()` — the exact
defect §3 calls not-optional. A clean cherry-pick reintroduces it for the third time.

---

## 6. Remaining work

### Phase 4 — the bridge — DONE (`de97b79`, `503182a`)

Backend dial and channel MITM. Known-hosts verification of the target, replacing the
`InsecureIgnoreHostKey` that both prior implementations shipped with a `TODO`. The client
leg is a man-in-the-middle by design; an unverified backend leg means the proxy→target hop
can be redirected and the recording then attests to a session with a host nobody checked.
First-connection behaviour is trust-on-first-use with the fingerprint written to the audit
log, not silent acceptance.

Backend credentials, two modes, keyed on the target and not on the session:

| Target | Credential | Why |
|---|---|---|
| Allowlisted host with our CA installed | Certificate signed per session, 5-minute TTL, target account as sole valid principal | Per-user identity on the target; nothing long-lived to steal from the proxy |
| GitHub Enterprise | Shared key, fixed backend user `git` | GHES cannot be given a `TrustedUserCAKeys` entry |

The certificate carries `permit-pty` and nothing else in v1. Port forwarding and agent
forwarding are out of scope, so the extensions that would enable them are not granted —
stronger than refusing the channel type, because the target's own `sshd` enforces it.

Write fresh rather than cherry-pick, for the reason in §5.7.

### Phase 5 — the recorder — DONE (`051db27`)

One asciicast v2 file per channel plus an HMAC sidecar. Per channel and not per connection,
because one SSH connection can carry several sessions and merging them interleaves two
terminals into an unreadable stream. The HMAC is written at close over the finished file —
it detects later tampering and does not protect a file mid-write, and should not be
described as if it does. Raw exec I/O off by default, so a `git clone` or `scp` does not
write its entire payload into the recording; metadata (command, exit status, byte counts)
always recorded. Prompt redaction tracks terminal echo state so a password typed at a
`sudo` prompt inside the session does not land in the cast in clear text.

### Phase 6 — the four edits in authn-service — DONE (`e65680b`)

Each follows a pattern the RADIUS and Database channels already established, so each has a
worked example to copy. Roughly 60 lines. All four seams verified present:

1. `ResourceForRequest` (`utils/mfa_challenge.go:42`) — a `case "SSH"` returning a `server`
   resource naming host and target account, so somebody receiving a push can recognise a
   session they did not start.
2. `ResolveUserEmail` (`utils/identity.go:44`) — a `case "SSH"` resolving by fingerprint.
   The SSH username is the *target*, never the person; the arm must not read it. More than
   one live row → refuse. Zero rows → refuse, no push.
3. DTO fields on `model/dto/policy_dto.go` — `sshKeyFingerprint`, `targetAccount`,
   `jumpServerId`.
4. The channel arm in `risk_based_repository.go`, beside the RADIUS arm. `IsSSHChannel`
   joins its three siblings (`IsADChannel`, `IsRADIUSChannel`, `IsDatabaseChannel` at
   `mfa_challenge.go:292/300/304`).

**Read the AD arm's comment before writing this.** Two failures it records are exactly the
ones an SSH arm can repeat: a dispatch function that overwrites `p.CredentialType` so the
policy search takes the wrong arm and finds nothing, and a challenge guarded by a condition
never satisfied. Both land on "no policy found", and **no policy means allow** — so the
session opens, unchallenged, looking like it worked. Without the channel test the AD branch
swallowed database and RADIUS logins, and it was found by an end-to-end `psql` login rather
than by any test.

Phases 6 and 7 can be built and exercised with `curl` before the proxy calls the endpoint
for real, which decouples the two halves. Worth doing — the SSH half has the longer tail.

### Phase 7 — the `ssh` policy block (gated on D3)

The policy JSON has `database` and `radius` blocks; it has no `ssh` block and
`searchPolicyJSON` has no SSH arm.

The action matters as much as the scope. On the database channel every matching policy was
treated as "challenge and then allow", which is right for exactly one of the three actions
an administrator can author. The live consequence: a policy written `block` sent its user a
push, the user approved it, and the session *opened*. A policy written to refuse access was
granting it — through the MFA prompt, which is the most convincing possible way to get it
wrong, because everything looks like it worked. So the SSH arm must read the action via
`PolicyActionOf` and honour all three. Do not reach for `dto.Policy.PolicyFlow`; it looks
like the answer and is never populated.

Scope at minimum: target hosts or host groups, target accounts, and the people or groups
granted. Jump server is D4.

**The D3 alternative:** ship v1 on registered key + MFA with no policy block. The key
registry is itself an allowlist — an administrator registered that key against that person.
The risk is that "registered key" is coarse: it does not distinguish `oracle` on a lab box
from `root` on a production database host. And it inherits the no-policy-means-allow
default, so if this option is taken it must be a **deliberate allow arm**, not an absent
arm that looks like one.

### Phase 8 — the HTTP authenticator — DONE (`7aad6d6`)

Fill the `Authenticator` interface with the call to `DoAuthenticationV4`. The PoC's
`auth/auth.go` is re-pointed, not deleted: it already calls an endpoint of the same name
(`do-authenticationV4`) with a request body that matches field for field, because that is
what Broadcom's deployment of the same contract expects. What comes out is the SSP OAuth
client-credentials dance; what stays is the request builder, the HTTP call, the response
handling and the blocking semantics the keyboard-interactive callback depends on.

Add `orgId` and `tenantId` to the request. Drop `fqdn`, `pam_service` and `sessionUser`,
which the V4 DTO does not carry.

**Rotate the SSP `client_secret`** committed in the PoC's `config.yaml`, whether or not the
PoC is retired.

### Phase 9 — ship it — DONE (`001e9f7`, `9693552`, repo `sshproxy` branch `v2`)

**Packaged as a host binary under systemd, not as a container.** This supersedes the
docker-compose service this section used to call for. The proxy sits on the
operator-to-target path, which the compose stack does not, so it ships the way the RADIUS
bridge does: a binary, an installer, a config template the customer edits, and nothing that
touches docker. Anyone still looking for an `authnull-sshproxy` service in
`onprem/docker-compose.yml` is looking for something that was deliberately not built.

Two systemd directives are load-bearing rather than boilerplate. `TimeoutStopSec` must
exceed `SSHPROXY_SHUTDOWN_GRACE_SEC`, or systemd sends SIGKILL mid-drain and truncates the
recording of whatever session was live — the exact outcome the drain exists to prevent. And
`ProtectSystem=strict` means every writable path is named, `/etc/authnull/sshproxy` being
the non-obvious one: `known_hosts` is appended to when a target is pinned on first use, so
without it the first connection to every new host fails with a permission error that reads
like a misconfiguration.

The installer is idempotent and never overwrites the config file (it holds the org and
tenant ids) or the host key (it is the proxy's identity — regenerating it trips every
client's `known_hosts` check with the warning that means an active man-in-the-middle, and
since this proxy is one by design that warning has to stay meaningful). It generates the
HMAC key rather than leaving it to the administrator, because a recommended setting that
requires work does not get done and without one every recording ships with no integrity
sidecar.

**The database-driver guardrail is now enforced, not just true.** `build.sh` refuses to ship
a binary that links one. Holding no database credentials is what lets this run in a DMZ, and
it was one careless import away from silently becoming false.

What remains is not packaging but **environment**: the four values in §6 below, and the
end-to-end proof in §8.

### Registering recordings with the console — blocked on decisions, not wiring

§15 says recordings are registered through the existing
`POST /api/v1/pam/sessionRecording/addSessionRecording` so they list in the console. That
endpoint exists, but it was built for the Guacamole and typescript recordings the current
PAM flow produces — where a user session, a jump-server connection and an object-storage
URL all exist. A proxy session has none of them, and three things need deciding before the
proxy can post to it honestly.

**It ignores its bearer token.** The handler reads one and `SaveSessionRecording` never
looks at it. So the proxy could post today without credentials — which removes the
technical blocker and replaces it with a question about whether an unauthenticated write
path into an audit-facing table is acceptable. It is the same posture D2 accepted for
`DoAuthenticationV4`, so the answer may well be yes; it should be a decision either way.

**It attributes an unknown user to user id 1.** `userId := 1; if payload.UserID != 0 { … }`.
The proxy has an email (now that `resolvedUser` is returned) but not a numeric id, so every
proxy-registered recording would claim to belong to whoever user 1 is. That is worse than
not registering: a wrong name in an audit trail is more damaging than a missing row. Either
authn-service returns the id alongside the email, or the endpoint learns to resolve one, or
it must accept a null.

**`jumpServerConnectionID` has no value for a proxy session.** It identifies a checkout,
and credential checkout is out of scope for v1 (§9). Posting 0 writes a row pointing at
nothing.

Until those are settled the proxy writes its `.cast` and `.hmac` to a local directory and
nothing appears in the console. The recordings are complete and verifiable; they are simply
not indexed.

### Also needed, belonging to no phase

- ~~**Admin CRUD for keys** (§5.6)~~ — **DONE.** `internal/pam/handler/sshkeys` wires the
  registry, which nothing had imported until now, to three routes under `/admin/v1/pam`:
  `sshKeys/addKey`, `sshKeys/listKeys`, `sshKeys/revokeKey`. Add and revoke require an
  administrator; list is self-service for your own keys and administrator-only for anyone
  else's, since without that guard it is an org-wide map of which credential belongs to
  which person, readable by every end user.

  The organisation comes from `middleware.SessionPrincipal` and the request DTOs carry no
  `orgId` **by design** — a test asserts they never grow one. An org read from the body
  would let any authenticated user of any customer register their own public key against a
  user in another organisation and then SSH in as them, which is the worst thing this
  endpoint could do. Until this landed, the only way to enrol an operator was hand-written
  SQL against each organisation database, and the only way to revoke one during an incident
  was the same.
- **`SSHPROXY_TENANT_ID`** is read today and set in neither env file. Do not guess it from
  `did.tenants` — there is no unique constraint on `organization_id` and the product counts
  tenants per org, so the mapping is one-to-many by design. Copy the tenant push MFA
  already uses for this org, so SSH challenges land in the same namespace as the working
  ones. More than one candidate means the org genuinely spans tenants: confirm which one
  the SSH users belong to rather than taking the most common.
- **`SSHPROXY_JUMP_SERVER_ID`** — register the host via
  `POST /admin/v1/pam/jumpserver/addJumpServer`, then read the id from `did.jump_server`
  (singular — `did.jump_servers_connections` is the grants table).
- **`install.sh`** generates the host key, backend key and HMAC key when absent. Never
  commit them.

### First end-to-end run — the sequence

Nothing here is a code change. In order, because each step depends on the one before:

1. **Pick the tenant.** Find the tenant this org's push MFA already uses — the one AD or
   database challenges are landing in today. This is `SSHPROXY_TENANT_ID`. Do not derive it
   from `did.tenants`; the org-to-tenant mapping is one-to-many by design. Getting it wrong
   does not fail loudly, it sends challenges into a namespace nobody is watching.

2. **Confirm that tenant has a working push provider.** If it does not, every SSH logon is
   denied with no message, which reads as an outage rather than a refusal — the same trap
   the AD path has. Verify by raising a challenge on a channel that already works, not by
   reading configuration.

3. **Register the jump server.** `POST /admin/v1/pam/jumpserver/addJumpServer`, then read
   the id from `did.jump_server` (singular; `did.jump_servers_connections` is the grants
   table). That is `SSHPROXY_JUMP_SERVER_ID`.

4. **Install on the jump host.** Run `deploy/install-sshproxy.sh` from the `sshproxy` repo,
   fill in `SSHPROXY_ORG_ID`, `SSHPROXY_TENANT_ID`, `SSHPROXY_JUMP_SERVER_ID`,
   `SSHPROXY_BACKEND_ALLOWLIST` (empty denies everything) and `SSHPROXY_AUTHN_URL`, then
   `systemctl enable --now authnull-sshproxy`. The installer prints the host key fingerprint
   — publish it, because that is what operators are being asked to trust.

5. **Register an operator's key.** `POST /admin/v1/pam/sshKeys/addKey` with
   `{"userId": <did.users.user_id>, "publicKey": "<contents of id_ed25519.pub>", "label":
   "work laptop"}`, as an administrator of that org. Confirm with `sshKeys/listKeys`. The
   response carries the fingerprint; it must match `ssh-keygen -lf` on the operator's
   machine, because that string is the entire identity anchor.

6. **Connect.** `ssh <account>@<target-host>@<proxy-host>:2222`. Expect one push naming the
   account and host, and a shell on approval.

Then work §8 in order. Criteria 1, 2, 3, 6, 7, 8 and 10 should pass. Criterion 5 will not —
the recording is written and verifiable but not indexed, per the section above. Criterion 4
is untestable rather than failing until D3 is settled, because there is no `ssh` policy
block to write a `block` policy in. Criterion 9 follows entirely from step 1.

---

## 7. Fail-closed matrix

Every failure denies. Each row is a test.

| Condition | Result | Decided by |
|---|---|---|
| Target not on the allowlist | Deny | Proxy |
| Username carries no target | Deny | Proxy |
| authn-service unreachable | Deny | Proxy |
| Decision errors, or errors alongside a well-formed allow | Deny | Proxy |
| Allow with no backend address | Deny | Proxy |
| Backend host key unknown or changed | Deny | Proxy |
| Recorder cannot start, under `fail_policy=closed` | Deny | Proxy |
| Any dependency nil at boot | Deny all | Proxy |
| Key not registered | Deny, no push | authn-service |
| Two live keys, one fingerprint | Deny | authn-service |
| Resolved user has no email | Deny | authn-service |
| Policy action is `block` | Deny, **no push** | authn-service |
| Push refused on the phone | Deny | authn-service |
| Challenge TTL expires | Deny | authn-service |
| MFA provider errors | Deny | authn-service |
| **No policy matches** | **Allow** | authn-service |

That last row is the existing product-wide default and the one thing here that does not
fail closed. It is why a channel arm that silently finds nothing is dangerous rather than
merely broken, and it is what makes D3 a decision about what the product *is* rather than
how it is built.

**Rule for the whole build:** no approving stub to make something work locally. A valid key
alone opening a privileged session is the thing this design prevents. If a local harness is
needed, it goes behind a build tag, never on this path.

---

## 8. Acceptance criteria

1. An operator with a registered key runs `ssh oracle@10.0.0.5@proxy:2222`, receives one
   push naming the account and host, approves it, and gets a shell.
2. Denying on the phone refuses the connection, and the refusal is distinguishable in the
   log from an MFA outage.
3. An unregistered key is refused *without* raising a push — there is no person to push to.
4. A `block` policy refuses and raises **no push**.
5. The session is written to a `.cast` with a valid HMAC sidecar and appears in the
   console's session-recording list.
6. The audit row names **both** the principal and the key fingerprint. On a shared account
   the person and the credential are different facts, and revoking the right key after an
   incident depends on having recorded which one authenticated.
7. `last_used_at` is stamped once per connection, from the verified callback and not the
   speculative one — the speculative one fires several times per connection as the agent
   offers each key it holds, and only one of those offers is real.
8. With authn-service unreachable, the proxy refuses every connection and says why.
9. An SSH challenge appears in the same console MFA activity view as an AD or database
   challenge, under the org's configured provider.
10. An unknown backend host key refuses the connection.

---

## 9. Out of scope for v1

- **Credential checkout.** The flow that populates `did.jump_servers_connections.user_id`
  does not run in production, and gating on it denies everybody.
- **Live session monitoring and termination.** Recording only; no join, no kill switch.
- **Command filtering.** The recorder sees commands; nothing blocks them.
- **Agent forwarding and port forwarding.** Refused, not proxied. Both are pivot paths and
  neither has a use case yet.
- **SFTP/SCP file policy.** Transfers bridged and recorded as metadata, not inspected.
- **Central object storage for recordings.** Local directory in v1; the metadata contract
  does not change when central storage lands.
- **A separate SSH lockout and rate-limit stack.** Whatever the V4 flow applies to the
  other channels applies here.

---

## 10. Pre-existing issues that block calling this shippable

None of these are caused by this work. All three are in the way.

**1. ~~`go test ./...` is not clean on `on-prem`.~~ FIXED.** All three packages
(`internal/issuer/handler`, `internal/issuer/service`, `internal/pam/service`) now pass, and
`go test ./...` is green across all 27 packages with 0 failures. The estimate of "roughly 30
lines of mechanical fixes" was right about the volume and wrong about the character, because
one of them was not cosmetic:

`service_account_service.go` built a delegation encryption key with
`fmt.Sprint("%v%v", walletId, serviceAccountUserId)` — `Sprint`, not `Sprintf`, so the format
verbs were never interpolated. The key every existing delegation was encrypted with is the
literal string `%v%v` followed by the wallet id, a space, and the account id: `"%v%v12 34"`,
not `"1234"`. Rewriting it to `Sprintf`, which is what the vet warning invites, would have
silently produced a different key and made every already-delegated credential
undecryptable. The value is now reproduced byte-for-byte by construction with the bug
documented in place; correcting it properly means re-encrypting existing rows, which is a
migration and a separate decision.

Note for anyone repeating this: `go vet` on its own also reports `composites` (unkeyed struct
literals) and `unreachable` in these packages, and neither is in the subset `go test` runs.
They are untouched, and they are not what "the suite is green" turns on.

**2. Committed secrets.** `.env` and `.env.prod` are both tracked and carry a GitHub PAT,
live `AKIA` AWS keys, Cloudflare, Duo, Okta, SMTP, Twilio and the JWT signing secret.
`.gitignore:36-37` intends to exclude them but reads `env` and `env.prod` — missing the
leading dot by two characters. Fix the patterns, rotate, purge history.

**3. The PoC's SSP `client_secret`** is in plaintext in a committed `config.yaml`. Rotate
it whether or not the PoC is retired, and drop the 11.9 MB tracked binary either way.

---

## 11. Build environment

`go.mod` requires **Go 1.25.8**. The system Go on the dev box is 1.20.3, which cannot even
parse the `go.mod`. A local toolchain at `~/sdk/go1.25.8` is what this branch was built and
tested with.

---

## 12. What we need decided

| | Decision | Blocks | Recommendation |
|---|---|---|---|
| **D3** | `ssh` policy block in v1, or key + MFA alone? | Phase 7 | Ship v1 on key + MFA with an **explicit allow arm**, design the policy block against real usage. Revisit before the first customer with more than one class of target host. The arm built in phase 6 already challenges unconditionally, so shipping this way needs no further change — only a decision. |
| **§6 rec.** | How does a proxy recording get indexed in the console? | Recordings appearing in the console | Return the numeric user id beside `resolvedUser`, allow a null `jumpServerConnectionID`, and decide whether the endpoint's ignored bearer token is acceptable. Until then recordings are written and verifiable but not listed. |
| **D4** | Does the jump server gate entitlement? | Phase 7 shape | Carry it in the request and the audit row from day one; decide whether it gates when the policy block lands. |
| **§5.5** | Which resolver is authoritative for fingerprint → person? | Cleanup | **authn-service**, settled by phase 6 — it is the only one on the authentication path. `internal/pam/sshkeys.Resolve` is now admin-side only and should say so or go. |
| **§10.1** | ~~Do we clear the three vet-failing packages?~~ | ~~Any "tests are green" claim~~ | **Settled and done.** Cleared; `go test ./...` is green. One of them turned out to be a live encryption-key bug rather than a formatting nit — see §10.1. |

Phases 4 and 5 are unblocked and can proceed while these are settled.
