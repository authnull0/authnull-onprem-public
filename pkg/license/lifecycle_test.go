package license

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

// The whole commercial lifecycle, once, through the real middleware.
//
// WHY THIS EXISTS SEPARATELY FROM THE OTHER TESTS IN THIS PACKAGE
//
// Everything here is covered piecewise elsewhere: Verify has its own tests, Evaluate has a table of
// states, Gate has a middleware test. What none of them do is run the SEQUENCE a paying customer
// actually walks through, against ONE Loader, with a REAL signature, on the REAL gated paths.
//
// That sequence is where the mistakes live. Each piece can be correct while the joins are wrong --
// an uploaded licence that does not take effect until a restart, a renewal that leaves the console
// read-only, a feature-scoped path that opens up when the licence lapses. Those are the failures a
// customer would report as "we paid and it is still broken", and not one of them is visible from a
// unit test of a single function.
//
// TIME IS MOVED BY MOVING THE TRIAL START AND THE EXPIRY DATES, not by faking a clock. Loader calls
// time.Now() internally and should keep doing so -- a clock injected purely for tests is a seam that
// only tests use. Backdating the recorded trial start is exactly what the real TrialStore hands over,
// so this exercises the production path rather than a parallel one.

// enforcingBuild installs a test keypair as the compiled-in public key for the duration of a test,
// making this behave like the on-premise build rather than the SaaS one.
//
// The key is generated per-run rather than checked in, so a fixture can never be mistaken for a real
// signing key, and nothing in this file could sign a licence a customer's deployment would accept.
func enforcingBuild(t *testing.T) ed25519.PrivateKey {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	saved := PublicKeyBase64
	PublicKeyBase64 = base64.StdEncoding.EncodeToString(pub)
	t.Cleanup(func() { PublicKeyBase64 = saved })
	return priv
}

// deployment is one running service: its licence sources and its HTTP surface.
type deployment struct {
	t      *testing.T
	loader *Loader
	router *gin.Engine

	mu         sync.Mutex
	trialStart time.Time
	document   []byte // what the master database holds, i.e. what was uploaded
}

// newDeployment boots a service with the trial starting trialAgo in the past and no licence
// installed -- a fresh customer install.
func newDeployment(t *testing.T, trialAgo time.Duration) *deployment {
	t.Helper()
	gin.SetMode(gin.TestMode)

	d := &deployment{t: t, trialStart: time.Now().Add(-trialAgo)}

	// Both sources are the real Loader options. WithDocumentSource is the seam the DocumentStore
	// occupies in production, and its contract is exactly this: bytes, or ErrNoLicense.
	d.loader = NewLoader("", d.readTrialStart, WithDocumentSource(d.readDocument))
	if !d.loader.Enforced() {
		t.Fatal("the loader is not enforcing, so this test would pass without testing anything")
	}

	r := gin.New()
	r.Use(Gate(d.loader.Status))
	// Real gated paths, from the real table. Registering every one of them means a path added to the
	// table without thought still gets walked through the whole lifecycle here.
	for _, p := range GatedPaths() {
		r.POST(p, func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"ok": true}) })
	}
	// Two paths that must NEVER be gated, for contrast: an agent sync and a console read.
	r.POST("/api/v1/database/dbSync", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"ok": true}) })
	r.GET("/api/v1/policyService/policyJson", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"ok": true}) })
	d.router = r
	return d
}

func (d *deployment) readTrialStart() time.Time {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.trialStart
}

func (d *deployment) readDocument() ([]byte, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if len(d.document) == 0 {
		return nil, ErrNoLicense
	}
	return d.document, nil
}

// install is what UploadLicense does once verification passes: store the document, then Reload so the
// customer is unblocked without waiting for the recheck interval or a restart.
func (d *deployment) install(raw []byte) {
	d.mu.Lock()
	d.document = raw
	d.mu.Unlock()
	d.loader.Reload()
}

// backdateTrial moves the recorded first boot, which is how this test advances the calendar.
func (d *deployment) backdateTrial(ago time.Duration) {
	d.mu.Lock()
	d.trialStart = time.Now().Add(-ago)
	d.mu.Unlock()
	d.loader.Reload()
}

type gateResult struct {
	code     int
	Error    string `json:"error"`
	State    string `json:"state"`
	Feature  string `json:"feature"`
	Message  string `json:"message"`
	Licensed bool   `json:"licensed"`
}

func (d *deployment) call(method, path string) gateResult {
	d.t.Helper()
	w := httptest.NewRecorder()
	d.router.ServeHTTP(w, httptest.NewRequest(method, path, nil))
	res := gateResult{code: w.Code}
	_ = json.Unmarshal(w.Body.Bytes(), &res)
	return res
}

