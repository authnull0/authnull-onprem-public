-- Restore the retired AD whitelist deny, for one domain, as real policies.
--
-- NOT A MIGRATION. This file is deliberately NOT in db-init/migrations/: everything there is
-- applied automatically to the master and every org database on every start, and this script
-- CREATES POLICIES THAT BLOCK LOGINS. It must be run by hand, per org database, per domain, by
-- someone who has decided they want this.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT CHANGED
--
-- GetEffectivePolicy used to return a sentinel, "user_enrolled_no_match", when some approved
-- policy targeted a principal but none covered the context their login arrived over -- the wrong
-- protocol, auth type, source or destination. EvaluateAuth turned that into a BLOCK.
--
-- That is a whitelist: once any policy named you, you could authenticate only from the contexts
-- a policy described. It is retired. A near miss now ALLOWS, and the reason is recorded on the
-- decision row in did.auth_logs.match_reason so the outcome is still explainable.
--
-- Two reasons it went:
--
--   * It was invisible. No screen showed it, nothing configured it, and it applied to every
--     domain in the tenant at once.
--   * It was easy to trigger by accident and total when it fired. Identity match includes
--     matchAll, so a single baseline "MFA for everyone on this domain" policy made every
--     principal in the directory a near miss for any context it did not cover. Combined with the
--     old destination rule, which skipped a destination-less policy whenever the event carried an
--     SPN, a baseline-only tenant matched NOTHING -- and switching enforcement on denied the
--     entire directory.
--
-- ---------------------------------------------------------------------------------------------
-- HOW TO GET IT BACK
--
-- Author what the sentinel used to do implicitly. Two shapes, and which you want depends on the
-- question you are actually answering:
--
--   SHAPE A -- "deny anything no policy covers, on this domain"
--     One matchAll policy with action block. Broader than the sentinel: it also catches
--     principals NO policy targets, who were previously allowed. Usually what people mean when
--     they say "default deny", and one row to review.
--
--   SHAPE B -- "reproduce the old behaviour exactly"
--     For each existing policy, a sibling at the same identity scope with no context predicates
--     and a high priority number. A principal is denied only if some policy targets them, which
--     is precisely the old rule. More rows, and they have to be maintained alongside the
--     originals.
--
-- WHY EITHER WORKS -- the ordering in loadADCandidates / sortADCandidates:
--
--     scope rank first   users(0) < groups(1) < ous(2) < matchAll(3)
--     then priority      lower number first
--     then age           older first
--
-- Scope rank OUTRANKS priority, so a matchAll policy is a fallback whatever number it carries
-- (Shape A). Within one scope priority decides, so a sibling at 900 sits behind its original at
-- 100 (Shape B). Both are pinned by tests in internal/policy/repo/ad_whitelist_retirement_test.go
-- -- if either ordering ever changed, these policies would start swallowing logins the specific
-- policies were written for, and nothing in a policy list would look wrong.
--
-- ---------------------------------------------------------------------------------------------
-- HOW TO RUN
--
--   psql "$ORG_DB_URL"          -- the ORG database, not the master
--   \set domain 'authnull.lab'
--   \i scripts/ad-whitelist-restore.sql
--
-- Nothing below writes until you uncomment a section. Read the impact queries first.
--
-- VALIDATION STATUS -- READ THIS BEFORE RUNNING SECTION 3 OR 4.
--
-- Sections 3 and 4 have NOT been executed against a live database. Every table, column and
-- function they touch was checked against db-init/01_schema.sql and db-init/migrations/007
-- (that check found and fixed one real error: would_have_been is a response field, not a
-- column), and the ordering they rely on is covered by tests. But checked is not the same as
-- run, and this script creates policies that block logins.
--
-- So dry-run them. Both sections are already wrapped in BEGIN/COMMIT: change the COMMIT to
-- ROLLBACK, run it, read the row counts, and only then put COMMIT back. Postgres will report a
-- bad column or a malformed jsonb before it reports anything else, and a rollback costs nothing.
--
--   BEGIN; <the INSERT> ROLLBACK;   -- then re-read section 1: the policy must NOT be there
--
-- REQUIRES db-init/migrations/007_schema_reconciliation.sql, which is what adds decision,
-- applied_decision, policy_id, policy_name and match_reason to did.auth_logs. On a deployment
-- that has never run it, section 2 errors on a missing column rather than returning nothing --
-- which is the correct failure: "no denials found" and "cannot tell" must not look alike.

\if :{?domain}
\else
  \echo '*** set :domain first, e.g.  \set domain ''authnull.lab'''
  \quit
\endif

