package pwreset

import (
	"context"
	"strings"
	"testing"
	"time"
)

// These exercise the in-memory fallback (no Redis in tests), which is also the path a
// deployment without Redis takes.

func TestTokenRoundTripCarriesIdentity(t *testing.T) {
	ctx := context.Background()
	want := Token{Email: "victim@example.com", OrgDbName: "alpha", Url: "default.alpha.dev.authnull.com"}

	if err := Store(ctx, "tok-1", want); err != nil {
		t.Fatalf("Store: %v", err)
	}

	got, ok := Consume(ctx, "tok-1")
	if !ok {
		t.Fatal("expected to find the stored token")
	}
	// The whole point: identity comes from the token, not from the request body.
	if got.Email != want.Email || got.OrgDbName != want.OrgDbName {
		t.Errorf("got %+v, want email=%q orgDb=%q", got, want.Email, want.OrgDbName)
	}
}

// Regression guard for the account-takeover flaw: a token issued for one account must
// not be usable to identify a different one. Callers must take the email from the
// returned Token and ignore any address supplied by the client.
func TestTokenIsBoundToOneAccount(t *testing.T) {
	ctx := context.Background()
	if err := Store(ctx, "tok-attacker", Token{Email: "attacker@example.com", OrgDbName: "alpha"}); err != nil {
		t.Fatalf("Store: %v", err)
	}
	got, ok := Consume(ctx, "tok-attacker")
	if !ok {
		t.Fatal("expected token")
	}
	if got.Email != "attacker@example.com" {
		t.Fatalf("token resolved to %q; it must only ever resolve to its own subject", got.Email)
	}
}

func TestTokenIsSingleUse(t *testing.T) {
	ctx := context.Background()
	if err := Store(ctx, "tok-2", Token{Email: "a@b.com", OrgDbName: "alpha"}); err != nil {
		t.Fatalf("Store: %v", err)
	}
	if _, ok := Consume(ctx, "tok-2"); !ok {
		t.Fatal("first consume should succeed")
	}
	// The old store never deleted on success, so one token worked for its whole life.
	if _, ok := Consume(ctx, "tok-2"); ok {
		t.Error("second consume must fail — reset tokens are single-use")
	}
}

func TestUnknownAndEmptyTokensRejected(t *testing.T) {
	ctx := context.Background()
	if _, ok := Consume(ctx, "never-issued"); ok {
		t.Error("unknown token must be rejected")
	}
	if _, ok := Consume(ctx, ""); ok {
		t.Error("empty token must be rejected")
	}
}

func TestExpiredTokenRejected(t *testing.T) {
	key := key("tok-expired")
	fallbackTokens.Store(key, fallbackEntry{
		data:      []byte(`{"email":"a@b.com","orgDbName":"alpha"}`),
		expiresAt: time.Now().Add(-time.Second),
	})
	if _, ok := Consume(context.Background(), "tok-expired"); ok {
		t.Error("expired token must be rejected")
	}
}

func TestLinkIsAbsoluteAndCarriesParams(t *testing.T) {
	t.Setenv("PASSWORD_RESET_URL", "https://onprem.dev.authnull.com/ssc/reset-password")
	got := Link("abc 123", "user+x@example.com", "default.alpha.dev.authnull.com")
	want := "https://onprem.dev.authnull.com/ssc/reset-password?token=abc+123&user_name=user%2Bx%40example.com" +
		"&url=default.alpha.dev.authnull.com"
	if got != want {
		t.Errorf("Link() = %q, want %q", got, want)
	}
}

// The reset page needs the tenant domain to send the user back to the right sign-in
// screen after a successful reset. It is appended as &url=, and omitted when unknown.
func TestLinkOmitsUrlWhenEmpty(t *testing.T) {
	t.Setenv("PASSWORD_RESET_URL", "https://x/ssc/reset-password")
	got := Link("t", "a@b.com", "")
	if want := "https://x/ssc/reset-password?token=t&user_name=a%40b.com"; got != want {
		t.Errorf("Link() = %q, want %q", got, want)
	}
}

func TestLinkFallsBackToClientHost(t *testing.T) {
	// Previously the link was a bare site_url with no scheme and no path, so the
	// emailed button was not a usable URL.
	t.Setenv("PASSWORD_RESET_URL", "")
	t.Setenv("CLIENT_URL", "https://onprem.dev.authnull.com")
	t.Setenv("SYSTEM_URL", "")
	got := Link("t", "a@b.com", "")
	want := "https://onprem.dev.authnull.com/ssc/reset-password?token=t&user_name=a%40b.com"
	if got != want {
		t.Errorf("Link() = %q, want %q", got, want)
	}
}

// An invitation must outlive the working day it was sent on.
//
// TTL is fifteen minutes, which is right for somebody staring at their inbox after clicking Forgot
// Password. An onboarding invitation is read whenever the recipient next opens their mail, and it
// is the ONLY credential they are ever issued — onboarding no longer sets a password at all. A
// fifteen-minute invitation is therefore an account nobody can ever reach: Forgot Password cannot
// rescue it either, because that path needs an account that already has a password.
func TestInviteTTLOutlivesAResetWindow(t *testing.T) {
	if InviteTTL <= TTL {
		t.Fatalf("InviteTTL (%v) must be longer than the reset TTL (%v)", InviteTTL, TTL)
	}
	// A weekend plus a holiday Monday. Asserted as a floor rather than an exact value so the number
	// can be tuned without editing a test, but not tuned down to something useless.
	if InviteTTL < 72*time.Hour {
		t.Errorf("InviteTTL is %v — an invitation sent on Friday evening must still work on Monday",
			InviteTTL)
	}
}

