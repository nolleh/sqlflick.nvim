package main

import (
	"database/sql"
	"fmt"
	_ "github.com/lib/pq" // PostgreSQL driver
)

func executeQuery(req QueryRequest) QueryResult {
	// Build connection string
	connStr := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
		req.Config.Host,
		req.Config.Port,
		req.Config.User,
		req.Config.Password,
		req.Config.DBName,
	)

	// Connect to database
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return QueryResult{Error: fmt.Sprintf("Failed to connect: %v", err)}
	}
	defer db.Close()

	// Execute query
	rows, err := db.Query(req.Query)
	if err != nil {
		return QueryResult{Error: fmt.Sprintf("Query failed: %v", err)}
	}
	defer rows.Close()

	// Get column names
	columns, err := rows.Columns()
	if err != nil {
		return QueryResult{Error: fmt.Sprintf("Failed to get columns: %v", err)}
	}

	// Prepare result
	result := QueryResult{
		Columns: columns,
		Rows:    make([][]interface{}, 0),
	}

	// Read rows
	for rows.Next() {
		// Create slice of interface{} to hold column values
		values := make([]interface{}, len(columns))
		valuePtrs := make([]interface{}, len(columns))
		for i := range values {
			valuePtrs[i] = &values[i]
		}

		// Scan row into values
		if err := rows.Scan(valuePtrs...); err != nil {
			return QueryResult{Error: fmt.Sprintf("Failed to scan row: %v", err)}
		}

		// Add row to results
		result.Rows = append(result.Rows, values)
	}

	if err := rows.Err(); err != nil {
		return QueryResult{Error: fmt.Sprintf("Error reading rows: %v", err)}
	}

	return result
}
