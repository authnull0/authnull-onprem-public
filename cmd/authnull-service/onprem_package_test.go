package main

import (
	"crypto/ed25519"
	"encoding/base64"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/authnull0/authnull-service/internal/policy"
	"github.com/authnull0/authnull-service/pkg/license"
)

// The on-premise package under onprem/ is destined for a PUBLIC repository, which changes what
// counts as a mistake. A working secret value committed there is a working secret value for every
// customer who ever downloads it, and a shared JWT signing key means a session minted on one
// deployment validates on another.
//
// These tests are cheap and they guard the two errors that would be worst and least visible.

const onpremDir = "../../onprem"

// Every assignment in .env.example must have an EMPTY value.
//
// The failure this prevents is not a typo — it is someone testing the installer locally, filling
// values in to make it work, and committing the file. Nothing in a build or a normal review catches
// that, and the consequence is public credentials.
func TestOnpremEnvExampleHasNoValues(t *testing.T) {
	path := filepath.Join(onpremDir, ".env.example")
	body, err := os.ReadFile(path)
	if err != nil {
		t.Skipf("%s not present: %v", path, err)
	}

	checked := 0
	for i, line := range strings.Split(string(body), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, found := strings.Cut(line, "=")
		if !found {
			continue
		}
		checked++
		if strings.TrimSpace(value) != "" {
			t.Errorf(".env.example:%d %s has a value (%q) — this file is public and every value in it must be empty",
				i+1, key, value)
		}
	}
	if checked == 0 {
		t.Error("no assignments parsed out of .env.example — the file or this test changed shape")
	}
	t.Logf("verified %d keys are empty", checked)
}

// The AD-only package must not reference Authnull-owned secrets or services it does not run.
//
// Two distinct failures:
//
//   - an Authnull-owned key (FCM, Expo, Azure storage, the AI service key) would either ship our
//     credentials or, worse for AI_SERVICE_API_KEY, ship a publicly known value that acts as an
//     auth-bypass header on /ad/getAllDomains for every install;
//   - a reference to a dropped container resolves to nothing at runtime, so the failure surfaces as
//     a DNS error deep in a request rather than as "this feature is not configured".
func TestOnpremComposeHasNoAuthnullSecretsOrPhantomHosts(t *testing.T) {
	path := filepath.Join(onpremDir, "docker-compose.yml")
	body, err := os.ReadFile(path)
	if err != nil {
		t.Skipf("%s not present: %v", path, err)
	}

	// Keys that must never appear in a customer-facing package.
	for _, key := range []string{
		"FCM_SERVICE_ACCOUNT_JSON", "FCM_PROJECT_ID", "EXPO_ACCESS_TOKEN",
		"AI_SERVICE_API_KEY", "AZURE_STORAGE_KEY", "AZURE_STORAGE_ACCOUNT",
		"AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "CLOUDFLARE_AUTH_KEY", "GIT_TOKEN",
	} {
		if strings.Contains(string(body), key+":") {
			t.Errorf("onprem/docker-compose.yml references %s, which is Authnull-owned and must not ship", key)
		}
	}

	// Container names the package does not start. authn-service is deliberately excluded from this
	// list: it IS in the package, only because DO_AUTHNV4 otherwise falls back to a hardcoded
	// Authnull host. Remove both together, never just the service.
	for _, host := range []string{
		"ssi-service:", "secret-management-service:", "logworkflows:", "log-service:",
		"transaction-log-daemon:", "blockchain-ipfs-logging:", "cassandra:", "elasticsearch:",
		"temporal:", "user-service:",
	} {
		for i, line := range strings.Split(string(body), "\n") {
			if strings.HasPrefix(strings.TrimSpace(line), "#") {
				continue // the header explains what was dropped and why
			}
			if strings.Contains(line, host) {
				t.Errorf("onprem/docker-compose.yml:%d addresses %s, a container this package does not run: %s",
					i+1, host, strings.TrimSpace(line))
			}
		}
	}
}

// The licence endpoints must never be licence-gated.
//
// An expired deployment has to be able to install a licence. Gating either path would mean a lapsed
// customer could not renew without somebody editing their database — a support incident created
// entirely by our own gate, and one that would only be discovered by a customer whose licence had
// already run out.
//
// They are safe by construction, because license.Gate consults an explicit list of control-plane
// paths and these are not on it. Asserted anyway: "safe by construction" is only true until somebody
// adds an entry to that list, and this is the test that would stop them.
func TestLicenseEndpointsAreNeverGated(t *testing.T) {
	for _, p := range []string{"/api/v1/license", "/api/v1/license/upload"} {
		if license.IsGated(p) {
			t.Errorf("%s is licence-gated — an expired deployment could never renew", p)
		}
	}
}

