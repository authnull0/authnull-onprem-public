package main

import (
	"encoding/json"
	"os"
	"sort"
	"testing"

	"github.com/gin-gonic/gin"
)

// TestDumpRoutes writes the full registered route table to the path in
// ROUTE_DUMP. It is the generator behind routes_output.json and ROUTE-MAPPING.md,
// so those stay derived from the live Gin engine rather than hand-maintained.
//
//	ROUTE_DUMP=routes_output.json go test ./cmd/authnull-service/ -run TestDumpRoutes
//
// Without ROUTE_DUMP set it skips, so a normal `go test ./...` is unaffected.
func TestDumpRoutes(t *testing.T) {
	out := os.Getenv("ROUTE_DUMP")
	if out == "" {
		t.Skip("ROUTE_DUMP not set")
	}

	gin.SetMode(gin.TestMode)
	r := gin.New()
	RegisterAllRoutes(r)

	type route struct {
		Method string `json:"method"`
		Path   string `json:"path"`
	}
	routes := make([]route, 0, len(r.Routes()))
	for _, ri := range r.Routes() {
		routes = append(routes, route{Method: ri.Method, Path: ri.Path})
	}
	sort.Slice(routes, func(i, j int) bool {
		if routes[i].Path != routes[j].Path {
			return routes[i].Path < routes[j].Path
		}
		return routes[i].Method < routes[j].Method
	})

	buf, err := json.MarshalIndent(routes, "", " ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(out, append(buf, '\n'), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Logf("wrote %d routes to %s", len(routes), out)
}