\echo ''
\echo '=== 1. WHO IS AFFECTED (upper bound) ================================================='
\echo 'Principals targeted by at least one approved policy on this domain. Only these could'
\echo 'ever have hit the whitelist deny; a principal no policy targets was always allowed.'
\echo 'This is an UPPER BOUND -- someone whose policy does cover their usual context was never'
\echo 'denied in practice.'
\echo ''

SELECT p.policy_name,
       p.priority,
       CASE
         WHEN jsonb_array_length(coalesce(p.policy_json->'ad'->'users',  '[]'::jsonb)) > 0 THEN 'users'
         WHEN jsonb_array_length(coalesce(p.policy_json->'ad'->'groups', '[]'::jsonb)) > 0 THEN 'groups'
         WHEN jsonb_array_length(coalesce(p.policy_json->'ad'->'ous',    '[]'::jsonb)) > 0 THEN 'ous'
         WHEN coalesce((p.policy_json->'ad'->>'matchAll')::boolean, false)              THEN 'matchAll (WHOLE DIRECTORY)'
         ELSE 'nothing -- targets no principal'
       END                                        AS targets,
       coalesce(p.policy_json->>'policyFlow', '(unset)') AS action,
       -- The context predicates are what turned a targeted principal into a near miss. A policy
       -- with none of these could never cause a whitelist deny.
       coalesce(p.policy_json->'ad'->'sources',      '[]'::jsonb) AS sources,
       coalesce(p.policy_json->'ad'->'destinations', '[]'::jsonb) AS destinations,
       coalesce(p.policy_json->'protocolControl',    '{}'::jsonb) AS protocol_control,
       coalesce(p.policy_json->'authTypes',          '[]'::jsonb) AS auth_types
  FROM did.auth_policy_json p
 WHERE p.status = 'Approved'
   AND p.policy_json ? 'ad'
   AND lower(p.policy_json->'ad'->>'domain') = lower(:'domain')
 ORDER BY p.priority, p.policy_name;

\echo ''
\echo '=== 2. WHAT WAS ACTUALLY DENIED (observed) ==========================================='
\echo 'Historical whitelist denials. CAVEAT: the lockout path (did.blocked_principals) also'
\echo 'writes decision=block with no policy attached, so these two are not distinguishable in'
\echo 'rows written before this change. Cross-check any principal here against the lockout'
\echo 'table before concluding the whitelist is what turned them away.'
\echo ''

SELECT l.ad_user,
       l.protocol,
       count(*)                                          AS denials,
       to_timestamp(max(l.timestamp))                     AS last_seen,
       count(DISTINCT l.destination_endpoint)             AS distinct_destinations
  FROM did.auth_logs l
 WHERE l.decision = 'block'
   AND l.policy_id IS NULL          -- a policy-driven block always carries policy_id
   AND lower(l.ad_domain) = lower(:'domain')
 GROUP BY l.ad_user, l.protocol
 ORDER BY denials DESC
 LIMIT 100;

\echo ''
\echo '=== 3. RESTORE -- SHAPE A: deny anything no policy covers ============================'
\echo 'Commented out. Uncomment to apply. Creates ONE policy.'
\echo ''
\echo 'Priority 9000 and matchAll: it loses to every scoped policy on scope rank, and to other'
\echo 'matchAll policies on priority, so it is genuinely last. Status Approved because an'
\echo 'unapproved policy is not a candidate -- if you want to review it in the console first,'
\echo 'insert it as Draft and approve it there.'
\echo ''

-- BEGIN;
--
-- INSERT INTO did.auth_policy_json
--        (id, policy_name, policy_type, policy_json, status, priority, is_baseline,
--         generated_by, created_at, updated_at, created_by, version)
-- SELECT gen_random_uuid(),
--        'Deny uncovered contexts -- ' || :'domain',
--        'AD',
--        jsonb_build_object(
--          'policyName',  'Deny uncovered contexts -- ' || :'domain',
--          'policyType',  'AD',
--          'policyFlow',  'block',
--          -- No sources, destinations, authTypes or protocolControl: this policy must cover
--          -- EVERY context, or it becomes a near miss itself and denies nothing.
--          'ad', jsonb_build_object(
--                  'domain',   lower(:'domain'),
--                  'matchAll', true,
--                  'users',    '[]'::jsonb,
--                  'groups',   '[]'::jsonb,
--                  'ous',      '[]'::jsonb),
--          'permissions', jsonb_build_object('allowed', true)),
--        'Approved',
--        9000,
--        false,
--        'Manual',
--        now(), now(),
--        '00000000-0000-0000-0000-000000000000',
--        1
--  WHERE NOT EXISTS (   -- idempotent: re-running must not stack duplicates
--        SELECT 1 FROM did.auth_policy_json e
--         WHERE e.policy_type = 'AD'
--           AND e.policy_name = 'Deny uncovered contexts -- ' || :'domain');
--
-- COMMIT;