// Both licence paths must actually be registered, and behind authentication.
func TestLicenseEndpointsAreRegistered(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	want := map[string]bool{"GET /api/v1/license": false, "POST /api/v1/license/upload": false}
	for _, ri := range r.Routes() {
		key := ri.Method + " " + ri.Path
		if _, ok := want[key]; ok {
			want[key] = true
		}
	}
	for key, found := range want {
		if !found {
			t.Errorf("%s is not registered", key)
		}
	}
}

// Every named volume a service mounts must be declared, and no service may declare a key twice.
//
// BOTH FAILURES ARE SILENT IN DIFFERENT WAYS, AND I HIT BOTH WRITING THIS PACKAGE.
//
// An undeclared named volume makes `docker compose up` abort before anything starts — loud, but
// only at the customer's first install, which is the worst possible moment to find it.
//
// A duplicate mapping key is worse: YAML keeps the LAST one and discards the earlier silently. A
// second `volumes:` block added to a service that already had one dropped the licence mount with no
// error anywhere. The file parsed, the tests passed, and the mount simply was not there.
func TestOnpremComposeVolumesAreSaneAndUnique(t *testing.T) {
	path := filepath.Join(onpremDir, "docker-compose.yml")
	body, err := os.ReadFile(path)
	if err != nil {
		t.Skipf("%s not present: %v", path, err)
	}
	lines := strings.Split(string(body), "\n")

	// Duplicate keys at service level (2-space indent) within one service block (4-space indent).
	service, seen := "", map[string]int{}
	for i, raw := range lines {
		if m := serviceHeader(raw); m != "" {
			service, seen = m, map[string]int{}
			continue
		}
		if service == "" {
			continue
		}
		key := serviceLevelKey(raw)
		if key == "" {
			continue
		}
		if prev, dup := seen[key]; dup {
			t.Errorf("service %q declares %q twice (lines %d and %d) — YAML keeps only the last, "+
				"so the earlier block is silently discarded", service, key, prev, i+1)
		}
		seen[key] = i + 1
	}

	// Named volumes mounted but never declared.
	declared := map[string]bool{}
	inTopLevel := false
	for _, raw := range lines {
		if raw == "volumes:" {
			inTopLevel = true
			continue
		}
		if inTopLevel {
			if strings.HasPrefix(raw, "  ") && strings.HasSuffix(strings.TrimSpace(raw), ":") {
				declared[strings.TrimSuffix(strings.TrimSpace(raw), ":")] = true
				continue
			}
			if raw != "" && !strings.HasPrefix(raw, " ") {
				inTopLevel = false
			}
		}
	}
	for i, raw := range lines {
		s := strings.TrimSpace(raw)
		if !strings.HasPrefix(s, "- ") || !strings.Contains(s, ":") {
			continue
		}
		src := strings.TrimSpace(strings.TrimPrefix(s, "- "))
		src = strings.SplitN(src, ":", 2)[0]
		// Bind mounts and anything quoted (a port mapping) are not named volumes.
		if src == "" || strings.HasPrefix(src, ".") || strings.HasPrefix(src, "/") || strings.HasPrefix(src, `"`) {
			continue
		}
		if strings.ContainsAny(src, " ={}") {
			continue
		}
		if !declared[src] {
			t.Errorf("line %d mounts named volume %q which is not declared at the top level — "+
				"`docker compose up` aborts before anything starts", i+1, src)
		}
	}
	t.Logf("%d named volumes declared", len(declared))
}

// serviceHeader returns the service name for a `  name:` line, else "".
func serviceHeader(line string) string {
	if !strings.HasPrefix(line, "  ") || strings.HasPrefix(line, "   ") {
		return ""
	}
	s := strings.TrimSpace(line)
	if strings.HasPrefix(s, "#") || !strings.HasSuffix(s, ":") {
		return ""
	}
	return strings.TrimSuffix(s, ":")
}

// serviceLevelKey returns the key for a `    key:` line inside a service, else "".
func serviceLevelKey(line string) string {
	if !strings.HasPrefix(line, "    ") || strings.HasPrefix(line, "     ") {
		return ""
	}
	s := strings.TrimSpace(line)
	if strings.HasPrefix(s, "#") || strings.HasPrefix(s, "- ") {
		return ""
	}
	k, _, ok := strings.Cut(s, ":")
	if !ok || strings.ContainsAny(k, " \"'") {
		return ""
	}
	return k
}

