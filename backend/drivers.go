package main

import (
	"context"
	"database/sql"
	"encoding/json"
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
	Count(query string) (int64, error)
	Close() error
}

// ContextDatabaseDriver propagates HTTP cancellation/deadlines into DB calls.
type ContextDatabaseDriver interface {
	QueryContext(context.Context, string) (QueryResult, error)
	QueryWithPaginationContext(context.Context, string, *int, *int) (QueryResult, error)
	CountContext(context.Context, string) (int64, error)
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
	db      *sql.DB
	release func() error
}

func (d *PostgresDriver) Connect(config Config) error {
	connStr := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
		config.Host, config.Port, config.User, config.Password, config.DBName)
	db, release, err := acquireSQLPool("postgres", connStr)
	if err != nil {
		return err
	}
	d.db, d.release = db, release
	return nil
}

func (d *PostgresDriver) Query(query string) (QueryResult, error) {
	return d.QueryContext(context.Background(), query)
}

func (d *PostgresDriver) QueryContext(ctx context.Context, query string) (QueryResult, error) {
	return executeSQLQueryContext(ctx, d.db, query)
}

func (d *PostgresDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	return d.QueryWithPaginationContext(context.Background(), query, limit, offset)
}

func (d *PostgresDriver) QueryWithPaginationContext(ctx context.Context, query string, limit *int, offset *int) (QueryResult, error) {
	return executeSQLQueryWithPaginationContext(ctx, d.db, query, limit, offset, "postgresql")
}

func (d *PostgresDriver) Count(query string) (int64, error) {
	return d.CountContext(context.Background(), query)
}

func (d *PostgresDriver) CountContext(ctx context.Context, query string) (int64, error) {
	return executeSQLCountContext(ctx, d.db, query)
}

func (d *PostgresDriver) Close() error {
	if d.release != nil {
		release := d.release
		d.release = nil
		return release()
	}
	return nil
}

// MySQLDriver implements DatabaseDriver for MySQL
type MySQLDriver struct {
	db      *sql.DB
	release func() error
}

func (d *MySQLDriver) Connect(config Config) error {
	connStr := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s",
		config.User, config.Password, config.Host, config.Port, config.DBName)
	db, release, err := acquireSQLPool("mysql", connStr)
	if err != nil {
		return err
	}
	d.db, d.release = db, release
	return nil
}

func (d *MySQLDriver) Query(query string) (QueryResult, error) {
	return d.QueryContext(context.Background(), query)
}

func (d *MySQLDriver) QueryContext(ctx context.Context, query string) (QueryResult, error) {
	return executeSQLQueryContext(ctx, d.db, query)
}

func (d *MySQLDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	return d.QueryWithPaginationContext(context.Background(), query, limit, offset)
}

func (d *MySQLDriver) QueryWithPaginationContext(ctx context.Context, query string, limit *int, offset *int) (QueryResult, error) {
	return executeSQLQueryWithPaginationContext(ctx, d.db, query, limit, offset, "mysql")
}

func (d *MySQLDriver) Count(query string) (int64, error) {
	return d.CountContext(context.Background(), query)
}

func (d *MySQLDriver) CountContext(ctx context.Context, query string) (int64, error) {
	return executeSQLCountContext(ctx, d.db, query)
}

func (d *MySQLDriver) Close() error {
	if d.release != nil {
		release := d.release
		d.release = nil
		return release()
	}
	return nil
}

// SQLiteDriver implements DatabaseDriver for SQLite
type SQLiteDriver struct {
	db      *sql.DB
	release func() error
}

func (d *SQLiteDriver) Connect(config Config) error {
	db, release, err := acquireSQLPool("sqlite3", config.DBName)
	if err != nil {
		return err
	}
	d.db, d.release = db, release
	return nil
}

func (d *SQLiteDriver) Query(query string) (QueryResult, error) {
	return d.QueryContext(context.Background(), query)
}

func (d *SQLiteDriver) QueryContext(ctx context.Context, query string) (QueryResult, error) {
	return executeSQLQueryContext(ctx, d.db, query)
}

func (d *SQLiteDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	return d.QueryWithPaginationContext(context.Background(), query, limit, offset)
}

