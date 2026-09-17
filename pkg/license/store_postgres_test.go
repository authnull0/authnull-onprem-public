package license

import (
	"crypto/ed25519"
	"errors"
	"os"
	"sync"
	"testing"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// The two DB-backed stores, against a real PostgreSQL.
//
// WHY THIS IS NOT A UNIT TEST
//
// TrialStore and DocumentStore are thin, and everything interesting about them is what POSTGRES does
// rather than what the Go does: whether the single-row CHECK actually holds, whether two containers
// booting at once really cannot produce two trial rows, and whether "newest upload wins" survives two
// uploads landing in the same clock tick. None of that can be asserted against a mock -- a mock would
// simply agree with whatever the code did.
//
// Skipped unless LICENSE_PG_DSN is set, so an ordinary `go test ./...` does not need a database:
//
//	LICENSE_PG_DSN="host=127.0.0.1 port=15432 user=... dbname=license_probe sslmode=disable" \
//	  go test -vet=off ./pkg/license/ -run Postgres -v
//
// Point it at a SCRATCH database. Every test here truncates the two tables.

func pgDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := os.Getenv("LICENSE_PG_DSN")
	if dsn == "" {
		t.Skip("LICENSE_PG_DSN not set; skipping the PostgreSQL-backed store tests")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	// Truncate rather than drop: the tables are what the migrations created, and recreating them here
	// would test this file's idea of the schema instead of the migration's.
	for _, tbl := range []string{"did.license_state", "did.license_documents"} {
		if err := db.Exec("TRUNCATE " + tbl).Error; err != nil {
			t.Fatalf("truncate %s (has migration 013/014 been applied?): %v", tbl, err)
		}
	}
	return db
}

// TestTrialStorePostgres covers the property the whole trial rests on: the recorded start never moves.
func TestTrialStorePostgres(t *testing.T) {
	db := pgDB(t)
	const key = "zT4gW9kJcV7pM1RbU3qXe8YaL6fDnZoB" // an ENCRYPTION_KEY-shaped value

	store := NewTrialStore(db, key)

	first := store.Ensure()
	if first.IsZero() {
		t.Fatal("first Ensure returned the zero time — the trial would restart on every boot")
	}

	// RESTARTING THE CONTAINER MUST NOT MOVE THE TRIAL FORWARD. If it did, a customer could hold the
	// trial open forever by restarting, which needs no intent and no knowledge to discover.
	time.Sleep(50 * time.Millisecond)
	for i := 0; i < 3; i++ {
		if got := NewTrialStore(db, key).Ensure(); !got.Equal(first) {
			t.Fatalf("restart %d moved the trial start: %s -> %s", i+1, first, got)
		}
	}
	if got := store.StartedAt(); !got.Equal(first) {
		t.Errorf("StartedAt = %s, want %s", got, first)
	}

	var rows int64
	db.Table("did.license_state").Count(&rows)
	if rows != 1 {
		t.Errorf("license_state holds %d rows, want exactly 1", rows)
	}

	// The signature was written and verifies. An unsigned row would mean an edit is undetectable.
	var sig string
	db.Table("did.license_state").Where("id = 1").Select("signature").Scan(&sig)
	if sig == "" {
		t.Error("no signature was written, so an edited trial start would be invisible")
	}

	// THE REGRESSION THIS FILE WAS WRITTEN TO CATCH.
	//
	// The signature must verify against the row as PostgreSQL returns it. It did not: Go signed a
	// nanosecond timestamp, Postgres kept microseconds, and the HMAC was computed over two different
	// strings. Every deployment therefore logged "trial signature does not match (record may have
	// been edited)" on every restart -- and a warning that fires on every honest boot is one nobody
	// reads, so a genuinely edited record would have gone unnoticed.
	//
	// Asserted on the value read BACK from the database, never on the one held in memory: an
	// in-memory check passes with the bug present, which is precisely why it survived.
	var stored TrialRecord
	if err := db.Where("id = 1").First(&stored).Error; err != nil {
		t.Fatalf("read back: %v", err)
	}
	if !NewTrialStore(db, key).verify(stored) {
		t.Errorf("the signature does not verify against the stored row (start=%s, %d ns) — "+
			"every restart would warn about tampering that never happened",
			stored.TrialStartedAt.UTC().Format(time.RFC3339Nano), stored.TrialStartedAt.Nanosecond())
	}
	if stored.TrialStartedAt.Nanosecond()%int(time.Microsecond) != 0 {
		t.Errorf("stored timestamp has sub-microsecond precision (%d ns), which Postgres cannot keep",
			stored.TrialStartedAt.Nanosecond())
	}

	// An EDITED start is honoured but reported. Backdating is the obvious way to fake an expired
	// trial into a fresh one -- and equally what a restored backup looks like, which is why this is
	// logged rather than refused.
	backdated := first.Add(-40 * 24 * time.Hour)
	if err := db.Exec("UPDATE did.license_state SET trial_started_at = ? WHERE id = 1", backdated).Error; err != nil {
		t.Fatalf("backdate: %v", err)
	}
	got := NewTrialStore(db, key).Ensure()
	if !got.Truncate(time.Second).Equal(backdated.Truncate(time.Second)) {
		t.Errorf("an edited start must be honoured, got %s want %s", got, backdated)
	}
	if Evaluate(nil, got, time.Now()).Licensed {
		t.Error("a trial backdated 40 days must evaluate as expired")
	}
}

// TestTrialStoreRaceOnFirstBootPostgres is the concurrency claim in Ensure()'s own comment, checked.
//
// Several containers of a compose deployment can boot simultaneously and all call Ensure() before any
// row exists. The requirement is that exactly ONE row results and its timestamp is never overwritten
// -- if the loser could overwrite the winner, the trial length would depend on scheduling.
func TestTrialStoreRaceOnFirstBootPostgres(t *testing.T) {
	db := pgDB(t)
	const key = "zT4gW9kJcV7pM1RbU3qXe8YaL6fDnZoB"
	const racers = 8

	var wg sync.WaitGroup
	results := make([]time.Time, racers)
	start := make(chan struct{})
	for i := 0; i < racers; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			results[i] = NewTrialStore(db, key).Ensure()
		}(i)
	}
	close(start)
	wg.Wait()

	var rows int64
	db.Table("did.license_state").Count(&rows)
	if rows != 1 {
		t.Fatalf("%d concurrent first boots produced %d rows, want 1 — the trial length would then "+
			"depend on which row a later read happened to return", racers, rows)
	}

	// Whatever landed in the table is the answer, and every racer that returned a non-zero time must
	// agree with it. A racer that LOST is allowed to return the zero time: the caller treats that as
	// "trial starts now", and the Loader re-reads the row on every Status() anyway, so the stored
	// value wins within milliseconds.
	var stored time.Time
	db.Table("did.license_state").Where("id = 1").Select("trial_started_at").Scan(&stored)
	won, lost := 0, 0
	for i, r := range results {
		switch {
		case r.IsZero():
			lost++
		case !r.Truncate(time.Millisecond).Equal(stored.Truncate(time.Millisecond)):
			t.Errorf("racer %d returned %s but the table holds %s — a loser overwrote the winner",
				i, r, stored)
		default:
			won++
		}
	}
	if won == 0 {
		t.Error("no racer returned the stored start; every container would log a trial it did not record")
	}
	t.Logf("%d racers: %d agreed with the stored row, %d returned zero (harmless: StartedAt re-reads)", racers, won, lost)
}

