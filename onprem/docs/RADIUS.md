# RADIUS MFA on-premise

Second-factor enforcement for VPNs, switches, firewalls — anything that speaks RADIUS.

```
VPN / switch / firewall
        │  RADIUS (UDP 1812)
        ▼
   FreeRADIUS                 ← the customer owns this; does the password
        │  post-auth: exec
        ▼
   authnull-radius-mfa        ← the bridge, one process per request
        │  HTTPS, ONE blocking call
        ▼
   authn-service              ← do-authenticationV4: identity, policy, second factor
        │
        ▼
   authnull-service           ← policy store and lookup
```

**FreeRADIUS does the password. The bridge only does the second factor.** By the time it
runs the user has already proved who they are. It emits no `Auth-Type`, so it can deny
but never grant, and a wrong password never reaches it — a reject goes to
`Post-Auth-Type REJECT`, which has no hook. An approved push cannot rescue a bad
password.

Exit code is the whole contract with `rlm_exec`: **`0` → accept, `1` → reject.** Every
error path exits 1.

---

## Prerequisites

| | |
|---|---|
| FreeRADIUS 3.x | on a host that can reach `authn-service` |
| the bridge binary | built from `authnull0/radius-bridge`, branch `radius-doauthnv4` |
| an MFA provider | Okta, Duo, TOTP or WebAuthn configured for the org |
| **AD sync** | see [Identity](#identity-requires-a-synced-user) — this is not optional today |

`authn-service` also needs `ENCRYPTION_KEY`, `TOTP_ENCRYPTION_KEY` and
`INTERNAL_API_KEY` set, and its `TENANT_*` URLs pointing at `authnull-service:8080`. With
any of those missing, RADIUS MFA fails closed on **every** login: the org's provider
config cannot be decrypted, so the RADIUS arm is skipped entirely and no push is ever
sent. `docker compose config` is the fastest way to confirm.

---

## Install

On the FreeRADIUS host:

```bash
sudo ./install-bridge.sh --check                        # preflight, changes nothing
sudo ./install-bridge.sh ./authnull-radius-mfa-linux-amd64
```

Then edit `/etc/authnull/radius-bridge.env` — `API_BASE_URL`, `ORG_ID`, `TENANT_ID` and
`DOMAIN` are required and have no defaults.

Add the appliance as a RADIUS client in `clients.conf`:

```
client vpn-hq {
    ipaddr = 10.10.0.5
    secret = <generated, not "testing123">
    require_message_authenticator = yes
    nas_type = other
}
```

Restart FreeRADIUS, then test **with `radclient`**:

```bash
echo "User-Name=alice,User-Password=<password>" | radclient -t 90 -r 1 127.0.0.1:1812 auth <secret>
```

---

## The timeout problem — read this before the first test

RADIUS is UDP with short timeouts. Push approval takes 10–30 seconds of human time.
**Five timeouts will each kill the request before the user reaches their phone**, and the
result looks like a broken integration rather than a slow one.

| Setting | Default | Must be | Set by |
|---|---|---|---|
| the appliance's RADIUS timeout | ~5s, 3 retries | **60s+, 1 retry** | **you, on the appliance** |
| FreeRADIUS `max_request_time` | 30s | 90s | `install-bridge.sh` |
| `rlm_exec` `timeout` | 10s | 90s | `install-bridge.sh` |
| `MFA_TIMEOUT_SEC` | 60 | below `rlm_exec timeout` | config file |
| the bridge's HTTP timeout | — | derived: `MFA_TIMEOUT_SEC + 15s` | not configurable |

Duo's RADIUS proxy has the identical constraint and documents raising the NAS timeout, so
this is an accepted pattern rather than a workaround — but it has to be done.

**`radtest` cannot be used to test this.** Its timeout is fixed at roughly 3s × 3
retries, so it gives up mid-approval and prints a failure that is not one. Use
`radclient -t 90 -r 1`.

**Retries mean repeat prompts.** Each retransmission that FreeRADIUS treats as a new
request raises a new push. Set the appliance to **one** retry, or a user who is slow to
answer gets several notifications for one login.

---

## Identity requires a synced user

The bridge sends the logon name. `authn-service` maps it to a person by database lookup
only — `did.ad_users.logoname`, then `did.users.logon_name`, then `did.epm_users`. There
is no other mapping.

So a **RADIUS-only deployment cannot authenticate**: with nothing populating those
tables every login ends at `could not identify the user for multi-factor approval`. AD
sync is a hard prerequisite today.

Note also that a hand-added row in `did.ad_users` does **not** survive the next sync —
the sync removes anything absent from the directory. Test accounts belong in real AD.

---

## Policy scoping

A RADIUS policy carries a `radius` block and is scoped by any combination of:

| Field | Matches |
|---|---|
| `users`, `groups`, `ous`, `matchAll` | identity; groups resolve through the same transitive closure as AD |
| `domain` | the directory; empty matches any |
| `clients` | device by NAS-Identifier, IP, CIDR, or `*` |
| `callingStations` | the user's address; exact or CIDR |
| `serviceTypes` | kind of access — see below |

`policyFlow` decides the outcome: `mfa_required`, `allow` or `block`. **`block` refuses
without sending a push** — a blocked user is never prompted.

**No matching policy means allow.** Installing this must not break a VPN that has no
RADIUS policy written yet.

**An unknown value is not an exemption.** A request that identifies no device, carries no
Calling-Station-Id, or presents a Service-Type this engine does not recognise still faces
a policy scoped on that dimension. The alternative — treating "unknown" as "does not
apply" — let a client escape enforcement by omitting an attribute.

### Service-Type values differ by vendor

`Service-Type` is an integer attribute, and what your appliance sends is often not what
you would guess. Written as words, numbers, or the dictionary name — all three match:

| Policy value | Also matches |
|---|---|
| `login` | `Login-User`, `1` |
| `framed` | `Framed-User`, `2` |
| `outbound` | `Outbound-User`, `5` |
| `administrative` | `Administrative-User`, `6` |
| `nas-prompt` | `NAS-Prompt-User`, `7` |

Confirm what yours actually sends before scoping a policy on it — OpenVPN's
`radiusplugin` template sends `5` (Outbound-User), for example, so a policy written as
`framed` would not fire. `tail -f /var/log/authnull/radius-bridge.log` prints the value
that arrived.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `CONFIG ERROR: ... missing required keys` | config absent or incomplete |
| Access-Reject, **nothing in the bridge log** | the bridge never ran. `/etc/authnull` must be group `freerad`, or the service account cannot traverse it |
| `Login incorrect` in `radius.log` | the password failed, so `post-auth` never ran. On Debian/Ubuntu the `files` module reads `mods-config/files/authorize`, **not** the top-level `users` file |
| `BlastRADIUS check: Received packet with Message-Authenticator` | set `require_message_authenticator` on that client entry |
| `HTTP 404` | `API_BASE_URL` points at authnull-service; it must be authn-service |
| `HTTP 401` | `INTERNAL_API_KEY` missing in authn-service, or the route was put behind auth |
| `could not identify the user` | the account is not synced — see [Identity](#identity-requires-a-synced-user) |
| `could not evaluate policy` | policy lookup failed. Check `TENANT_POLICY` and `INTERNAL_API_KEY` in authn-service |
| `FAIL-CLOSED: rejecting request` | AuthNull unreachable and `FAIL_OPEN=false`. Correct behaviour |
| no push, instant Accept | no policy matched. Check the scope — a device- or service-type-scoped policy may not cover this login |
| several notifications for one login | the appliance is retrying. One retry, 60s+ |

```bash
tail -f /var/log/authnull/radius-bridge.log
tail -f /var/log/freeradius/radius.log
```

---

## Verified transports

The decision path has been tested end to end against:

- **FreeRADIUS with PAP** (`radclient`)
- **FreeRADIUS with MSCHAPv2** — what most appliances use
- **OpenVPN** with `openvpn-auth-radius`
- **strongSwan IKEv2 with EAP-MSCHAPv2 over RADIUS** — the shape FortiGate, Cisco ASA
  and GlobalProtect use

Two notes from that work. `radiusplugin` requires a client certificate: with
`verify-client-cert none` it fails with `common_name is not defined`, so cert **plus**
RADIUS password is mandatory there. And strongSwan needs `load = yes` in
`/etc/strongswan.d/charon/eap-radius.conf` — without it the daemon starts normally and
only fails at connection time.
