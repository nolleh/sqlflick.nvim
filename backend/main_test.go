package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// --- responseWriter tests ---

func TestResponseWriter_NormalWrite(t *testing.T) {
	recorder := httptest.NewRecorder()
	rw := &responseWriter{ResponseWriter: recorder}

	n, err := rw.Write([]byte("hello"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if n != 5 {
		t.Errorf("expected 5 bytes written, got %d", n)
	}
	if recorder.Body.String() != "hello" {
		t.Errorf("expected 'hello', got '%s'", recorder.Body.String())
	}
}

func TestResponseWriter_ErrorResponse(t *testing.T) {
	recorder := httptest.NewRecorder()
	rw := &responseWriter{ResponseWriter: recorder}

	rw.WriteHeader(http.StatusBadRequest)
	_, err := rw.Write([]byte("bad request"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var resp ErrorResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to unmarshal error response: %v", err)
	}
	if resp.Error != "bad request" {
		t.Errorf("expected error 'bad request', got '%s'", resp.Error)
	}
}

func TestResponseWriter_StatusCodeCapture(t *testing.T) {
	recorder := httptest.NewRecorder()
	rw := &responseWriter{ResponseWriter: recorder}

	rw.WriteHeader(http.StatusInternalServerError)
	if rw.statusCode != http.StatusInternalServerError {
		t.Errorf("expected status code 500, got %d", rw.statusCode)
	}
}

// --- handleQuery tests ---

func TestHandleQuery_MethodNotAllowed(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/query", nil)
	recorder := httptest.NewRecorder()

	handleQuery(recorder, req)

	if recorder.Code != http.StatusMethodNotAllowed {
		t.Errorf("expected 405, got %d", recorder.Code)
	}
}

func TestHandleQuery_InvalidJSON(t *testing.T) {
	body := bytes.NewBufferString("{invalid json")
	req := httptest.NewRequest(http.MethodPost, "/query", body)
	recorder := httptest.NewRecorder()

	handleQuery(recorder, req)

	if recorder.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", recorder.Code)
	}
}

func TestHandleQuery_UnsupportedDatabase(t *testing.T) {
	reqBody := QueryRequest{
		Database: "unsupported_db",
		Query:    "SELECT 1",
		Config:   Config{},
	}
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/query", bytes.NewBuffer(body))
	recorder := httptest.NewRecorder()

	handleQuery(recorder, req)

	if recorder.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", recorder.Code)
	}
}

func TestHandleQuery_SQLite_Success(t *testing.T) {
	db := setupSQLiteTestDB(t)
	defer db.Close()

	origDrivers := drivers
	drivers = map[string]DatabaseDriver{
		"sqlite": &testSQLiteDriver{db: db},
	}
	defer func() { drivers = origDrivers }()

	reqBody := QueryRequest{
		Database: "sqlite",
		Query:    "SELECT id, name FROM users ORDER BY id",
		Config:   Config{DBName: ":memory:"},
	}
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/query", bytes.NewBuffer(body))
	recorder := httptest.NewRecorder()

	handleQuery(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recorder.Code, recorder.Body.String())
	}

	var result QueryResult
	if err := json.Unmarshal(recorder.Body.Bytes(), &result); err != nil {
		t.Fatalf("failed to unmarshal response: %v", err)
	}
	if len(result.Columns) != 2 {
		t.Errorf("expected 2 columns, got %d", len(result.Columns))
	}
	if len(result.Rows) != 3 {
		t.Errorf("expected 3 rows, got %d", len(result.Rows))
	}
}

func TestHandleQuery_SQLite_WithPagination(t *testing.T) {
	db := setupSQLiteTestDB(t)
	defer db.Close()

	origDrivers := drivers
	drivers = map[string]DatabaseDriver{
		"sqlite": &testSQLiteDriver{db: db},
	}
	defer func() { drivers = origDrivers }()

	limit := 2
	offset := 1
	reqBody := QueryRequest{
		Database: "sqlite",
		Query:    "SELECT name FROM users ORDER BY id",
		Config:   Config{DBName: ":memory:"},
		Limit:    &limit,
		Offset:   &offset,
	}
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/query", bytes.NewBuffer(body))
	recorder := httptest.NewRecorder()

	handleQuery(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recorder.Code, recorder.Body.String())
	}

	var result QueryResult
	if err := json.Unmarshal(recorder.Body.Bytes(), &result); err != nil {
		t.Fatalf("failed to unmarshal response: %v", err)
	}
	if len(result.Rows) != 2 {
		t.Errorf("expected 2 rows, got %d", len(result.Rows))
	}
}

