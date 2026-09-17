package main

import (
	"log"
	"os"
	"strings"

	"github.com/authnull0/authnull-service/pkg/db"
	"github.com/authnull0/authnull-service/pkg/license"
)

// Licence wiring.
//
// Mirrors the schema-check wiring in schema.go on purpose: built once at boot, held in one place, and
// surfaced through the health endpoint. Two subsystems that answer "is this deployment healthy"
// should not have two different shapes.
//
// NOTHING HERE IS ENFORCED ON A BUILD WITHOUT A LICENCE PUBLIC KEY, which is every build except the
// on-premise one. See license.PublicKeyBase64.

var licenseLoader *license.Loader

// initLicense builds the loader and, on an enforcing build, records the trial start.
//
// Ordering matters: the trial row is only touched when this build can actually enforce something.
// Writing trial state into Authnull's own SaaS database would be noise at best, and misleading at
// worst — a row saying "trial started" in a deployment that has no trial.
func initLicense() {
	path := strings.TrimSpace(os.Getenv("LICENSE_FILE"))

	if strings.TrimSpace(license.PublicKeyBase64) == "" {
		// Not an on-premise build. Construct a loader anyway so callers never have to nil-check, and
		// skip the database entirely.
		licenseLoader = license.NewLoader(path, nil)
		log.Println("license: this build has no licence public key, so licensing is not enforced")
		return
	}

	// Master database: a licence covers the deployment, not an organisation.
	master := db.GetConnectiontoDatabaseDynamically(os.Getenv("DB_NAME"))
	if master == nil {
		// Without the master DB the trial start cannot be read, so every boot would look like first
		// boot and the trial would never expire. Log it plainly rather than failing to start: the
		// service's job is authentication, and refusing to serve over a licence bookkeeping problem
		// would be exactly the outage this design exists to avoid.
		log.Println("license: master database unavailable, so the trial window cannot be read; " +
			"treating this boot as the start of the trial")
		licenseLoader = license.NewLoader(path, nil)
		return
	}

	// ENCRYPTION_KEY is the deployment's own secret and is already required for other columns, so it
	// needs no new configuration. Empty simply means the trial row is unsigned.
	trials := license.NewTrialStore(master, os.Getenv("ENCRYPTION_KEY"))
	start := trials.Ensure()

	// The uploaded licence lives in the master database, because that is the only store that survives
	// what happens to a deployment: containers are recreated on upgrade, the packaged licence path is
	// mounted read-only, and with several replicas a file upload reaches only one of them. The file at
	// LICENSE_FILE remains the bootstrap path for an air-gapped operator dropping a licence in before
	// first boot.
	licenseStore = license.NewDocumentStore(master)

	// StartedAt rather than a captured value: the loader re-reads on a timer, and reading the row each
	// time means a corrected trial start takes effect without a restart.
	licenseLoader = license.NewLoader(path, trials.StartedAt,
		license.WithDocumentSource(licenseStore.Current))

	st := licenseLoader.Status()
	log.Printf("license: state=%s licensed=%v days_remaining=%d%s",
		st.State, st.Licensed, st.DaysRemaining, describeLicence(st))
	if start.IsZero() {
		log.Println("license: no trial start recorded; the trial will be treated as beginning now")
	}
}

func describeLicence(st license.Status) string {
	if st.Customer != "" {
		return " customer=" + st.Customer
	}
	return ""
}

// licenseStatus is what the gate middleware and the health endpoint read.
//
// Safe before initLicense runs — tests build a router without booting — and it reports a permissive
// status in that case rather than blocking writes. An uninitialised loader is a programming error, not
// a customer's expired licence, and the two must not look the same.
func licenseStatus() license.Status {
	if licenseLoader == nil {
		return license.Status{State: license.StateNotEnforced, Licensed: true}
	}
	return licenseLoader.Status()
}
