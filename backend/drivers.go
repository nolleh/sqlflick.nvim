package main

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	_ "github.com/go-sql-driver/mysql"
	_ "github.com/lib/pq"
	_ "github.com/mattn/go-sqlite3"
	"github.com/redis/go-redis/v9"
	_ "github.com/sijms/go-ora/v2"
)

// DatabaseDriver interface defines methods for database operations
type DatabaseDriver interface {
	Connect(config Config) error
	Query(query string) (QueryResult, error)
	QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error)
	Close() error
}

// Config holds database connection configuration
type Config struct {
	Host     string `json:"host"`
	Port     int    `json:"port"`
	User     string `json:"user"`
	Password string `json:"password"`
	DBName   string `json:"dbname"`
}

// PostgresDriver implements DatabaseDriver for PostgreSQL
type PostgresDriver struct {
	db *sql.DB
}

func (d *PostgresDriver) Connect(config Config) error {
	connStr := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
		config.Host, config.Port, config.User, config.Password, config.DBName)
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return err
	}
	d.db = db
	return nil
}

func (d *PostgresDriver) Query(query string) (QueryResult, error) {
	return executeSQLQuery(d.db, query)
}

func (d *PostgresDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	return executeSQLQueryWithPagination(d.db, query, limit, offset)
}

func (d *PostgresDriver) Close() error {
	return d.db.Close()
}

// MySQLDriver implements DatabaseDriver for MySQL
type MySQLDriver struct {
	db *sql.DB
}

func (d *MySQLDriver) Connect(config Config) error {
	connStr := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s",
		config.User, config.Password, config.Host, config.Port, config.DBName)
	db, err := sql.Open("mysql", connStr)
	if err != nil {
		return err
	}
	d.db = db
	return nil
}

func (d *MySQLDriver) Query(query string) (QueryResult, error) {
	return executeSQLQuery(d.db, query)
}

func (d *MySQLDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	return executeSQLQueryWithPagination(d.db, query, limit, offset)
}

func (d *MySQLDriver) Close() error {
	return d.db.Close()
}

// SQLiteDriver implements DatabaseDriver for SQLite
type SQLiteDriver struct {
	db *sql.DB
}

func (d *SQLiteDriver) Connect(config Config) error {
	db, err := sql.Open("sqlite3", config.DBName)
	if err != nil {
		return err
	}
	d.db = db
	return nil
}

func (d *SQLiteDriver) Query(query string) (QueryResult, error) {
	return executeSQLQuery(d.db, query)
}

func (d *SQLiteDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	return executeSQLQueryWithPagination(d.db, query, limit, offset)
}

func (d *SQLiteDriver) Close() error {
	return d.db.Close()
}

// RedisDriver implements DatabaseDriver for Redis
type RedisDriver struct {
	client *redis.Client
	ctx    context.Context
}

func (d *RedisDriver) Connect(config Config) error {
	d.ctx = context.Background()
	d.client = redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%d", config.Host, config.Port),
		Password: config.Password,
		DB:       0,
	})
	return nil
}

func (d *RedisDriver) Query(query string) (QueryResult, error) {
	// Parse Redis command
	cmd, err := parseRedisCmd(query)
	if err != nil {
		return QueryResult{}, err
	}

	// Execute command
	response, err := d.client.Do(d.ctx, cmd...).Result()
	if err != nil {
		return QueryResult{}, err
	}

	// Convert response to QueryResult
	return redisResponseToQueryResult(response)
}

func (d *RedisDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	// Redis doesn't support SQL-style pagination, so just execute normally
	return d.Query(query)
}

func (d *RedisDriver) Close() error {
	return d.client.Close()
}

// OracleDriver implements DatabaseDriver for Oracle
type OracleDriver struct {
	db *sql.DB
}

func (d *OracleDriver) Connect(config Config) error {
	// Use config values for connection
	// urlOptions := map[string]string{
	//  "SID": config.DBName, // Use DBName as SID (should be "XE")
	// }
	// connStr := go_ora.BuildUrl(config.Host, config.Port, "", config.User, config.Password, urlOptions)
	// db, err := sql.Open("oracle", connStr)
	// Use go-ora BuildUrl for Oracle connection string
	connStr := fmt.Sprintf("oracle://%s:%s@%s:%d/%s", config.User,
		config.Password, config.Host, config.Port, config.DBName)
	db, err := sql.Open("oracle", connStr)
	if err != nil {
		return fmt.Errorf("%s, %s", err.Error(), connStr)
	}
	d.db = db
	return nil
}

func (d *OracleDriver) Query(query string) (QueryResult, error) {
	// Remove trailing semicolon if present
	query = strings.TrimSpace(query)
	if strings.HasSuffix(query, ";") {
		query = strings.TrimSuffix(query, ";")
	}
	return executeSQLQuery(d.db, query)
}

func (d *OracleDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	// Remove trailing semicolon if present
	query = strings.TrimSpace(query)
	if strings.HasSuffix(query, ";") {
		query = strings.TrimSuffix(query, ";")
	}
	return executeSQLQueryWithPagination(d.db, query, limit, offset)
}

func (d *OracleDriver) Close() error {
	return d.db.Close()
}