// --- handleCount tests ---

func TestHandleCount_MethodNotAllowed(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/count", nil)
	recorder := httptest.NewRecorder()

	handleCount(recorder, req)

	if recorder.Code != http.StatusMethodNotAllowed {
		t.Errorf("expected 405, got %d", recorder.Code)
	}
}

func TestHandleCount_InvalidJSON(t *testing.T) {
	body := bytes.NewBufferString("not json")
	req := httptest.NewRequest(http.MethodPost, "/count", body)
	recorder := httptest.NewRecorder()

	handleCount(recorder, req)

	if recorder.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", recorder.Code)
	}
}

func TestHandleCount_UnsupportedDatabase(t *testing.T) {
	reqBody := QueryRequest{
		Database: "nosql_thing",
		Query:    "SELECT 1",
	}
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/count", bytes.NewBuffer(body))
	recorder := httptest.NewRecorder()

	handleCount(recorder, req)

	if recorder.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", recorder.Code)
	}
}

func TestHandleCount_SQLite_Success(t *testing.T) {
	db := setupSQLiteTestDB(t)
	defer db.Close()

	origDrivers := drivers
	drivers = map[string]DatabaseDriver{
		"sqlite": &testSQLiteDriver{db: db},
	}
	defer func() { drivers = origDrivers }()

	reqBody := QueryRequest{
		Database: "sqlite",
		Query:    "SELECT * FROM users",
		Config:   Config{DBName: ":memory:"},
	}
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/count", bytes.NewBuffer(body))
	recorder := httptest.NewRecorder()

	handleCount(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recorder.Code, recorder.Body.String())
	}

	var result CountResult
	if err := json.Unmarshal(recorder.Body.Bytes(), &result); err != nil {
		t.Fatalf("failed to unmarshal response: %v", err)
	}
	if result.Count != 3 {
		t.Errorf("expected count 3, got %d", result.Count)
	}
}

// --- jsonErrorMiddleware tests ---

func TestJsonErrorMiddleware_WrapsError(t *testing.T) {
	handler := jsonErrorMiddleware(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "something went wrong", http.StatusInternalServerError)
	})

	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	recorder := httptest.NewRecorder()

	handler(recorder, req)

	contentType := recorder.Header().Get("Content-Type")
	if contentType != "application/json" {
		t.Errorf("expected application/json content type, got '%s'", contentType)
	}

	var resp ErrorResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to unmarshal error response: %v", err)
	}
	if resp.Error == "" {
		t.Error("expected non-empty error message")
	}
}

func TestJsonErrorMiddleware_PassesThrough(t *testing.T) {
	handler := jsonErrorMiddleware(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	})

	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	recorder := httptest.NewRecorder()

	handler(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", recorder.Code)
	}
}

// --- test helpers ---

// testSQLiteDriver wraps an existing *sql.DB so handlers can use it
// without opening a new connection via Connect()
type testSQLiteDriver struct {
	db *sql.DB
}

func (d *testSQLiteDriver) Connect(config Config) error {
	return nil
}

func (d *testSQLiteDriver) Query(query string) (QueryResult, error) {
	return executeSQLQuery(d.db, query)
}

func (d *testSQLiteDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	return executeSQLQueryWithPagination(d.db, query, limit, offset, "sqlite")
}

func (d *testSQLiteDriver) Count(query string) (int64, error) {
	return executeSQLCount(d.db, query)
}

func (d *testSQLiteDriver) Close() error {
	return nil
}

func setupSQLiteTestDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatalf("failed to open sqlite: %v", err)
	}
	_, err = db.Exec(`
		CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT);
		INSERT INTO users (name, email) VALUES ('Alice', 'alice@test.com');
		INSERT INTO users (name, email) VALUES ('Bob', 'bob@test.com');
		INSERT INTO users (name, email) VALUES ('Charlie', 'charlie@test.com');
	`)
	if err != nil {
		t.Fatalf("failed to setup test db: %v", err)
	}
	return db
}
