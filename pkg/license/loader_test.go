package license

import (
	"crypto/ed25519"
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// withBuildKey swaps the compiled-in public key for the duration of a test.
func withBuildKey(t *testing.T, pub ed25519.PublicKey) {
	t.Helper()
	prev := PublicKeyBase64
	t.Cleanup(func() { PublicKeyBase64 = prev })
	if pub == nil {
		PublicKeyBase64 = ""
		return
	}
	PublicKeyBase64 = base64.StdEncoding.EncodeToString(pub)
}

func writeLicense(t *testing.T, body []byte) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "authnull.lic")
	if err := os.WriteFile(path, body, 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// The single most important behaviour in this file.
//
// The same binary serves Authnull's own SaaS and reference deployments, which have no licence and
// never will. If an absent build key meant "nothing verifies", wiring this package in would put every
// one of those consoles into read-only — an outage we shipped to ourselves. Only the on-premise build
// sets the key, and only that build can refuse anything.
func TestNoBuildKeyMeansNotEnforced(t *testing.T) {
	withBuildKey(t, nil)

	l := NewLoader("", nil)
	if l.Enforced() {
		t.Fatal("a build with no public key must not enforce")
	}
	st := l.Status()
	if st.State != StateNotEnforced || !st.Licensed {
		t.Fatalf("expected not_enforced and licensed, got %+v", st)
	}

	// Even a deliberately forged file must not flip such a build into refusing.
	_, otherPriv := keypair(t)
	forged := writeLicense(t, issue(t, otherPriv, Payload{
		ID: "forged", ExpiresAt: time.Now().AddDate(1, 0, 0), Features: []string{FeatureAD},
	}))
	if st := NewLoader(forged, nil).Status(); !st.Licensed {
		t.Errorf("a non-enforcing build must stay licensed regardless of the file, got %+v", st)
	}
}

func TestLoaderReadsValidLicense(t *testing.T) {
	pub, priv := keypair(t)
	withBuildKey(t, pub)

	path := writeLicense(t, issue(t, priv, Payload{
		ID: "lic-100", Customer: "Acme Ltd",
		ExpiresAt: time.Now().AddDate(1, 0, 0),
		Features:  []string{FeatureAD},
	}))

	st := NewLoader(path, nil).Status()
	if st.State != StateValid || !st.Licensed {
		t.Fatalf("expected valid and licensed, got %+v", st)
	}
	if st.Customer != "Acme Ltd" {
		t.Errorf("customer not surfaced: %+v", st)
	}
	if !st.Has(FeatureAD) || st.Has(FeatureRADIUS) {
		t.Errorf("features wrong: %+v", st.Features)
	}
}

// Absent, empty and unreadable files are three different situations and only one of them is an
// accusation. Conflating them would tell a customer with a broken volume mount that their licence was
// tampered with.
func TestLoaderDistinguishesAbsentFromForged(t *testing.T) {
	pub, priv := keypair(t)
	withBuildKey(t, pub)

	// No path at all → trial.
	if st := NewLoader("", nil).Status(); st.State != StateTrial {
		t.Errorf("no licence path should mean trial, got %s", st.State)
	}
	// Path that does not exist → trial, not invalid.
	missing := filepath.Join(t.TempDir(), "nope.lic")
	if st := NewLoader(missing, nil).Status(); st.State != StateTrial {
		t.Errorf("a missing file should mean trial, got %s", st.State)
	}
	// Empty file → trial. This is what a truncated mount or half-finished upload looks like.
	if st := NewLoader(writeLicense(t, []byte("   \n")), nil).Status(); st.State != StateTrial {
		t.Errorf("an empty file should mean trial, got %s", st.State)
	}
	// Edited file → invalid, and it must say so.
	_, foreign := keypair(t)
	forged := writeLicense(t, issue(t, foreign, Payload{
		ID: "x", ExpiresAt: time.Now().AddDate(1, 0, 0), Features: []string{FeatureAD},
	}))
	st := NewLoader(forged, nil).Status()
	if st.State != StateInvalid || st.Licensed {
		t.Fatalf("a foreign-signed licence must be invalid and unlicensed, got %+v", st)
	}
	if st.Reason == "" {
		t.Error("an invalid licence must explain itself")
	}
	_ = priv
}

// An expired licence must leave the deployment unlicensed for writes while still reporting who it
// belonged to and when it lapsed — that is what the console renders.
func TestLoaderExpiredLicenceStillReportsDetail(t *testing.T) {
	pub, priv := keypair(t)
	withBuildKey(t, pub)

	path := writeLicense(t, issue(t, priv, Payload{
		ID: "lic-old", Customer: "Acme Ltd",
		ExpiresAt: time.Now().AddDate(0, 0, -3),
		Features:  []string{FeatureAD},
	}))

	st := NewLoader(path, nil).Status()
	if st.State != StateExpired || st.Licensed {
		t.Fatalf("expected expired and unlicensed, got %+v", st)
	}
	if st.Customer != "Acme Ltd" || st.ExpiresAt == nil {
		t.Errorf("an expired licence must still report its detail: %+v", st)
	}
	if st.DaysRemaining >= 0 {
		t.Errorf("DaysRemaining should be negative once expired, got %d", st.DaysRemaining)
	}
}

// Reload is what makes the upload path feel instantaneous: a customer who uploads a licence must be
// unblocked without restarting the service or waiting out the recheck interval.
func TestReloadPicksUpANewFileImmediately(t *testing.T) {
	pub, priv := keypair(t)
	withBuildKey(t, pub)

	path := filepath.Join(t.TempDir(), "authnull.lic")
	l := NewLoader(path, nil)
	if st := l.Status(); st.State != StateTrial {
		t.Fatalf("expected trial before any file exists, got %s", st.State)
	}

	body := issue(t, priv, Payload{
		ID: "lic-200", Customer: "Acme",
		ExpiresAt: time.Now().AddDate(1, 0, 0),
		Features:  []string{FeatureAD},
	})
	if err := os.WriteFile(path, body, 0o600); err != nil {
		t.Fatal(err)
	}
	l.Reload()
	if st := l.Status(); st.State != StateValid {
		t.Fatalf("Reload should pick up the new licence at once, got %s", st.State)
	}
}

// A trial start recorded in the past must be honoured, so restarting the container cannot extend the
// trial by resetting the clock to "now".
func TestTrialStartIsHonoured(t *testing.T) {
	pub, _ := keypair(t)
	withBuildKey(t, pub)

	long := time.Now().Add(-TrialDuration - 48*time.Hour)
	st := NewLoader("", func() time.Time { return long }).Status()
	if st.State != StateExpired || st.Licensed {
		t.Fatalf("a trial started before the window must be expired, got %+v", st)
	}

	recent := time.Now().Add(-24 * time.Hour)
	st = NewLoader("", func() time.Time { return recent }).Status()
	if st.State != StateTrial || !st.Licensed {
		t.Fatalf("a trial started yesterday must still be active, got %+v", st)
	}
}

// A malformed build-time key is a release-engineering mistake. It must not brick a customer's console:
// log it and leave licensing unenforced.
func TestMalformedBuildKeyDoesNotBrick(t *testing.T) {
	prev := PublicKeyBase64
	t.Cleanup(func() { PublicKeyBase64 = prev })

	for _, bad := range []string{"!!!not base64!!!", base64.StdEncoding.EncodeToString([]byte("too short"))} {
		PublicKeyBase64 = bad
		l := NewLoader("", nil)
		if l.Enforced() {
			t.Errorf("key %q should not be accepted as enforceable", bad)
		}
		if st := l.Status(); !st.Licensed {
			t.Errorf("a bad build key must leave the deployment usable, got %+v", st)
		}
	}
}
