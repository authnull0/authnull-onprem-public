# The AD whitelist deny is retired

**Behaviour change, customer-visible, loosening.** An AD login that was previously refused may now
be allowed. Read this before upgrading a deployment that has AD enforcement switched on.

---

## What changed

`GetEffectivePolicy` used to return a sentinel — `user_enrolled_no_match` — when some approved
policy **targeted** a principal but none **covered the context** their login arrived over: the
wrong protocol, auth type, source address or destination SPN. `EvaluateAuth` turned that sentinel
into a **block**.

That is a whitelist: once any policy named you, you could authenticate only from the contexts a
policy described. Anything else was refused.

It is gone. A near miss now **allows**, and the reason is recorded on the decision row.

| | Before | After |
|---|---|---|
| No policy targets the principal | allow | allow |
| A policy targets them and covers this context | that policy's action | unchanged |
| **A policy targets them, none covers this context** | **block** | **allow, reason logged** |
| Policy JSON unreadable / tenant DB unreachable | refuse | refuse (unchanged) |

The last row is the line that has not moved and must not: **absence of a policy is `allow`;
inability to determine is `refuse`.** This change is entirely about the first of those.

## Why

**It was invisible.** No screen showed it, nothing configured it, and it applied to every domain in
a tenant at once. An admin looking at their policy list could not see the rule that was turning
their users away, because it was not in the list.

**It was easy to trigger by accident, and total when it fired.** Identity match includes
`matchAll`, so a single baseline *"MFA for everyone on this domain"* policy made **every principal
in the directory** a near miss for any context it did not cover. Combined with the old destination
rule — which skipped a destination-less policy whenever the event carried an SPN, and Kerberos
service tickets always carry one — a baseline-only tenant matched *nothing*. Switching enforcement
on then denied the entire directory. That destination bug is fixed, but the shape of the failure is
the argument: a default-deny nobody authored, nobody could see, and that fired on a matcher bug.

**The other channels disagreed with it.** RADIUS and Database both treat no-match as allow. Three
engines with three answers to the same question is how you get a forecast screen that tells an
admin one thing and enforcement doing another — which
[has already happened here once](internal/policy/service/auth_decision_service.go) with the
`"deny"` spelling.

## What you lose, and how to get it back

You lose a default-deny you may have been relying on. It is reproducible **as real policies**, which
is the point: per-domain, visible in the console, and reviewable.

Two shapes, depending on which question you are actually answering:

**Shape A — "deny anything no policy covers, on this domain."** One `matchAll` policy with action
`block`. *Broader than the old behaviour*: it also catches principals no policy targets, who were
previously allowed. This is usually what people mean by "default deny", and it is one row to review.

**Shape B — "reproduce the old behaviour exactly."** For each existing policy, a sibling at the same
identity scope with no context predicates and a high priority number. A principal is denied only if
some policy targets them — precisely the old rule. More rows, and they must be maintained alongside
the originals.

Both are authored by [`scripts/ad-whitelist-restore.sql`](scripts/ad-whitelist-restore.sql), which
also carries the two impact queries below. It is **not** in `db-init/migrations/`: everything there
is applied automatically to every org database on every start, and this script creates policies that
block logins. Run it by hand, per org database, per domain.

### Why authoring it works

The ordering in `sortADCandidates`:

```
scope rank first   users(0) < groups(1) < ous(2) < matchAll(3)
then priority      lower number first
then age           older first
```

Scope rank **outranks priority**, so a `matchAll` policy is a fallback whatever number it carries
(Shape A). Within one scope priority decides, so a sibling at 900 sits behind its original at 100
(Shape B). Both orderings are pinned by
[`ad_whitelist_retirement_test.go`](internal/policy/repo/ad_whitelist_retirement_test.go) — if
either changed, these policies would start swallowing logins the specific policies were written for,
and nothing in a policy list would look wrong.

## Before you upgrade