// TestSingleRowConstraintPostgres proves the CHECK in migration 013 is real.
func TestSingleRowConstraintPostgres(t *testing.T) {
	db := pgDB(t)
	err := db.Exec("INSERT INTO did.license_state (id, trial_started_at) VALUES (2, now())").Error
	if err == nil {
		t.Fatal("a second row was accepted — which licence state applies would then depend on query order")
	}
	t.Logf("second row correctly refused: %v", err)
}

// TestDocumentStorePostgres covers upload, retrieval, and the ordering that decides which licence
// applies.
func TestDocumentStorePostgres(t *testing.T) {
	db := pgDB(t)
	store := NewDocumentStore(db)

	// A fresh install: nothing uploaded. This must be ErrNoLicense, not an error -- the caller falls
	// back to the file and then to the trial, and a hard error there would look like a broken install.
	if _, err := store.Current(); !errors.Is(err, ErrNoLicense) {
		t.Fatalf("Current on an empty table = %v, want ErrNoLicense", err)
	}

	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("keygen: %v", err)
	}
	issue := func(id string, expiresIn time.Duration, features ...string) []byte {
		raw, err := Sign(Payload{
			ID: id, Customer: "Acme Corp", IssuedAt: time.Now().UTC(),
			ExpiresAt: time.Now().Add(expiresIn).UTC(), Tier: "enterprise",
			Features: features, Nonce: id,
		}, priv)
		if err != nil {
			t.Fatalf("sign %s: %v", id, err)
		}
		return raw
	}

	// First purchase.
	one := issue("LIC-001", 365*24*time.Hour, FeatureAD)
	p1, err := Verify(one, pub)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if err := store.Save(one, p1, 42); err != nil {
		t.Fatalf("save: %v", err)
	}

	// THE ROUND TRIP IS BYTE-EXACT. The signature covers exact bytes, so anything Postgres does to
	// this column -- encoding, trailing whitespace, newline translation -- would make a licence that
	// verified at upload fail on the next read.
	back, err := store.Current()
	if err != nil {
		t.Fatalf("Current: %v", err)
	}
	if string(back) != string(one) {
		t.Fatal("the stored licence did not come back byte-for-byte; the signature would stop verifying")
	}
	if _, err := Verify(back, pub); err != nil {
		t.Fatalf("the licence read back from Postgres does not verify: %v", err)
	}

	// Renewal. The newest upload must win, and the previous one must still be there -- uploading the
	// wrong file over a good licence has to be recoverable.
	two := issue("LIC-002", 730*24*time.Hour, FeatureAD, FeatureDatabase)
	p2, _ := Verify(two, pub)
	if err := store.Save(two, p2, 42); err != nil {
		t.Fatalf("save renewal: %v", err)
	}
	back, _ = store.Current()
	if string(back) != string(two) {
		t.Error("Current returned the old licence after a renewal")
	}

	// TWO UPLOADS IN THE SAME CLOCK TICK. uploaded_at alone cannot separate them, which is exactly
	// why Current orders by id as well. Written directly with an identical timestamp because that is
	// the only way to force the tie deterministically.
	// A second in the FUTURE of every row saved above. Truncate(time.Second) was the obvious thing
	// to write and was wrong: it moves the timestamp BACKWARDS by up to a second, placing the tied
	// rows before the earlier saves, so Current() rightly returned the older licence and the test
	// blamed the ordering.
	same := time.Now().UTC().Add(time.Second).Truncate(storedPrecision)
	three := issue("LIC-003", 1000*24*time.Hour, FeatureAD, FeatureDatabase, FeatureRADIUS)
	for _, raw := range [][]byte{two, three} {
		if err := db.Exec(
			"INSERT INTO did.license_documents (document, license_id, uploaded_at) VALUES (?, ?, ?)",
			string(raw), "tie", same).Error; err != nil {
			t.Fatalf("tie insert: %v", err)
		}
	}
	back, _ = store.Current()
	if string(back) != string(three) {
		t.Error("with equal timestamps the higher id must win, or which licence applies is arbitrary")
	}

	// History: newest first, and WITHOUT the document bodies.
	hist, err := store.History(10)
	if err != nil {
		t.Fatalf("History: %v", err)
	}
	if len(hist) != 4 {
		t.Errorf("History returned %d rows, want 4 — nothing should be deleted on renewal", len(hist))
	}
	for i, h := range hist {
		if h.Document != "" {
			t.Errorf("History row %d carries the document body; a console table has no use for kilobytes of signed blob", i)
		}
	}
	if len(hist) > 1 && hist[0].UploadedAt.Before(hist[len(hist)-1].UploadedAt) {
		t.Error("History is not newest-first")
	}
	if hist[len(hist)-1].LicenseID != "LIC-001" || hist[len(hist)-1].UploadedByUserID != 42 {
		t.Errorf("the oldest row lost its display fields: %+v", hist[len(hist)-1])
	}
}