func TestStoreForHonoursAnExplicitLifetime(t *testing.T) {
	ctx := context.Background()
	tok := Token{Email: "invited@example.com", OrgDbName: "alpha"}

	// Long enough to still be there.
	if err := StoreFor(ctx, "invite-live", tok, InviteTTL); err != nil {
		t.Fatalf("StoreFor: %v", err)
	}
	got, ok := Consume(ctx, "invite-live")
	if !ok {
		t.Fatal("an invitation stored with InviteTTL should still be present")
	}
	if got.Email != tok.Email || got.OrgDbName != tok.OrgDbName {
		t.Errorf("identity did not round-trip: %+v", got)
	}

	// Short enough to be gone.
	if err := StoreFor(ctx, "invite-dead", tok, time.Nanosecond); err != nil {
		t.Fatalf("StoreFor: %v", err)
	}
	time.Sleep(2 * time.Millisecond)
	if _, ok := Consume(ctx, "invite-dead"); ok {
		t.Error("a token past its lifetime must not be accepted")
	}
}

// A zero or negative lifetime must not mean "never expires".
//
// StoreFor takes a duration, so a caller can reach this by passing an unset config value or a
// subtraction that went the wrong way. Storing a token with no expiry turns a single-use invitation
// into a permanent password-reset capability for that account, which is the one outcome here worth
// making unreachable by accident.
func TestStoreForRefusesToCreateAnImmortalToken(t *testing.T) {
	ctx := context.Background()
	for _, ttl := range []time.Duration{0, -time.Hour} {
		name := "immortal"
		if err := StoreFor(ctx, name, Token{Email: "a@b.c", OrgDbName: "alpha"}, ttl); err != nil {
			t.Fatalf("StoreFor(%v): %v", ttl, err)
		}
		// Present now...
		if _, ok := Consume(ctx, name); !ok {
			t.Fatalf("ttl %v: token should have been stored under the fallback TTL", ttl)
		}
		// ...and the entry it wrote must carry a real expiry, not the zero time.
		if err := StoreFor(ctx, name, Token{Email: "a@b.c", OrgDbName: "alpha"}, ttl); err != nil {
			t.Fatalf("StoreFor(%v): %v", ttl, err)
		}
		v, ok := fallbackTokens.Load(key(name))
		if !ok {
			t.Fatalf("ttl %v: nothing in the fallback store", ttl)
		}
		entry, ok := v.(fallbackEntry)
		if !ok || entry.expiresAt.IsZero() {
			t.Errorf("ttl %v: stored with no expiry — that is a permanent credential", ttl)
		}
		if got := time.Until(entry.expiresAt); got > TTL+time.Minute {
			t.Errorf("ttl %v: expiry is %v away, expected the %v fallback", ttl, got, TTL)
		}
		fallbackTokens.Delete(key(name))
	}
}

// The query parameter names are a contract with the reset page.
//
// A renamed parameter does not fail loudly: the page finds no token, shows "this link has expired",
// and that is indistinguishable from a genuinely expired token. So the flow breaks silently for
// every user at once, and the only symptom is a support ticket saying the link does not work.
func TestLinkParameterNamesAreTheContract(t *testing.T) {
	t.Setenv("PASSWORD_RESET_URL", "https://console.example.com/ssc/reset-password")

	got := Link("tok-1", "someone@example.com", "default.alpha.dev.authnull.com")
	for _, want := range []string{"?token=tok-1", "&user_name=someone%40example.com", "&url=default.alpha.dev.authnull.com"} {
		if !strings.Contains(got, want) {
			t.Errorf("link is missing %q — the page reads these names exactly\n  got: %s", want, got)
		}
	}
	// A reset must NOT carry kind, so a page that ignores the parameter is unaffected.
	if strings.Contains(got, "kind=") {
		t.Errorf("a reset link should carry no kind parameter: %s", got)
	}
}

// An invitation must be distinguishable from a reset by the page.
//
// Same token, same store, same completion endpoint — only the copy differs. "Set a new password"
// and "request a new one" are both wrong for someone who has never had a password and cannot
// self-serve a replacement: Forgot Password needs an account that already has one, so an invited
// user with an expired link has to be re-invited by an administrator.
func TestInviteLinkIsDistinguishableFromAReset(t *testing.T) {
	t.Setenv("PASSWORD_RESET_URL", "https://console.example.com/ssc/reset-password")

	invite := InviteLink("tok-2", "invited@example.com", "default.alpha.dev.authnull.com")
	if !strings.Contains(invite, "&kind=invite") {
		t.Errorf("an invitation must carry kind=invite so the page can word itself: %s", invite)
	}
	// Everything else identical, so the page's mechanics need no branch — only its wording.
	reset := Link("tok-2", "invited@example.com", "default.alpha.dev.authnull.com")
	if strings.TrimSuffix(invite, "&kind="+KindInvite) != reset {
		t.Errorf("invite and reset links should differ ONLY by the kind parameter\n  reset:  %s\n  invite: %s",
			reset, invite)
	}
}