**1. Who could be affected (upper bound).** Principals targeted by at least one approved policy on
the domain — only these could ever have hit the deny. An upper bound: someone whose policy does
cover their usual context was never denied in practice. Section 1 of the script.

**2. Who actually was denied (observed).** Historical denials in `did.auth_logs`. Section 2 of the
script.

> **Caveat, stated because it would otherwise mislead you.** The lockout path
> (`did.blocked_principals`) also writes `decision=block` with no policy attached, so in rows
> written before this change a whitelist deny and a lockout are **not distinguishable**. Cross-check
> any principal against the lockout table before concluding the whitelist is what turned them away.

**3. If you restore a deny, put the domain in monitor mode first** and watch for a day. A block
policy that is wrong locks people out of their own directory. There is no `would_have_been` column —
that field exists only on the API response; in the table the pair is `decision` (what the policy
decided) and `applied_decision` (what the sensor was told), so a suppressed block is
`decision='block' AND applied_decision='allow'`. Section 6 of the script has the query.

## What you gain

**The outcome is explainable.** The near-miss reason now travels onto
`did.auth_logs.match_reason` — *"policy does not cover protocol `ntlm`"* — instead of only into a
container log. The question this change creates is *"a policy names me, so why was I not
challenged?"*, and it is answerable from the audit screen.

Only near misses are logged, not every allow. On a domain of any size most traffic is principals no
policy targets, and a row per Kerberos ticket for all of them buys nothing an admin would read while
making `did.auth_logs` grow without bound.

**All channels now answer the same way.** AD, RADIUS and Database agree: no covering policy is
allow, and a tenant who wants otherwise authors it.

## The Users screen was re-based onto this

`POST /api/v1/policy/ad/mfaCoverage` answers "which policy applies to these users, and would they
be challenged" for the MFA / Protected column. It read the same matcher, so retiring the whitelist
changed what it should say — and it had three ways of reporting `allow` that were not true.

| Situation | Was reported as | Now |
|---|---|---|
| Policy could not be evaluated | `allow` | `action: "unknown"` |
| Policy matched but could not be read | `allow` | `action: "unknown"` |
| A policy targets them, not this context | `allow`, "no policy covers this user" | `allow`, `targetedByPolicy: true`, reason |
| Domain is in monitor mode | `mfaRequired: true` | `appliedAction: "allow"`, `mfaRequired: false` |

Every one of those errs the same direction — toward the reassuring cell an admin glances past. The
last is the most misleading: the screen claimed people would be challenged on a domain that
challenges nobody.

New on the response: `enforcementMode` (per page), and per row `appliedAction` (what would
actually happen, after enforcement mode) alongside `action` (what the policy says), plus
`targetedByPolicy`. The `action`/`appliedAction` pair deliberately mirrors
`did.auth_logs.decision` / `applied_decision` — same distinction, same names, so a row and an
audit record read together. `mfaRequired` now follows `appliedAction`.

`appliedAction` is computed with the **same** monitor-mode predicate the live login path uses, not
a copy, and a test asserts the screen's answer equals what `applyEnforcementMode` does for every
action and both postures. That agreement is the only reason this endpoint is allowed to exist
rather than being a second decision engine.

**No UI change is forced.** Nothing consumes this endpoint yet — it is documented in
[`UI-HANDOFF.md`](UI-HANDOFF.md) §3a as the replacement for the stale `ad_users.mfa_flag`, and
that section now describes the new fields. Whoever builds the column should bind the badge to
`mfaRequired` or `appliedAction`, and must not render `"unknown"` as a green tick.

## Companion change

`POST /api/v1/policy/ad/simulate` — the enforcement forecast — is removed separately, in PR #29.
It evaluated policies through a second route into the matcher, which is the divergence a shared
matcher exists to prevent, and the forecast is the one an admin trusts right before turning
enforcement on. Its withdrawal note is [`UI-HANDOFF.md`](UI-HANDOFF.md) §3b.

The two land independently and in either order; neither depends on the other.

`ADMfaCoverage` — the MFA column on the Users screen — is unaffected by both.