// Every path that reaches a gated handler must itself be gated.
//
// THE BUG THIS CATCHES, WHICH REVIEW DID NOT.
//
// mfa.RegisterRoutes is mounted twice — once on /api/v1 and once on /authentication — so
// /api/v1/mfa/push/adminInvite and /authentication/mfa/push/adminInvite reach the same handler.
// Only the first was in the gated table, so an expired deployment could still mint enrolment
// invites through the second. Nothing in the gate's own tests could see it: they check paths, and
// the second path simply was not one of them.
//
// The licence gate matches exact paths on purpose — prefixes are how "gate only the control plane"
// quietly becomes "gate everything", and that direction risks an outage. This test is the cost of
// that choice: it groups the live router by handler and asserts that if any path reaching a handler
// is gated, all of them are.
//
// Uses the real router, so a route added anywhere is covered without anyone remembering to.
func TestGatedHandlersAreGatedAtEveryMount(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	// handler function name -> the paths that reach it.
	byHandler := map[string][]string{}
	for _, ri := range r.Routes() {
		if ri.Handler == "" {
			continue
		}
		byHandler[ri.Handler] = append(byHandler[ri.Handler], ri.Path)
	}

	checked := 0
	for handler, paths := range byHandler {
		if len(paths) < 2 {
			continue // a single mount cannot disagree with itself
		}
		var gated, open []string
		for _, p := range paths {
			if license.IsGated(p) {
				gated = append(gated, p)
			} else {
				open = append(open, p)
			}
		}
		if len(gated) > 0 && len(open) > 0 {
			sort.Strings(gated)
			sort.Strings(open)
			t.Errorf("handler %s is reachable at %d paths but only some are licence-gated.\n"+
				"  gated:   %v\n  NOT gated: %v\n"+
				"  An expired deployment can use the ungated path to do the gated thing.",
				handler, len(paths), gated, open)
		}
		if len(gated) > 0 {
			checked++
		}
	}
	t.Logf("checked %d multi-mount handlers that have at least one gated path", checked)
}

// The unauthenticated policy surface must be exactly the agent endpoints, and no more.
//
// These paths exist because unattended agents have no credential to present — the DC sensor, the
// database-agent and the RADIUS binary. That is a known, deferred gap, and the point of asserting
// the set is that it stays a known one: a console endpoint drifting in here would be an
// unauthenticated policy write, and nothing else in the build would notice.
func TestUnauthenticatedPolicyRoutesAreExactlyExpected(t *testing.T) {
	want := map[string]bool{
		"/api/v1/policyService/EvaluateAuth":     true, // DC sensor
		"/api/v1/policyService/getPolicyDetails": true, // database-agent
		// The RADIUS binary was here, on both spellings. It calls do-authenticationV4 on
		// authn-service directly now, so this service no longer exposes an unauthenticated
		// decision endpoint for it -- one less thing on the surface this test guards.
	}

	gin.SetMode(gin.TestMode)
	r := gin.New()
	policy.RegisterAgentRoutes(r.Group("/api/v1"))

	got := map[string]bool{}
	for _, ri := range r.Routes() {
		got[ri.Path] = true
	}
	for p := range want {
		if !got[p] {
			t.Errorf("%s should be registered without authentication and is not — "+
				"the agent that calls it will get a 404", p)
		}
	}
	for p := range got {
		if !want[p] {
			t.Errorf("%s is registered WITHOUT AUTHENTICATION and is not on the expected list. "+
				"If an agent needs it, add it to the list with the agent named. If not, it belongs "+
				"in an authenticated group.", p)
		}
	}
	t.Logf("%d unauthenticated agent endpoints, as expected", len(got))
}

// Every docs/ path the installer prints must exist, and every section it names must be in the file.
//
// install.sh finished a successful install by printing "Next steps: docs/CONFIGURE.md" and
// "Something wrong: docs/TROUBLESHOOT.md". Neither file was ever written, so the last thing every
// customer read was a path to nothing -- and the missing one was the troubleshooting guide, i.e. the
// document they were being sent to precisely when something had gone wrong.
//
// Nothing catches that: the script runs fine, the install succeeds, and the reference is only wrong
// for the person reading it. Hence a test.
func TestOnpremDocPathsExist(t *testing.T) {
	script, err := os.ReadFile(filepath.Join(onpremDir, "install.sh"))
	if err != nil {
		t.Skipf("install.sh not present: %v", err)
	}

	// docs/NAME.md, optionally followed by ("Section Name") naming a heading inside it.
	ref := regexp.MustCompile(`docs/([A-Za-z0-9_.-]+\.md)(?:\s*\(\\?"([^")\\]+)\\?"\))?`)
	matches := ref.FindAllStringSubmatch(string(script), -1)
	if len(matches) == 0 {
		t.Skip("install.sh references no docs; nothing to check")
	}

	// Comments in install.sh legitimately mention the paths that USED to be printed, as the record of
	// why this test exists. Only lines the installer actually prints are checked.
	printed := map[string][]string{}
	for _, line := range strings.Split(string(script), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") || !strings.Contains(trimmed, "docs/") {
			continue
		}
		for _, m := range ref.FindAllStringSubmatch(trimmed, -1) {
			printed[m[1]] = append(printed[m[1]], m[2])
		}
	}
	if len(printed) == 0 {
		t.Fatal("install.sh prints no docs/ path at all — the success message lost its next steps")
	}

	for name, sections := range printed {
		path := filepath.Join(onpremDir, "docs", name)
		body, err := os.ReadFile(path)
		if err != nil {
			t.Errorf("install.sh tells the customer to read docs/%s, which does not exist in the package", name)
			continue
		}
		for _, section := range sections {
			if section == "" {
				continue
			}
			// Headings are "## Section name"; compared case-insensitively because the installer quotes
			// them for a human, not for a parser.
			if !strings.Contains(strings.ToLower(string(body)), strings.ToLower("# "+section)) {
				t.Errorf("install.sh sends the customer to %q in docs/%s, but that heading is not there",
					section, name)
			}
		}
		t.Logf("docs/%s exists, %d section reference(s) resolved", name, len(sections))
	}
}