func (d *deployment) post(path string) gateResult { return d.call(http.MethodPost, path) }

// mustPass and mustBlock read as the business rule rather than as HTTP.
func (d *deployment) mustPass(stage, path string) {
	d.t.Helper()
	if got := d.post(path); got.code != http.StatusOK {
		d.t.Errorf("%s: POST %s = %d, want 200 (state=%s, %s)", stage, path, got.code, got.State, got.Message)
	}
}

func (d *deployment) mustBlock(stage, path string) gateResult {
	d.t.Helper()
	got := d.post(path)
	if got.code != http.StatusPaymentRequired {
		d.t.Errorf("%s: POST %s = %d, want 402", stage, path, got.code)
	}
	return got
}

// signLicence issues one, the way the CEO's signing tool will.
func signLicence(t *testing.T, priv ed25519.PrivateKey, id string, expiresIn time.Duration, features ...string) []byte {
	t.Helper()
	raw, err := Sign(Payload{
		ID:        id,
		Customer:  "Acme Corp",
		IssuedAt:  time.Now().Add(-time.Hour).UTC(),
		ExpiresAt: time.Now().Add(expiresIn).UTC(),
		Tier:      "enterprise",
		Features:  features,
		Nonce:     id,
	}, priv)
	if err != nil {
		t.Fatalf("sign %s: %v", id, err)
	}
	return raw
}

// Representative paths, chosen because each is gated differently.
const (
	pathSharedPolicy = "/api/v1/policyService/CreateJSONPolicy"    // FeatureAny
	pathADOnly       = "/api/v1/policyService/DiscoverADPolicies"  // FeatureAD
	pathDatabase     = "/api/v1/database/createDbHost"             // FeatureDatabase
	pathAgentSync    = "/api/v1/database/dbSync"                   // never gated: data plane
	pathConsoleRead  = "/api/v1/policyService/policyJson"          // never gated: a read
)