func (d *SQLiteDriver) QueryWithPaginationContext(ctx context.Context, query string, limit *int, offset *int) (QueryResult, error) {
	return executeSQLQueryWithPaginationContext(ctx, d.db, query, limit, offset, "sqlite")
}

func (d *SQLiteDriver) Count(query string) (int64, error) {
	return d.CountContext(context.Background(), query)
}

func (d *SQLiteDriver) CountContext(ctx context.Context, query string) (int64, error) {
	return executeSQLCountContext(ctx, d.db, query)
}

func (d *SQLiteDriver) Close() error {
	if d.release != nil {
		release := d.release
		d.release = nil
		return release()
	}
	return nil
}

// RedisDriver implements DatabaseDriver for Redis
type RedisDriver struct {
	client  *redis.Client
	release func() error
}

func (d *RedisDriver) Connect(config Config) error {
	identity, _ := json.Marshal(config)
	value, release, err := connectionPools.acquire(poolKey("redis", string(identity)), func() (interface{}, func() error, error) {
		client := redis.NewClient(&redis.Options{
			Addr: fmt.Sprintf("%s:%d", config.Host, config.Port),
			Password: config.Password,
			DB: 0,
			PoolSize: maxPoolConnections,
			MaxActiveConns: maxPoolConnections,
			MaxIdleConns: 2,
			ConnMaxIdleTime: poolIdleTimeout,
			ContextTimeoutEnabled: true,
			MaxRetries: -1,
		})
		return client, client.Close, nil
	})
	if err != nil {
		return err
	}
	d.client, d.release = value.(*redis.Client), release
	return nil
}

func (d *RedisDriver) Query(query string) (QueryResult, error) {
	return d.QueryContext(context.Background(), query)
}

func (d *RedisDriver) QueryContext(ctx context.Context, query string) (QueryResult, error) {
	// Parse Redis command
	cmd, err := parseRedisCmd(query)
	if err != nil {
		return QueryResult{}, err
	}

	// Execute command
	response, err := d.client.Do(ctx, cmd...).Result()
	if err != nil {
		return QueryResult{}, err
	}

	// Convert response to QueryResult
	return redisResponseToQueryResult(response)
}

func (d *RedisDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	return d.Query(query)
}

func (d *RedisDriver) QueryWithPaginationContext(ctx context.Context, query string, limit *int, offset *int) (QueryResult, error) {
	return d.QueryContext(ctx, query)
}

func (d *RedisDriver) CountContext(ctx context.Context, query string) (int64, error) {
	return d.Count(query)
}

func (d *RedisDriver) Count(query string) (int64, error) {
	return 0, fmt.Errorf("count is not supported for Redis")
}

func (d *RedisDriver) Close() error {
	if d.release != nil {
		release := d.release
		d.release = nil
		return release()
	}
	return nil
}

// OracleDriver implements DatabaseDriver for Oracle
type OracleDriver struct {
	db      *sql.DB
	release func() error
}

func (d *OracleDriver) Connect(config Config) error {
	connStr := fmt.Sprintf("oracle://%s:%s@%s:%d/%s", config.User,
		config.Password, config.Host, config.Port, config.DBName)
	db, release, err := acquireSQLPool("oracle", connStr)
	if err != nil {
		return fmt.Errorf("failed to configure Oracle connection: %w", err)
	}
	d.db, d.release = db, release
	return nil
}

func (d *OracleDriver) Query(query string) (QueryResult, error) {
	return d.QueryContext(context.Background(), query)
}

func (d *OracleDriver) QueryContext(ctx context.Context, query string) (QueryResult, error) {
	query = strings.TrimSuffix(strings.TrimSpace(query), ";")
	return executeSQLQueryContext(ctx, d.db, query)
}

func (d *OracleDriver) QueryWithPagination(query string, limit *int, offset *int) (QueryResult, error) {
	return d.QueryWithPaginationContext(context.Background(), query, limit, offset)
}

func (d *OracleDriver) QueryWithPaginationContext(ctx context.Context, query string, limit *int, offset *int) (QueryResult, error) {
	query = strings.TrimSuffix(strings.TrimSpace(query), ";")
	return executeSQLQueryWithPaginationContext(ctx, d.db, query, limit, offset, "oracle")
}

