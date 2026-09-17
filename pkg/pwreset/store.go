package pwreset

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/authnull0/authnull-service/pkg/appurl"
	"github.com/authnull0/authnull-service/pkg/db"
)

// Password-reset tokens.
//
// This replaces a store that was map[token]expiry — the token carried no identity, so
// ForgotPassword validated the token and then reset whatever address arrived in the
// request body. Requesting a reset for your own account yielded a token that could
// change ANY user's password, in any organisation, on an unauthenticated endpoint.
//
// A token now carries the account it was issued for. The reset uses that identity and
// ignores any email in the request. It is also single-use, and held in Redis so it
// survives a restart and works across replicas — the old map did neither.

const TTL = 15 * time.Minute

// InviteTTL is the lifetime of the link in an onboarding invitation, as opposed to a reset the
// user asked for seconds ago.
//
// Fifteen minutes is right for "I clicked Forgot Password and I am staring at my inbox". It is
// useless for an invitation: an administrator onboards somebody at 18:00, they read it the next
// morning, and the only credential they will ever be issued has already expired. They cannot even
// use Forgot Password to recover, because that path requires an account that already has a
// password -- so the account is unreachable until an administrator notices and re-invites.
//
// Seven days is long enough to survive a weekend and a holiday Monday. It is a longer window than
// a reset deserves, which is why this is a separate value rather than a change to TTL: the token is
// single-use and bound to one account, so the exposure is one unclaimed invitation, not a standing
// reset capability.
const InviteTTL = 7 * 24 * time.Hour

const keyPrefix = "tenant:pwreset:"

// Token is the identity bound to a reset token. Everything the reset needs
// comes from here rather than from the request, which is the point.
type Token struct {
	Email     string    `json:"email"`
	OrgDbName string    `json:"orgDbName"`
	Url       string    `json:"url"`
	IssuedAt  time.Time `json:"issuedAt"`
}

type fallbackEntry struct {
	data      []byte
	expiresAt time.Time
}

// fallbackTokens is used only when Redis is unavailable. Entries carry an expiry
// and are evicted on read, unlike the map this replaces.
var fallbackTokens sync.Map

func key(token string) string { return keyPrefix + token }

// Store binds a token to an account for TTL. For an onboarding invitation use StoreFor with
// InviteTTL instead -- see the note there on why the two windows differ.
func Store(ctx context.Context, token string, data Token) error {
	return StoreFor(ctx, token, data, TTL)
}

// StoreFor binds a token to an account for an explicit lifetime.
//
// A non-positive ttl falls back to TTL rather than storing something that never expires: a token
// with no expiry is a permanent credential, and that is not a mistake worth making reachable by
// passing a zero value.
func StoreFor(ctx context.Context, token string, data Token, ttl time.Duration) error {
	if ttl <= 0 {
		log.Default().Printf("password reset: ttl %v is not usable, falling back to %v", ttl, TTL)
		ttl = TTL
	}

	payload, err := json.Marshal(data)
	if err != nil {
		return fmt.Errorf("marshal reset token: %w", err)
	}

	if r := db.GetRedisInstance(); r != nil {
		if err := r.Set(ctx, key(token), payload, ttl).Err(); err != nil {
			return fmt.Errorf("store reset token: %w", err)
		}
		return nil
	}

	// The in-memory fallback does not survive a restart, which matters more for a seven-day
	// invitation than for a fifteen-minute reset: an invited user whose token was only ever held in
	// one process's memory has to be re-invited after a deploy. Said out loud because the symptom
	// -- "the link in my email says invalid" -- gives no hint of the cause.
	log.Default().Printf("password reset: Redis unavailable, holding token in memory for %v", ttl)
	fallbackTokens.Store(key(token), fallbackEntry{
		data:      payload,
		expiresAt: time.Now().Add(ttl),
	})
	return nil
}

// Consume returns the account bound to a token and invalidates it.
//
// Single-use by design: the previous ValidateToken only deleted expired entries, so one
// token kept working for its whole lifetime and could be replayed.
func Consume(ctx context.Context, token string) (*Token, bool) {
	if token == "" {
		return nil, false
	}
	key := key(token)

	var payload []byte
	if r := db.GetRedisInstance(); r != nil {
		b, err := r.GetDel(ctx, key).Bytes()
		if err != nil {
			return nil, false
		}
		payload = b
	} else {
		v, ok := fallbackTokens.LoadAndDelete(key)
		if !ok {
			return nil, false
		}
		entry, ok := v.(fallbackEntry)
		if !ok || time.Now().After(entry.expiresAt) {
			return nil, false
		}
		payload = entry.data
	}

	var data Token
	if err := json.Unmarshal(payload, &data); err != nil {
		log.Default().Println("password reset: could not decode token payload:", err)
		return nil, false
	}
	if data.Email == "" || data.OrgDbName == "" {
		return nil, false
	}
	return &data, true
}

// Link builds the URL emailed to the user.
//
// It was previously fmt.Sprintf("%s?token=%s&user_name=%s", req.Url, ...) where req.Url
// is a bare site_url such as "default.alpha.dev.authnull.com" — no scheme and no path,
// so the emailed button was not a usable link.
//
// PASSWORD_RESET_URL overrides the page; it defaults to the configured client host plus
// /ssc/reset-password.
//
// THE QUERY PARAMETER NAMES ARE A CONTRACT with that page and must not be renamed casually.
// It reads token, user_name and kind; only token is load-bearing. A renamed parameter does not
// fail loudly -- the page finds no token and shows "this link has expired", which is
// indistinguishable from a genuinely expired one, so the flow breaks silently for everybody.
// tenantURL is carried as &url= so the reset page knows which tenant the account
// belongs to. The page needs it only to send the user back to the right sign-in screen
// afterwards -- it is NOT needed to submit the reset, since ForgotPassword takes the
// identity from the token and ignores any url in the request body. It is also returned
// in the reset response, so the redirect works even if the query string is mangled by a
// mail client.
func Link(token, email, tenantURL string) string {
	return linkOfKind(token, email, tenantURL, KindReset)
}

// Kinds of link. Carried as &kind= so the landing page can word itself correctly.
//
// The token, the store and the endpoint that completes the change are IDENTICAL for both -- only
// the lifetime differs (TTL versus InviteTTL). This exists purely because the copy has to differ:
// "Set a new password" and "request a new one" are both wrong for somebody who has never had a
// password and cannot self-serve a replacement, since Forgot Password requires an account that
// already has one. An invited user whose link expired has to ask an administrator to re-invite.
//
// Absent kind means reset, so an older page that ignores the parameter keeps behaving exactly as
// it does today.
const (
	KindReset  = "reset"
	KindInvite = "invite"
)

// InviteLink builds the link for an onboarding invitation.
func InviteLink(token, email, tenantURL string) string {
	return linkOfKind(token, email, tenantURL, KindInvite)
}

func linkOfKind(token, email, tenantURL, kind string) string {
	base := strings.TrimRight(strings.TrimSpace(os.Getenv("PASSWORD_RESET_URL")), "/")
	if base == "" {
		base = appurl.Client() + "/ssc/reset-password"
	}
	link := fmt.Sprintf("%s?token=%s&user_name=%s", base, url.QueryEscape(token), url.QueryEscape(email))
	if u := strings.TrimSpace(tenantURL); u != "" {
		link += "&url=" + url.QueryEscape(u)
	}
	if kind != "" && kind != KindReset {
		link += "&kind=" + url.QueryEscape(kind)
	}
	return link
}