// TestLicenceLifecycle walks a customer from install to renewal, in order, on one deployment.
func TestLicenceLifecycle(t *testing.T) {
	priv := enforcingBuild(t)
	d := newDeployment(t, 0) // installed just now

	// ── 1. Day 1: a fresh install runs on the trial, and the trial grants everything ──────────
	//
	// A crippled evaluation is how an evaluation is lost, so all three modules must work here even
	// though nothing has been bought.
	for _, p := range []string{pathSharedPolicy, pathADOnly, pathDatabase} {
		d.mustPass("day 1 trial", p)
	}
	if st := d.loader.Status(); st.State != StateTrial || !st.Licensed {
		t.Fatalf("day 1: state=%s licensed=%v, want trial/true", st.State, st.Licensed)
	}

	// ── 2. Day 29: still working, and the console can now warn ───────────────────────────────
	d.backdateTrial(29 * 24 * time.Hour)
	d.mustPass("day 29", pathSharedPolicy)
	if st := d.loader.Status(); st.DaysRemaining != 0 {
		t.Errorf("day 29: daysRemaining = %d, want 0 (the last day)", st.DaysRemaining)
	}

	// ── 3. Day 31: the trial has ended. The console goes read-only, and NOTHING ELSE DOES ────
	//
	// This is the single most important assertion in the file. If the two "never gated" calls below
	// ever start returning 402, a customer's databases stop accepting logins and their agents stop
	// syncing because an invoice was late.
	d.backdateTrial(31 * 24 * time.Hour)
	blocked := d.mustBlock("day 31", pathSharedPolicy)
	if blocked.State != string(StateExpired) {
		t.Errorf("day 31: state = %q, want %q", blocked.State, StateExpired)
	}
	if !strings.Contains(blocked.Message, "trial period has ended") {
		t.Errorf("day 31: message should say the trial ended, got %q", blocked.Message)
	}
	if !strings.Contains(blocked.Message, "continue to be enforced") {
		t.Errorf("day 31: message must say enforcement continues, or this reads as an outage: %q", blocked.Message)
	}
	d.mustPass("day 31 data plane", pathAgentSync)
	if got := d.call(http.MethodGet, pathConsoleRead); got.code != http.StatusOK {
		t.Errorf("day 31: a console READ returned %d — an expired deployment must still be readable", got.code)
	}

	// ── 4. They buy the full product. The upload unblocks them WITHOUT A RESTART ─────────────
	d.install(signLicence(t, priv, "LIC-001", 365*24*time.Hour, FeatureAD, FeatureDatabase, FeatureRADIUS))
	for _, p := range []string{pathSharedPolicy, pathADOnly, pathDatabase} {
		d.mustPass("licensed", p)
	}
	st := d.loader.Status()
	if st.State != StateValid || st.Customer != "Acme Corp" {
		t.Fatalf("licensed: state=%s customer=%q, want valid/Acme Corp", st.State, st.Customer)
	}
	// The trial is still expired underneath. A valid licence must override it, or a renewal would
	// only ever work on a deployment less than a month old.
	if !st.Licensed {
		t.Error("a valid licence must override an exhausted trial")
	}

	// ── 5. Renewal, downgraded to AD only ────────────────────────────────────────────────────
	//
	// The customer drops Database MFA. AD keeps working; database CONFIGURATION is refused, with a
	// different error from expiry, because "you did not buy this" and "you did not pay" need
	// different answers from support.
	d.install(signLicence(t, priv, "LIC-002", 365*24*time.Hour, FeatureAD))
	d.mustPass("ad-only", pathADOnly)
	d.mustPass("ad-only shared policy", pathSharedPolicy)
	refused := d.mustBlock("ad-only", pathDatabase)
	if refused.Error != "feature not licensed" {
		t.Errorf("ad-only: error = %q, want \"feature not licensed\"", refused.Error)
	}
	if !refused.Licensed {
		t.Error("ad-only: licensed must be true — the licence is valid, the module simply is not included")
	}
	if refused.Feature != FeatureDatabase {
		t.Errorf("ad-only: feature = %q, want %q — the console needs to know what to offer to sell", refused.Feature, FeatureDatabase)
	}
	// Database logins keep working. Losing the module means losing the ability to CHANGE it.
	d.mustPass("ad-only data plane", pathAgentSync)

	// ── 6. They let it lapse ─────────────────────────────────────────────────────────────────
	d.install(signLicence(t, priv, "LIC-003", -24*time.Hour, FeatureAD, FeatureDatabase))
	lapsed := d.mustBlock("lapsed", pathADOnly)
	if lapsed.State != string(StateExpired) {
		t.Errorf("lapsed: state = %q, want expired", lapsed.State)
	}
	if !strings.Contains(lapsed.Message, "licence expired on") {
		t.Errorf("lapsed: message should name the expiry date, got %q", lapsed.Message)
	}
	// Distinguishable from the trial ending: an admin needs to know which of the two happened.
	if strings.Contains(lapsed.Message, "trial") {
		t.Errorf("lapsed: an expired licence must not be reported as an expired trial: %q", lapsed.Message)
	}
	if expired := d.loader.Status(); expired.Customer != "Acme Corp" || expired.ExpiresAt == nil {
		t.Error("an expired licence must still report who it belonged to and when it ran out")
	}
	d.mustPass("lapsed data plane", pathAgentSync)

	// ── 7. They renew, and are unblocked again ───────────────────────────────────────────────
	d.install(signLicence(t, priv, "LIC-004", 365*24*time.Hour, FeatureAD, FeatureDatabase, FeatureRADIUS))
	for _, p := range []string{pathSharedPolicy, pathADOnly, pathDatabase} {
		d.mustPass("renewed", p)
	}
}

// TestEditedExpiryIsRefusedByTheRunningService is the attack the signature exists to stop, checked
// where it matters -- through the gate, not through Verify.
//
// Someone whose trial has ended edits the expiry date in the licence file. Verify has its own test
// for this; what this asserts is that the running service ends up REFUSING rather than accepting,
// and says so in a way that does not accuse a customer with a genuinely corrupt file of forgery.
func TestEditedExpiryIsRefusedByTheRunningService(t *testing.T) {
	priv := enforcingBuild(t)
	d := newDeployment(t, 40*24*time.Hour) // trial long gone

	raw := signLicence(t, priv, "LIC-EDIT", 30*24*time.Hour, FeatureAD)
	d.install(raw)
	d.mustPass("before editing", pathADOnly)

	// Push the expiry out by a decade, leaving the signature alone.
	edited := strings.Replace(string(raw), time.Now().Add(30*24*time.Hour).UTC().Format("2006"),
		time.Now().Add(30*24*time.Hour).AddDate(10, 0, 0).UTC().Format("2006"), 1)
	if edited == string(raw) {
		t.Fatal("the edit did not change anything, so this test proves nothing")
	}
	d.install([]byte(edited))

	got := d.mustBlock("edited", pathADOnly)
	if got.State != string(StateInvalid) {
		t.Errorf("edited: state = %q, want %q — an edited licence is not the same as an expired one",
			got.State, StateInvalid)
	}
	if !strings.Contains(got.Message, "signature does not verify") {
		t.Errorf("edited: message should name the signature, got %q", got.Message)
	}
	// And enforcement is untouched even here. A forged licence is not grounds for an outage.
	d.mustPass("edited, data plane", pathAgentSync)
}

