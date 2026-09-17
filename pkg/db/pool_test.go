package db

import (
	"testing"
)

// The pool is PER DATABASE and this service opens one per organisation plus one for the master,
// so the total demand is (orgs+1) x maxOpenConns. The measured deployment has
// max_connections = 100 with 3 reserved and ~30 already in use by other services, so a default
// that does not fit inside that is a "too many clients already" outage waiting for a burst.
func TestDefaultPoolFitsAModestServer(t *testing.T) {
	const (
		serverMax        = 100 // measured: pg_settings max_connections
		reserved         = 3   // measured: superuser_reserved_connections
		otherServices    = 30  // measured: pg_stat_activity at rest
		databasesAtLeast = 2   // master + one org, the smallest real deployment
	)
	budget := serverMax - reserved - otherServices
	demand := maxOpenConns() * databasesAtLeast
	if demand > budget {
		t.Errorf("default pool demands %d connections (%d per database x %d databases) but only "+
			"%d are available; lower defaultMaxOpenConns or raise Postgres max_connections",
			demand, maxOpenConns(), databasesAtLeast, budget)
	}
}

// database/sql silently reduces idle to open when idle is larger. That is not an error, but it is
// never what anyone meant, so the clamp makes the effective value match the configured one.
func TestIdleNeverExceedsOpen(t *testing.T) {
	if maxIdleConns() > maxOpenConns() {
		t.Errorf("idle %d > open %d", maxIdleConns(), maxOpenConns())
	}
	t.Setenv("DB_MAX_OPEN_CONNS", "4")
	t.Setenv("DB_MAX_IDLE_CONNS", "50")
	if got := maxIdleConns(); got != 4 {
		t.Errorf("idle should clamp to open, got %d want 4", got)
	}
}

// A typo in the environment must not produce an unbounded or zero-sized pool: zero would make
// every query wait forever for a connection, and there is no way to express "unlimited" here by
// accident.
func TestEnvIntRejectsUnusableValues(t *testing.T) {
	for _, bad := range []string{"0", "-1", "abc", "  ", "1e3", "20.5"} {
		t.Setenv("DB_MAX_OPEN_CONNS", bad)
		if got := maxOpenConns(); got != defaultMaxOpenConns {
			t.Errorf("DB_MAX_OPEN_CONNS=%q gave %d, want the %d default", bad, got, defaultMaxOpenConns)
		}
	}
	t.Setenv("DB_MAX_OPEN_CONNS", "40")
	if got := maxOpenConns(); got != 40 {
		t.Errorf("a valid override should apply, got %d", got)
	}
}
