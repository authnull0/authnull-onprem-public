package license

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

// issue signs a payload the way the signing CLI does, so the tests exercise the real format rather
// than a convenient approximation.
func issue(t *testing.T, priv ed25519.PrivateKey, p Payload) []byte {
	t.Helper()
	body, err := json.Marshal(p)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	out, err := json.Marshal(file{
		Payload:   body,
		Signature: base64.StdEncoding.EncodeToString(ed25519.Sign(priv, body)),
	})
	if err != nil {
		t.Fatalf("marshal file: %v", err)
	}
	return out
}

func keypair(t *testing.T) (ed25519.PublicKey, ed25519.PrivateKey) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	return pub, priv
}

func TestVerifyRoundTrip(t *testing.T) {
	pub, priv := keypair(t)
	want := Payload{
		ID: "lic-001", Customer: "Acme Ltd", Tier: "enterprise",
		IssuedAt:  time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC),
		ExpiresAt: time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC),
		Features:  []string{FeatureAD},
	}

	got, err := Verify(issue(t, priv, want), pub)
	if err != nil {
		t.Fatalf("Verify on a freshly signed licence: %v", err)
	}
	if got.Customer != want.Customer || !got.ExpiresAt.Equal(want.ExpiresAt) {
		t.Errorf("round trip lost data: %+v", got)
	}
	if !got.Has("AD") || !got.Has(" ad ") {
		t.Error("Has should be case- and space-insensitive")
	}
	if got.Has(FeatureDatabase) {
		t.Error("a licence granting only ad must not report database")
	}
}

// Editing the expiry date in a text editor is the obvious attack, and it must fail as a SIGNATURE
// error rather than as a parse error — the distinction is what lets the console say "this file was
// modified" instead of "something went wrong".
func TestVerifyRejectsEditedExpiry(t *testing.T) {
	pub, priv := keypair(t)
	raw := issue(t, priv, Payload{
		ID: "lic-002", Customer: "Acme",
		ExpiresAt: time.Now().AddDate(0, 0, -1),
		Features:  []string{FeatureAD},
	})

	var f file
	if err := json.Unmarshal(raw, &f); err != nil {
		t.Fatal(err)
	}
	var p map[string]any
	if err := json.Unmarshal(f.Payload, &p); err != nil {
		t.Fatal(err)
	}
	p["expiresAt"] = time.Now().AddDate(5, 0, 0).Format(time.RFC3339) // "renew" it
	edited, _ := json.Marshal(p)
	f.Payload = edited
	tampered, _ := json.Marshal(f)

	if _, err := Verify(tampered, pub); err != ErrBadSignature {
		t.Fatalf("an edited expiry must be ErrBadSignature, got %v", err)
	}
}

func TestVerifyRejectsForeignKeyAndJunk(t *testing.T) {
	pub, _ := keypair(t)
	_, otherPriv := keypair(t)

	// Signed by someone else's key — i.e. a licence somebody generated themselves.
	raw := issue(t, otherPriv, Payload{ID: "x", ExpiresAt: time.Now().AddDate(1, 0, 0), Features: []string{FeatureAD}})
	if _, err := Verify(raw, pub); err != ErrBadSignature {
		t.Errorf("foreign key should be ErrBadSignature, got %v", err)
	}

	if _, err := Verify(nil, pub); err != ErrNoLicense {
		t.Errorf("empty input should be ErrNoLicense, got %v", err)
	}
	for name, body := range map[string]string{
		"not json":       `hello`,
		"no signature":   `{"payload":{"id":"x"}}`,
		"bad base64 sig": `{"payload":{"id":"x"},"signature":"!!!"}`,
	} {
		if _, err := Verify([]byte(body), pub); err == nil {
			t.Errorf("%s should not verify", name)
		}
	}
}

// A licence with no expiry must be rejected outright. Accepting it would mean a zero time, which
// Evaluate would read as "expired in year 1" — technically safe, but it would present a signing bug
// as a customer's expired licence.
func TestVerifyRequiresExpiry(t *testing.T) {
	pub, priv := keypair(t)
	if _, err := Verify(issue(t, priv, Payload{ID: "x", Features: []string{FeatureAD}}), pub); err == nil {
		t.Error("a licence with no expiry must be rejected")
	}
}