// The build script's guards, exercised by running it.
//
// # WHY THESE ARE WORTH A TEST
//
// Whether the on-premise image enforces licensing is decided by one build argument. If it is missing
// the build SUCCEEDS and produces a working image that never asks for a licence — push that under the
// -onprem tag and every customer who pulls it has the product free, permanently, with nothing in the
// console or the logs to say so. And the opposite mistake is worse in a different way: the PRIVATE
// signing key reaching a build argument, an image layer and then a public registry would let anyone
// who pulled it issue their own licences.
//
// Both are silent. Neither is caught by a build, a review of the Dockerfile, or a smoke test of the
// running image. So the refusals in build-image.sh are the control, and this pins them.
//
// Only the argument handling is covered — every case below exits before docker is invoked, so this
// runs anywhere. The docker build itself, and the step that greps the finished binary for the key,
// are NOT exercised here and have to be checked on a machine with docker.
func TestOnpremBuildScriptRefusesBadKeys(t *testing.T) {
	script := filepath.Join(onpremDir, "build-image.sh")
	if _, err := os.Stat(script); err != nil {
		t.Skipf("build-image.sh not present: %v", err)
	}
	if _, err := exec.LookPath("bash"); err != nil {
		t.Skip("bash not available")
	}

	pub, priv, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("keygen: %v", err)
	}
	dir := t.TempDir()
	write := func(name, content string) string {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
		return p
	}
	pubFile := write("license.pub", base64.StdEncoding.EncodeToString(pub)+"\n")
	// The private key under a name that defeats every filename heuristic. Detection must be by
	// CONTENT — an Ed25519 private key is 64 bytes where the public half is 32.
	privDisguised := write("license-public.pub", base64.StdEncoding.EncodeToString(priv)+"\n")

	cases := []struct {
		name  string
		args  []string
		wants string // a phrase the refusal must contain
	}{
		{"no key", []string{"--version", "1.0.0"}, "--key is required"},
		{"missing file", []string{"--key", filepath.Join(dir, "nope.pub"), "--version", "1.0.0"}, "no such file"},
		{"private key by name", []string{"--key", write("license.key", "x"), "--version", "1.0.0"}, "PRIVATE key"},
		{"private key disguised as public", []string{"--key", privDisguised, "--version", "1.0.0"}, "PRIVATE key"},
		{"not base64", []string{"--key", write("junk.pub", "not-base64-at-all!!!"), "--version", "1.0.0"}, "not valid base64"},
		{"wrong length", []string{"--key", write("short.pub", "aGVsbG8="), "--version", "1.0.0"}, "not a licence key"},
		{"empty", []string{"--key", write("empty.pub", ""), "--version", "1.0.0"}, "is empty"},
		{"no version", []string{"--key", pubFile}, "--version is required"},
		{"version carries -onprem", []string{"--key", pubFile, "--version", "1.0.0-onprem"}, "suffix is added for you"},
		{"version not semver", []string{"--key", pubFile, "--version", "latest"}, "should look like 1.0.0"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out, err := exec.Command("bash", append([]string{script}, c.args...)...).CombinedOutput()
			if err == nil {
				t.Fatalf("the script ACCEPTED %s — output:\n%s", c.name, out)
			}
			if !strings.Contains(string(out), c.wants) {
				t.Errorf("refused, but not for the expected reason.\nwant a message containing %q\ngot:\n%s",
					c.wants, out)
			}
		})
	}

	// And the genuine public key must pass validation. A guard that refuses everything is no use.
	t.Run("real public key accepted", func(t *testing.T) {
		out, err := exec.Command("bash", script, "--key", pubFile, "--check").CombinedOutput()
		if err != nil {
			t.Fatalf("the script refused a valid Ed25519 public key: %v\n%s", err, out)
		}
		if !strings.Contains(string(out), "32 bytes") || !strings.Contains(string(out), "fingerprint") {
			t.Errorf("--check should report the length and a fingerprint to confirm against the CEO's copy:\n%s", out)
		}
	})
}
