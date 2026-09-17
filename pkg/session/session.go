// Package session holds the login-session lifetime rules shared by the handler that
// creates sessions and the middleware that validates them.
//
// It exists so the two cannot drift apart. They already did once: login stamped
// ExpireTime = now + 20 minutes on the session object but wrote the Redis key with a TTL
// of 0, and since authorisation is "does this key exist in Redis", no login ever expired.
package session

import (
	"log"
	"os"
	"strings"
	"time"
)

const (
	// DefaultIdleTTL is how long a session survives without use. Refreshed on every
	// authorised request, so it expresses "idle for this long", not "this long since
	// sign-in".
	DefaultIdleTTL = 20 * time.Minute

	// DefaultAbsoluteTTL caps total session lifetime regardless of activity. Without it
	// a sliding window never closes: anyone making a request every 19 minutes stays
	// signed in forever.
	DefaultAbsoluteTTL = time.Hour

	// absolutePrefix namespaces the companion key that enforces the absolute cap.
	absolutePrefix = "sess:abs:"
)

// AbsoluteKey is the companion key for a session id.
//
// It is written once at login with the absolute TTL and deliberately NEVER refreshed,
// while the session key itself is refreshed on use. Requiring both to exist gives an idle
// timeout and a hard ceiling from two independent expiries, without changing the session
// value format that getUserDetails parses.
func AbsoluteKey(sessionID string) string {
	return absolutePrefix + sessionID
}

// IdleTTL reads SESSION_IDLE_TTL (a Go duration such as "30m").
func IdleTTL() time.Duration {
	return durationFromEnv("SESSION_IDLE_TTL", DefaultIdleTTL)
}

// AbsoluteTTL reads SESSION_ABSOLUTE_TTL (a Go duration such as "8h").
func AbsoluteTTL() time.Duration {
	return durationFromEnv("SESSION_ABSOLUTE_TTL", DefaultAbsoluteTTL)
}

func durationFromEnv(key string, fallback time.Duration) time.Duration {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil || d <= 0 {
		log.Default().Printf("session: %s=%q is not a valid positive duration, using %s", key, v, fallback)
		return fallback
	}
	return d
}
