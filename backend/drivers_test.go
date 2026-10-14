package main

import (
	"database/sql"
	"fmt"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// --- parseRedisCmd tests ---

func TestParseRedisCmd_SimpleCommand(t *testing.T) {
	result, err := parseRedisCmd("GET mykey")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result) != 2 {
		t.Fatalf("expected 2 args, got %d", len(result))
	}
	if result[0] != "GET" || result[1] != "mykey" {
		t.Errorf("expected [GET, mykey], got %v", result)
	}
}

func TestParseRedisCmd_MultipleArgs(t *testing.T) {
	result, err := parseRedisCmd("SET mykey myvalue")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result) != 3 {
		t.Fatalf("expected 3 args, got %d", len(result))
	}
	if result[0] != "SET" || result[1] != "mykey" || result[2] != "myvalue" {
		t.Errorf("expected [SET, mykey, myvalue], got %v", result)
	}
}

func TestParseRedisCmd_DoubleQuotedString(t *testing.T) {
	result, err := parseRedisCmd(`SET mykey "hello world"`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result) != 3 {
		t.Fatalf("expected 3 args, got %d", len(result))
	}
	if result[2] != "hello world" {
		t.Errorf("expected 'hello world', got '%v'", result[2])
	}
}

func TestParseRedisCmd_SingleQuotedString(t *testing.T) {
	result, err := parseRedisCmd(`SET mykey 'hello world'`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result) != 3 {
		t.Fatalf("expected 3 args, got %d", len(result))
	}
	if result[2] != "hello world" {
		t.Errorf("expected 'hello world', got '%v'", result[2])
	}
}

func TestParseRedisCmd_EscapedQuoteInDoubleQuotes(t *testing.T) {
	result, err := parseRedisCmd(`SET mykey "hello \"world\""`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result) != 3 {
		t.Fatalf("expected 3 args, got %d", len(result))
	}
	if result[2] != `hello "world"` {
		t.Errorf("expected 'hello \"world\"', got '%v'", result[2])
	}
}

func TestParseRedisCmd_UnmatchedDoubleQuote(t *testing.T) {
	_, err := parseRedisCmd(`SET mykey "hello world`)
	if err == nil {
		t.Fatal("expected error for unmatched double quote")
	}
}

func TestParseRedisCmd_UnmatchedSingleQuote(t *testing.T) {
	_, err := parseRedisCmd(`SET mykey 'hello world`)
	if err == nil {
		t.Fatal("expected error for unmatched single quote")
	}
}

func TestParseRedisCmd_EmptyString(t *testing.T) {
	result, err := parseRedisCmd("")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result) != 0 {
		t.Errorf("expected empty result, got %v", result)
	}
}

func TestParseRedisCmd_SingleArg(t *testing.T) {
	result, err := parseRedisCmd("PING")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result) != 1 || result[0] != "PING" {
		t.Errorf("expected [PING], got %v", result)
	}
}

func TestParseRedisCmd_QuoteAfterNonSpace(t *testing.T) {
	_, err := parseRedisCmd(`SET key value"bad`)
	if err == nil {
		t.Fatal("expected error for quote not followed by space")
	}
}

// --- redisResponseToQueryResult tests ---

func TestRedisResponseToQueryResult_String(t *testing.T) {
	result, err := redisResponseToQueryResult("OK")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Columns) != 1 || result.Columns[0] != "value" {
		t.Errorf("expected columns [value], got %v", result.Columns)
	}
	if len(result.Rows) != 1 || result.Rows[0][0] != "OK" {
		t.Errorf("expected rows [[OK]], got %v", result.Rows)
	}
}

func TestRedisResponseToQueryResult_Int64(t *testing.T) {
	result, err := redisResponseToQueryResult(int64(42))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Rows) != 1 || result.Rows[0][0] != int64(42) {
		t.Errorf("expected rows [[42]], got %v", result.Rows)
	}
}

func TestRedisResponseToQueryResult_Array(t *testing.T) {
	input := []interface{}{"a", "b", "c"}
	result, err := redisResponseToQueryResult(input)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Columns) != 1 || result.Columns[0] != "value" {
		t.Errorf("expected columns [value], got %v", result.Columns)
	}
	if len(result.Rows) != 3 {
		t.Fatalf("expected 3 rows, got %d", len(result.Rows))
	}
	for i, v := range []string{"a", "b", "c"} {
		if result.Rows[i][0] != v {
			t.Errorf("row %d: expected %s, got %v", i, v, result.Rows[i][0])
		}
	}
}

