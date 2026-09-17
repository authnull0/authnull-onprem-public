package httpclient

import (
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

// The whole point of this package. If a client ever comes back with Timeout == 0 it is
// unbounded, and one unresponsive host parks the caller's goroutine forever — which is the
// defect that motivated the package in the first place.
func TestNoClientIsEverUnbounded(t *testing.T) {
	for name, c := range map[string]*http.Client{
		"Default":         Default(),
		"Auth":            Auth(),
		"Long":            Long(),
		"WithTimeout(0)":  WithTimeout(0),
		"WithTimeout(-1)": WithTimeout(-time.Second),
		"WithTimeout(2s)": WithTimeout(2 * time.Second),
	} {
		if c == nil {
			t.Fatalf("%s returned nil", name)
		}
		if c.Timeout <= 0 {
			t.Errorf("%s has Timeout=%v; this package must never hand out an unbounded client", name, c.Timeout)
		}
		if c.Transport == nil {
			t.Errorf("%s has no transport, so it falls back to DefaultTransport's MaxIdleConnsPerHost of 2", name)
		}
	}
}

// Clients are memoised per duration and share one transport, so N call sites do not each keep
// their own idle connection pool to the same host.
func TestClientsAreSharedPerTimeout(t *testing.T) {
	if WithTimeout(7*time.Second) != WithTimeout(7*time.Second) {
		t.Error("the same timeout must return the same client")
	}
	if WithTimeout(7*time.Second) == WithTimeout(8*time.Second) {
		t.Error("different timeouts must be different clients")
	}
	if Default().Transport != Long().Transport {
		t.Error("all clients must share one transport")
	}
}

// The memo map is read and written from request paths, so it must be safe under concurrency —
// an unguarded map here would be the same crash this pass has been removing elsewhere.
func TestConcurrentAccessIsSafe(t *testing.T) {
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			if c := WithTimeout(time.Duration(i%5+1) * time.Second); c.Timeout <= 0 {
				t.Error("unbounded client from a concurrent caller")
			}
		}(i)
	}
	wg.Wait()
}

// AUTHNZ_TIMEOUT_SEC may raise the bound but must never remove it: a zero or unparseable value
// has to fall back to the constant rather than to "wait forever".
func TestAuthTimeoutEnvCannotDisableTheBound(t *testing.T) {
	for _, v := range []string{"", "0", "-5", "abc", "  "} {
		t.Setenv("AUTHNZ_TIMEOUT_SEC", v)
		if got := authTimeout(); got != AuthTimeout {
			t.Errorf("AUTHNZ_TIMEOUT_SEC=%q gave %v, want the %v default", v, got, AuthTimeout)
		}
	}
	t.Setenv("AUTHNZ_TIMEOUT_SEC", "30")
	if got := authTimeout(); got != 30*time.Second {
		t.Errorf("AUTHNZ_TIMEOUT_SEC=30 gave %v, want 30s", got)
	}
}

// End to end: a server that accepts the connection and never answers is precisely the failure
// an unbounded client cannot survive. The client must give up on its own.
func TestTimeoutActuallyFires(t *testing.T) {
	block := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-block // never respond
	}))
	defer srv.Close()
	defer close(block)

	start := time.Now()
	_, err := WithTimeout(150 * time.Millisecond).Get(srv.URL)
	if err == nil {
		t.Fatal("expected a timeout error from a server that never responds")
	}
	if elapsed := time.Since(start); elapsed > 2*time.Second {
		t.Errorf("took %v to give up; the timeout did not apply", elapsed)
	}
}
