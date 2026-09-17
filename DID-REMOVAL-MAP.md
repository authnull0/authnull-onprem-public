# DID / Wallet / Blockchain Removal Map

Inventory of every touchpoint for removing the decentralized-identity subsystem
(DIDs, verifiable credentials, wallet, blockchain anchoring).

Disabled code is commented out with a leading `// DID-REMOVAL:` tag —
`grep -rn "DID-REMOVAL" --include=*.go .` finds everything to restore.

## Status

Phases 1-7 are **done and verified compiling** — `go build ./...` clean and
`./cmd/authnull-service` links, using the go1.25.8 toolchain in the module cache
(see the note at the end of §8).

| Phase | Target | Status |
|---|---|---|
| 1 | verifier route unmount | ✅ done |
| 2 | issuer + wallet route unmount (5 groups) | ✅ done |
| 3 | leaf callers | ✅ done — 5 files |
| 4 | ethereum / Merkle anchoring | ✅ done |
| 5 | pam onboarding (the reported crash path) | ✅ done |
| 6 | tenant + user onboarding, password reset, SAML | ✅ done — both copies |
| 7 | `checkouts.go` — 5 VC calls + 2 hard gates | ✅ done (Q1 resolved, see §7) |
| 8 | package bodies + go.mod deps | **not possible yet** — see below |
| 9 | drop tables | not doing — schema stays as is |

**The subsystem is now entirely unreachable from the binary.** Verified with
`go list -deps ./cmd/authnull-service`:

| | linked packages |
|---|---:|
| `internal/issuer` | 0 |
| `internal/wallet` | 0 |
| `internal/verifier` | 0 |
| `authnull0/did-proto` | 0 |
| `ethereum/go-ethereum` | 0 |
| `txaty/go-merkletree` | 0 |

The linked binary dropped from 67.85 MB to 65.91 MB (**1.8 MB / 2.9% smaller**),
which is the `go-ethereum` and `did-proto` trees falling out.

**Why Phase 8 cannot be done yet:** the issuer/wallet/verifier packages still
exist on disk and still compile, so they still `import` `did-proto` and
`go-ethereum` — which means those entries must stay in [go.mod](go.mod). Dropping
them requires deleting or commenting out the ~22.6k lines of package bodies, which
is a separate decision from "comment out the call sites". Nothing references those
packages any more, so this is cleanup, not a functional change.

Phase 9 is deliberately not being done: the `did.` Postgres schema and every table
stay exactly as they are, per instruction. No queries were retargeted.

---

## 0. Read this first — two traps

### Trap 1: `did` is the Postgres schema name, not just the feature name

All **103** tables in this application live in a Postgres schema literally called
`did` — `did.ad_users`, `did.auth_log`, `did.epm_machines`, and so on. A
grep-and-delete on `did` will destroy the entire application.

Only **20** of those 103 tables are actually DID/VC/wallet tables. See §5.

### Trap 2: `internal/verifier` is a third subsystem, easy to miss

The obvious targets are `internal/issuer` and `internal/wallet`. But
`internal/verifier` (5,051 lines) is the verification half of the same
subsystem — presentation requests and presentation-submission verification — and
it is *entirely* DID-based. It must be in scope or the removal is half-done.

---

## 1. Scale

| Package | Files | Lines | Notes |
|---|---:|---:|---|
| `internal/issuer` | 29 | 11,535 | `service/credential_service.go` alone is 5,065 |
| `internal/wallet` | 20 | 5,300 | |
| `internal/verifier` | 33 | 5,051 | presentation request/verify half |
| `internal/serviceaccounts/ethereum` | 1 | 673 | Merkle-tree anchoring |
| `internal/issuer/ethereum` | 1 | 71 | (counted in issuer above) |
| `internal/serviceaccounts/grpc/did_client.go` | 1 | ~30 | |
| `internal/endpoint/grpc/did_client.go` | 1 | 30 | |
| **Total** | **~85** | **~22,600** | |

Plus **12 files outside** these packages that call in (§3).

---

## 2. Entry points (routes)

All registered in [cmd/authnull-service/routes.go](cmd/authnull-service/routes.go):

| Line | Registration | Endpoints | Consumer |
|---|---|---:|---|
| 82 | `issuer.RegisterRoutes` | 47 | admin UI |
| 93 | `verifier.RegisterRoutes` | ~10 | endpoint / AD / RADIUS agents |
| 94 | `wallet.RegisterRoutes` | 28 | SSC (`/ssc/v1/wallet/*`) |
| 103 | `wallet.RegisterWalletServiceRoutes` | 28 | mobile wallet app (`/api/v1/walletService/*`) |
| 109 | `issuer.RegisterDidAliasRoutes` | 12 | admin UI short paths (`/api/v1/did/*`) |
| 130 | `serviceaccounts.RegisterRoutes` | — | partially DID (see §3.11) |

