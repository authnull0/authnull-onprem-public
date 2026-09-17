package main

import (
	"crypto/ed25519"
	"encoding/base64"
	"io"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	mfautil "github.com/authnull0/authnull-service/internal/mfa/utils"
	"github.com/authnull0/authnull-service/internal/mfapush"
	pkgdb "github.com/authnull0/authnull-service/pkg/db"
	"github.com/authnull0/authnull-service/pkg/license"
	"github.com/authnull0/authnull-service/pkg/middleware"
)

// Licence endpoints: one to read the state, one to install a licence.
//
// THE DEADLOCK THESE MUST NOT CREATE
//
// An expired deployment has to be able to install a licence. If either endpoint were licence-gated, a
// lapsed customer could never renew without somebody editing their database — a support incident
// caused entirely by our own gate.
//
// They are safe by construction rather than by exemption: license.Gate consults an explicit list of
// control-plane paths, and these are not on it. That is the payoff from listing what IS gated instead
// of what is not. TestLicenseEndpointsAreNeverGated asserts it rather than trusting the reading.

// licenseAdminRoles may install a licence. Same allow-list as the admin-invite path — installing a
// licence changes what the entire deployment is permitted to do, so it is not an end-user action.
var licenseAdminRoles = map[string]bool{"ADMIN": true, "SUPERADMIN": true}

// maxLicenseUpload caps the request body. A licence is around one kilobyte; 64 KiB is generous and
// stops an unauthenticated-shaped endpoint being a way to make the process allocate.
const maxLicenseUpload = 64 << 10

// licenseStore is set by initLicense when the master database is reachable. Nil means uploads cannot
// be persisted, which is reported honestly rather than accepted and silently lost.
var licenseStore *license.DocumentStore

// GetLicense handles GET /api/v1/license.
//
// Readable by any authenticated session, not just administrators: the console shows the expiry banner
// to whoever is logged in, and hiding "your trial ends in 3 days" from the person who would chase it
// serves nobody. It returns no secrets — the licence is a signed statement about the deployment, and
// the document body is deliberately not included.
func GetLicense(c *gin.Context) {
	st := licenseStatus()

	body := gin.H{
		"state":         st.State,
		"licensed":      st.Licensed,
		"daysRemaining": st.DaysRemaining,
		// So the console can render the correct banner without duplicating the state machine.
		"enforced": licenseLoader != nil && licenseLoader.Enforced(),
	}
	if st.Reason != "" {
		body["reason"] = st.Reason
	}
	if st.Customer != "" {
		body["customer"] = st.Customer
	}
	if st.Tier != "" {
		body["tier"] = st.Tier
	}
	if st.ExpiresAt != nil {
		body["expiresAt"] = st.ExpiresAt.UTC()
	}
	if len(st.Features) > 0 {
		body["features"] = st.Features
	}

	// Stated explicitly so a console author does not have to infer it, and so an administrator reading
	// the raw response is not left wondering whether logins are about to stop.
	body["enforcementUnaffected"] = true

	if history, err := licenseStore.History(10); err == nil && len(history) > 0 {
		rows := make([]gin.H, 0, len(history))
		for _, h := range history {
			row := gin.H{"licenseId": h.LicenseID, "customer": h.Customer, "uploadedAt": h.UploadedAt.UTC()}
			if h.ExpiresAt != nil {
				row["expiresAt"] = h.ExpiresAt.UTC()
			}
			rows = append(rows, row)
		}
		body["history"] = rows
	}

	c.JSON(http.StatusOK, body)
}

// UploadLicense handles POST /api/v1/license/upload.
//
// Accepts the raw licence file as the request body. Not multipart: the file is a kilobyte of JSON, and
// a raw body is simpler for both a browser fetch and a curl one-liner from a support engineer.
func UploadLicense(c *gin.Context) {
	principal, err := middleware.SessionPrincipal(c)
	if err != nil || principal == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	// Role is resolved from the caller's own organisation database, exactly as the admin-invite path
	// does. middleware.Principal deliberately carries only identity — org, domain, user — so a role
	// check has to go and look, and doing it the same way in both places means there is one answer to
	// "who counts as an administrator here".
	orgName, err := mfautil.GetOrganizationDatabaseName(principal.OrgID)
	if err != nil || orgName == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	tenantDB := pkgdb.GetConnectiontoDatabaseDynamically(orgName)
	if tenantDB == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "organisation database unavailable"})
		return
	}
	role, _ := mfapush.RoleForIdentity(tenantDB, mfapush.IdentityPlatform, principal.UserID)
	if !licenseAdminRoles[strings.ToUpper(strings.TrimSpace(role))] {
		log.Printf("license: upload refused for user %d in org %d with role %q",
			principal.UserID, principal.OrgID, role)
		c.JSON(http.StatusForbidden, gin.H{"error": "administrator role required"})
		return
	}

	raw, err := io.ReadAll(io.LimitReader(c.Request.Body, maxLicenseUpload+1))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not read the uploaded file"})
		return
	}
	if len(raw) > maxLicenseUpload {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{
			"error": "that file is far larger than a licence — check you uploaded the right one",
		})
		return
	}
	if len(strings.TrimSpace(string(raw))) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no file was uploaded"})
		return
	}

	// A build with no public key cannot verify anything, so accepting an upload would store a document
	// nothing will ever check. Say so plainly instead of appearing to succeed.
	if licenseLoader == nil || !licenseLoader.Enforced() {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "this build does not use licences, so there is nothing to install",
		})
		return
	}

	// VERIFIED BEFORE IT IS STORED. Nothing unverified reaches the database, so a later read cannot
	// resurrect a forgery even if the verification path changed.
	payload, verr := license.Verify(raw, buildPublicKey())
	if verr != nil {
		st := license.EvaluateInvalid(verr)
		log.Printf("license: upload by user %d rejected: %v", principal.UserID, verr)
		c.JSON(http.StatusBadRequest, gin.H{"error": st.Reason, "state": st.State})
		return
	}

	if licenseStore == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "the licence is valid but cannot be saved — the master database is unavailable",
		})
		return
	}
	if err := licenseStore.Save(raw, payload, principal.UserID); err != nil {
		log.Printf("license: could not save licence %s: %v", payload.ID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not save the licence"})
		return
	}

	// Reload immediately so the response already reflects the new licence. Waiting for the recheck
	// interval would make a successful upload look like it had not worked.
	licenseLoader.Reload()
	st := licenseStatus()

	// Audited: installing a licence changes what the deployment may do, and an expiry date somebody
	// later disputes should be traceable to an upload.
	log.Printf("license: %s installed by user %d (%s), customer=%q expires=%s state=%s",
		payload.ID, principal.UserID, role, payload.Customer,
		payload.ExpiresAt.UTC().Format("2006-01-02"), st.State)

	c.JSON(http.StatusOK, gin.H{
		"state":         st.State,
		"licensed":      st.Licensed,
		"customer":      st.Customer,
		"tier":          st.Tier,
		"features":      st.Features,
		"daysRemaining": st.DaysRemaining,
		"expiresAt":     payload.ExpiresAt.UTC(),
		"reason":        st.Reason,
	})
}

// buildPublicKey decodes the compiled-in key. Errors are impossible here in practice, because
// Loader.Enforced() already established it decodes — checked again rather than assumed, since a nil
// key would make ed25519.Verify panic.
func buildPublicKey() ed25519.PublicKey {
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(license.PublicKeyBase64))
	if err != nil || len(decoded) != ed25519.PublicKeySize {
		return nil
	}
	return ed25519.PublicKey(decoded)
}
