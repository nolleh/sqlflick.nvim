package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
)

// QueryRequest represents an incoming SQL query request
type QueryRequest struct {
	Database string `json:"database"`
	Query    string `json:"query"`
	Config   Config `json:"config"`
}

// UnmarshalJSON implements custom JSON unmarshaling for QueryRequest
// func (q *QueryRequest) UnmarshalJSON(data []byte) error {
// 	type Alias QueryRequest
// 	aux := &struct {
// 		*Alias
// 		Query string `json:"query"`
// 	}{
// 		Alias: (*Alias)(q),
// 	}
// 	if err := json.Unmarshal(data, &aux); err != nil {
// 		return err
// 	}
// 	// Preserve the original query string with quotes
// 	q.Query = aux.Query
// 	return nil
// }

// QueryResult represents the result of a SQL query
type QueryResult struct {
	Columns []string        `json:"columns,omitempty"`
	Rows    [][]interface{} `json:"rows,omitempty"`
	Error   string          `json:"error,omitempty"`
}

// ErrorResponse represents a JSON error response
type ErrorResponse struct {
	Error string `json:"error"`
}

var drivers = map[string]DatabaseDriver{
	"postgresql": &PostgresDriver{},
	"mysql":      &MySQLDriver{},
	"sqlite":     &SQLiteDriver{},
	"redis":      &RedisDriver{},
}

// jsonErrorMiddleware wraps HTTP errors in JSON format
func jsonErrorMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Create a custom ResponseWriter that captures the status code
		rw := &responseWriter{ResponseWriter: w}
		next(rw, r)
	}
}

// responseWriter is a custom ResponseWriter that captures the status code
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	if rw.statusCode >= 400 {
		// If it's an error response, wrap it in JSON
		w := rw.ResponseWriter
		w.Header().Set("Content-Type", "application/json")
		response := ErrorResponse{Error: string(b)}
		jsonData, err := json.Marshal(response)
		if err != nil {
			return 0, err
		}
		return w.Write(jsonData)
	}
	return rw.ResponseWriter.Write(b)
}

func handleQuery(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Only POST method is allowed", http.StatusMethodNotAllowed)
		return
	}

	// Read the raw request body first
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Failed to read request body", http.StatusBadRequest)
		return
	}
	// Restore the body for later use
	r.Body = io.NopCloser(bytes.NewBuffer(body))

	// Debug log the raw request body
	fmt.Printf("Raw request body: %s\n", string(body))

	var req QueryRequest
	if err := json.NewDecoder(bytes.NewBuffer(body)).Decode(&req); err != nil {
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
	if err := json.NewEncoder(w).Encode(result); err != nil {
		http.Error(w, fmt.Sprintf("Failed to encode response: %v", err), http.StatusInternalServerError)
		return
	}
}

func main() {
	http.HandleFunc("/query", jsonErrorMiddleware(handleQuery))

	port := 9091
	// Check for command line arguments
	if len(os.Args) > 1 {
		for i := 0; i < len(os.Args)-1; i++ {
			if os.Args[i] == "-port" {
				if p, err := strconv.Atoi(os.Args[i+1]); err == nil {
					port = p
				}
			}
		}
	}

	fmt.Printf("Starting SQLSnap backend server on port %d...\n", port)
	if err := http.ListenAndServe(fmt.Sprintf(":%d", port), nil); err != nil {
		log.Fatal(err)
	}
}
