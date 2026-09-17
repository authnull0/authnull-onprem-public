package middleware

import (
	"context"
	"encoding/base64"
	"errors"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	pkgdb "github.com/authnull0/authnull-service/pkg/db"
)

// Session principal resolution.
//
// The session value in Redis is base64("orgId:domainId:userId"). That decode was inlined in
// cmd/authnull-service/routes.go's getUserDetails handler, which made it unavailable to
// anything else — so a handler needing the caller's identity had to either duplicate the
// decode or, worse, trust an orgId/email from the request body.
//
// That distinction matters for anything that MINTS something on the caller's behalf.
// AuthnzMiddleware proves only that SOME valid session exists; it does not check that the
// session belongs to the org or user named in the body. A handler that mints an enrollment
// invite from body fields is therefore a cross-tenant forgery primitive: any authenticated
// user could request an invite for any account in any organisation.

// Principal is who the caller actually is, according to their session.
type Principal struct {
	OrgID    int
	DomainID int
	UserID   int
}

// ErrNoPrincipal means no usable session was found.
var ErrNoPrincipal = errors.New("middleware: no session principal")

// SessionPrincipal resolves the caller's identity from their session token.
//
// Reads the same header set AuthnzMiddleware accepts, so a request that passed that
// middleware resolves here too.
func SessionPrincipal(c *gin.Context) (*Principal, error) {
	if c == nil {
		return nil, ErrNoPrincipal
	}
	sessionID := sessionTokenFrom(c)
	if sessionID == "" {
		return nil, ErrNoPrincipal
	}

	rdb := pkgdb.GetRedisInstance()
	if rdb == nil {
		// No fallback to an authnz proxy here, deliberately. getUserDetails can proxy
		// because it only reports identity; a caller minting something must fail closed
		// rather than proceed on an unverified one.
		return nil, ErrNoPrincipal
	}

	encoded, err := rdb.Get(context.Background(), sessionID).Result()
	if err != nil || strings.TrimSpace(encoded) == "" {
		return nil, ErrNoPrincipal
	}
	decoded, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, ErrNoPrincipal
	}
	parts := strings.Split(string(decoded), ":")
	if len(parts) < 3 {
		return nil, ErrNoPrincipal
	}

	orgID, err1 := strconv.Atoi(strings.TrimSpace(parts[0]))
	domainID, _ := strconv.Atoi(strings.TrimSpace(parts[1]))
	userID, err2 := strconv.Atoi(strings.TrimSpace(parts[2]))
	if err1 != nil || err2 != nil || orgID <= 0 || userID <= 0 {
		return nil, ErrNoPrincipal
	}
	return &Principal{OrgID: orgID, DomainID: domainID, UserID: userID}, nil
}

// sessionTokenFrom reads the session id from any header the console is known to send.
//
// The session value itself contains "&DOMAIN&...&ORGID&..." appended by the console, so only
// the leading segment is the Redis key.
func sessionTokenFrom(c *gin.Context) string {
	for _, h := range []string{"X-Authorization", "x-authorization", "Authorization"} {
		if v := strings.TrimSpace(c.GetHeader(h)); v != "" {
			v = strings.TrimPrefix(v, "Bearer ")
			v = strings.TrimPrefix(v, "bearer ")
			if i := strings.Index(v, "&"); i > 0 {
				v = v[:i]
			}
			return strings.TrimSpace(v)
		}
	}
	return ""
}
