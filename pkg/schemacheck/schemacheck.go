// Package schemacheck verifies at startup that the columns this service writes actually exist.
//
// # WHY THIS EXISTS
//
// did.auth_logs held zero rows in every database for months. policy/repo LogAuthDecision
// writes decision, policy_id, policy_name, match_reason and session_id; none of those columns
// existed, because the migration that adds them lived in internal/policy/db/migrations, which
// nothing replays. Every insert failed. Nothing surfaced, because the caller treats audit
// logging as best-effort and swallows the error — correctly, since gateway latency must not
// depend on an audit write. The AD challenge-context correlation failed the same way, for the
// same reason, and also failed silently by design.
//
// That is the pattern worth defending against: a schema gap that only manifests as a feature
// quietly doing nothing. Tests do not catch it (they never touch a real database), code review
// does not catch it (the SQL is correct — the schema is not), and monitoring does not catch it
// (nothing errors). The only reliable moment to notice is startup, where the full column list
// can be compared against the database in one cheap query.
//
// NOT FATAL, deliberately. A missing column degrades one feature; refusing to boot takes down
// authentication for everything. The check logs loudly and returns its findings so a caller
// can surface them on a health endpoint.
package schemacheck

import (
	"fmt"
	"log"
	"sort"
	"strings"

	"gorm.io/gorm"
)

// Requirement is one table and the columns some writer depends on.
//
// Why is mandatory in spirit: a bare list of column names tells whoever reads the log nothing
// about what breaks. Naming the caller turns "column missing" into "the decision log will not
// record anything".
type Requirement struct {
	Table   string
	Columns []string
	Why     string
}

// Problem is a requirement that the database does not satisfy.
type Problem struct {
	Database string
	Table    string
	Missing  []string
	Why      string
}

func (p Problem) String() string {
	return fmt.Sprintf("%s: did.%s is missing %s — %s",
		p.Database, p.Table, strings.Join(p.Missing, ", "), p.Why)
}

// Requirements is the manifest.
//
// Deliberately NOT generated from the GORM models. Most models carry columns that are optional,
// legacy, or written only by one code path that may itself be dead — a generated list would be
// mostly noise and would be ignored within a week. This is the hand-picked set where a missing
// column means a shipped feature silently does nothing, which is the failure this package
// exists to catch. Keep it short enough that every entry is worth reading.
var Requirements = []Requirement{
	{
		Table: "auth_logs",
		Columns: []string{
			"decision", "policy_id", "policy_name", "match_reason", "session_id",
			"mfa_outcome", "applied_decision", "enforcement_mode", "ad_challenge_id",
		},
		Why: "policy LogAuthDecision writes these; without them every decision row is " +
			"silently dropped and the AD challenge-context correlation finds nothing",
	},
	{
		Table:   "ad_gateways",
		Columns: []string{"gateway_id", "mode", "fallback", "dc_hostname"},
		Why: "the generated sensor.yml carries mode and fallback_action from these; " +
			"without them the DC sensor gets a config that does not match the dashboard",
	},
	{
		Table:   "blocked_principals",
		Columns: []string{"principal", "domain", "org_id"},
		Why:     "/ad/BlockPrincipal, /ad/UnblockPrincipal and /ad/GetBlockedPrincipals all fail without this table",
	},
	{
		Table:   "ad_group_nesting",
		Columns: []string{"child_group_id", "parent_group_id"},
		Why:     "nested AD group membership; without it a user in a nested group matches no policy",
	},
	{
		Table: "mfa_devices",
		// public_key / public_key_alg were MISSING from this list, and missing from the alpha
		// database, and this check reported clean anyway. They hold the device's ECDSA key:
		// without them enrollment cannot write a key and no signature can be verified, so the
		// entire Authenticator flow is dead while every other table looks right. The lesson is
		// that a manifest which omits a column is worse than no manifest, because it converts
		// "unknown" into a false all-clear.
		Columns: []string{
			"public_key", "public_key_alg", "key_id", "biometric_public_key",
			"push_enabled", "push_transport", "push_token",
		},
		Why: "the device's signing key and its id; without these enrollment cannot store a key " +
			"and every signed device call and challenge response fails verification",
	},
	{
		Table:   "mfa_device_identities",
		Columns: []string{"push_enabled", "require_biometric", "display_name"},
		Why:     "per-account push and biometric preferences; without them the app's toggles silently do nothing",
	},
	{
		Table:   "mfa_push_activity",
		Columns: []string{"flow", "challenge_ref", "fetch_token_sha256", "risk_level", "status"},
		Why:     "push challenge context and history; without it getChallenge cannot authenticate a fetch token",
	},
	{
		Table: "jump_server",
		// Liveness, not administrative state: status is what a person set, these are what
		// the proxy last reported. Absent, the heartbeat write fails on every beat and the
		// console shows every proxy as never-seen -- which reads as "the proxies are down"
		// rather than "the migration did not run".
		Columns: []string{"last_seen_at", "proxy_version"},
		Why: "the SSH proxy heartbeats into these, and the console reports a proxy as live " +
			"from last_seen_at rather than from anything an administrator declared",
	},
	{
		Table: "user_ssh_keys",
		// revoked_at earns its place here as much as fingerprint does. Without the column the
		// resolver's "AND revoked_at IS NULL" is a syntax error and every lookup fails, which is
		// at least loud; with the table absent entirely the proxy denies every connection and the
		// only symptom is that SSH stopped working for everyone at once.
		Columns: []string{"org_id", "user_id", "fingerprint", "public_key", "last_used_at", "revoked_at"},
		Why: "the SSH proxy resolves an offered key's fingerprint here and has no other notion of " +
			"identity; without this table (migration 015) every SSH connection is denied",
	},
}

