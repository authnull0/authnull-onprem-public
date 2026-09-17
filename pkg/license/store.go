package license

import (
	"time"

	"gorm.io/gorm"
)

// Document storage: uploaded licences, in the master database.
//
// The database is the primary source because a container filesystem does not survive a restart or an
// upgrade, the packaged licence path is mounted read-only, and with more than one replica a file
// upload only reaches whichever container served the request. See migration 012.

// Document is one uploaded licence.
type Document struct {
	ID int64 `gorm:"column:id;primaryKey"`
	// Document is the signed licence exactly as uploaded. Re-verified on every read; never trusted
	// because it is in our own database.
	Document string `gorm:"column:document"`
	// LicenseID, Customer and ExpiresAt are copies extracted AFTER verification, for display and
	// support only. Nothing authorises off them.
	LicenseID string     `gorm:"column:license_id"`
	Customer  string     `gorm:"column:customer"`
	ExpiresAt *time.Time `gorm:"column:expires_at"`

	UploadedByUserID int       `gorm:"column:uploaded_by_user_id"`
	UploadedAt       time.Time `gorm:"column:uploaded_at"`
}

// TableName maps to the master database. A licence covers the deployment, not an organisation.
func (Document) TableName() string { return "did.license_documents" }

// DocumentStore reads and appends licence documents.
type DocumentStore struct{ db *gorm.DB }

// NewDocumentStore builds a store. A nil db yields a store whose Current reports no licence, so the
// caller does not have to nil-check before wiring the loader.
func NewDocumentStore(db *gorm.DB) *DocumentStore { return &DocumentStore{db: db} }

// Current returns the newest uploaded licence.
//
// Returns ErrNoLicense when there is none, which is the ordinary state of a fresh install — the
// caller treats it as "fall back to the file, then to the trial", not as a failure.
//
// Ordered by uploaded_at DESC with id as the tiebreak: two uploads inside the same clock tick are
// possible, and without the tiebreak which one applied would depend on query order.
func (s *DocumentStore) Current() ([]byte, error) {
	if s == nil || s.db == nil {
		return nil, ErrNoLicense
	}
	var doc Document
	err := s.db.Order("uploaded_at DESC, id DESC").First(&doc).Error
	if err == gorm.ErrRecordNotFound {
		return nil, ErrNoLicense
	}
	if err != nil {
		return nil, err
	}
	if doc.Document == "" {
		return nil, ErrNoLicense
	}
	return []byte(doc.Document), nil
}

// Save appends a licence.
//
// The caller MUST have verified the document first — Save records display fields from the payload and
// would happily store a forgery if handed one. Verification lives at the handler, immediately after
// reading the request body, so an unverified document never reaches persistence.
//
// Appends rather than replaces, so uploading the wrong file over a good licence is recoverable.
func (s *DocumentStore) Save(document []byte, p *Payload, uploadedByUserID int) error {
	if s == nil || s.db == nil {
		return gorm.ErrInvalidDB
	}
	rec := Document{
		Document:         string(document),
		UploadedByUserID: uploadedByUserID,
		UploadedAt:       time.Now().UTC(),
	}
	if p != nil {
		rec.LicenseID = p.ID
		rec.Customer = p.Customer
		expires := p.ExpiresAt
		rec.ExpiresAt = &expires
	}
	return s.db.Create(&rec).Error
}

// History returns the most recent uploads, newest first, WITHOUT the document bodies.
//
// The bodies are excluded on purpose. A licence is not a secret, but there is no reason for a console
// page to ship several kilobytes of signed blobs to a browser to render a table of dates.
func (s *DocumentStore) History(limit int) ([]Document, error) {
	if s == nil || s.db == nil {
		return nil, nil
	}
	if limit <= 0 || limit > 50 {
		limit = 10
	}
	var out []Document
	err := s.db.
		Select("id", "license_id", "customer", "expires_at", "uploaded_by_user_id", "uploaded_at").
		Order("uploaded_at DESC, id DESC").
		Limit(limit).
		Find(&out).Error
	return out, err
}