func (d *OracleDriver) Count(query string) (int64, error) {
	return d.CountContext(context.Background(), query)
}

func (d *OracleDriver) CountContext(ctx context.Context, query string) (int64, error) {
	query = strings.TrimSuffix(strings.TrimSpace(query), ";")
	return executeSQLCountContext(ctx, d.db, query)
}

func (d *OracleDriver) Close() error {
	if d.release != nil {
		release := d.release
		d.release = nil
		return release()
	}
	return nil
}

// Helper function to execute SQL queries
func executeSQLQuery(db *sql.DB, query string) (QueryResult, error) {
	return executeSQLQueryContext(context.Background(), db, query)
}

func executeSQLQueryContext(ctx context.Context, db *sql.DB, query string) (QueryResult, error) {
	rows, err := db.QueryContext(ctx, query)
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

func executeSQLCount(db *sql.DB, query string) (int64, error) {
	return executeSQLCountContext(context.Background(), db, query)
}

func executeSQLCountContext(ctx context.Context, db *sql.DB, query string) (int64, error) {
	query = strings.TrimSpace(query)
	query = strings.TrimSuffix(query, ";")
	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM (%s) t", query)

	var count int64
	if err := db.QueryRowContext(ctx, countQuery).Scan(&count); err != nil {
		return 0, err
	}
	return count, nil
}

// Helper function to execute SQL queries with pagination
func executeSQLQueryWithPagination(db *sql.DB, query string, limit *int, offset *int, dbType string) (QueryResult, error) {
	return executeSQLQueryWithPaginationContext(context.Background(), db, query, limit, offset, dbType)
}

func executeSQLQueryWithPaginationContext(ctx context.Context, db *sql.DB, query string, limit *int, offset *int, dbType string) (QueryResult, error) {
	// Build paginated query based on database type
	// This is a basic implementation - in production, you might want to parse SQL properly

	// Trim whitespace and remove trailing semicolon
	query = strings.TrimSpace(query)
	query = strings.TrimSuffix(query, ";")
	query = strings.TrimSpace(query)

	// Check if query already has LIMIT/OFFSET
	queryLower := strings.ToLower(query)
	hasLimit := strings.Contains(queryLower, "limit")
	hasOffset := strings.Contains(queryLower, "offset")
	hasFetch := strings.Contains(queryLower, "fetch")

	var paginatedQuery string
	if hasLimit || hasOffset || hasFetch {
		// If query already has pagination, don't modify it
		paginatedQuery = query
	} else {
		// Add pagination based on database type
		paginatedQuery = query

		switch dbType {
		case "mysql":
			// MySQL requires LIMIT to use OFFSET
			if limit != nil && *limit > 0 {
				paginatedQuery = fmt.Sprintf("%s LIMIT %d", paginatedQuery, *limit)
				if offset != nil && *offset > 0 {
					paginatedQuery = fmt.Sprintf("%s OFFSET %d", paginatedQuery, *offset)
				}
			} else if offset != nil && *offset > 0 {
				// For MySQL, if only offset is provided, we need to add a LIMIT
				paginatedQuery = fmt.Sprintf("%s LIMIT 1000 OFFSET %d", paginatedQuery, *offset)
			}

		case "postgresql", "sqlite":
			// PostgreSQL and SQLite support OFFSET without LIMIT
			if limit != nil && *limit > 0 {
				paginatedQuery = fmt.Sprintf("%s LIMIT %d", paginatedQuery, *limit)
			}
			if offset != nil && *offset > 0 {
				paginatedQuery = fmt.Sprintf("%s OFFSET %d", paginatedQuery, *offset)
			}

		case "oracle":
			// Oracle 12c+ uses FETCH FIRST/OFFSET syntax
			// Note: This works for Oracle 12c and above
			if offset != nil && *offset > 0 {
				paginatedQuery = fmt.Sprintf("%s OFFSET %d ROWS", paginatedQuery, *offset)
			}
			if limit != nil && *limit > 0 {
				paginatedQuery = fmt.Sprintf("%s FETCH NEXT %d ROWS ONLY", paginatedQuery, *limit)
			}
		}
	}

	return executeSQLQueryContext(ctx, db, paginatedQuery)
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
