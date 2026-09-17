# RADIUS MFA — backend changes (uncommitted)

Wires the **live** RADIUS login path onto the `radius` policy block + the seven-rule
matcher, so a policy authored in the console (device / calling-station / service-type
scoping) is actually applied at login. Before this, a live RADIUS login only ever read
`policy_json.networks` and was matched on identity alone; the `internal/radius` engine
was fully built and unit-tested but **unreached** (its package header literally said
`// # NOT CURRENTLY REACHED`).

Nothing here is committed. Direction was chosen deliberately: wire the `radius` block
(the only path where device/service-type MFA scoping can work).

---

## What changed in this repo

### 1. `internal/policy/dto/dto.go`

- **New `RadiusAuth` struct** and a `RadiusAuth` field on `SearchPolicyJSONRequest`
  (`json:"radiusAuth"`). Carries the RADIUS event's identity + device context:
  `adUser`, `domain`, `nasIdentifier`, `nasIp`, `callingStation`, `serviceType`.
  When `adUser` is set, the service routes to the radius-block engine; empty, it
  falls back to the legacy `networks` search, so existing callers keep working.
- **Extended `DoAuthenticationV4RequestDTO`** with `nasIdentifier`, `nasIp`,
  `callingStation`, `serviceType`. This is the binary → authn-service request; the
  fields give the NAS context a home end-to-end. The binary reads them from
  FreeRADIUS (`%{NAS-Identifier}`, `%{NAS-IP-Address}`, `%{Calling-Station-Id}`,
  `%{Service-Type}`).

### 2. `internal/policy/service/policyjson_service.go`

- `SearchPolicyJSON` now branches: `CredentialType == "RADIUS"` **and**
  `RadiusAuth.AdUser != ""` → new `searchRadiusPolicy` helper. Otherwise unchanged
  (legacy `repo.SearchPolicyJSON`).
- **New `searchRadiusPolicy`** resolves the tenant DB and calls
  `radius.GetEffectivePolicy(tenantDB, dto.EvaluateRadiusRequest{…})`, which already
  does: AD group/OU transitive-closure resolution (`BuildAuthContext`) → candidate
  load (`policy_json` has key `radius`, scoped to domain/org/tenant) → the seven-rule
  matcher (device, calling-station, service-type). It returns the single governing
  policy in the existing `Data []model.PolicyModel` shape (one element, or empty).
- Added the `internal/radius` import.

**Why the service layer and not `repo`:** `internal/radius` imports
`internal/policy/repo` for its normalisation helpers, so `repo` calling back into
`radius` would be an import cycle. The service layer is the one place that can see
both — see the comment block in `decision.go`.

**Behavioural note for review:** the legacy `networks` search returned every
endpoint-matched candidate for the caller to re-rank. `GetEffectivePolicy` returns
**at most one** policy — already sorted by `Priority` and fully context-matched. If
authn-service iterates `Data` and applies `policyFlow`, a single-element set is
correct; confirm it does not assume multiple rows.

**No matching policy → allow.** Empty `Data` = "no policy governs this login", the
RADIUS default (a customer with no policy written must not have their VPN break). The
near-miss reason ("known user, but not from that device") is returned in `Message`
for the decision log.

---

## Verification done

```sh
go build ./internal/policy/service/ ./internal/policy/dto/ ./internal/radius/   # ok
go vet ./internal/policy/service/                                                # ok
go test -vet=off ./internal/radius/                                             # ok
```

Suggested full check before commit:

```sh
go build ./... && go test -vet=off ./internal/policy/... ./pkg/license/ ./internal/mfapush/
```

### Manual smoke (once authn-service forwards RadiusAuth)

`POST /api/v1/policy/json/searchPolicy` (internal, `InternalKeyOrAuthnz`):

```json
{
  "orgId": 1, "tenantId": 1, "credentialType": "RADIUS",
  "radiusAuth": {
    "adUser": "jdoe", "domain": "corp.lab",
    "nasIdentifier": "vpn-hq", "nasIp": "10.10.0.1",
    "callingStation": "10.20.0.5", "serviceType": "framed"
  }
}
```

Expect `data` to hold the governing `radius` policy (or `[]` with a near-miss
message).

---

## What still belongs to the backend trainee

Most of the remaining work is in **authn-service** (a separate repo, not present
here) — this repo now exposes the contract it needs.

1. **authn-service: forward the RADIUS context** on `/policy/json/searchPolicy`.
   Populate `radiusAuth.adUser` (the RADIUS User-Name) and the NAS fields from
   `do-authenticationV4`. Until it does, `adUser` is empty and the branch falls back
   to the legacy user-scoped `networks` search — no regression, but no device scoping.
2. **The binary → do-authenticationV4:** populate the four new NAS fields
   (`nasIdentifier`, `nasIp`, `callingStation`, `serviceType`) from FreeRADIUS. Prefer
   the packet source address for `nasIp` — see the packet-source note in
   `internal/radius/matcher.go` (a client can omit the NAS-IP attribute).
3. **Push says "VPN":** the push is minted in authn-service. The `KindRADIUS` path in
   this repo is complete — `mfapush.KindRADIUS`, `mfapush.RADIUSResource`,
   `ResourceTypeNetworkDevice`, and `case mfapush.KindRADIUS` in
   `internal/ad/src/repository/mfa_push_repository.go`. Confirm the live push uses
   `KindRADIUS` (not `KindAD`) so it does not inherit a Kerberos SPN via
   `correlateFromAuthLog`, and add the RADIUS twin of
   `TestDatabaseChallengeDoesNotInheritADContext`.
4. **Two-block migration:** `PolicyJSON` still has both `Networks` (legacy) and
   `Radius`. Decide whether the console writes `radius` only (it now does — see the
   frontend changes) and whether to migrate/deprecate `networks` for RADIUS. Existing
   `networks` policies have no device/service-type scoping.
5. **Fail-closed + data-plane licensing:** verify authn-service rejects on
   authnull-service being unreachable, and that no RADIUS path is added to
   `pkg/license/gate.go` (a licence lapse must never stop VPN logins). Assert both
   spellings of any RADIUS path in `pkg/license/license_test.go`'s `dataPlanePaths`.

---

## Files touched

| File | Change |
|---|---|
| `internal/policy/dto/dto.go` | `RadiusAuth` struct + field on `SearchPolicyJSONRequest`; NAS fields on `DoAuthenticationV4RequestDTO` |
| `internal/policy/service/policyjson_service.go` | RADIUS branch + `searchRadiusPolicy` helper + `internal/radius` import |

Unchanged but now reached: `internal/radius/{decision,matcher}.go`.
