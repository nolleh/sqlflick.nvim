package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
)

// QueryRequest represents an incoming SQL query request
type QueryRequest struct {
	Database string `json:"database"`
	Query    string `json:"query"`
	Config   Config `json:"config"`
}

// QueryResult represents the result of a SQL query
type QueryResult struct {
	Columns []string        `json:"columns"`
	Rows    [][]interface{} `json:"rows"`
	Error   string          `json:"error,omitempty"`
}

var drivers = map[string]DatabaseDriver{
	"postgresql": &PostgresDriver{},
	"mysql":      &MySQLDriver{},
	"sqlite":     &SQLiteDriver{},
	"redis":      &RedisDriver{},
}

func handleQuery(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Only POST method is allowed", http.StatusMethodNotAllowed)
		return
	}

	var req QueryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Get appropriate driver
	driver, ok := drivers[req.Database]
	if !ok {
		http.Error(w, fmt.Sprintf("Unsupported database type: %s", req.Database), http.StatusBadRequest)
		return
	}

	// Connect to database
	if err := driver.Connect(req.Config); err != nil {
		http.Error(w, fmt.Sprintf("Failed to connect: %v", err), http.StatusInternalServerError)
		return
	}
	defer driver.Close()

	// Execute query
	result, err := driver.Query(req.Query)
	if err != nil {
		http.Error(w, fmt.Sprintf("Query failed: %v", err), http.StatusInternalServerError)
		return
	}

	// Send response
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

func main() {
	http.HandleFunc("/query", handleQuery)

	port := 8080
	fmt.Printf("Starting SQLSnap backend server on port %d...\n", port)
	if err := http.ListenAndServe(fmt.Sprintf(":%d", port), nil); err != nil {
		log.Fatal(err)
	}
}