// Helper function to execute SQL queries
func executeSQLQuery(db *sql.DB, query string) (QueryResult, error) {
	rows, err := db.Query(query)
	if err != nil {
		return QueryResult{}, err
	}
	defer rows.Close()

	columns, err := rows.Columns()
	if err != nil {
		return QueryResult{}, err
	}

	result := QueryResult{
		Columns: columns,
		Rows:    make([][]interface{}, 0),
	}

	for rows.Next() {
		values := make([]interface{}, len(columns))
		valuePtrs := make([]interface{}, len(columns))
		for i := range values {
			valuePtrs[i] = &values[i]
		}

		if err := rows.Scan(valuePtrs...); err != nil {
			return QueryResult{}, err
		}

		for i, val := range values {
			if bytes, ok := val.([]byte); ok {
				values[i] = string(bytes)
			}
		}
		result.Rows = append(result.Rows, values)
	}

	if err := rows.Err(); err != nil {
		return QueryResult{}, err
	}

	return result, nil
}

// Helper function to execute SQL queries with pagination
func executeSQLQueryWithPagination(db *sql.DB, query string, limit *int, offset *int) (QueryResult, error) {
	// Build paginated query based on database type
	// For now, we'll use a simple approach: modify the query to add LIMIT and OFFSET
	// This is a basic implementation - in production, you might want to parse SQL properly

	// Trim whitespace and remove trailing semicolon
	query = strings.TrimSpace(query)
	query = strings.TrimSuffix(query, ";")
	query = strings.TrimSpace(query)

	// Check if query already has LIMIT/OFFSET
	queryLower := strings.ToLower(query)
	hasLimit := strings.Contains(queryLower, "limit")
	hasOffset := strings.Contains(queryLower, "offset")

	var paginatedQuery string
	if hasLimit || hasOffset {
		// If query already has LIMIT/OFFSET, don't modify it
		paginatedQuery = query
	} else {
		// Add LIMIT and OFFSET to the query
		paginatedQuery = query
		if limit != nil && *limit > 0 {
			paginatedQuery = fmt.Sprintf("%s LIMIT %d", paginatedQuery, *limit)
		}
		if offset != nil && *offset >= 0 {
			// Allow offset 0 for first page
			if *offset > 0 {
				paginatedQuery = fmt.Sprintf("%s OFFSET %d", paginatedQuery, *offset)
			}
		}
	}

	return executeSQLQuery(db, paginatedQuery)
}

// parseRedisCmd parses string command into args for redis.Do
func parseRedisCmd(unparsed string) ([]any, error) {
	// error helper
	quoteErr := func(quote rune, position int) error {
		if quote == '"' {
			return fmt.Errorf("syntax error: unmatched double quote at: %d", position)
		} else {
			return fmt.Errorf("syntax error: unmatched single quote at: %d", position)
		}
	}

	// return array
	var fields []any
	// what char is the current quote
	var blank rune
	var currentQuote struct {
		char     rune
		position int
	}
	// is the current char escaped or not?
	var escaped bool

	sb := &strings.Builder{}
	for i, r := range unparsed {
		// handle unescaped quotes
		if !escaped && (r == '"' || r == '\'') {
			// next char
			next := byte(' ')
			if i < len(unparsed)-1 {
				next = unparsed[i+1]
			}

			if r == currentQuote.char {
				if next != ' ' {
					return nil, quoteErr(r, i+1)
				}
				// end quote
				currentQuote.char = blank
				continue
			} else if currentQuote.char == blank {
				// start quote
				currentQuote.char = r
				currentQuote.position = i + 1
				continue
			}
		}

		// handle escapes
		if r == '\\' {
			escaped = true
			continue
		}

		// handle word end
		if currentQuote.char == blank && r == ' ' {
			fields = append(fields, sb.String())
			sb.Reset()
			continue
		}

		escaped = false
		sb.WriteRune(r)
	}

	// check if quote is not closed
	if currentQuote.char != blank {
		return nil, quoteErr(currentQuote.char, currentQuote.position)
	}

	// write last word
	if sb.Len() > 0 {
		fields = append(fields, sb.String())
	}

	return fields, nil
}

// redisResponseToQueryResult converts Redis response to QueryResult
func redisResponseToQueryResult(response any) (QueryResult, error) {
	switch resp := response.(type) {
	case string:
		return QueryResult{
			Columns: []string{"value"},
			Rows:    [][]interface{}{{resp}},
		}, nil
	case int64:
		return QueryResult{
			Columns: []string{"value"},
			Rows:    [][]interface{}{{resp}},
		}, nil
	case []interface{}:
		// Handle array responses
		rows := make([][]interface{}, len(resp))
		for i, v := range resp {
			rows[i] = []interface{}{v}
		}
		return QueryResult{
			Columns: []string{"value"},
			Rows:    rows,
		}, nil
	case map[interface{}]interface{}:
		// Handle hash responses
		rows := make([][]interface{}, 0, len(resp))
		for k, v := range resp {
			rows = append(rows, []interface{}{k, v})
		}
		return QueryResult{
			Columns: []string{"key", "value"},
			Rows:    rows,
		}, nil
	default:
		return QueryResult{
			Columns: []string{"value"},
			Rows:    [][]interface{}{{fmt.Sprintf("%v", resp)}},
		}, nil
	}
}
