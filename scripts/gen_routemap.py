#!/usr/bin/env python3
"""Generate ROUTE-MAPPING.md from routes_output.json (the live Gin engine dump)."""
import json, re
from collections import defaultdict

BASE = '/media/gandalf/New Volume/K1/authnull-service/'
routes = json.load(open(BASE + 'routes_output.json'))

# Classify each path into a group. Order matters: first match wins.
RULES = [
    (r'^/system/v1/health',                 'system — health'),
    (r'^/api/v1/pam/',                      'pam (canonical)'),
    (r'^/pam/api/v1/',                      'pam (UI alias)'),
    (r'^/api/v1/policyService/',            'policy (policyService alias)'),
    (r'^/api/v1/policy/',                   'policy'),
    (r'^/api/v1/dashboardService/',         'dashboard (dashboardService alias)'),
    (r'^/api/v1/dashboard/',                'dashboard'),
    (r'^/api/v1/databaseService/',          'database (databaseService alias)'),
    (r'^/api/v1/database/',                 'database'),
    (r'^/api/v1/serviceAccounts/',          'serviceaccounts'),
    (r'^/api/v1/service-accounts/',         'serviceaccounts (UI alias)'),
    (r'^/api/v1/tenants/tenants/',          'tenant (double-prefix alias)'),
    (r'^/api/v1/tenants/',                  'tenant + org (SSC alias)'),
    (r'^/api/v1/tenant/',                   'tenant'),
    (r'^/api/v1/issuer/',                   'issuer'),
    (r'^/api/v1/(did|credential|schema)/',  'issuer (short-path alias)'),
    (r'^/api/v1/wallet/',                   'wallet'),
    (r'^/api/v1/verifier/',                 'verifier'),
    (r'^/api/v1/user/',                     'user'),
    (r'^/api/v1/org/',                      'org'),
    (r'^/api/v1/endpoint/',                 'endpoint'),
    (r'^/api/v1/entra/',                    'entra'),
    (r'^/api/v1/ad/',                       'ad'),
    (r'^/api/v1/mfa/',                      'mfa'),
    (r'^/api/v1/dbconsole/|^/console/',     'dbconsole'),
    (r'^/api/v1/secretservice/',            'secretservice (stub)'),
    (r'^/api/v1/',                          'other /api/v1'),
    (r'^/ad/',                              'ad (root alias)'),
    (r'^/authentication/',                  'mfa (SSC /authentication alias)'),
    (r'^/authnz/',                          'authnz (proxy)'),
    (r'^/(okta|auth|mfa|saml|v1|passkey|push|sms|totp|provider|backToLogin|oauth2|emaptasaml|\.well-known)',
                                            'mfa (root paths)'),
    (r'^/ssc/',                             'ssc redirect'),
]


def group_of(path):
    for pat, name in RULES:
        if re.match(pat, path):
            return name
    return 'ungrouped'


groups = defaultdict(list)
for r in routes:
    groups[group_of(r['path'])].append(r)

order = [n for _, n in RULES]
seen, ordered = set(), []
for n in order:
    if n in groups and n not in seen:
        ordered.append(n); seen.add(n)
for n in sorted(groups):
    if n not in seen:
        ordered.append(n)

# collision check
pairs = [(r['method'], r['path']) for r in routes]
dupes = {p for p in pairs if pairs.count(p) > 1}

out = []
out.append('# ROUTE-MAPPING.md — registered HTTP routes')
out.append('')
out.append('**Generated** from the live Gin engine. Do not hand-edit; regenerate with:')
out.append('')
out.append('```sh')
out.append('ROUTE_DUMP=routes_output.json go test ./cmd/authnull-service/ -run TestDumpRoutes')
out.append('python3 scripts/gen_routemap.py   # or re-run the generator used to produce this file')
out.append('```')
out.append('')
out.append('`routes_output.json` is the machine-readable form of the same dump.')
out.append('')
out.append('## Actual URL scheme')
out.append('')
out.append('Everything is mounted under **`/api/v1`** by `RegisterAllRoutes` in')
out.append('[cmd/authnull-service/routes.go](cmd/authnull-service/routes.go), plus a set of')
out.append('root-level and legacy aliases kept for the admin UI and the self-service console.')
out.append('')
out.append('> **Correction to earlier revisions of this document.** Previous versions of this')
out.append('> file specified a `/{tier}/v1/{service}/{action}` scheme with `admin` / `ssc` /')
out.append('> `tenant` tiers and listed 486 routes. **That scheme was never implemented.** No')
out.append('> `/admin/v1`, `/ssc/v1` or `/tenant/v1` group exists anywhere in the Go source.')
out.append('> The `// OLD:` / `// NEW:` comments still present above many route registrations')
out.append('> refer to that abandoned plan and describe paths that are not served. This')
out.append('> document now reflects what the engine actually registers.')
out.append('')
out.append('**Total registered routes: %d**' % len(routes))
out.append('')
by_method = defaultdict(int)
for r in routes:
    by_method[r['method']] += 1
out.append('| Method | Count |')
out.append('|---|---|')
for m in sorted(by_method):
    out.append('| %s | %d |' % (m, by_method[m]))
out.append('')
out.append('The count is higher than the number of distinct handlers because several modules')
out.append('are deliberately registered on more than one prefix (for example `pam` is mounted')
out.append('at both `/api/v1/pam` and `/pam/api/v1`, and `tenant` at `/api/v1/tenant`,')
out.append('`/api/v1/tenants` and `/api/v1/tenants/tenants`).')
out.append('')
out.append('**Duplicate method+path check: %s**' % (
    'PASS — none' if not dupes else 'FAIL — %d duplicates' % len(dupes)))
out.append('')
out.append('Gin panics on a duplicate method+path registration, so a booting server is itself')
out.append('proof of no collisions. `TestRegisterAllRoutes` covers this in CI.')
out.append('')
out.append('## Groups')
out.append('')
out.append('| Group | Routes |')
out.append('|---|---|')
for n in ordered:
    out.append('| %s | %d |' % (n, len(groups[n])))
out.append('')

for n in ordered:
    rs = sorted(groups[n], key=lambda r: (r['path'], r['method']))
    out.append('## %s  (%d)' % (n, len(rs)))
    out.append('')
    out.append('| Method | Path |')
    out.append('|---|---|')
    for r in rs:
        out.append('| %s | `%s` |' % (r['method'], r['path']))
    out.append('')

open(BASE + 'ROUTE-MAPPING.md', 'w').write('\n'.join(out) + '\n')
print('wrote ROUTE-MAPPING.md: %d routes, %d groups' % (len(routes), len(ordered)))
print('ungrouped:', len(groups.get('ungrouped', [])))
for r in groups.get('ungrouped', [])[:15]:
    print('   ', r['method'], r['path'])