func TestEvaluateStates(t *testing.T) {
	now := time.Date(2026, 6, 1, 12, 0, 0, 0, time.UTC)
	lic := func(d time.Duration) *Payload {
		return &Payload{Customer: "Acme", ExpiresAt: now.Add(d), Features: []string{FeatureAD}}
	}

	cases := []struct {
		name         string
		p            *Payload
		wantState    State
		wantLicensed bool
	}{
		{"comfortably valid", lic(90 * 24 * time.Hour), StateValid, true},
		{"inside the warning window", lic(10 * 24 * time.Hour), StateExpiring, true},
		{"expired yesterday", lic(-24 * time.Hour), StateExpired, false},
		// The boundary is worth pinning: "expires in exactly 14 days" must warn, not run out.
		{"exactly at the warning boundary", lic(ExpiryWarningWindow), StateExpiring, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			st := Evaluate(c.p, time.Time{}, now)
			if st.State != c.wantState || st.Licensed != c.wantLicensed {
				t.Errorf("got state=%s licensed=%v, want state=%s licensed=%v",
					st.State, st.Licensed, c.wantState, c.wantLicensed)
			}
			// Expiring must be as permissive as valid — the warning exists to prevent surprise, not
			// to start restricting early.
			if c.wantState == StateExpiring && !st.Licensed {
				t.Error("an expiring licence must still permit control-plane writes")
			}
		})
	}
}

func TestTrial(t *testing.T) {
	start := time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)

	fresh := Evaluate(nil, start, start.Add(24*time.Hour))
	if fresh.State != StateTrial || !fresh.Licensed {
		t.Fatalf("day 1 of the trial should be licensed, got %+v", fresh)
	}
	// A trial must grant everything: a crippled evaluation is how an evaluation is lost.
	for _, f := range []string{FeatureAD, FeatureDatabase, FeatureRADIUS} {
		if !fresh.Has(f) {
			t.Errorf("trial should grant %q", f)
		}
	}

	over := Evaluate(nil, start, start.Add(TrialDuration+time.Hour))
	if over.State != StateExpired || over.Licensed {
		t.Errorf("past the trial window must be expired and unlicensed, got %+v", over)
	}
	if over.Has(FeatureAD) {
		t.Error("an expired trial must not report features as available")
	}

	// No recorded start means first boot: treat as starting now rather than as long expired.
	first := Evaluate(nil, time.Time{}, start)
	if first.State != StateTrial {
		t.Errorf("an unrecorded trial start should begin the trial, got %s", first.State)
	}
}

// A licence listing no features must grant none. The failure mode this guards is a truncated or
// half-written file unlocking the whole product.
func TestEmptyFeatureListGrantsNothing(t *testing.T) {
	now := time.Now()
	st := Evaluate(&Payload{Customer: "Acme", ExpiresAt: now.AddDate(1, 0, 0)}, time.Time{}, now)
	if !st.Licensed {
		t.Fatal("a valid licence should still be Licensed even with no features")
	}
	for _, f := range []string{FeatureAD, FeatureDatabase, FeatureRADIUS} {
		if st.Has(f) {
			t.Errorf("no features listed, but %q reported as granted", f)
		}
	}
}

