// Package httpclient provides the outbound HTTP clients this service uses.
//
// It exists for one reason: a zero-value &http.Client{} HAS NO TIMEOUT. Not a long one — none
// at all. A request to a host that accepts the connection and then never answers blocks
// forever, and 23 call sites across this repo were built that way, including the two
// authorization checks that run inline on every authenticated request. One unresponsive authnz
// instance is enough to park every in-flight request on a goroutine, each holding whatever
// database connection it had already taken, until the process is restarted. The symptom is a
// service that stops answering while looking perfectly healthy — no error, no restart, no log.
//
// What this package does NOT fix, despite appearances: connection reuse. A zero-value
// http.Client already uses http.DefaultTransport, which is a shared, pooled transport, so
// allocating a Client struct per call was never a socket leak. The clients here are shared
// anyway because there is no reason not to, but the defect being repaired is the timeout.
//
// It does raise one transport limit that mattered. http.DefaultTransport sets
// MaxIdleConnsPerHost to 2, so beyond two concurrent calls to the same host every extra
// request opens and discards its own connection — including the TLS handshake. For authnz,
// which is called once per authenticated request against a single host, that is the difference
// between reusing a warm pool and renegotiating TLS under load.
package httpclient

import (
	"net"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"
)

// Timeouts. These are whole-request deadlines: connect, write, read and body, together.
const (
	// DefaultTimeout covers ordinary outbound calls to internal services.
	DefaultTimeout = 15 * time.Second

	// AuthTimeout is deliberately shorter. The authorization check runs INLINE inside every
	// authenticated request, so its timeout is the worst case a user waits before being told
	// "no" — and a slow authorization answer is not worth waiting for when the fallback is a
	// clean 401 the caller can retry. Overridable with AUTHNZ_TIMEOUT_SEC.
	AuthTimeout = 5 * time.Second

	// LongTimeout is for calls that legitimately take a while: provisioning, imports, and
	// anything that does real work on the far side.
	LongTimeout = 60 * time.Second
)

// maxIdlePerHost replaces http.DefaultTransport's 2. Almost every outbound call from this
// service goes to one of a handful of internal hosts, which is exactly the shape that default
// penalises.
const maxIdlePerHost = 32

var (
	transportOnce sync.Once
	transport     *http.Transport

	clientMu sync.Mutex
	clients  = map[time.Duration]*http.Client{}
)

// sharedTransport is built once and shared by every client here, so they pool connections
// together rather than each keeping its own idle set to the same hosts.
func sharedTransport() *http.Transport {
	transportOnce.Do(func() {
		transport = &http.Transport{
			Proxy: http.ProxyFromEnvironment,
			DialContext: (&net.Dialer{
				// Bounded separately from the overall deadline: a host that is down should
				// fail fast rather than consuming the caller's whole budget on a connect.
				Timeout:   5 * time.Second,
				KeepAlive: 30 * time.Second,
			}).DialContext,
			MaxIdleConns:          100,
			MaxIdleConnsPerHost:   maxIdlePerHost,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   10 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
			ForceAttemptHTTP2:     true,
		}
	})
	return transport
}

// WithTimeout returns the shared client for a given whole-request timeout.
//
// Memoised per duration rather than per call site, so the handful of distinct timeouts in this
// service map onto a handful of clients, all sharing one transport.
//
// A non-positive timeout is treated as DefaultTimeout, deliberately: this package exists to
// make an unbounded client impossible to obtain, so it must not hand one out when a caller
// passes a zero value.
func WithTimeout(d time.Duration) *http.Client {
	if d <= 0 {
		d = DefaultTimeout
	}
	clientMu.Lock()
	defer clientMu.Unlock()
	if c, ok := clients[d]; ok {
		return c
	}
	c := &http.Client{Timeout: d, Transport: sharedTransport()}
	clients[d] = c
	return c
}

// Default returns the client for ordinary internal calls.
func Default() *http.Client { return WithTimeout(DefaultTimeout) }

// Long returns the client for calls that legitimately take a while.
func Long() *http.Client { return WithTimeout(LongTimeout) }

// Auth returns the client for the inline authorization check.
func Auth() *http.Client { return WithTimeout(authTimeout()) }

// authTimeout reads AUTHNZ_TIMEOUT_SEC, so a deployment whose authnz is genuinely slower can
// raise it without a code change — and cannot disable the bound: a value of 0 or a
// unparseable one falls back to the constant rather than to "wait forever".
func authTimeout() time.Duration {
	raw := os.Getenv("AUTHNZ_TIMEOUT_SEC")
	if raw == "" {
		return AuthTimeout
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		return AuthTimeout
	}
	return time.Duration(n) * time.Second
}
