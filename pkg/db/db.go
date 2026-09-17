package db

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/sirupsen/logrus"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var (
	once     sync.Once
	commonDB *gorm.DB

	orgMu                sync.Mutex
	organizationDatabase map[string]*gorm.DB
)

type Organization struct {
	ID               int64  `json:"id"`
	OrganizationName string `json:"organizationName" gorm:"column:organization_name"`
	AdminEmail       string `json:"adminEmail"       gorm:"column:admin_email"`
	Status           string `json:"status"           gorm:"column:status"`
	DatabaseStatus   string `json:"databaseStatus"   gorm:"column:database_status"`
	DatabaseName     string `json:"databaseName"     gorm:"column:database_name"`
}

func (o *Organization) TableName() string {
	return "did.organizations"
}

func dsnFor(database string) (dsn, host, port string) {
	host = os.Getenv("DB_HOST")
	port = os.Getenv("DB_PORT")
	user := os.Getenv("DB_USER")
	password := os.Getenv("DB_PASSWORD")
	schema := os.Getenv("DB_SCHEMA")
	if schema == "" {
		schema = "did"
	}
	dsn = fmt.Sprintf("host=%s user=%s password=%s dbname=%s port=%s sslmode=disable search_path=%s", host, user, password, database, port, schema)
	return dsn, host, port
}

func GetInstance(database string) *gorm.DB {
	if database == "" {
		logrus.Errorf("GetInstance called with empty database name — returning nil")
		return nil
	}
	dsn, host, port := dsnFor(database)
	db, err := gorm.Open(postgres.New(postgres.Config{DSN: dsn, PreferSimpleProtocol: true}), &gorm.Config{})
	if err != nil {
		logrus.Errorf("Error connecting to the database at %s:%s/%s: %v", host, port, database, err)
		return nil
	}
	sqlDB, err := db.DB()
	if err != nil {
		logrus.Errorf("Error getting GORM DB definition: %v", err)
		return nil
	}
	sqlDB.SetMaxIdleConns(maxIdleConns())
	sqlDB.SetMaxOpenConns(maxOpenConns())
	// Recycle connections. Without a lifetime, a pool holds handles across a Postgres restart
	// or a failover and every one of them fails on first use afterwards; with one, the pool
	// heals itself within the lifetime. The idle timeout returns connections a quiet tenant is
	// no longer using, which is what stops per-tenant pools accumulating against the server's
	// ceiling as the tenant count grows.
	sqlDB.SetConnMaxLifetime(30 * time.Minute)
	sqlDB.SetConnMaxIdleTime(5 * time.Minute)
	logrus.Infof("Successfully established connection to %s:%s/%s (pool: %d idle / %d open)",
		host, port, database, maxIdleConns(), maxOpenConns())
	return db
}

// Pool sizing.
//
// THESE ARE PER DATABASE, and this service opens one pool per organisation plus one for the
// master. So the ceiling it can demand is (orgs + 1) x maxOpenConns, and that has to fit inside
// Postgres max_connections MINUS superuser_reserved_connections MINUS whatever every other
// service on the box is holding.
//
// The measured deployment has max_connections = 100, 3 reserved, and ~30 already in use across
// authn-service, ssi-service, log-service and this one. The previous value here was 100 per
// database, which on two databases is a 200-connection demand against a 97-connection server --
// invisible until a burst, and then it surfaces as "FATAL: sorry, too many clients already",
// which reads like a database fault rather than a client misconfiguration.
//
// 20/5 keeps a two-database deployment inside 40 and leaves real headroom. Raise
// DB_MAX_OPEN_CONNS only together with Postgres max_connections, or put a pooler in front:
// past roughly a dozen tenants, per-tenant pools stop being the right shape at all.
const (
	defaultMaxOpenConns = 20
	defaultMaxIdleConns = 5
)

func maxOpenConns() int { return envInt("DB_MAX_OPEN_CONNS", defaultMaxOpenConns) }

