package main

import (
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

// Every METHOD+path quoted in a handoff document must actually be registered.
//
// The first draft of UI-HANDOFF.md named three paths that did not exist — a prefix the routes never
// had, twice. A handoff whose paths are wrong costs the reader a day and teaches them not to trust
// the rest of it, so the documents are checked against the router rather than against anyone's
// memory of it.
//
// Health is registered in main() rather than RegisterAllRoutes, so it is added here explicitly
// instead of being reported as missing.
func TestHandoffPathsAreReal(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/system/v1/health", func(*gin.Context) {})
	r.GET("/system/v1/health/readiness", func(*gin.Context) {})
	r.GET("/system/v1/health/liveness", func(*gin.Context) {})
	RegisterAllRoutes(r)

	have := map[string]bool{}
	for _, ri := range r.Routes() {
		have[ri.Method+" "+ri.Path] = true
	}

	// Backticked `METHOD /path` occurrences. The path may carry a query string or fragment in the
	// prose — documenting `GET /x?token=<t>` is normal and useful — so only the path is compared.
	re := regexp.MustCompile("`(GET|POST|PUT|DELETE) (/[^`\\s]*)`")

	docs := []string{"../../UI-HANDOFF.md", "../../APP-HANDOFF.md", "../../UI-ENROLLMENT-TASK.md"}
	checked := 0
	withdrawn := 0
	for _, name := range docs {
		// Each file is scanned separately so a failure names the document it came from. Scanning
		// the concatenation reported every miss against the first filename, which sends the reader
		// to the wrong file.
		body, err := os.ReadFile(name)
		if err != nil {
			t.Logf("%s not readable, skipping it: %v", name, err)
			continue
		}
		for _, m := range re.FindAllStringSubmatch(string(body), -1) {
			method, path := m[1], m[2]
			if i := strings.IndexAny(path, "?#"); i >= 0 {
				path = path[:i]
			}
			// Placeholder paths in prose, e.g. `POST /ad/<something>`, are not routes.
			if strings.ContainsAny(path, "<>{}") {
				continue
			}

			// A handoff document also has to record endpoints it previously described and that
			// have since been WITHDRAWN -- otherwise a reader who saw the earlier draft cannot
			// tell a removal from a rename, which is the confusion the document exists to avoid.
			// For those the assertion inverts: the path must NOT be registered. That way marking
			// something withdrawn while leaving the route mounted is a failure too, rather than a
			// quiet exemption.
			//
			// The marker must be uppercase WITHDRAWN or REMOVED on the same line, so prose that
			// merely uses the word cannot grant the exemption by accident.
			if line := lineContaining(string(body), m[0]); strings.Contains(line, "WITHDRAWN") ||
				strings.Contains(line, "REMOVED") {
				withdrawn++
				if have[method+" "+path] {
					t.Errorf("%s marks %s %s as withdrawn, but it is still registered",
						name, method, path)
				}
				continue
			}

			checked++
			if !have[method+" "+path] {
				t.Errorf("%s documents %s %s, which is NOT registered", name, method, path)
			}
		}
	}
	if checked == 0 {
		t.Error("no paths parsed out of any handoff document — the regex or the documents changed shape")
	}
	t.Logf("verified %d documented paths and %d withdrawn across %d documents",
		checked, withdrawn, len(docs))
}

// lineContaining returns the whole line of body that the given match sits on, so a marker written
// alongside a path can be seen. Matching on the line rather than the surrounding section keeps the
// exemption narrow: it applies to the path it is written next to and nothing else.
func lineContaining(body, match string) string {
	i := strings.Index(body, match)
	if i < 0 {
		return ""
	}
	start := strings.LastIndexByte(body[:i], '\n') + 1
	end := strings.IndexByte(body[i:], '\n')
	if end < 0 {
		return body[start:]
	}
	return body[start : i+end]
}