func TestRedisResponseToQueryResult_Map(t *testing.T) {
	input := map[interface{}]interface{}{
		"field1": "value1",
	}
	result, err := redisResponseToQueryResult(input)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Columns) != 2 || result.Columns[0] != "key" || result.Columns[1] != "value" {
		t.Errorf("expected columns [key, value], got %v", result.Columns)
	}
	if len(result.Rows) != 1 {
		t.Fatalf("expected 1 row, got %d", len(result.Rows))
	}
}

func TestRedisResponseToQueryResult_UnknownType(t *testing.T) {
	result, err := redisResponseToQueryResult(3.14)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Rows) != 1 {
		t.Fatalf("expected 1 row, got %d", len(result.Rows))
	}
	if result.Rows[0][0] != "3.14" {
		t.Errorf("expected '3.14', got %v", result.Rows[0][0])
	}
}

// --- SQLite-based integration tests for SQL helpers ---

func setupTestDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatalf("failed to open in-memory sqlite: %v", err)
	}

	_, err = db.Exec(`
		CREATE TABLE users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			email TEXT NOT NULL
		);
		INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
		INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com');
		INSERT INTO users (name, email) VALUES ('Charlie', 'charlie@example.com');
		INSERT INTO users (name, email) VALUES ('Dave', 'dave@example.com');
		INSERT INTO users (name, email) VALUES ('Eve', 'eve@example.com');
	`)
	if err != nil {
		t.Fatalf("failed to setup test data: %v", err)
	}
	return db
}

func TestExecuteSQLQuery_Basic(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	result, err := executeSQLQuery(db, "SELECT id, name FROM users ORDER BY id")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Columns) != 2 {
		t.Fatalf("expected 2 columns, got %d", len(result.Columns))
	}
	if result.Columns[0] != "id" || result.Columns[1] != "name" {
		t.Errorf("expected columns [id, name], got %v", result.Columns)
	}
	if len(result.Rows) != 5 {
		t.Fatalf("expected 5 rows, got %d", len(result.Rows))
	}
}

func TestExecuteSQLQuery_EmptyResult(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	result, err := executeSQLQuery(db, "SELECT * FROM users WHERE id = 999")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Rows) != 0 {
		t.Errorf("expected 0 rows, got %d", len(result.Rows))
	}
	if len(result.Columns) != 3 {
		t.Errorf("expected 3 columns, got %d", len(result.Columns))
	}
}

func TestExecuteSQLQuery_InvalidSQL(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	_, err := executeSQLQuery(db, "INVALID SQL STATEMENT")
	if err == nil {
		t.Fatal("expected error for invalid SQL")
	}
}

func TestExecuteSQLCount(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	count, err := executeSQLCount(db, "SELECT * FROM users")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if count != 5 {
		t.Errorf("expected count 5, got %d", count)
	}
}

func TestExecuteSQLCount_WithSemicolon(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	count, err := executeSQLCount(db, "SELECT * FROM users;")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if count != 5 {
		t.Errorf("expected count 5, got %d", count)
	}
}

func TestExecuteSQLCount_WithFilter(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	count, err := executeSQLCount(db, "SELECT * FROM users WHERE name = 'Alice'")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if count != 1 {
		t.Errorf("expected count 1, got %d", count)
	}
}

func TestExecuteSQLQueryWithPagination_LimitOnly(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	limit := 2
	result, err := executeSQLQueryWithPagination(db, "SELECT * FROM users ORDER BY id", &limit, nil, "sqlite")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Rows) != 2 {
		t.Errorf("expected 2 rows, got %d", len(result.Rows))
	}
}

func TestExecuteSQLQueryWithPagination_LimitAndOffset(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	limit := 2
	offset := 2
	result, err := executeSQLQueryWithPagination(db, "SELECT name FROM users ORDER BY id", &limit, &offset, "sqlite")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Rows) != 2 {
		t.Fatalf("expected 2 rows, got %d", len(result.Rows))
	}
	if result.Rows[0][0] != "Charlie" {
		t.Errorf("expected first row to be Charlie, got %v", result.Rows[0][0])
	}
	if result.Rows[1][0] != "Dave" {
		t.Errorf("expected second row to be Dave, got %v", result.Rows[1][0])
	}
}

