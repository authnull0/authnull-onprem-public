package main

import (
	"log"
	"os"
	"sync/atomic"
	"time"

	"gorm.io/gorm"

	"github.com/authnull0/authnull-service/pkg/db"
	"github.com/authnull0/authnull-service/pkg/schemacheck"
)

// schemaProblemsValue holds the verification result for /health to report.
//
// atomic.Value, not a plain slice: verifySchema runs in a background goroutine while the
// server is already accepting requests, so a bare package variable would be written by that
// goroutine and read concurrently by every health check. That is a data race, and in Go a
// racing slice read can observe a header whose pointer and length disagree. "It is written
// once, early" is not a synchronisation argument -- it is exactly the reasoning behind the
// unguarded maps this pass has been removing.
var schemaProblemsValue atomic.Value // []schemacheck.Problem

// lastSchemaCheckValue is when the check last completed, for the staleness bound above.
var lastSchemaCheckValue atomic.Value // time.Time

// schemaProblems returns the verification result, re-verifying when the cached one is stale.
//
// The first version ran verifySchema() exactly once at boot and cached it forever. That is wrong
// in the one situation that matters: after an operator fixes the drift, the endpoint keeps
// reporting the old problems until the service is restarted -- so the fix looks like it failed,
// and the check becomes something people learn to disbelieve. Observed for real: the migrations
// were applied, both databases verified clean by direct query, and /health still listed seven
// problems.
//
// Re-verified on read, rate-limited to schemaRecheckInterval so the container's own 10-second
// healthcheck poll does not turn into an information_schema query per poll per database.
func schemaProblems() []schemacheck.Problem {
	if time.Since(lastSchemaCheck()) > schemaRecheckInterval {
		// Not under a lock: a concurrent duplicate check is two cheap read-only queries, which
		// is cheaper than serialising every health request behind a mutex.
		verifySchema()
	}
	p, _ := schemaProblemsValue.Load().([]schemacheck.Problem)
	return p
}

// schemaRecheckInterval bounds how stale the answer can be. Two minutes is short enough that an
// operator who just ran the migrations sees the truth on their next poll, and long enough that the
// 10s healthcheck almost never triggers a re-verify.
const schemaRecheckInterval = 2 * time.Minute

func lastSchemaCheck() time.Time {
	t, _ := lastSchemaCheckValue.Load().(time.Time)
	return t
}

// verifySchema checks the master database and every org database.
//
// The master is included even though most of these tables are only meaningful per-org: a new
// organisation's database is created from the same migrations, so a gap visible on the master
// is a gap every future tenant will inherit. That is exactly how the alpha org ended up with
// columns the master lacked -- they were applied by hand to one database and to nothing else.
func verifySchema() {
	targets := map[string]*gorm.DB{}

	if master := os.Getenv("DB_NAME"); master != "" {
		targets[master] = db.GetConnectiontoDatabaseDynamically(master)
	}

	names, err := db.AllOrgDatabaseNames()
	if err != nil {
		// Not fatal: checking the master alone is still worth doing, and it is the database
		// that determines what new organisations inherit.
		log.Printf("schemacheck: could not list organisation databases (checking master only): %v", err)
	}
	for _, name := range names {
		targets[name] = db.GetConnectiontoDatabaseDynamically(name)
	}

	if len(targets) == 0 {
		log.Printf("schemacheck: no databases to verify")
		return
	}
	problems := schemacheck.VerifyAll(targets)
	if problems == nil {
		// Store a non-nil empty slice: atomic.Value panics on a nil interface, and an
		// explicit empty result is also what distinguishes "checked, all good" from "has
		// not run yet" for anything that later wants to tell them apart.
		problems = []schemacheck.Problem{}
	}
	schemaProblemsValue.Store(problems)
	lastSchemaCheckValue.Store(time.Now())
}
