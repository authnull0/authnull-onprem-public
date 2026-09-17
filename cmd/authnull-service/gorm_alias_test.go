package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// GORM silently drops a bare-space alias on a schema-qualified table, and the failure only appears
// at runtime as a Postgres error.
//
// Table() recognises an alias with this regexp (vendor/gorm.io/gorm/chainable_api.go):
//
//	(?i)(?:.+? AS (\w+)\s*(?:$|,)|^\w+\s+(\w+)$)
//
// The bare-space alternative is anchored as ^\w+\s+(\w+)$, and \w does not match a dot — so
// "did.mfa_devices d" never matches. Statement.Table is left empty, the destination model's
// TableName() then supplies it, and the FROM clause is rebuilt QUOTED AND WITHOUT THE ALIAS:
//
//	SELECT d.* FROM "did"."mfa_devices" JOIN … ON i.device_id = d.id
//	ERROR: missing FROM-clause entry for table "d" (SQLSTATE 42P01)
//
// Six queries shipped like this, including resolveGroupClosure and resolveOUs in the policy matcher
// — both of which log and continue, so group- and OU-scoped AD policies silently matched nobody.
//
// This is a static check because no unit test can catch it: the package tests use a nil *gorm.DB and
// assert that guards fire BEFORE any query runs, which is exactly the code path that never builds
// SQL. Use "AS" and it works, which is what the rest of the repo already does.
func TestNoBareSpaceTableAliases(t *testing.T) {
	// Table("did.something x") — a dotted name, a space, then a bare alias with no AS.
	bad := regexp.MustCompile(`Table\("[a-zA-Z_]+\.[a-zA-Z_]+\s+[a-zA-Z_]+"\)`)

	root := filepath.Join("..", "..")
	var offenders []string
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // unreadable paths are not this test's problem
		}
		if info.IsDir() {
			switch info.Name() {
			case ".git", "vendor", "node_modules":
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		src, readErr := os.ReadFile(path)
		if readErr != nil {
			return nil
		}
		for _, m := range bad.FindAll(src, -1) {
			offenders = append(offenders, path+": "+string(m))
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walk: %v", err)
	}
	for _, o := range offenders {
		t.Errorf("bare-space table alias — GORM will drop it and the query fails at runtime. "+
			"Write it as \"did.table AS alias\": %s", o)
	}
}