\echo ''
\echo '=== 4. RESTORE -- SHAPE B: reproduce the old rule exactly ============================'
\echo 'Commented out. Creates ONE SIBLING PER EXISTING POLICY. Review section 1 first: if any'
\echo 'policy there targets matchAll, its sibling denies the whole directory for every context'
\echo 'no other policy covers, and Shape A is the honest way to say that.'
\echo ''

-- BEGIN;
--
-- INSERT INTO did.auth_policy_json
--        (id, policy_name, policy_type, policy_json, status, priority, is_baseline,
--         generated_by, created_at, updated_at, created_by, version)
-- SELECT gen_random_uuid(),
--        'Deny uncovered -- ' || p.policy_name,
--        'AD',
--        jsonb_build_object(
--          'policyName', 'Deny uncovered -- ' || p.policy_name,
--          'policyType', 'AD',
--          'policyFlow', 'block',
--          -- Same identity scope, NO context predicates. Copying sources/destinations here
--          -- would reproduce the original's blind spot and deny nothing extra.
--          'ad', jsonb_build_object(
--                  'domain',   lower(:'domain'),
--                  'adId',     p.policy_json->'ad'->'adId',
--                  'users',    coalesce(p.policy_json->'ad'->'users',  '[]'::jsonb),
--                  'groups',   coalesce(p.policy_json->'ad'->'groups', '[]'::jsonb),
--                  'ous',      coalesce(p.policy_json->'ad'->'ous',    '[]'::jsonb),
--                  'matchAll', coalesce((p.policy_json->'ad'->>'matchAll')::boolean, false),
--                  'excludeServiceAccounts',
--                      coalesce((p.policy_json->'ad'->>'excludeServiceAccounts')::boolean, false)),
--          'permissions', jsonb_build_object('allowed', true)),
--        'Approved',
--        9000,
--        false,
--        'Manual',
--        now(), now(),
--        '00000000-0000-0000-0000-000000000000',
--        1
--   FROM did.auth_policy_json p
--  WHERE p.status = 'Approved'
--    AND p.policy_json ? 'ad'
--    AND lower(p.policy_json->'ad'->>'domain') = lower(:'domain')
--    -- A policy with no context predicates already covers everything it targets, so it can
--    -- never produce a near miss and needs no sibling.
--    AND (jsonb_array_length(coalesce(p.policy_json->'ad'->'sources',      '[]'::jsonb)) > 0
--      OR jsonb_array_length(coalesce(p.policy_json->'ad'->'destinations', '[]'::jsonb)) > 0
--      OR jsonb_array_length(coalesce(p.policy_json->'authTypes',          '[]'::jsonb)) > 0
--      OR coalesce(p.policy_json->'protocolControl', '{}'::jsonb) <> '{}'::jsonb)
--    -- Never sibling a sibling.
--    AND p.policy_name NOT LIKE 'Deny uncovered%'
--    AND NOT EXISTS (
--        SELECT 1 FROM did.auth_policy_json e
--         WHERE e.policy_type = 'AD'
--           AND e.policy_name = 'Deny uncovered -- ' || p.policy_name);
--
-- COMMIT;

\echo ''
\echo '=== 5. UNDO =========================================================================='
\echo 'Either shape is removable by name. Do this before re-running with different choices.'
\echo ''

-- DELETE FROM did.auth_policy_json
--  WHERE policy_type = 'AD'
--    AND (policy_name = 'Deny uncovered contexts -- ' || :'domain'
--      OR policy_name LIKE 'Deny uncovered -- %')
--    AND lower(policy_json->'ad'->>'domain') = lower(:'domain');

\echo ''
\echo '=== 6. AFTER APPLYING ================================================================'
\echo 'Put the domain in MONITOR mode first and watch for a day. A block policy that is wrong'
\echo 'locks people out of their own directory, and monitor mode is the only way to find that'
\echo 'out before they do.'
\echo ''
\echo 'There is no would_have_been COLUMN -- that field exists only on the API response. In the'
\echo 'table the pair is decision (what the policy decided) and applied_decision (what the'
\echo 'sensor was told), so a suppressed block is decision=block with applied_decision=allow:'
\echo ''
\echo '  SELECT ad_user, protocol, decision, applied_decision, policy_name, match_reason,'
\echo '         to_timestamp(timestamp) AS at'
\echo '    FROM did.auth_logs'
\echo '   WHERE lower(ad_domain) = lower(:''domain'')'
\echo '     AND decision = ''block'' AND applied_decision = ''allow'''
\echo '   ORDER BY timestamp DESC LIMIT 50;'
\echo ''
\echo 'Then flip to enforce only once that list holds nobody you did not intend.'
\echo ''
