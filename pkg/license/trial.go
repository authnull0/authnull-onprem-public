package license

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"log"
	"strings"
	"time"

	"gorm.io/gorm"
)

// Trial state, and an honest account of what it can and cannot do.
//
// The trial has to self-start: the package is downloaded from a public repository and installed
// without Authnull involved, so there is nothing to activate. First boot records a timestamp, and
// thirty days later the control plane goes read-only.
//
// WHAT THIS DOES NOT DEFEND AGAINST, ON PURPOSE
//
// The customer owns the database, the disk and the clock. They can delete the volume and reinstall,
// or set the clock back. None of that is preventable, and every mitigation for it — hardware
// fingerprints, hidden filesystem markers, refusing to run when time moves backwards — is defeatable
// by anyone determined, while breaking legitimate restores, migrations and VM snapshots for everyone
// else. The trial is a lead-generation mechanism, not a security control, and treating it as the
// latter costs more in support than it recovers in licence revenue.
//
// So the row is HMAC'd rather than encrypted or hidden. That makes CASUAL editing visible — a
// support engineer can tell "somebody ran an UPDATE" from "this install is genuinely 12 days old" —
// and stops there.

// TrialRecord is the single row holding first-boot time.
type TrialRecord struct {
	// ID is always 1. A CHECK constraint enforces it, so there is exactly one trial per deployment
	// and no ambiguity about which row counts.
	ID             int       `gorm:"column:id;primaryKey"`
	TrialStartedAt time.Time `gorm:"column:trial_started_at"`
	// Signature is an HMAC over the timestamp keyed on the deployment's own ENCRYPTION_KEY. It does
	// not stop an edit; it makes one visible.
	Signature string    `gorm:"column:signature"`
	CreatedAt time.Time `gorm:"column:created_at"`
	UpdatedAt time.Time `gorm:"column:updated_at"`
}

// TableName maps to the master database. A licence covers the deployment, not an organisation, so
// this lives in the master DB and not per-org.
func (TrialRecord) TableName() string { return "did.license_state" }

// TrialStore reads and records the trial window.
type TrialStore struct {
	db *gorm.DB
	// hmacKey is the deployment's own secret, normally ENCRYPTION_KEY. Empty means signatures are
	// not checked — see Verify.
	hmacKey []byte
}

// NewTrialStore builds a store. hmacKey may be empty, in which case the signature is neither written
// nor checked; the trial still works.
func NewTrialStore(db *gorm.DB, hmacKey string) *TrialStore {
	return &TrialStore{db: db, hmacKey: []byte(strings.TrimSpace(hmacKey))}
}

// storedPrecision is the precision the trial timestamp is rounded to before it is signed and
// written, and it is not cosmetic.
//
// PostgreSQL timestamptz holds MICROSECONDS. time.Now() carries nanoseconds. The signature is an HMAC
// over the timestamp formatted as RFC3339Nano, so signing the in-memory value and then verifying the
// value Postgres returned meant hashing two different strings:
//
//	signed   "2026-08-24T04:33:08.667440734Z"   <- what Go had
//	verified "2026-08-24T04:33:08.66744Z"       <- what Postgres kept
//
// The HMAC could therefore never match, and every deployment logged "trial signature does not match
// (record may have been edited or restored from another deployment)" on every restart after the first.
// A tamper signal that cries wolf on every honest boot is worse than none: it is the line a support
// engineer learns to skip past, so a record that really had been edited would go unnoticed.
//
// Truncating before signing makes the signed bytes identical to the stored bytes. Truncate rather than
// Round, so the value can only move backwards -- a trial can end a microsecond late, never early.
//
// Found by pkg/license/store_postgres_test.go running against a real PostgreSQL. No unit test could
// have caught it: the truncation happens inside the database.
const storedPrecision = time.Microsecond

func (s *TrialStore) sign(t time.Time) string {
	if len(s.hmacKey) == 0 {
		return ""
	}
	m := hmac.New(sha256.New, s.hmacKey)
	// UTC RFC3339Nano so the signed form does not depend on the server's timezone. A deployment that
	// changes TZ must not invalidate its own trial record.
	m.Write([]byte(t.UTC().Format(time.RFC3339Nano)))
	return hex.EncodeToString(m.Sum(nil))
}

