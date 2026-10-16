package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"
)

const VERSION = "0.7.0"

// QueryRequest represents an incoming SQL query request
type QueryRequest struct {
	TimeoutMS int `json:"timeout_ms,omitempty"`
	Database  string `json:"database"`
	Query     string `json:"query"`
	Config    Config `json:"config"`
	Limit     *int   `json:"limit,omitempty"`  // Optional limit for pagination
	Offset    *int   `json:"offset,omitempty"` // Optional offset for pagination
}

// QueryResult represents the result of a SQL query
type QueryResult struct {
	Columns []string        `json:"columns,omitempty"`
	Rows    [][]interface{} `json:"rows,omitempty"`
	Error   string          `json:"error,omitempty"`
}

// CountResult represents the result of a count query
type CountResult struct {
	Count int64  `json:"count"`
	Error string `json:"error,omitempty"`
}

// SchemaRequest represents a request for relational database metadata.
type SchemaRequest struct {
	Database string `json:"database"`
	Config   Config `json:"config"`
}

// ErrorResponse represents a JSON error response
type ErrorResponse struct {
	ErrorCode string `json:"error_code,omitempty"`
	Error     string `json:"error"`
}

// Each request owns a driver wrapper; wrappers lease shared, bounded connection pools.
var drivers = map[string]func() DatabaseDriver{
	"postgresql": func() DatabaseDriver { return &PostgresDriver{} },
	"mysql": func() DatabaseDriver { return &MySQLDriver{} },
	"sqlite": func() DatabaseDriver { return &SQLiteDriver{} },
	"redis": func() DatabaseDriver { return &RedisDriver{} },
	"oracle": func() DatabaseDriver { return &OracleDriver{} },
}

const defaultTimeoutMS = 30000
const maxTimeoutMS = 3600000

func executionContext(r *http.Request, timeoutMS int) (context.Context, context.CancelFunc, error) {
	if timeoutMS < 0 || timeoutMS > maxTimeoutMS {
		return nil, nil, fmt.Errorf("timeout_ms must be between 1 and %d (or omitted)", maxTimeoutMS)
	}
	if timeoutMS == 0 {
		timeoutMS = defaultTimeoutMS
	}
	ctx, cancel := context.WithTimeout(r.Context(), time.Duration(timeoutMS) * time.Millisecond)
	return ctx, cancel, nil
}

func writeExecutionError(w http.ResponseWriter, ctx context.Context, err error) {
	code, status := "query", http.StatusInternalServerError
	if ctx.Err() != nil {
		err = ctx.Err()
	}
	if errors.Is(err, context.DeadlineExceeded) {
		code, status = "timeout", http.StatusGatewayTimeout
	} else if errors.Is(err, context.Canceled) {
		code, status = "cancelled", http.StatusRequestTimeout
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(ErrorResponse{Error: err.Error(), ErrorCode: code})
}

func writeConnectionError(w http.ResponseWriter, ctx context.Context, err error) {
	if ctx.Err() != nil {
		writeExecutionError(w, ctx, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusBadGateway)
	_ = json.NewEncoder(w).Encode(ErrorResponse{Error: fmt.Sprintf("Failed to connect: %v", err), ErrorCode: "transport"})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Only GET method is allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"version": VERSION, "protocol": 1})
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
	wrapError  bool
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.wrapError = code >= 400 && rw.Header().Get("Content-Type") != "application/json"
	if rw.wrapError {
		rw.Header().Set("Content-Type", "application/json")
	}
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	if rw.wrapError {
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

	var req QueryRequest
	if err := json.NewDecoder(bytes.NewBuffer(body)).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Get appropriate driver
	factory, ok := drivers[req.Database]
	if !ok {
		http.Error(w, fmt.Sprintf("Unsupported database type: %s", req.Database), http.StatusBadRequest)
		return
	}

	ctx, cancel, err := executionContext(r, req.TimeoutMS)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	defer cancel()
	driver := factory()
	executor, ok := driver.(ContextDatabaseDriver)
	if !ok {
		http.Error(w, "Driver does not support cancellation", http.StatusBadRequest)
		return
	}
	// Connect to database
	if err := driver.Connect(req.Config); err != nil {
		writeConnectionError(w, ctx, err)
		return
	}
	defer driver.Close()

	// Execute query with pagination if provided
	var result QueryResult
	if req.Limit != nil || req.Offset != nil {
		result, err = executor.QueryWithPaginationContext(ctx, req.Query, req.Limit, req.Offset)
	} else {
		result, err = executor.QueryContext(ctx, req.Query)
	}
	if err != nil {
		writeExecutionError(w, ctx, err)
		return
	}

	// Send response
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(result); err != nil {
		http.Error(w, fmt.Sprintf("Failed to encode response: %v", err), http.StatusInternalServerError)
		return
	}
}

func handleCount(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Only POST method is allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Failed to read request body", http.StatusBadRequest)
		return
	}

	var req QueryRequest
	if err := json.NewDecoder(bytes.NewBuffer(body)).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	factory, ok := drivers[req.Database]
	if !ok {
		http.Error(w, fmt.Sprintf("Unsupported database type: %s", req.Database), http.StatusBadRequest)
		return
	}

	ctx, cancel, err := executionContext(r, req.TimeoutMS)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	defer cancel()
	driver := factory()
	executor, ok := driver.(ContextDatabaseDriver)
	if !ok {
		http.Error(w, "Driver does not support cancellation", http.StatusBadRequest)
		return
	}
	if err := driver.Connect(req.Config); err != nil {
		writeConnectionError(w, ctx, err)
		return
	}
	defer driver.Close()

	count, err := executor.CountContext(ctx, req.Query)
	if err != nil {
		writeExecutionError(w, ctx, err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(CountResult{Count: count}); err != nil {
		http.Error(w, fmt.Sprintf("Failed to encode response: %v", err), http.StatusInternalServerError)
		return
	}
}

func handleSchema(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Only POST method is allowed", http.StatusMethodNotAllowed)
		return
	}

	var req SchemaRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	factory, ok := drivers[req.Database]
	if !ok {
		http.Error(w, fmt.Sprintf("Unsupported database type: %s", req.Database), http.StatusBadRequest)
		return
	}

	driver := factory()
	provider, ok := driver.(SchemaProvider)
	if !ok {
		http.Error(w, fmt.Sprintf("Schema completion is not supported for database type: %s", req.Database), http.StatusBadRequest)
		return
	}

	if err := driver.Connect(req.Config); err != nil {
		http.Error(w, fmt.Sprintf("Failed to connect: %v", err), http.StatusInternalServerError)
		return
	}
	defer driver.Close()

	schema, err := provider.Schema()
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to load schema: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(schema); err != nil {
		http.Error(w, fmt.Sprintf("Failed to encode response: %v", err), http.StatusInternalServerError)
	}
}

func main() {
	port := 9091
	for i := 0; i < len(os.Args); i++ {
		if os.Args[i] == "-version" {
			fmt.Println(VERSION)
			return
		}
		if os.Args[i] == "-port" {
			if p, err := strconv.Atoi(os.Args[i+1]); err == nil {
				port = p
			}
		}
	}

	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/query", jsonErrorMiddleware(handleQuery))
	http.HandleFunc("/count", jsonErrorMiddleware(handleCount))
	http.HandleFunc("/schema", jsonErrorMiddleware(handleSchema))

	fmt.Printf("Starting SQLFlick backend server on port %d...\n", port)
	if err := http.ListenAndServe(fmt.Sprintf("127.0.0.1:%d", port), nil); err != nil {
		log.Fatal(err)
	}
}
