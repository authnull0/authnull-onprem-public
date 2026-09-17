# Task: Identity Providers screen — show what's actually happening

**Screen:** `/pam/directory` (Identity Providers list)
**Backend:** done, needs deploy. No new endpoints — `GetAllDomains` returns four new things.

## Why

Today the row says `Running` / `Not Protected` / `Jan 01, 1, 05:53 AM`. All three are misleading:

- **`Running`** is per *domain*, but a domain can have several Domain Controllers each running
  a sensor. If two of three are dead the row still says Running.
- **`Not Protected`** doesn't say why, and there's no way to find out.
- **`Jan 01, 1`** is a never-synced domain rendering Go's zero timestamp.

Worst of all, nothing on this screen shows whether the directory is in **monitor** or **enforce**
mode — which is the single most important fact about it, because in monitor mode the sensor
never blocks anything and never sends an MFA push. An admin can configure everything correctly
and see nothing happen, with no clue why.

---

## What the API returns now

`POST /ad/GetAllDomains` — same request, four additions per domain:

```json
{
  "id": 15,
  "directoryName": "test01",
  "domainName": "authnull.lab",
  "status": "Active",
  "integration_type": "Agent",

  "enforcementMode": "monitor",
  "fallbackAction": "allow",
  "lastSyncTime": null,
  "sensors": [
    { "hostname": "WIN-JCHJ9VPTQVJ", "lastSeen": "2026-08-07T05:15:00Z", "eventCount": 1284 }
  ]
}
```

| field | values | notes |
|---|---|---|
| `enforcementMode` | `"monitor"` \| `"enforce"` | always one of these two, never null |
| `fallbackAction` | `"allow"` \| `"deny"` | what happens during an Authnull outage |
| `lastSyncTime` | ISO string **or `null`** | **breaking-ish:** was previously always a string |
| `sensors` | array, may be `[]` | one entry per DC actually reporting |

`sensors` is derived from real auth events the sensor forwards, not from anything typed into the
form — `hostname` is the DC's own machine name. So it's trustworthy, and it's the hostname/IP
that was missing from this screen.

---

## Changes

### 1. Mode — a control, not just a badge

This is the one thing on the screen an admin actually sets, so make it interactive: a segmented
control or a dropdown on the row.

- `monitor` → **Monitoring** (neutral/grey). Tooltip: *"Authentications are evaluated and logged.
  Nothing is blocked and no MFA prompts are sent."*
- `enforce` → **Enforcing** (green/blue). Tooltip: *"MFA verdicts are applied. Users may be blocked."*

```
POST /ad/updateDomainEnforcement
{ "tenantId": 1, "orgId": 2, "adId": 16, "enforcementMode": "enforce" }
```

**It takes effect on the next authentication.** The mode lives server-side, not in the sensor's
config file, so there is nothing to re-download and no service to restart on the domain
controllers. Don't add a "now re-download sensor.yml" dialog — that requirement is gone.

Do still confirm before switching to Enforcing: it is the moment real logins start being
challenged and blocked. A short dialog naming the domain is enough. Switching back to Monitoring
is equally instant, so the confirm for that direction can be lighter or omitted.

> If someone opens `sensor.yml` on a DC they will see `mode: "enforce"` even for a domain shown
> here as Monitoring. That is expected — to the sensor that value means "ask Authnull on every
> authentication", and Authnull decides. The file says so in a comment. Worth knowing so it
> doesn't get reported as a bug.

### 2. Replace `Agent Status` with per-DC sensors

`sensors` and `lastSyncTime` are **two different facts**, and a sensor can satisfy one without
the other: `lastSyncTime` means its AD user sync is working, `sensors` means it is forwarding
authentication events. Combine them — an empty `sensors` array on its own does NOT mean no
sensor:

| `lastSyncTime` | `sensors` | show |
|---|---|---|
| recent | 1+ entries | **Reporting** — hostname + relative last-seen (*"2 min ago"*) |
| recent | `[]` | **Syncing — no auth events yet** (neutral, not an error) |
| null / stale | `[]` | **No sensor detected** — amber. *"No DC has reported yet."* |