// TestALicenceFromAnotherVendorKeyIsRefused covers the case of a licence signed by a DIFFERENT key --
// a leaked development key, or a self-signed file made by someone who read this package.
func TestALicenceFromAnotherVendorKeyIsRefused(t *testing.T) {
	enforcingBuild(t) // this deployment trusts one key
	_, otherPriv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("generate: %v", err)
	}

	d := newDeployment(t, 40*24*time.Hour)
	d.install(signLicence(t, otherPriv, "LIC-FOREIGN", 365*24*time.Hour, FeatureAD, FeatureDatabase))

	got := d.mustBlock("foreign key", pathADOnly)
	if got.State != string(StateInvalid) {
		t.Errorf("foreign key: state = %q, want %q", got.State, StateInvalid)
	}
}

// TestSaaSBuildIsUnaffectedByAnyOfThis pins the default, because getting it wrong takes down
// deployments that have nothing to do with licensing.
//
// Every build except the on-premise one is compiled with no public key. Such a build must behave as
// though this package were not wired in at all -- including on the feature-scoped paths, which is
// precisely where an earlier version of Status.Has() would have returned 402 for every customer on
// Authnull's own SaaS.
func TestSaaSBuildIsUnaffectedByAnyOfThis(t *testing.T) {
	saved := PublicKeyBase64
	PublicKeyBase64 = ""
	t.Cleanup(func() { PublicKeyBase64 = saved })

	gin.SetMode(gin.TestMode)
	loader := NewLoader("", func() time.Time { return time.Now().Add(-10 * 365 * 24 * time.Hour) })
	if loader.Enforced() {
		t.Fatal("a build with no public key must not enforce")
	}

	r := gin.New()
	r.Use(Gate(loader.Status))
	for _, p := range GatedPaths() {
		r.POST(p, func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"ok": true}) })
	}

	// A trial start ten years ago would expire any enforcing deployment. This one must not notice.
	for _, p := range GatedPaths() {
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, p, nil))
		if w.Code != http.StatusOK {
			t.Fatalf("POST %s = %d on a non-enforcing build — this would be an outage on every SaaS "+
				"and reference deployment", p, w.Code)
		}
	}
	if st := loader.Status(); st.State != StateNotEnforced {
		t.Errorf("state = %q, want %q", st.State, StateNotEnforced)
	}
}

// TestTrialNeverReportsExpiring pins the fact that surprised the documentation.
//
// A purchased licence spends its last fortnight in StateExpiring, which is what a console banner would
// naturally key on. THE TRIAL DOES NOT: it reports StateTrial until the moment it reports StateExpired.
// So a banner written as `state === "expiring" ? warn() : ok()` shows nothing for twenty-nine days and
// then a read-only console on the thirtieth -- which is both a support call and a lost sale.
//
// The rule the console must use instead is DaysRemaining, populated for both. Asserted here rather
// than left as a comment, because onprem/docs/INSTALL.md had already come to describe a day-16 warning
// that does not exist.
func TestTrialNeverReportsExpiring(t *testing.T) {
	now := time.Now()

	for day := 1; day <= 29; day++ {
		st := Evaluate(nil, now.AddDate(0, 0, -day), now)
		if st.State != StateTrial {
			t.Errorf("day %d of the trial: state = %q, want %q", day, st.State, StateTrial)
		}
		if !st.Licensed {
			t.Errorf("day %d of the trial must still permit changes", day)
		}
		if st.DaysRemaining != 30-day {
			t.Errorf("day %d: daysRemaining = %d, want %d — the console warns on this number",
				day, st.DaysRemaining, 30-day)
		}
	}

	// Day 30 is the cliff.
	if st := Evaluate(nil, now.AddDate(0, 0, -30), now); st.State != StateExpired || st.Licensed {
		t.Errorf("day 30: state=%s licensed=%v, want expired/false", st.State, st.Licensed)
	}

	// A purchased licence DOES warn, and the contrast is the point.
	near := Evaluate(&Payload{Customer: "Acme", ExpiresAt: now.Add(13 * 24 * time.Hour),
		Features: []string{FeatureAD}}, now, now)
	if near.State != StateExpiring || !near.Licensed {
		t.Errorf("a licence 13 days from expiry: state=%s licensed=%v, want expiring/true",
			near.State, near.Licensed)
	}

	// And the reason reads correctly at one day, which is when somebody actually reads it.
	if st := Evaluate(nil, now.AddDate(0, 0, -29), now); !strings.Contains(st.Reason, "1 day remaining") {
		t.Errorf("reason on the last day = %q, want \"1 day remaining\"", st.Reason)
	}
}