func TestInvalidStatusExplainsItself(t *testing.T) {
	st := EvaluateInvalid(ErrBadSignature)
	if st.State != StateInvalid || st.Licensed {
		t.Fatalf("an unverifiable licence must be invalid and unlicensed, got %+v", st)
	}
	if st.Reason == "" {
		t.Error("an invalid licence must explain itself — the console shows this verbatim")
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// The test this package exists for.
// ─────────────────────────────────────────────────────────────────────────────

// dataPlanePaths are the routes that carry live authentication. Every one of them must work with an
// expired, missing or forged licence.
//
// If any of these ever becomes gated, a lapsed licence stops authentication across a customer's
// domain controllers — an outage we would have caused, on their most critical path, from a billing
// event. That is strictly worse than any amount of unpaid usage, which is why this list is asserted
// rather than trusted to review.
var dataPlanePaths = []string{
	// The DC sensor's decision call, at the exact path it hardcodes.
	"/api/v1/policyService/EvaluateAuth",
	"/api/v1/policy/auth/evaluateAuth",
	// The RADIUS binary's decision endpoint used to be listed here, on both spellings. It now
	// calls do-authenticationV4 on authn-service directly, so the path it depends on is that
	// service's -- and the licence rule it needed still holds through the challenge endpoints
	// below, which authn-service's own MFA does not use either.
	//
	// The rule itself is unchanged and still worth stating: a licence lapse must never stop a
	// VPN login. The binary fails closed, so a 402 anywhere in its path would turn a billing
	// state into every remote worker being locked out.
	// Challenge lifecycle: sensor, gateway and RADIUS all use these.
	"/api/v1/ad/InitiateMFAChallenge",
	"/api/v1/ad/GetMFAChallenge",
	"/api/v1/ad/initiateMFAChallenge",
	"/api/v1/ad/getMFAChallenge",
	// ProxySQL's authorisation call. A licence lapse must not stop database logins: ProxySQL has
	// already discarded the client's password by the time it asks, so a 402 here would refuse every
	// database session in the estate.
	"/api/v1/database/mfa/authorize",
	"/api/v1/database/mfa/Authorize",
	// Directory sync and sensor status.
	"/api/v1/ad/UserSync",
	"/api/v1/ad/UpdateDomainStatus",
	// The phone answering a push.
	"/authentication/push/challenge",
	"/authentication/push/respond",
	"/authentication/push/status",
	"/authentication/push/getChallenge",
	"/authentication/push/confirmSetup",
	// Enrollment completion: a user finishing setup must not be blocked by a licence state, or an
	// expiry mid-rollout leaves half a directory unable to answer challenges.
	"/api/v1/ad/GetEnrollmentDetails",
	"/api/v1/ad/RegisterDevice",
	// Liveness. Gating health would make an expired deployment look dead to a load balancer.
	"/system/v1/health",
	"/system/v1/health/readiness",
	"/system/v1/health/liveness",
}

func TestDataPlaneIsNeverGated(t *testing.T) {
	for _, p := range dataPlanePaths {
		if IsGated(p) {
			t.Errorf("DATA-PLANE PATH IS GATED: %s — a licence lapse would break live authentication", p)
		}
	}
	t.Logf("%d data-plane paths confirmed ungated; %d control-plane paths gated",
		len(dataPlanePaths), len(GatedPaths()))
}

// Reads must survive expiry, or "read-only console" is a euphemism for "broken console".
func TestReadsAreNeverGated(t *testing.T) {
	for _, p := range []string{
		"/api/v1/policyService/ListPolicy",
		"/api/v1/policyService/listADGroups",
		"/api/v1/policyService/listADUsers",
		"/api/v1/policy/json/listPolicy",
		"/api/v1/policy/json/getEffectivePolicy",
		"/api/v1/policy/json/simulatePolicy",
		"/api/v1/policy/json/previewImpact",
		"/api/v1/policy/ad/mfaCoverage",
		"/api/v1/policyService/AuthenticationLog",
	} {
		if IsGated(p) {
			t.Errorf("read path is gated: %s — an expired console must still be able to show its own state", p)
		}
	}
}

func TestGateMiddleware(t *testing.T) {
	gin.SetMode(gin.TestMode)

	const gated = "/api/v1/policyService/CreateJSONPolicy"
	if !IsGated(gated) {
		t.Fatalf("%s should be gated; the table changed", gated)
	}

	run := func(st Status, path string) int {
		r := gin.New()
		r.Use(Gate(func() Status { return st }))
		r.POST(path, func(c *gin.Context) { c.Status(http.StatusOK) })
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, path, nil))
		return w.Code
	}

	if code := run(Status{State: StateValid, Licensed: true}, gated); code != http.StatusOK {
		t.Errorf("a valid licence must allow a gated write, got %d", code)
	}
	if code := run(Status{State: StateTrial, Licensed: true}, gated); code != http.StatusOK {
		t.Errorf("a trial must allow a gated write, got %d", code)
	}
	if code := run(Status{State: StateExpired, Licensed: false}, gated); code != http.StatusPaymentRequired {
		t.Errorf("an expired licence must refuse a gated write with 402, got %d", code)
	}
	// The load-bearing case: an ungated route is untouched even when unlicensed.
	if code := run(Status{State: StateExpired, Licensed: false}, "/api/v1/policyService/EvaluateAuth"); code != http.StatusOK {
		t.Errorf("EvaluateAuth must succeed while unlicensed, got %d", code)
	}
}

// The refusal must tell an admin that authentication is still working. Without that sentence, "402
// on create policy" reads like a total outage and gets escalated as one.
func TestGateMessageSaysEnforcementContinues(t *testing.T) {
	msg := gateMessage(Status{State: StateExpired, Reason: "trial period has ended"})
	for _, want := range []string{"trial period has ended", "continue to be enforced"} {
		if !strings.Contains(msg, want) {
			t.Errorf("refusal message %q should contain %q", msg, want)
		}
	}
}