With 2+ entries show `WIN-JCHJ9VPTQVJ +2 more`, expandable to the full list.

The middle row matters: the auth-event pipeline is newer than the sync pipeline, so a healthy
sensor may legitimately show no events for a while. Rendering that as "No sensor detected" would
be a step backwards from today's "Running".

Treat a sensor as **stale** if `lastSeen` is older than ~15 minutes and mark it amber. If some
sensors are live and others stale, the domain is **Partially reporting** — that state is the whole
reason this field is an array, so please don't collapse it to a single boolean.

`eventCount` is useful in the expanded view: a sensor with a recent `lastSeen` but a low count is
up-but-quiet, which is a different problem from being down.

### 3. `Not Protected` should explain itself

Derive it, don't hardcode:

Evaluate in this order — the first match wins:

| condition | show |
|---|---|
| no sensor at all (per the table in §2) | **Not protected** — *no sensor reporting* |
| `enforcementMode === "monitor"` | **Monitoring only** — *not enforcing yet* |
| enforce, sensor syncing but no events yet | **Enforcing — no traffic seen yet** |
| enforce + events flowing | **Enforcing** |

> **Do not label this state "Protected" yet — known bug.**
>
> Enforcing with a live sensor does not mean anyone is actually covered. A domain with zero
> policies evaluates every authentication to "no policy covers this user" → allow, so nothing is
> challenged and nothing is blocked. Observed live on `authnull.lab`: sensor green, mode
> Enforcing, zero policies, badge reading "Protected" — the one thing this screen exists to stop
> it from doing.
>
> "Enforcing" is accurate with the data available today and needs no backend change. The real fix
> needs a policy-coverage count per domain, which cannot be added to `GetAllDomains` because
> `internal/policy` imports `internal/ad` and the reverse would be an import cycle. It will
> arrive as a separate call, joined on `adId`:
>
> ```
> POST /api/v1/policy/ad/domainCoverage  →  [{ "adId": 16, "policyCount": 0 }]
> ```
>
> Then: `policyCount === 0` → **Enforcing — no policies** (amber); otherwise **Protected**.

Note "no sensor at all" means the §2 bottom row (no sync AND no events), not simply
`sensors.length === 0`.

Make it a link to the directory's detail/settings so the next step is one click away.

### 4. Last sync

`lastSyncTime === null` → **Never synced**. Please guard this — the field genuinely comes back
null now and `new Date(null)` will render 1970.

### 5. Small

`corp.authnull…` truncates with no tooltip — add `title` or wrap.

---

## Don't do yet

**Leave the `MFA` column and the 3-dot menu alone.** The `Enable MFA` action is being reworked:
it currently writes a field that nothing reads, and approving a policy already sets it. It'll
become a read-only status in the next change. Adding UI around it now means redoing it.

---

## Testing

`test01` on alpha is a live domain with a real sensor. To exercise the other states:

- **never synced / no sensor** — `Corp AD` on alpha is already in this state
- **monitor vs enforce** — flip with the call in §1 (`adId` 16 is `test01` on alpha). The
  response echoes the stored value. Set it back to `"monitor"` when you're done; it applies
  immediately either way.
- **multiple sensors** — needs a second DC; mock the array for layout.

## Done when

- [ ] Mode is an interactive control on every row and switching it persists
- [ ] Switching to Enforcing asks for confirmation; no "re-download sensor.yml" instruction
- [ ] Sensor hostname + relative last-seen shown; multiple DCs don't collapse into one status
- [ ] Empty `sensors` with a recent `lastSyncTime` reads "Syncing — no auth events yet", NOT
      "No sensor detected" and NOT "Running"
- [ ] `lastSyncTime: null` renders "Never synced", not a 1970 or year-1 date
- [ ] Protection state explains its reason and links onward
- [ ] Long domain names don't truncate without a tooltip
