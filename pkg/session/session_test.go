package session

import (
	"testing"
	"time"
)

func TestDefaults(t *testing.T) {
	t.Setenv("SESSION_IDLE_TTL", "")
	t.Setenv("SESSION_ABSOLUTE_TTL", "")

	if got := IdleTTL(); got != 20*time.Minute {
		t.Errorf("IdleTTL() = %s, want 20m", got)
	}
	// The absolute cap must exceed the idle window, or a session would be killed by the
	// ceiling before it could ever go idle.
	if got := AbsoluteTTL(); got != time.Hour {
		t.Errorf("AbsoluteTTL() = %s, want 1h", got)
	}
	if AbsoluteTTL() <= IdleTTL() {
		t.Error("absolute TTL must be longer than the idle TTL")
	}
}

func TestOverrides(t *testing.T) {
	t.Setenv("SESSION_IDLE_TTL", "45m")
	t.Setenv("SESSION_ABSOLUTE_TTL", "8h")

	if got := IdleTTL(); got != 45*time.Minute {
		t.Errorf("IdleTTL() = %s, want 45m", got)
	}
	if got := AbsoluteTTL(); got != 8*time.Hour {
		t.Errorf("AbsoluteTTL() = %s, want 8h", got)
	}
}

// A bad value must not silently disable expiry — that is how the original bug behaved.
func TestInvalidValuesFallBackToDefaults(t *testing.T) {
	for _, bad := range []string{"20", "abc", "0", "-5m", "  "} {
		t.Setenv("SESSION_IDLE_TTL", bad)
		if got := IdleTTL(); got != 20*time.Minute {
			t.Errorf("IdleTTL() with %q = %s, want the 20m default", bad, got)
		}
		t.Setenv("SESSION_ABSOLUTE_TTL", bad)
		if got := AbsoluteTTL(); got != time.Hour {
			t.Errorf("AbsoluteTTL() with %q = %s, want the 1h default", bad, got)
		}
	}
}

func TestAbsoluteKeyIsNamespacedAndDistinct(t *testing.T) {
	const id = "My3e4GUdxCDpjtmkQBtWa7d3i/n7CtTZ/7XTjVAsScs="
	got := AbsoluteKey(id)
	if want := "sess:abs:" + id; got != want {
		t.Errorf("AbsoluteKey() = %q, want %q", got, want)
	}
	// Must not collide with the session key itself, or refreshing one would refresh the
	// other and the cap would never bite.
	if got == id {
		t.Error("companion key must differ from the session key")
	}
}
