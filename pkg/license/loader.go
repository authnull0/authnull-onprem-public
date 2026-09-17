package license

import (
	"crypto/ed25519"
	"encoding/base64"
	"errors"
	"log"
	"os"
	"strings"
	"sync/atomic"
	"time"
)

// PublicKeyBase64 is the Ed25519 key licences are verified against, injected at build time:
//
//	go build -ldflags "-X github.com/authnull0/authnull-service/pkg/license.PublicKeyBase64=<key>"
//
// EMPTY MEANS LICENSING IS NOT ENFORCED, AND THAT IS THE CORRECT DEFAULT.
//
// The same binary serves Authnull's own SaaS and reference deployments, where there is no licence and
// never will be. If an absent key meant "nothing verifies", every one of those consoles would go
// read-only the moment this package was wired in — we would have shipped ourselves an outage.
//
// Only the on-premise build sets it. That build is the only one that can refuse anything, which also
// means licensing cannot be disabled at runtime by editing an env var: the key is in the binary.
var PublicKeyBase64 = ""

// StateNotEnforced means this build carries no licence public key, so licensing does not apply.
// Reported honestly rather than disguised as StateValid, so the health endpoint distinguishes
// "licensed" from "not a licensed build".
const StateNotEnforced State = "not_enforced"

// recheckInterval bounds how stale the answer can be.
//
// Five minutes: long enough that a busy console is not re-reading a file constantly, short enough
// that a customer who uploads a licence sees it take effect while they are still looking at the
// screen. Reload() exists for the upload path so they do not have to wait even that long.
const recheckInterval = 5 * time.Minute

// Loader holds the current licence status and refreshes it.
//
// Deliberately mirrors the verifySchema / schemaProblems pattern in cmd/authnull-service/schema.go:
// atomic.Value, a rate-limited re-read, and the answer surfaced through the health endpoint. Two
// mechanisms that behave differently would be two things to learn.
type Loader struct {
	publicKey ed25519.PublicKey
	path      string
	// trialStart returns the recorded first-boot time, or the zero time if none is recorded. A
	// function rather than a value because it comes from the database, which is not available when
	// the Loader is constructed.
	trialStart func() time.Time

	// document returns the uploaded licence from the database, and is tried BEFORE the file.
	//
	// The database is primary because it is the only store that survives what actually happens to a
	// deployment: containers are recreated on upgrade, the packaged licence path is mounted
	// read-only, and with several replicas a file upload reaches only one of them.
	//
	// The file remains the BOOTSTRAP path — an air-gapped operator can drop a licence beside the
	// compose file before first boot, with no console and no database write.
	document func() ([]byte, error)

	status    atomic.Value // Status
	lastCheck atomic.Value // time.Time
}

// Option configures a Loader.
//
// Variadic options rather than a wider constructor: every existing caller and test keeps working, and
// a deployment that has no database source (a build with licensing off, or a boot where the master DB
// was unreachable) simply omits it.
type Option func(*Loader)

// WithDocumentSource supplies the database-backed licence, which takes precedence over the file.
func WithDocumentSource(fn func() ([]byte, error)) Option {
	return func(l *Loader) { l.document = fn }
}

// NewLoader builds a Loader. licensePath may be empty, which simply means no licence file is
// installed — the database is then consulted, and failing that the trial applies.
func NewLoader(licensePath string, trialStart func() time.Time, opts ...Option) *Loader {
	l := &Loader{
		path:       strings.TrimSpace(licensePath),
		trialStart: trialStart,
	}
	if l.trialStart == nil {
		// No trial source: treat every boot as the first. Wrong in the customer's favour, which is
		// the right direction for a bug in this position.
		l.trialStart = func() time.Time { return time.Time{} }
	}

	if key := strings.TrimSpace(PublicKeyBase64); key != "" {
		decoded, err := base64.StdEncoding.DecodeString(key)
		switch {
		case err != nil:
			// A build-time key that does not decode is a release-engineering error, not a customer
			// one. Log it loudly and leave licensing unenforced rather than bricking the console.
			log.Printf("license: PublicKeyBase64 does not decode (%v) — licensing NOT enforced", err)
		case len(decoded) != ed25519.PublicKeySize:
			log.Printf("license: PublicKeyBase64 is %d bytes, want %d — licensing NOT enforced",
				len(decoded), ed25519.PublicKeySize)
		default:
			l.publicKey = ed25519.PublicKey(decoded)
		}
	}

	for _, opt := range opts {
		if opt != nil {
			opt(l)
		}
	}

	// Applied before the first Reload so the initial status already reflects the database. Otherwise
	// a restart with a valid uploaded licence would log "trial" and then silently correct itself on
	// the next recheck, which is exactly the sort of thing that gets debugged twice.
	l.Reload()
	return l
}