// Ensure records first boot if it has not been recorded, and returns the trial start.
//
// Idempotent: the insert is guarded, so restarting the container does not move the start forward. If
// it did, a customer could hold the trial open indefinitely by restarting — which is the one abuse
// worth actually preventing here, because it needs no intent and no knowledge.
//
// Returns the zero time on any failure. Callers treat that as "trial starts now", which errs in the
// customer's favour — the right direction when the alternative is refusing to work because a table
// is missing.
func (s *TrialStore) Ensure() time.Time {
	if s == nil || s.db == nil {
		return time.Time{}
	}

	var rec TrialRecord
	err := s.db.Where("id = ?", 1).First(&rec).Error
	if err == nil {
		if !s.verify(rec) {
			// Deliberately not treated as tampering-with-consequences: log it and honour the stored
			// value. Refusing to run, or resetting the trial, would punish a restored backup as
			// harshly as an edit — and a restored backup is far more likely.
			log.Printf("license: trial signature does not match for start=%s "+
				"(record may have been edited or restored from another deployment)",
				rec.TrialStartedAt.UTC().Format(time.RFC3339))
		}
		return rec.TrialStartedAt
	}
	if err != gorm.ErrRecordNotFound {
		log.Printf("license: cannot read trial state: %v", err)
		return time.Time{}
	}

	// Truncated to what Postgres will actually keep, so the signature covers the stored value rather
	// than the in-memory one. See storedPrecision.
	now := time.Now().UTC().Truncate(storedPrecision)
	rec = TrialRecord{ID: 1, TrialStartedAt: now, Signature: s.sign(now), CreatedAt: now, UpdatedAt: now}
	// FirstOrCreate rather than Create: it selects first and only inserts when nothing is there, so a
	// restart cannot overwrite a start already recorded.
	//
	// This is NOT an ON CONFLICT DO NOTHING -- GORM emits a SELECT and then an INSERT, with no upsert
	// clause -- so a genuine race is resolved by the primary key rather than by the statement. A racer
	// that loses gets a duplicate-key error, logs it, and returns the zero time; the caller reads that
	// as "the trial starts now", and the Loader's next Status() reads the winner's row anyway, so the
	// stored value takes over within milliseconds. Exactly one row results either way, which is the
	// property that matters: it is guaranteed by the id = 1 CHECK in migration 013, not by this call.
	//
	// TestTrialStoreRaceOnFirstBootPostgres exercises this with eight concurrent first boots against a
	// real PostgreSQL and asserts the single row and the agreed timestamp.
	if err := s.db.Where("id = ?", 1).FirstOrCreate(&rec).Error; err != nil {
		log.Printf("license: cannot record trial start: %v", err)
		return time.Time{}
	}
	log.Printf("license: trial started at %s, ends %s",
		rec.TrialStartedAt.UTC().Format(time.RFC3339),
		rec.TrialStartedAt.Add(TrialDuration).UTC().Format(time.RFC3339))
	return rec.TrialStartedAt
}

func (s *TrialStore) verify(rec TrialRecord) bool {
	if len(s.hmacKey) == 0 || rec.Signature == "" {
		return true // nothing to check against
	}
	// Truncated on the read side as well. Ensure already truncates before signing, so this changes
	// nothing for a row this code wrote -- it is here so a row written by a build without the fix, or
	// by a store that keeps more precision than Postgres, still verifies instead of being reported as
	// edited.
	return hmac.Equal([]byte(rec.Signature),
		[]byte(s.sign(rec.TrialStartedAt.UTC().Truncate(storedPrecision))))
}

// StartedAt returns the recorded trial start without creating one. Suitable as the Loader's
// trialStart function on every call after boot.
func (s *TrialStore) StartedAt() time.Time {
	if s == nil || s.db == nil {
		return time.Time{}
	}
	var rec TrialRecord
	if err := s.db.Where("id = ?", 1).First(&rec).Error; err != nil {
		return time.Time{}
	}
	return rec.TrialStartedAt
}
