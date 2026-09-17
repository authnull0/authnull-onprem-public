package schemacheck

import (
	"encoding/json"
	"os"
	"testing"
)

// TestDumpManifest writes the manifest as JSON so a verification script can query the real thing
// rather than regex the source. An ad-hoc regex over this file mis-attributed one table's columns
// to another once comments appeared inside the struct literal, and produced a false "missing
// column" report — which is exactly the kind of wrong answer that erodes trust in the check.
//
// Skipped unless SCHEMACHECK_DUMP is set to an absolute path.
func TestDumpManifest(t *testing.T) {
	dest := os.Getenv("SCHEMACHECK_DUMP")
	if dest == "" {
		t.Skip("set SCHEMACHECK_DUMP to an absolute path to dump the manifest")
	}
	out := map[string][]string{}
	for _, r := range Requirements {
		out[r.Table] = r.Columns
	}
	b, err := json.MarshalIndent(out, "", " ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dest, b, 0o600); err != nil {
		t.Fatal(err)
	}
	t.Logf("dumped %d tables", len(out))
}
