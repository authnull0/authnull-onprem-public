# Licence signing key — custody and switch-on

The licence signing key is held by the **CEO**.

Anyone holding it can issue unlimited Authnull licences. Losing it means **no existing
customer can ever renew**, because every licence already issued was signed by it and
there is no way to re-sign them with a different key. It is the most consequential
secret in the product.

This document is the procedure for generating it, getting the public half into the
build, and confirming the switch-on worked.

---

## 1. What the two halves are for

| | |
|---|---|
| `license.key` — **private** | signs customer licences. **CEO's machine only.** Never in git, never in an image, never in Slack or email, never on a build server. |
| `license.pub` — **public** | verifies them. Compiled into the on-premise binary. Not secret; publishing it costs nothing. |

The asymmetry is the point: a customer's deployment can *check* a licence but cannot
*create* one.

---

## 2. Generating it — CEO, once, ever

Run on a machine the CEO controls. Not on a build server, not on a shared box.

```sh
# Get the tool. Build from the repo, or ask engineering for a signed binary.
go build -o authnull-license ./cmd/authnull-license

# Generate. This is a one-time act.
./authnull-license keygen -out ~/authnull-license-keys
```

It writes two files and prints the exact build command engineering needs. It **refuses
to overwrite** an existing key, because regenerating silently invalidates every licence
ever issued and nothing would tell you until customers started failing.

### Storing the private key

Requirements, in order of importance:

1. **Findable in three years by someone who is not you.** The realistic failure is not
   theft, it is nobody knowing where it went after a laptop is replaced. A password
   manager entry owned by the company, or a sealed offline copy in a safe, both work. A
   file in `~/Downloads` does not.
2. **Not on a machine that syncs to a consumer cloud.** Check Desktop and Documents.
3. **A second copy in a different place.** Loss is a worse outcome than compromise here:
   compromise can be recovered from by rotating and reissuing, loss cannot.

### What to send engineering

Only the contents of `license.pub`. It is one line of base64 and it is not secret.

**If you are ever asked for `license.key`, or for the whole keys directory, the answer is
no.** Nothing in the build, the pipeline or the product needs it. Only the signing step
does, and that runs on your machine.

---

## 3. Compiling the public key into the on-premise build — engineering

```sh
docker build \
  --build-arg LICENSE_PUBLIC_KEY="$(cat license.pub)" \
  -t docker-repo-public.authnull.com/authnull-service:1.0.0-onprem .
```

The build log states which mode it produced:

```
build: licence enforcement ENABLED (public key compiled in)
build: licence enforcement disabled (no LICENSE_PUBLIC_KEY given)
```

**Tag it `-onprem`.** Two images that differ only in a compiled-in constant are
indistinguishable once pushed, and deploying the wrong one is either a silently
read-only console or a silently unlicensed customer.

### Why the SaaS build must not get the key

`LICENSE_PUBLIC_KEY` defaults to empty, and empty means **do not enforce**. Authnull's
own SaaS and reference deployments have no licence and never will; a key compiled into
those images would put every one of their consoles into read-only. Only the on-premise
build sets it.

---

## 4. Issuing a customer's licence — CEO, when a deal closes

```sh
./authnull-license sign \
    -key ~/authnull-license-keys/license.key \
    -customer "Acme Ltd" \
    -days 365 \
    -features ad,database,radius \
    -out acme.lic
```

`-features` takes any combination of `ad`, `database`, `radius`. Unknown names are
**rejected at issue time**, so a typo cannot produce a licence that verifies perfectly
and grants nothing.

Check what the customer will see before sending it:

```sh
./authnull-license show -pub ~/authnull-license-keys/license.pub -in acme.lic
```

```
customer:  Acme Ltd
expires:   2027-08-20
features:  ad,database,radius
state:     valid (licensed=true, 364 days remaining)
```

Then email `acme.lic` to the customer. They upload it in the console; it takes effect
immediately with no restart.

---

## 5. Confirming the switch-on worked

On a deployment running the `-onprem` image:

```sh
curl -s https://<their-host>/system/v1/health | jq .license
```

| Response | Meaning |
|---|---|
| `"state": "not_enforced"` | the key is **not** in this image — wrong tag deployed |
| `"state": "trial"` | key present, no licence installed, 30-day trial running |
| `"state": "valid"` | licence installed and current |
| `"state": "expiring"` | valid, inside the last 14 days |
| `"state": "expired"` | trial or licence ran out — console read-only |
| `"state": "invalid"` | a licence file is present but does not verify |

`not_enforced` on a customer deployment is the one to watch for: it means licensing is
doing nothing.

---

## 6. What expiry does, and does not do

**Expiry never blocks authentication.** MFA keeps working, pushes keep arriving, the DC
sensor and the RADIUS path are untouched. What stops is *administration*: the console
goes read-only, so no new policies, directories or users.

This is deliberate and enforced by a test. If expiry blocked logins, a late invoice
would become an outage on a customer's domain controllers — an outage we caused. If it
were ignored, nobody would pay. Read-only administration keeps the commercial lever
while costing the customer neither availability nor security.

An expired customer can **still upload a licence** — otherwise renewal would be
impossible without database access.

---

## 7. If the key is compromised

1. Generate a new keypair (a new directory; do not overwrite the old one).
2. Build and publish a new `-onprem` image with the new public key.
3. Re-sign and reissue every active customer's licence.
4. Customers upgrade the image and upload the new licence.

Every existing licence stops verifying at step 2, so **do not start until the reissues
are ready to send**. This is why the private key's storage matters more than its
strength.

## 8. If the key is lost

There is no recovery. Existing deployments keep working on the licences they already
have, but nothing further can be issued or renewed, and the sequence in §7 has to be
run for every customer at once. Keep the second copy.

---

Related: [LICENSING-PLAN.md](LICENSING-PLAN.md) for the programme, and
[ONPREM-PACKAGING-PLAN.md](ONPREM-PACKAGING-PLAN.md) for the package this ships in.