// Clamped to maxOpenConns: database/sql silently reduces idle to open when idle is larger, so a
// config where idle > open is not an error but is never what anyone meant.
func maxIdleConns() int {
	n := envInt("DB_MAX_IDLE_CONNS", defaultMaxIdleConns)
	if open := maxOpenConns(); n > open {
		return open
	}
	return n
}

// envInt reads a positive integer, falling back to the default on anything unusable -- a typo
// must not turn into an unbounded or zero-sized pool.
func envInt(name string, def int) int {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return def
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		logrus.Warnf("%s=%q is not a positive integer; using %d", name, raw, def)
		return def
	}
	return n
}

func GetCommonDBInstance() *gorm.DB {
	once.Do(func() {
		commonDB = GetInstance(os.Getenv("DB_NAME"))
	})
	return commonDB
}

func GetConnectiontoDatabaseDynamically(database string) *gorm.DB {
	orgMu.Lock()
	defer orgMu.Unlock()
	if organizationDatabase == nil {
		organizationDatabase = make(map[string]*gorm.DB)
	}
	if organizationDatabase[database] == nil {
		organizationDatabase[database] = GetInstance(database)
	}
	return organizationDatabase[database]
}

func GetOrganizationDatabaseName(orgid int) (string, error) {
	var org Organization
	conn := GetConnectiontoDatabaseDynamically(os.Getenv("DB_NAME"))
	err := conn.Where("id = ?", orgid).First(&org).Error
	if err != nil {
		return "", err
	}
	// Use database_name if set, fall back to organization_name (legacy)
	if org.DatabaseName != "" {
		return org.DatabaseName, nil
	}
	return org.OrganizationName, nil
}

// GetOrgDatabaseByName looks up the database_name for an org by org name or site_url.
func GetOrgDatabaseByName(orgName string) (string, error) {
	var org Organization
	conn := GetConnectiontoDatabaseDynamically(os.Getenv("DB_NAME"))
	err := conn.Where("organization_name = ? OR site_url LIKE ?", orgName, "%"+orgName+"%").First(&org).Error
	if err != nil {
		return orgName, nil // fall back to orgName itself
	}
	if org.DatabaseName != "" {
		return org.DatabaseName, nil
	}
	return org.OrganizationName, nil
}

// SetUUID stores a UUID key in Redis (value=0, no expiry).
func SetUUID(uuid string) error {
	client := GetRedisInstance()
	return client.Set(context.Background(), uuid, 0, 0).Err()
}

// SetOrgAndTenant stores a requestId→orgTenantName mapping in Redis.
func SetOrgAndTenant(requestId, orgTenantName string) error {
	client := GetRedisInstance()
	return client.Set(context.Background(), requestId, orgTenantName, 0).Err()
}

// AllOrgDatabaseNames lists every organisation's database name.
//
// Lives here rather than beside mfapush.AllOrgDatabases (which returns open handles keyed by
// org id) because the name is what a log line or an operator needs — "alpha is missing
// auth_logs.decision" is actionable in a way that "org 2" is not. Both apply the same
// database_name-then-organization_name fallback, so they always agree on which databases exist.
func AllOrgDatabaseNames() ([]string, error) {
	master := GetConnectiontoDatabaseDynamically(os.Getenv("DB_NAME"))
	if master == nil {
		return nil, fmt.Errorf("db: cannot reach the master database (DB_NAME=%q)", os.Getenv("DB_NAME"))
	}
	var orgs []Organization
	if err := master.Table("did.organizations").Find(&orgs).Error; err != nil {
		return nil, fmt.Errorf("db: list organisations: %w", err)
	}
	out := make([]string, 0, len(orgs))
	for _, org := range orgs {
		name := strings.TrimSpace(org.DatabaseName)
		if name == "" {
			name = strings.TrimSpace(org.OrganizationName)
		}
		if name != "" {
			out = append(out, name)
		}
	}
	return out, nil
}