// Enforced reports whether this build can refuse anything.
func (l *Loader) Enforced() bool { return len(l.publicKey) == ed25519.PublicKeySize }

// Status returns the current licence status, re-reading if the cached answer is stale.
func (l *Loader) Status() Status {
	if time.Since(l.lastChecked()) > recheckInterval {
		l.Reload()
	}
	st, _ := l.status.Load().(Status)
	return st
}

// Reload re-reads and re-verifies immediately. Called after a licence upload so the console reflects
// it at once, and on a timer via Status.
func (l *Loader) Reload() {
	l.status.Store(l.evaluate())
	l.lastCheck.Store(time.Now())
}

func (l *Loader) lastChecked() time.Time {
	t, _ := l.lastCheck.Load().(time.Time)
	return t
}

func (l *Loader) evaluate() Status {
	if !l.Enforced() {
		return Status{State: StateNotEnforced, Licensed: true}
	}

	raw, source, err := l.read()
	switch {
	case errors.Is(err, ErrNoLicense):
		// No file: the trial decides. This is the normal state of a fresh install.
		return Evaluate(nil, l.trialStart(), time.Now())
	case err != nil:
		// Unreadable for a reason other than absence — permissions, a directory where a file should
		// be. Not a forgery, so do not accuse the customer of one.
		log.Printf("license: cannot read %s: %v", source, err)
		st := Evaluate(nil, l.trialStart(), time.Now())
		if st.Licensed {
			// Still inside the trial, so nothing is blocked; say why the file was ignored anyway.
			st.Reason = st.Reason + " (a licence file is present but could not be read)"
		}
		return st
	}

	payload, err := Verify(raw, l.publicKey)
	if err != nil {
		log.Printf("license: %s does not verify: %v", source, err)
		return EvaluateInvalid(err)
	}
	return Evaluate(payload, l.trialStart(), time.Now())
}

// read returns the licence bytes and a human-readable description of WHERE they came from.
//
// The source is returned rather than assumed because there are two of them, and a log line that
// names the wrong one sends a support engineer to check a file that is perfectly fine -- or, when
// the database is the source, names nothing at all. That happened: "license:  does not verify",
// with an empty path, on a deployment whose licence was in the database.
func (l *Loader) read() ([]byte, string, error) {
	// Database first. A read error here is NOT a fallthrough to the file: the two sources can hold
	// different licences, and silently preferring a stale file because the database blipped would
	// change what the deployment is entitled to for a reason nobody could see. Report it instead.
	if l.document != nil {
		raw, err := l.document()
		switch {
		case err == nil && len(raw) > 0:
			return raw, "the licence uploaded to this deployment", nil
		case err != nil && !errors.Is(err, ErrNoLicense):
			return nil, "the licence uploaded to this deployment", err
		}
		// ErrNoLicense: nothing uploaded yet, so the file is the next place to look.
	}

	if l.path == "" {
		return nil, "", ErrNoLicense
	}
	raw, err := os.ReadFile(l.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, l.path, ErrNoLicense
	}
	if err != nil {
		return nil, l.path, err
	}
	if len(strings.TrimSpace(string(raw))) == 0 {
		// An empty file is "no licence", not a malformed one. It is what a half-finished upload or a
		// truncated volume mount looks like, and calling that tampering would be wrong.
		return nil, l.path, ErrNoLicense
	}
	return raw, l.path, nil
}