// Verify reports which requirements the database does not satisfy.
//
// One query for every requirement together, rather than one per table: this runs against every
// org database at startup, and a per-table round trip would make boot time scale with the
// tenant count.
//
// A table that does not exist reports every one of its columns as missing, which reads
// correctly — "blocked_principals is missing principal, domain, org_id" is true, and the fix is
// the same either way.
func Verify(db *gorm.DB, dbName string) []Problem {
	if db == nil {
		return []Problem{{Database: dbName, Table: "*", Missing: []string{"(no connection)"},
			Why: "the database could not be reached, so nothing could be verified"}}
	}

	tables := make([]string, 0, len(Requirements))
	for _, r := range Requirements {
		tables = append(tables, r.Table)
	}

	type row struct{ TableName, ColumnName string }
	var rows []row
	if err := db.Raw(`
		SELECT table_name, column_name FROM information_schema.columns
		 WHERE table_schema = 'did' AND table_name IN ?`, tables).Scan(&rows).Error; err != nil {
		log.Printf("schemacheck: could not read information_schema for %s (skipping): %v", dbName, err)
		return nil
	}

	present := map[string]map[string]bool{}
	for _, r := range rows {
		if present[r.TableName] == nil {
			present[r.TableName] = map[string]bool{}
		}
		present[r.TableName][r.ColumnName] = true
	}

	var problems []Problem
	for _, req := range Requirements {
		var missing []string
		for _, col := range req.Columns {
			if !present[req.Table][col] {
				missing = append(missing, col)
			}
		}
		if len(missing) > 0 {
			sort.Strings(missing)
			problems = append(problems, Problem{
				Database: dbName, Table: req.Table, Missing: missing, Why: req.Why,
			})
		}
	}
	return problems
}

// VerifyAll checks every database and logs what it finds.
//
// Returns the problems so a caller can also surface them on a health endpoint — a startup log
// line is easy to miss, and this is precisely the class of fault that goes unnoticed.
func VerifyAll(databases map[string]*gorm.DB) []Problem {
	names := make([]string, 0, len(databases))
	for name := range databases {
		names = append(names, name)
	}
	sort.Strings(names) // deterministic log order, so two boots are diffable

	var all []Problem
	for _, name := range names {
		all = append(all, Verify(databases[name], name)...)
	}

	if len(all) == 0 {
		log.Printf("schemacheck: %d database(s) match the expected schema", len(databases))
		return nil
	}

	// Loud, and repeated per problem rather than summarised: each line names a feature that
	// is currently doing nothing, and that is what someone reading the log needs.
	log.Printf("schemacheck: ==================== SCHEMA DRIFT ====================")
	for _, p := range all {
		log.Printf("schemacheck: %s", p)
	}
	log.Printf("schemacheck: %d problem(s). Migrations live in db-init/migrations/ and are "+
		"replayed on every boot; internal/*/db/migrations is inert and is not applied.", len(all))
	log.Printf("schemacheck: ======================================================")
	return all
}