// TestLoaderAgainstPostgres wires the real Loader to the real DocumentStore and TrialStore, which is
// the exact composition initLicense builds at boot. The last untested join.
func TestLoaderAgainstPostgres(t *testing.T) {
	db := pgDB(t)
	priv := enforcingBuild(t)

	trials := NewTrialStore(db, "zT4gW9kJcV7pM1RbU3qXe8YaL6fDnZoB")
	docs := NewDocumentStore(db)
	trials.Ensure()

	loader := NewLoader("", trials.StartedAt, WithDocumentSource(docs.Current))
	if st := loader.Status(); st.State != StateTrial {
		t.Fatalf("a fresh install with a recorded trial should be in trial, got %s", st.State)
	}

	// Trial exhausted.
	if err := db.Exec("UPDATE did.license_state SET trial_started_at = ? WHERE id = 1",
		time.Now().Add(-31*24*time.Hour)).Error; err != nil {
		t.Fatalf("backdate: %v", err)
	}
	loader.Reload()
	if st := loader.Status(); st.Licensed {
		t.Fatal("an exhausted trial must not be licensed")
	}

	// A licence is uploaded. UploadLicense verifies, saves, then Reloads -- so does this.
	raw, err := Sign(Payload{
		ID: "LIC-PG", Customer: "Acme Corp", IssuedAt: time.Now().UTC(),
		ExpiresAt: time.Now().Add(365 * 24 * time.Hour).UTC(),
		Features:  []string{FeatureAD, FeatureDatabase}, Tier: "enterprise",
	}, priv)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	payload, err := Verify(raw, ed25519.PublicKey(loaderKey(t, loader)))
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if err := docs.Save(raw, payload, 7); err != nil {
		t.Fatalf("save: %v", err)
	}
	loader.Reload()

	st := loader.Status()
	if !st.Licensed || st.State != StateValid || st.Customer != "Acme Corp" {
		t.Fatalf("after upload: licensed=%v state=%s customer=%q, want true/valid/Acme Corp",
			st.Licensed, st.State, st.Customer)
	}
	if !st.Has(FeatureAD) || st.Has(FeatureRADIUS) {
		t.Errorf("features from Postgres are wrong: %v", st.Features)
	}
	// The trial is still exhausted underneath, and the licence overrides it.
	if trials.StartedAt().After(time.Now().Add(-30 * 24 * time.Hour)) {
		t.Error("the trial row was modified by installing a licence; it must be left alone")
	}
}

// loaderKey exposes the loader's public key for the test's own Verify call, so the test cannot drift
// from whatever key enforcingBuild installed.
func loaderKey(t *testing.T, l *Loader) ed25519.PublicKey {
	t.Helper()
	if !l.Enforced() {
		t.Fatal("loader is not enforcing")
	}
	return l.publicKey
}