// Reformatting a licence must not invalidate it, but editing one must.
//
// THIS TEST EXISTS BECAUSE THE SIGNING CLI FAILED TO VERIFY ITS OWN OUTPUT. The signature originally
// covered the literal payload bytes, and writing the document with json.MarshalIndent re-indented the
// embedded payload — so every licence the CLI produced was rejected as a forgery.
//
// The lesson generalises past that bug: a licence is a JSON file that people open in editors, paste
// into tickets and mail to each other, and plenty of tools reformat JSON on save. Signing literal
// bytes would mean a customer could invalidate a genuine licence by looking at it, and be told the
// file had been tampered with.
func TestSignedLicenceSurvivesReformattingButNotEditing(t *testing.T) {
	pub, priv := keypair(t)
	doc, err := Sign(Payload{
		ID: "lic-fmt", Customer: "Acme Ltd",
		IssuedAt:  time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC),
		ExpiresAt: time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC),
		Features:  []string{FeatureAD},
	}, priv)
	if err != nil {
		t.Fatalf("Sign: %v", err)
	}

	// The signer's own output must verify. Obvious, and it did not hold.
	if _, err := Verify(doc, pub); err != nil {
		t.Fatalf("a freshly signed licence must verify: %v", err)
	}

	// Re-indent as an editor's "format document" would: a TEXT transformation, which preserves key
	// order. json.Indent rather than Unmarshal-then-Marshal, because the latter round-trips through a
	// map and Go sorts map keys — that reorders the payload, which canonicalisation does NOT forgive.
	// See the limitation noted on Verify.
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(doc, &raw); err != nil {
		t.Fatal(err)
	}
	var indented bytes.Buffer
	if err := json.Indent(&indented, raw["payload"], "", "    "); err != nil {
		t.Fatal(err)
	}
	raw["payload"] = indented.Bytes()
	reformatted, err := json.Marshal(raw)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Verify(reformatted, pub); err != nil {
		t.Errorf("re-indenting must not invalidate a licence: %v", err)
	}

	// But changing a value must still fail. Canonicalisation removes whitespace, nothing else.
	var payload map[string]any
	if err := json.Unmarshal(raw["payload"], &payload); err != nil {
		t.Fatal(err)
	}
	payload["expiresAt"] = "2099-01-01T00:00:00Z"
	edited, _ := json.Marshal(payload)
	raw["payload"] = edited
	tampered, _ := json.Marshal(raw)
	if _, err := Verify(tampered, pub); err != ErrBadSignature {
		t.Errorf("an edited expiry must still be ErrBadSignature, got %v", err)
	}
}

// A customer may buy AD, Database and RADIUS in any combination, so the gate has to refuse a module
// they did not buy — while a licence that is perfectly valid stays valid for everything they did.
func TestFeatureCombinationsAreEnforced(t *testing.T) {
	gin.SetMode(gin.TestMode)

	const dbPath = "/api/v1/database/createDbHost"
	if f, gated := FeatureFor(dbPath); !gated || f != FeatureDatabase {
		t.Fatalf("%s should be gated on the database feature, got %q gated=%v", dbPath, f, gated)
	}

	call := func(features []string, path string) (int, string) {
		st := Status{State: StateValid, Licensed: true, Features: features}
		r := gin.New()
		r.Use(Gate(func() Status { return st }))
		r.POST(path, func(c *gin.Context) { c.Status(http.StatusOK) })
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, path, nil))
		return w.Code, w.Body.String()
	}

	// AD only: AD work allowed, database work refused.
	if code, _ := call([]string{FeatureAD}, "/api/v1/mfa/push/adminInvite"); code != http.StatusOK {
		t.Errorf("an AD licence must permit AD configuration, got %d", code)
	}
	code, body := call([]string{FeatureAD}, dbPath)
	if code != http.StatusPaymentRequired {
		t.Errorf("an AD-only licence must refuse database configuration, got %d", code)
	}
	if !strings.Contains(body, "Database MFA") {
		t.Errorf("the refusal should name the module in words an admin reads, got %s", body)
	}
	// It must NOT read as an expiry problem — the licence is fine, the module simply was not bought.
	if !strings.Contains(body, `"licensed":true`) {
		t.Errorf("a feature refusal must still report the licence as valid, got %s", body)
	}

	// Database only: the reverse.
	if code, _ := call([]string{FeatureDatabase}, dbPath); code != http.StatusOK {
		t.Errorf("a database licence must permit database configuration, got %d", code)
	}
	// Two of three.
	if code, _ := call([]string{FeatureAD, FeatureDatabase}, dbPath); code != http.StatusOK {
		t.Errorf("AD+database must permit database configuration, got %d", code)
	}
	// All three.
	if code, _ := call([]string{FeatureAD, FeatureDatabase, FeatureRADIUS}, dbPath); code != http.StatusOK {
		t.Errorf("a full licence must permit everything, got %d", code)
	}
}