func TestExecuteSQLQueryWithPagination_QueryWithExistingLimit(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	limit := 100
	result, err := executeSQLQueryWithPagination(db, "SELECT * FROM users ORDER BY id LIMIT 1", &limit, nil, "sqlite")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Rows) != 1 {
		t.Errorf("expected 1 row (existing LIMIT respected), got %d", len(result.Rows))
	}
}

func TestExecuteSQLQueryWithPagination_WithSemicolon(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	limit := 2
	result, err := executeSQLQueryWithPagination(db, "SELECT * FROM users ORDER BY id;", &limit, nil, "sqlite")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Rows) != 2 {
		t.Errorf("expected 2 rows, got %d", len(result.Rows))
	}
}

func TestExecuteSQLQueryWithPagination_MySQL_OffsetWithoutLimit(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	offset := 1
	result, err := executeSQLQueryWithPagination(db, "SELECT * FROM users ORDER BY id", nil, &offset, "mysql")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Rows) != 4 {
		t.Errorf("expected 4 rows (MySQL adds LIMIT 1000 with offset), got %d", len(result.Rows))
	}
}

func TestExecuteSQLQueryWithPagination_ZeroLimit(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	limit := 0
	result, err := executeSQLQueryWithPagination(db, "SELECT * FROM users ORDER BY id", &limit, nil, "sqlite")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Rows) != 5 {
		t.Errorf("expected 5 rows (zero limit should not apply), got %d", len(result.Rows))
	}
}

// --- SQLiteDriver tests ---

func TestSQLiteDriver_ConnectAndQuery(t *testing.T) {
	driver := &SQLiteDriver{}
	err := driver.Connect(Config{DBName: ":memory:"})
	if err != nil {
		t.Fatalf("failed to connect: %v", err)
	}
	defer driver.Close()

	_, err = driver.db.Exec("CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT)")
	if err != nil {
		t.Fatalf("failed to create table: %v", err)
	}
	_, err = driver.db.Exec("INSERT INTO test (val) VALUES ('hello'), ('world')")
	if err != nil {
		t.Fatalf("failed to insert: %v", err)
	}

	result, err := driver.Query("SELECT * FROM test ORDER BY id")
	if err != nil {
		t.Fatalf("query failed: %v", err)
	}
	if len(result.Rows) != 2 {
		t.Errorf("expected 2 rows, got %d", len(result.Rows))
	}
}

func TestSQLiteDriver_Count(t *testing.T) {
	driver := &SQLiteDriver{}
	err := driver.Connect(Config{DBName: ":memory:"})
	if err != nil {
		t.Fatalf("failed to connect: %v", err)
	}
	defer driver.Close()

	_, err = driver.db.Exec("CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT)")
	if err != nil {
		t.Fatalf("failed to create table: %v", err)
	}
	_, err = driver.db.Exec("INSERT INTO test (val) VALUES ('a'), ('b'), ('c')")
	if err != nil {
		t.Fatalf("failed to insert: %v", err)
	}

	count, err := driver.Count("SELECT * FROM test")
	if err != nil {
		t.Fatalf("count failed: %v", err)
	}
	if count != 3 {
		t.Errorf("expected count 3, got %d", count)
	}
}

func TestSQLiteDriver_QueryWithPagination(t *testing.T) {
	driver := &SQLiteDriver{}
	err := driver.Connect(Config{DBName: ":memory:"})
	if err != nil {
		t.Fatalf("failed to connect: %v", err)
	}
	defer driver.Close()

	_, err = driver.db.Exec("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)")
	if err != nil {
		t.Fatalf("failed to create table: %v", err)
	}
	for i := 1; i <= 10; i++ {
		_, err = driver.db.Exec("INSERT INTO items (name) VALUES (?)", fmt.Sprintf("item_%d", i))
		if err != nil {
			t.Fatalf("failed to insert: %v", err)
		}
	}

	limit := 3
	offset := 2
	result, err := driver.QueryWithPagination("SELECT * FROM items ORDER BY id", &limit, &offset)
	if err != nil {
		t.Fatalf("query with pagination failed: %v", err)
	}
	if len(result.Rows) != 3 {
		t.Errorf("expected 3 rows, got %d", len(result.Rows))
	}
}
