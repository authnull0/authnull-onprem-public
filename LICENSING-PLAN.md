# On-premise licensing — the plan

Customers download Authnull from a public repository and install it themselves. Licensing
is what makes that free for 30 days and paid after.

**Products covered: AD MFA, Database MFA, RADIUS MFA — sold in any combination.**
A customer can buy one, any two, or all three, and the software enforces exactly what
they bought.

Status: 4 of 7 steps built. Nothing is switched on yet — see step 6.

---

## 1. What a licence actually is

**A signed file.** A small file saying "Acme Ltd may use this until 17 Aug 2027, features:
AD and Database." Authnull stamps it with a secret key; the software carries only the half
that checks the stamp. Customers cannot produce their own, and editing one breaks the
stamp.

**Checked offline.** No internet needed. On-premise servers are frequently locked away
with no outbound access, so the check happens entirely on the customer's machine.

**Free for 30 days.** A fresh install has no licence. It records the install date and runs
free for a month, with no action required from us.

**Expiry never blocks logins.** When a licence lapses, staff keep logging in and MFA keeps
working. Only the admin console goes read-only — no new policies until they pay.

That last point is the decision everything else rests on. The alternatives were both bad:
blocking logins turns a late invoice into a domain-wide outage we caused, and ignoring
expiry means nobody ever pays. Read-only administration keeps the commercial lever while
the customer loses neither availability nor security.

---

## 2. Selling the three products separately

The licence lists which products it covers. The software checks that list in two places:

- **Product-specific screens.** Registering a database host needs Database. AD directory
  discovery and enrolment invites need AD. A customer with an AD-only licence gets a clear
  refusal on database configuration: *"your licence does not include Database MFA"* — and
  the licence itself still reports as valid, because it is.
- **Policy authoring.** AD, database and RADIUS policies are all created through the same
  screens, with the type chosen in the form. The licence check there reads the policy type
  rather than the page, so a customer without Database cannot create a database policy.

Every combination is tested: AD only, Database only, two of three, all three.

**One piece still to wire:** the per-policy-type check exists and is tested, but is not yet
called from the policy save path. Until it is, a customer with an AD-only licence could
create a database policy — which would do nothing for them, since they have no database
licence and the module's screens are refused. Small piece of work, listed in step 5.

---

## 3. What the customer experiences

1. Signs up on the website, gets the download link
2. Installs it — the 30-day trial starts by itself, nothing needed from us
3. From day 16 the console warns: *"trial ends in 14 days"*
4. They buy. We run one command to produce their licence file and email it
5. They upload it in the console — takes effect immediately, no restart
6. A year later, the same reminder and the same upload

---

## 4. The seven steps

### Step 1 — Agree what expiry does · **Done**

The decision above. Recorded in code and protected by an automated test, so it cannot be
reversed by accident.

### Step 2 — Build the licence checker · **Done**

Reads the file, verifies the stamp, checks the date and the product list, runs the 30-day
trial clock, and switches the console to read-only when it lapses.

- Detects an edited file and says so, rather than failing vaguely
- Survives being reformatted by a text editor — a customer opening the file must not
  invalidate it
- 27 automated tests, including ones asserting that logins can never be blocked by
  licensing and that every product combination is enforced

### Step 3 — Build the tool that issues licences · **Done**

An internal command-line tool. One command produces a customer's licence file when a deal
closes.

- Creates the signing key, and refuses to overwrite it — regenerating it would invalidate
  every licence ever issued
- Rejects typos in product names, so we cannot issue a licence that quietly grants nothing
- Can preview exactly what the customer will see before we send it

### Step 4 — Storage and the upload API · **Done**

The licence is stored in the customer's database rather than on disk, because containers
are wiped and recreated on every upgrade — a file would vanish and they would look
unlicensed again.

- Admin-only upload, verified before anything is saved
- Every upload is kept, so uploading the wrong file over a good licence is recoverable
- An expired customer can still upload, otherwise renewal would be impossible

### Step 5 — Console screens · **Next — needs the UI team**

The only part a customer sees. The API they build against is finished.

- A licence page: who it belongs to, when it expires, which products, upload button
- Reminder banners from day 16 and day 25 of the trial
- A clear message when the console is read-only, saying MFA is still protecting them
- Backend follow-up: call the per-product check from the policy save path (§2)

Estimate: 3–4 days of UI work, half a day of backend.

### Step 6 — Switch it on · **Not started**

Licensing is deliberately dormant today. It does nothing until we build the on-premise
package with the signing key in it, which is what keeps our own SaaS and test systems
unaffected while this is finished.

- Generate the real signing key and store it somewhere findable in three years
- Build the on-premise image with the checking key compiled in
- Apply two small database changes
- Install on a clean machine and walk the whole journey end to end

### Step 7 — The sales process around it · **Not started, needs decisions**

The software is only half of it. Someone has to issue licences when deals close and chase
renewals.

---

## 5. Decisions needed

None of these block steps 5 or 6, but step 7 cannot start without them.

**Where does the signing key live, and who holds it?** Anyone with it can issue unlimited
licences. Losing it means no customer can ever renew. This is the one that needs an owner
before we generate the real key.

**Who issues a licence when a deal closes?** It is one command, but it needs a named owner
and a turnaround expectation.

**How are the three products priced?** The software supports any combination. What the
bundles are, and what they cost, is a pricing decision rather than a build one.

**Renewal reminders by email as well as in-product?** Console-only is built. Email needs a
contact list and a system to send from.

---

## 6. What this deliberately does not do

**The trial can be reset.** A customer can wipe the install and start another 30 days.
Every defence against this is defeatable by anyone determined, while breaking legitimate
backups and server migrations for honest customers. The trial generates leads; it is not
anti-piracy.

**The clock can be turned back.** They own the server, so they own its date. We can detect
it, not prevent it.

**Licensing never stops authentication.** A design commitment, enforced by an automated
test. If we ever want expiry to block logins, that is a deliberate reversal and should be
argued on its merits.

**Database and RADIUS have open issues of their own.** They are licensable and sellable
from day one, as agreed — the underlying fixes are tracked separately in
[DATABASE-MFA-FLOW.md](DATABASE-MFA-FLOW.md) and the RADIUS packaging work, and do not
block this.

---

## 7. Where the code is

| Piece | Location |
|---|---|
| Licence checking, trial, product entitlement | `pkg/license/` |
| Boot wiring and the read-only switch | `cmd/authnull-service/license.go` |
| Upload and status endpoints | `cmd/authnull-service/license_handler.go` |
| Issuing tool | `cmd/authnull-license/` |
| Database changes | `db-init/migrations/011_*.sql`, `012_*.sql` |
| On-premise packaging | [ONPREM-PACKAGING-PLAN.md](ONPREM-PACKAGING-PLAN.md) |