// Policy authoring is shared by all three products — same endpoint, type in the body — so the URL
// cannot decide the feature. The middleware enforces licence validity only, and the per-type check
// happens where policyType has been parsed.
func TestSharedPolicyPathsAreNotTiedToOneFeature(t *testing.T) {
	for _, p := range []string{
		"/api/v1/policyService/CreateJSONPolicy",
		"/api/v1/policy/json/updatePolicy",
	} {
		f, gated := FeatureFor(p)
		if !gated {
			t.Errorf("%s should still require a licence", p)
		}
		if f != FeatureAny {
			t.Errorf("%s must not be tied to %q — all three policy types use it", p, f)
		}
	}

	for policyType, want := range map[string]string{
		"AD": FeatureAD, "GroupAD": FeatureAD, "ad": FeatureAD,
		"database": FeatureDatabase, "Database": FeatureDatabase,
		"radius": FeatureRADIUS,
		// An unrecognised type must stay authorable rather than becoming unreachable because this
		// mapping has not caught up with a new policy type.
		"somethingnew": FeatureAny,
	} {
		if got := FeatureForPolicyType(policyType); got != want {
			t.Errorf("FeatureForPolicyType(%q) = %q, want %q", policyType, got, want)
		}
	}
}

// The database AGENT endpoints are data plane. Gating them would stop database provisioning and
// logins on a licence lapse, which is the outage this design exists to prevent.
func TestDatabaseAgentPathsAreNeverGated(t *testing.T) {
	for _, p := range []string{
		"/api/v1/databaseService/dbSync",
		"/api/v1/databaseService/dbTable",
		"/api/v1/databaseService/dbUser",
		"/api/v1/databaseService/getJobQueue",
		"/api/v1/databaseService/updateQueue",
		"/api/v1/databaseService/registerDbAgent",
		"/api/v1/databaseService/updateLastActive",
		// How a user obtains the credentials to open a database session.
		"/api/v1/database/listConnections",
	} {
		if IsGated(p) {
			t.Errorf("DATA-PLANE PATH IS GATED: %s — a licence lapse would break database access", p)
		}
	}
}

// A build that does not enforce licensing must grant every feature.
//
// REGRESSION TEST FOR A PRODUCTION-BREAKING BUG. StateNotEnforced carries an empty feature list, so
// Has() answered false for everything, and Gate's feature branch turned every feature-scoped path
// into a 402 on Authnull's own SaaS and reference deployments — which is every build that has no
// licence public key compiled in, i.e. all of them today.
//
// The original tests missed it by asserting Status.Licensed rather than Status.Has, and by exercising
// the feature branch only with StateValid. Both mistakes are covered here.
func TestNotEnforcedGrantsEveryFeature(t *testing.T) {
	st := Status{State: StateNotEnforced, Licensed: true}
	for _, f := range []string{FeatureAD, FeatureDatabase, FeatureRADIUS} {
		if !st.Has(f) {
			t.Errorf("a non-enforcing build must grant %q", f)
		}
	}

	// And end to end through the middleware, on a path that IS feature-scoped.
	gin.SetMode(gin.TestMode)
	const dbPath = "/api/v1/database/createDbHost"
	if f, _ := FeatureFor(dbPath); f != FeatureDatabase {
		t.Fatalf("%s should be scoped to the database feature; the table changed", dbPath)
	}
	r := gin.New()
	r.Use(Gate(func() Status { return st }))
	r.POST(dbPath, func(c *gin.Context) { c.Status(http.StatusOK) })
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, dbPath, nil))
	if w.Code != http.StatusOK {
		t.Errorf("a non-enforcing build must allow feature-scoped writes, got %d: %s", w.Code, w.Body.String())
	}
}
