package main

import (
	"database/sql"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/go-sql-driver/mysql"
)

func TestPostgresConnectionURLPreservesOptions(t *testing.T) {
	for _, scheme := range []string{"postgresql", "postgres"} {
		dsn, err := postgresConnectionString(Config{
			URL: scheme + "://app:p%40ss@localhost:5433/app_dev?sslmode=require&application_name=sqlflick",
		})
		if err != nil {
			t.Fatal(err)
		}
		for _, setting := range []string{"user='app'", "password='p@ss'", "host='localhost'", "port='5433'", "dbname='app_dev'", "sslmode='require'", "application_name='sqlflick'"} {
			if !strings.Contains(dsn, setting) {
				t.Errorf("missing expected setting %s", setting)
			}
		}
		if strings.Contains(dsn, "sslmode=disable") {
			t.Fatal("URL TLS setting was overridden")
		}
	}
}

func TestMySQLURLPreservesCredentialsAndOptions(t *testing.T) {
	dsn, err := mysqlConnectionString(Config{URL: "mysql://app:p%40ss@localhost:3307/app?parseTime=true&tls=true&timeout=2s&charset=utf8mb4"})
	if err != nil {
		t.Fatal(err)
	}
	config, err := mysql.ParseDSN(dsn)
	if err != nil {
		t.Fatal(err)
	}
	if config.User != "app" || config.Passwd != "p@ss" || config.Addr != "localhost:3307" || config.DBName != "app" {
		t.Fatal("URL target or credentials changed")
	}
	if !config.ParseTime || config.TLSConfig != "true" || config.Timeout != 2*time.Second || config.Params["charset"] != "utf8mb4" {
		t.Fatal("MySQL URL options were lost")
	}
}

func TestMySQLURLKeepsDefaultAuthentication(t *testing.T) {
	for _, input := range []string{
		"mysql://test_user:test_password@localhost:3306/test_db",
		"mysql://test_user:test_password@localhost:3306/test_db?parseTime=true",
	} {
		dsn, err := mysqlConnectionString(Config{URL: input})
		if err != nil {
			t.Fatal(err)
		}
		config, err := mysql.ParseDSN(dsn)
		if err != nil || !config.AllowNativePasswords {
			t.Fatal("URL conversion disabled native password authentication")
		}
	}
}

func TestMySQLURLQueryCredentialsAndIPv6(t *testing.T) {
	dsn, err := mysqlConnectionString(Config{URL: "mysql://old:old@[::1]/app?user=new&password=p%40ss&timeout=2000ms"})
	if err != nil {
		t.Fatal(err)
	}
	config, err := mysql.ParseDSN(dsn)
	if err != nil || config.User != "new" || config.Passwd != "p@ss" || config.Addr != "[::1]:3306" || config.Timeout != 2*time.Second {
		t.Fatal("query credentials, IPv6, or JDBC timeout conversion was lost")
	}
}

func TestRedisURLPreservesTLSAuthAndDatabase(t *testing.T) {
	opts, err := redisConnectionOptions(Config{URL: "rediss://app:p%40ss@localhost:6380/3?read_timeout=2s&pool_size=100"})
	if err != nil {
		t.Fatal(err)
	}
	if opts.Username != "app" || opts.Password != "p@ss" || opts.DB != 3 || opts.Addr != "localhost:6380" || opts.TLSConfig == nil {
		t.Fatal("Redis URL settings were lost")
	}
	if opts.ReadTimeout != 2*time.Second || opts.PoolSize != maxPoolConnections || opts.MaxActiveConns != maxPoolConnections || !opts.ContextTimeoutEnabled {
		t.Fatal("Redis timeout or shared pool policy changed")
	}
}

func TestRedisURLDefaultsIPv6Port(t *testing.T) {
	opts, err := redisConnectionOptions(Config{URL: "redis://[::1]/2"})
	if err != nil || opts.Addr != "[::1]:6379" || opts.DB != 2 {
		t.Fatal("Redis IPv6 URL lost its default port or database")
	}
}

func TestSQLiteURLReadsExistingFileAndPreservesReadOnly(t *testing.T) {
	path := filepath.Join(t.TempDir(), "app dev.db")
	db, err := sql.Open("sqlite3", path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec("CREATE TABLE items (id INTEGER); INSERT INTO items VALUES (1)"); err != nil {
		t.Fatal(err)
	}
	_ = db.Close()
	u := url.URL{Scheme: "file", Path: path, RawQuery: "mode=ro"}
	driver := &SQLiteDriver{}
	if err := driver.Connect(Config{URL: u.String(), DBName: "must-not-be-used.db"}); err != nil {
		t.Fatal(err)
	}
	defer driver.Close()
	result, err := driver.Query("SELECT id FROM items")
	if err != nil || len(result.Rows) != 1 {
		t.Fatal("SQLite URL did not open the original file")
	}
	if _, err := driver.db.Exec("INSERT INTO items VALUES (2)"); err == nil {
		t.Fatal("SQLite read-only option was discarded")
	}
}

func TestOracleURLPreservesOptions(t *testing.T) {
	input := "oracle://app:p%40ss@localhost:1521/appservice?SSL=enable&SSL%20VERIFY=true"
	dsn, err := oracleConnectionString(Config{URL: input})
	if err != nil || dsn != input {
		t.Fatal("Oracle connection options were lost")
	}
}

func TestInvalidDatabaseURLDiagnosticsDoNotExposeSecrets(t *testing.T) {
	if _, err := mysqlConnectionString(Config{URL: "mysql://app:secret@localhost/app?timeout=secret"}); err == nil || strings.Contains(err.Error(), "secret") {
		t.Fatal("MySQL diagnostics exposed credentials or accepted invalid options")
	}
	if _, err := redisConnectionOptions(Config{URL: "redis://app:secret@localhost/not-a-number"}); err == nil || strings.Contains(err.Error(), "secret") {
		t.Fatal("Redis diagnostics exposed credentials or accepted an invalid DB")
	}
	if _, err := oracleConnectionString(Config{URL: "oracle://app:secret%ZZ@localhost/app"}); err == nil || strings.Contains(err.Error(), "secret") {
		t.Fatal("Oracle diagnostics exposed credentials or accepted an invalid URL")
	}
}

func TestPostgresConnectionURLRedactsInvalidInput(t *testing.T) {
	for _, input := range []string{"mysql://app:secret@localhost/app", "postgres://app:secret%ZZ@localhost/app"} {
		_, err := postgresConnectionString(Config{URL: input})
		if err == nil || strings.Contains(err.Error(), "secret") {
			t.Fatal("invalid URL must produce a credential-free error")
		}
	}
}

func TestPostgresFieldConfigurationStillWorks(t *testing.T) {
	dsn, err := postgresConnectionString(Config{Host: "localhost", Port: 5432, User: "app", Password: "pass", DBName: "app_dev"})
	if err != nil || dsn != "host=localhost port=5432 user=app password=pass dbname=app_dev sslmode=disable" {
		t.Fatal("legacy connection configuration changed")
	}
}
