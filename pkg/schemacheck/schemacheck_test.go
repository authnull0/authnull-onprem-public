package schemacheck

import (
	"strings"
	"testing"
)

// A nil handle must report a problem rather than silently passing. Reporting "all good" for a
// database that could not be reached is worse than not checking at all — it is a false
// assurance about exactly the thing being verified.
func TestNilConnectionIsAProblemNotASilentPass(t *testing.T) {
	problems := Verify(nil, "alpha")
	if len(problems) == 0 {
		t.Fatal("an unreachable database must be reported, not treated as verified")
	}
	if problems[0].Database != "alpha" {
		t.Errorf("the problem must name the database, got %q", problems[0].Database)
	}
}

// Every requirement has to carry a Why. A log line reading "auth_logs is missing decision"
// tells an operator nothing about what stopped working; the Why is the whole value of the
// manifest, and an entry without one is a line someone will scroll past.
func TestEveryRequirementExplainsWhatBreaks(t *testing.T) {
	if len(Requirements) == 0 {
		t.Fatal("the manifest is empty")
	}
	seen := map[string]bool{}
	for _, r := range Requirements {
		if strings.TrimSpace(r.Table) == "" {
			t.Error("a requirement has no table")
		}
		if len(r.Columns) == 0 {
			t.Errorf("%s lists no columns", r.Table)
		}
		if len(strings.TrimSpace(r.Why)) < 20 {
			t.Errorf("%s has no useful Why (%q) — the log line would not say what breaks", r.Table, r.Why)
		}
		if seen[r.Table] {
			t.Errorf("%s appears twice; merge the entries so one log line covers the table", r.Table)
		}
		seen[r.Table] = true
		// The manifest is queried with table_schema='did' and bare table names, so a
		// schema-qualified entry here silently matches nothing and the check passes for a
		// table it never looked at.
		if strings.Contains(r.Table, ".") {
			t.Errorf("%s must be a bare table name, not schema-qualified", r.Table)
		}
	}
}

// The manifest must keep covering the failure that motivated this package: LogAuthDecision
// writing columns that did not exist, so did.auth_logs stayed empty in every database.
func TestManifestCoversTheDecisionLog(t *testing.T) {
	var cols []string
	for _, r := range Requirements {
		if r.Table == "auth_logs" {
			cols = r.Columns
		}
	}
	if cols == nil {
		t.Fatal("auth_logs must stay in the manifest; its absence is the bug this package was written for")
	}
	for _, want := range []string{"decision", "policy_id", "policy_name", "match_reason", "session_id"} {
		found := false
		for _, c := range cols {
			if c == want {
				found = true
			}
		}
		if !found {
			t.Errorf("auth_logs.%s is written by LogAuthDecision but is not in the manifest", want)
		}
	}
}

// The rendered line is what an operator reads, so it has to name all three of: which database,
// which column, and what stops working.
func TestProblemStringIsActionable(t *testing.T) {
	s := Problem{Database: "alpha", Table: "auth_logs", Missing: []string{"decision"},
		Why: "the decision log records nothing"}.String()
	for _, want := range []string{"alpha", "did.auth_logs", "decision", "records nothing"} {
		if !strings.Contains(s, want) {
			t.Errorf("the message %q should mention %q", s, want)
		}
	}
}

// No databases must not read as success.
func TestVerifyAllWithNoDatabases(t *testing.T) {
	if got := VerifyAll(nil); got != nil {
		t.Errorf("no databases should yield no problems, got %v", got)
	}
}