Note lines 94 and 103 register the **same 28 handlers** under two path prefixes,
and 82/109 overlap similarly. Unmounting must cover both or endpoints stay live.

**External-client risk:** the wallet routes are called by the *mobile app* and
the verifier routes by *installed agents*. Those clients 404 the moment the
routes come down — they cannot be fixed by editing this repo. Confirm client
rollout before Phase 2/3 below. Cross-check against
[API-INVENTORY.md](API-INVENTORY.md) and [routes_output.json](routes_output.json).

---

## 3. Call sites outside the DID packages

Ordered by removal risk, lowest first.

### 3.1 `internal/serviceaccounts/routes.go` — ALREADY DEAD
`StartMerkleWorker` (line 76) is already disabled at
[cmd/authnull-service/main.go:59](cmd/authnull-service/main.go#L59) with a comment
explaining it panics on empty DB name. Precedent for the commenting style.

### 3.2 `internal/serviceaccounts/services/serviceAccountService.go` — 1 site
Line 298: `CreateServiceAccountCredential`. Fire-and-forget.

### 3.3 `internal/issuer/service/service_account_service.go` — 1 site
Line 283: `ethereum.WriteToEth(signedVcbyte)`. **Contains a hardcoded Sepolia
Infura key and a hardcoded private key** at
[internal/issuer/ethereum/ethereum.go:17-21](internal/issuer/ethereum/ethereum.go#L17-L21).
Worth rotating/revoking regardless of this work.

### 3.4 `internal/policy/repo/policyjson_repository.go` — 2 sites
Lines 2722 (`CreateSharedAdUserCredential`), 2932 (`RevokeCredential`).

### 3.5 `internal/ad/src/repository/repository.go` — 2 sites
Lines 840 (`CreateADUserCredentialV2`), 906 (`CreateSharedAdUserCredential`).

### 3.6 `internal/pam/service/lums.go` — 2 sites
Lines 498, 541: `CreateEpmUserCredential`. Both log-and-continue.

### 3.7 `internal/mfa/handler/decentralized.go` — 1 site
Line 86: `walletSvc.CreateWallet`. This is the QR-code wallet-registration
handler — the whole endpoint is DID-only and can go wholesale rather than being
gutted in place.

### 3.8 `internal/pam/service/user_service.go` — 3 sites ⚠ the crash path
- 316 `CreateHolderDid`
- 380 `RegisterDeviceWallet`
- 485 / 497 `CreateADUserCredential` / `...V2`

**Both `GenerateUserDid` and `RegisterWallet` return `Status: "Success"` after
logging a failure** ([user_service.go:325-334](internal/pam/service/user_service.go#L325-L334)).
That is why a fully failed onboarding reported success end to end. Deciding
whether these should fail loudly is a prerequisite, not a detail — see §7.

### 3.9 `internal/tenant/repo/tenant_repository.go` — ~6 sites ⚠⚠
Lines 502 (`CreateIssuerDid`), 535 (`SeedCredentialSchema`), 546
(`CreateHolderDid`), 567 (wallet), 616 + 1952 (`CreatePlatformCredential`).
This is **tenant onboarding** — the deepest coupling in the repo. A tenant is
currently not considered provisioned until it has an issuer DID and seeded
credential schemas.

### 3.10 `internal/user/repo/tenant_repository.go` — ~6 sites ⚠⚠
Lines 572, 605, 616, 637, 719, 2099 — a **near-duplicate copy** of 3.9. Both
copies must be changed identically or tenant onboarding behaviour diverges by
code path.

### 3.11 `internal/pam/service/checkouts.go` — 5 sites ⚠⚠⚠ HARD GATES *(done)*
Lines 377 (SSH), 466 (password), 540 (VNC), 626 (RDP), 684 (EPM user).

Unlike every other caller, these **fail the request closed**:

```go
createCredentialResp, err := credSvc.CreateSshCredential(...)
if err != nil {
    return nil, err                                    // ← gate 1
}
if createCredentialResp.CredentialId == 0 {
    return nil, fmt.Errorf("Failed to create credential")   // ← gate 2
}
credentialId := createCredentialResp.CredentialId
return &checkouts.APIResponse{ CredentialID: &credentialId, ... }  // ← in the response body
```

Commenting out the call alone will not compile, and removing the gates changes
the API response contract (`CredentialID` is a returned field).

**Resolved (Q1 in §7):** the gates were removed with the calls. `CredentialID` is
kept as a non-nil pointer to `0` rather than becoming `nil`, because
[`AssignEpmUserToWallet`](internal/pam/service/checkouts.go#L742) calls
`GeneratePasswordlessVc` in a loop and dereferences `*res.CredentialID`
unconditionally — returning nil there would have reproduced exactly the panic class
this whole investigation started from. That deref is now also nil-guarded.

Clients that read `credentialId` from these responses will see `0`. Any client that
then looked the credential up did so through the issuer/wallet endpoints, which are
already unmounted (§2), so no working flow is being cut here.

---

## 4. gRPC / external services

| Item | Location |
|---|---|
| `did-proto` gRPC client (DID, Credential, Schema services) | [internal/issuer/grpc/did_client.go](internal/issuer/grpc/did_client.go) |
| duplicate client | `internal/serviceaccounts/grpc/did_client.go` |
| duplicate client | `internal/endpoint/grpc/did_client.go` |
| Address resolution | `DID_SERVICE_ADDR` env, else `localhost:50051` |
| SSI engine HTTP clients | `internal/wallet/did_service/{brcm,ssi,idid,engine}.go` and the identical `internal/verifier/did_service/*` |
| Ethereum | Sepolia via Infura, hardcoded (§3.3) |

Removing the subsystem eliminates the dependency on the **:50051 DID service**
entirely — which is the service that was down in the reported crash.

### go.mod dependencies that become removable
- `github.com/authnull0/did-proto` (line 8)
- `github.com/ethereum/go-ethereum` v1.17.3 (line 16) — large dependency tree
- `github.com/txaty/go-merkletree` v0.2.2 (line 41)

---

## 5. Database — the 20 DID/VC/wallet tables

Out of 103 tables in the `did` schema, these are the subsystem's:

```
did.issuer_dids                    did.users_dids
did.verifier_dids                  did.issuer_credentials
did.issuer_credential_schema       did.credentials
did.credential_rotation_jobs       did.credential_rotation_policy
did.credential_submission_queue    did.user_credential_mapping
did.user_wallets                   did.user_wallet_credentials
did.user_wallet_mapping            did.policy_credential_mapping
did.service_account_credentials    did.service_account_credential_mapping
did.presentation_request_submission_queue
did.presentation_response_submission_queue
did.custom_presentation_response_submission_queue
did.passkey_credentials  ← NOT part of this removal (WebAuthn; name is coincidental)
```

Recommendation: **leave all tables in place** for the commenting-out phase. Drop
them only after the code removal is confirmed permanent.

### Related open defect (separate from removal)
`did.user_wallets` is missing the `device_token`, `expo_push_token`,
`push_platform`, `push_device_name`, `push_token_updated_at` columns that
[internal/wallet/models/wallet_models.go:51-52](internal/wallet/models/wallet_models.go#L51-L52)
declares. There is **no `.sql` migration anywhere in the repo** that adds them.
If wallet registration is being removed this becomes moot; if not, it needs a
migration.

---

## 6. Config keys

In [config/config.yaml](config/config.yaml), per environment (`local`, and the
second block at ~line 163):

| Key | Status |
|---|---|
| `<env>.did.url` / `.wallet` / `.adurl` / `.adv2url` | already commented as "No longer used" — now direct Go calls |
| `<env>.services.ssiService.url` | live — SSI engine |
| `<env>.services.walletService.url` | already "No longer used" |
| `<env>.services.issuerService` | already "No longer used" |
| `<env>.issuer.policy_credential` | never live (blank deliberately) |
| `<env>.redis.host` / `.key` | ⚠ **used to store DID private keys** — check nothing else depends on Redis before removing |
| `<env>.logger.path` | shared with pam — **keep** |

---

## 6b. Hard gates found during implementation (not in the original survey)

The survey found one hard gate (`checkouts.go`). Implementing phases 5-6 turned up
**four more** — places where a missing DID/wallet row failed a request outright.
Each would have broken a live flow silently once provisioning stopped, and each is
now commented out along with the credential call it fed:

| Location | Gate | Flow it would have broken |
|---|---|---|
| [tenant/repo:1930](internal/tenant/repo/tenant_repository.go#L1930) | missing `user_wallets` row -> 500 "Not able to find user wallet table" | **Password reset**, for every user created after signup stops making wallets |
| [user/repo:2025](internal/user/repo/tenant_repository.go#L2025) | same gate, duplicate copy | same |
| [tenant/repo:3720](internal/tenant/repo/tenant_repository.go#L3720) | missing `issuer_dids` row -> 500; `CreateHolderDid` error -> 500; wallet email failure -> 400 | **SAML user onboarding** |
| [user/repo:3929](internal/user/repo/tenant_repository.go#L3929) | same three gates, duplicate copy | same |

The password-reset one is the notable find: recent commits (`b66727a`, `06f3ff6`)
were fixing that flow, and it would have started failing for all new users. The
password is written to the users table *before* the gate, so removing the block
lets the reset complete rather than changing what it does.

Two wallet-onboarding emails per signup path were also removed — they instructed
users to install the mobile wallet and scan a QR code carrying a `walletKey` that
is no longer generated. The `<p>Wallet Key: ...</p>` line was likewise dropped
from the PAM invitation email in
[pam/service/user_service.go](internal/pam/service/user_service.go).

## 7. Open questions that must be answered before editing

1. ~~**`checkouts.go` secret delivery (blocking).**~~ **RESOLVED from the code —
   the concern was unfounded.** Four independent findings:

   - [`StoreCredentialsInVault`](internal/pam/service/checkouts.go#L1008) ends with
     `var result string; return result, nil` — it **always returns an empty string
     and a nil error**, and swallows every HTTP failure. It cannot be a delivery
     path; it is a fire-and-forget write to an external vault service.
   - It returns immediately unless `VAULT_SERVICE_URL` is set, which on-prem it is
     not.
   - On-prem provisioning sets
     [`tenant.VaultFlag = "1"`](internal/org/service/provisioning.go#L326), so the
     `VaultFlag == "2"` branch never fires for a provisioned org regardless.
   - `/api/v1/secretservice/*` is a **stub** in
     [routes.go](cmd/authnull-service/routes.go) returning
     `"vault not configured"`.

   So the vault was never delivering the secret. Nor was the VC: the caller already
   holds the secret (it passes `p.Password` / `p.SSHPrivateKey` *in*), and the
   plaintext already lives in `did.epm_users`. What these endpoints actually did was
   push a credential into the user's **wallet** for later presentation — and both
   the wallet and verifier endpoints that would consume it are already unmounted.
   Removing VC issuance therefore removes a dead-end write, not a delivery
   mechanism. Both hard gates were removed with the calls.

   *(Aside, still true and still unrelated: the vault block is duplicated
   back-to-back — `StoreCredentialsInVault` is called twice with identical
   arguments in each checkout path. Copy-paste bug.)*

2. **Is `internal/mfapush/` the intended replacement?** The untracked
   `internal/mfapush/` (1,634 lines: azure_ad, duo, okta, expo, config, status,
   provider) plus the deleted `internal/mfa/handler/providers/*` in the working
   tree read as push-MFA replacing wallet-presentation MFA. `internal/ad/` has
   **zero** presentation coupling already, which supports that. Confirming this
   fixes the order of operations: mfapush lands first, verifier comes down after.

3. **Tenant onboarding definition of done.** Should a tenant still be "completed"
   without an issuer DID and seeded schemas (§3.9/3.10)?

4. **Client rollout.** Mobile wallet app and installed agents call these routes
   directly (§2). Are those already migrated?

5. **Onboarding error contract.** Should `GenerateUserDid` / `RegisterWallet`
   keep returning `"Success"`, or is fixing that in scope (§3.8)?

---

## 8. Suggested removal order

| Phase | Target | Risk | Notes |
|---|---|---|---|
| 0 | Confirm §7 answers | — | phases 5-6 are unsafe without Q1/Q3 |
| 1 | `internal/verifier` route unmount | **low** | fully self-contained; only `routes.go` imports it. Gated on Q4 |
| 2 | issuer + wallet route unmount (4 groups) | low-med | gated on Q4; admin UI 404s otherwise |
| 3 | Leaf callers §3.2, 3.4, 3.5, 3.6, 3.7 | low | all log-and-continue; no contract change |
| 4 | Ethereum: §3.3 + `serviceaccounts/ethereum` | low | worker already disabled; rotate leaked keys |
| 5 | `pam/user_service.go` §3.8 | med | the reported crash path; needs Q5 |
| 6 | Tenant onboarding §3.9 + §3.10 | **high** | two copies, keep identical; needs Q3 |
| 7 | `checkouts.go` §3.11 | **high** | hard gates + response contract; needs Q1 |
| 8 | Package bodies + go.mod deps | low | mechanical once 1-7 land |
| 9 | Drop tables | deferred | only once removal is permanent |

**Verification:** `go` on PATH is 1.20.3 while [go.mod](go.mod#L3) requires
1.25.8, so plain `go build` fails at go.mod parsing. A go1.25.8 toolchain is
already present in the module cache and does work:

```sh
GOTOOLCHAIN=local \
  ~/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.25.8.linux-amd64/bin/go build ./...
```

Phases 1-6 build clean with it, and `./cmd/authnull-service` links. `go vet` on
the changed packages reports only pre-existing findings (unkeyed struct literals,
Printf-directive warnings) in code this work did not touch. All twelve edited
files were already non-gofmt-clean before the change (repo-wide import grouping
and BOMs), so no formatting regression was introduced.

This matters because commenting out Go call sites reliably strands unused imports
and variables. Several were caught this way and handled: `privUser`/`pass`/a
shadowed `res` in `lums.go`, `fmt` and `time` in `serviceAccountService.go`,
`log`/`time`/`ethereum` in `serviceaccounts/routes.go`, and the
`serviceaccounts` import in `main.go`.
