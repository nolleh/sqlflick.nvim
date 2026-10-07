package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSQLiteSchemaIncludesTablesViewsAndColumns(t *testing.T) {
	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatalf("failed to open sqlite: %v", err)
	}
	defer db.Close()

	if _, err := db.Exec(`
		CREATE TABLE users (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL,
			email TEXT
		);
		CREATE VIEW named_users AS SELECT id, name FROM users;
	`); err != nil {
		t.Fatalf("failed to create schema: %v", err)
	}

	driver := &SQLiteDriver{db: db}
	schema, err := driver.Schema()
	if err != nil {
		t.Fatalf("failed to load schema: %v", err)
	}

	tables := make(map[string]SchemaTable)
	for _, table := range schema.Tables {
		tables[table.Name] = table
	}

	users, ok := tables["users"]
	if !ok {
		t.Fatal("expected users table")
	}
	if users.Type != "table" {
		t.Fatalf("expected table type, got %q", users.Type)
	}
	if len(users.Columns) != 3 {
		t.Fatalf("expected 3 user columns, got %d", len(users.Columns))
	}
	if users.Columns[0].Name != "id" || users.Columns[1].Name != "name" {
		t.Fatalf("unexpected user columns: %#v", users.Columns)
	}
	if users.Columns[1].Nullable {
		t.Fatal("expected NOT NULL column to be non-nullable")
	}

	view, ok := tables["named_users"]
	if !ok {
		t.Fatal("expected named_users view")
	}
	if view.Type != "view" || len(view.Columns) != 2 {
		t.Fatalf("unexpected view schema: %#v", view)
	}
}

func TestHandleSchemaReturnsProviderMetadata(t *testing.T) {
	originalDrivers := drivers
	drivers = map[string]DatabaseDriver{
		"schema_stub": &schemaStubDriver{},
	}
	defer func() { drivers = originalDrivers }()

	body, err := json.Marshal(SchemaRequest{Database: "schema_stub"})
	if err != nil {
		t.Fatalf("failed to marshal request: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/schema", bytes.NewReader(body))
	recorder := httptest.NewRecorder()

	handleSchema(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recorder.Code, recorder.Body.String())
	}
	var schema SchemaResult
	if err := json.Unmarshal(recorder.Body.Bytes(), &schema); err != nil {
		t.Fatalf("failed to decode schema: %v", err)
	}
	if len(schema.Tables) != 1 || schema.Tables[0].Name != "users" {
		t.Fatalf("unexpected schema: %#v", schema)
	}
}

type schemaStubDriver struct{}

func (d *schemaStubDriver) Connect(Config) error { return nil }
func (d *schemaStubDriver) Query(string) (QueryResult, error) {
	return QueryResult{}, nil
}
func (d *schemaStubDriver) QueryWithPagination(string, *int, *int) (QueryResult, error) {
	return QueryResult{}, nil
}
func (d *schemaStubDriver) Count(string) (int64, error) { return 0, nil }
func (d *schemaStubDriver) Close() error                { return nil }
func (d *schemaStubDriver) Schema() (SchemaResult, error) {
	return SchemaResult{Tables: []SchemaTable{{Name: "users", Type: "table"}}}, nil
}
