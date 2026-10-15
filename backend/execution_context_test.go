package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// A bounded probe makes missing context propagation fail promptly instead of
// leaving a slow query (or the test runner) blocked indefinitely.
type executionContextProbe struct {
	started chan context.Context
	closed  bool
}

func (d *executionContextProbe) Connect(Config) error { return nil }
func (d *executionContextProbe) Close() error         { d.closed = true; return nil }
func (d *executionContextProbe) Query(string) (QueryResult, error) {
	return QueryResult{}, errors.New("legacy query path ignored request context")
}
func (d *executionContextProbe) QueryWithPagination(string, *int, *int) (QueryResult, error) {
	return QueryResult{}, errors.New("legacy pagination path ignored request context")
}
func (d *executionContextProbe) Count(string) (int64, error) {
	return 0, errors.New("legacy count path ignored request context")
}

func (d *executionContextProbe) wait(ctx context.Context, query string) error {
	d.started <- ctx
	if query == "SELECT 1" {
		return nil
	}
	timer := time.NewTimer(time.Second)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return errors.New("database context was never cancelled")
	}
}

func (d *executionContextProbe) QueryContext(ctx context.Context, query string) (QueryResult, error) {
	err := d.wait(ctx, query)
	return QueryResult{Columns: []string{"value"}, Rows: [][]interface{}{{1}}}, err
}
func (d *executionContextProbe) QueryWithPaginationContext(ctx context.Context, query string, _, _ *int) (QueryResult, error) {
	return d.QueryContext(ctx, query)
}
func (d *executionContextProbe) CountContext(ctx context.Context, query string) (int64, error) {
	return 1, d.wait(ctx, query)
}

var executionRoutes = []struct {
	name    string
	path    string
	handler http.HandlerFunc
	paged   bool
}{
	{"query", "/query", handleQuery, false},
	{"count", "/count", handleCount, false},
	{"page", "/query", handleQuery, true},
}

func installExecutionProbe(t *testing.T) *executionContextProbe {
	t.Helper()
	probe := &executionContextProbe{started: make(chan context.Context, 1)}
	original := drivers
	drivers = map[string]func() DatabaseDriver{"test-context": func() DatabaseDriver { return probe }}
	t.Cleanup(func() { drivers = original })
	return probe
}

func executionRequest(t *testing.T, path string, paged bool, query string, timeoutMS int) *http.Request {
	t.Helper()
	body := map[string]interface{}{
		"database":   "test-context",
		"query":      query,
		"config":     map[string]interface{}{},
		"timeout_ms": timeoutMS,
	}
	if paged {
		body["limit"], body["offset"] = 20, 0
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	return httptest.NewRequest(http.MethodPost, path, bytes.NewReader(encoded))
}

func waitExecutionDone(t *testing.T, done <-chan struct{}) {
	t.Helper()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("HTTP execution did not finish after cancellation/deadline")
	}
}

func TestHandleExecution_PropagatesCancellation(t *testing.T) {
	for _, route := range executionRoutes {
		t.Run(route.name, func(t *testing.T) {
			probe := installExecutionProbe(t)
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			req := executionRequest(t, route.path, route.paged, "WAIT", 1000).WithContext(ctx)
			recorder := httptest.NewRecorder()
			done := make(chan struct{})
			go func() { defer close(done); route.handler(recorder, req) }()

			var dbContext context.Context
			select {
			case dbContext = <-probe.started:
			case <-done:
				t.Fatalf("execution never received a context: %s", recorder.Body.String())
			case <-time.After(time.Second):
				cancel()
				waitExecutionDone(t, done)
				t.Fatal("execution never started")
			}
			cancel()
			waitExecutionDone(t, done)
			if !errors.Is(dbContext.Err(), context.Canceled) {
				t.Errorf("database did not receive cancellation: %v", dbContext.Err())
			}
			if recorder.Code == http.StatusOK {
				t.Error("cancelled execution was reported as successful")
			}
			if !probe.closed {
				t.Error("cancelled execution did not release its driver")
			}
		})
	}
}

func TestHandleExecution_EnforcesRequestTimeout(t *testing.T) {
	for _, route := range executionRoutes {
		t.Run(route.name, func(t *testing.T) {
			probe := installExecutionProbe(t)
			req := executionRequest(t, route.path, route.paged, "WAIT", 25)
			recorder := httptest.NewRecorder()
			done := make(chan struct{})
			go func() { defer close(done); route.handler(recorder, req) }()
			waitExecutionDone(t, done)

			select {
			case dbContext := <-probe.started:
				if !errors.Is(dbContext.Err(), context.DeadlineExceeded) {
					t.Errorf("timeout_ms did not stop database work: %v", dbContext.Err())
				}
			default:
				t.Fatal("execution never received a context")
			}
			if recorder.Code == http.StatusOK {
				t.Error("timed-out execution was reported as successful")
			}
			if !probe.closed {
				t.Error("timed-out execution did not release its driver")
			}
		})
	}
}

func TestHandleExecution_ContextPathStillReturnsSuccessfulResults(t *testing.T) {
	for _, route := range executionRoutes {
		t.Run(route.name, func(t *testing.T) {
			probe := installExecutionProbe(t)
			recorder := httptest.NewRecorder()
			route.handler(recorder, executionRequest(t, route.path, route.paged, "SELECT 1", 500))
			if recorder.Code != http.StatusOK {
				t.Fatalf("successful context execution failed: %s", recorder.Body.String())
			}
			var result map[string]interface{}
			if err := json.Unmarshal(recorder.Body.Bytes(), &result); err != nil {
				t.Fatal(err)
			}
			if route.name == "count" {
				if result["count"] != float64(1) {
					t.Errorf("unexpected count: %v", result)
				}
			} else if rows, ok := result["rows"].([]interface{}); !ok || len(rows) != 1 {
				t.Errorf("unexpected result: %v", result)
			}
			if !probe.closed {
				t.Error("successful execution did not release its driver")
			}
		})
	}
}

func TestExecutionErrorsRemainStructuredThroughMiddleware(t *testing.T) {
	for _, test := range []struct {
		name string
		deadline bool
		code string
	}{
		{"cancelled", false, "cancelled"},
		{"deadline", true, "timeout"},
	} {
		t.Run(test.name, func(t *testing.T) {
			installExecutionProbe(t)
			var ctx context.Context
			var cancel context.CancelFunc
			if test.deadline {
				ctx, cancel = context.WithDeadline(context.Background(), time.Now().Add(-time.Second))
			} else {
				ctx, cancel = context.WithCancel(context.Background())
				cancel()
			}
			defer cancel()
			req := executionRequest(t, "/query", false, "WAIT", 500).WithContext(ctx)
			recorder := httptest.NewRecorder()
			jsonErrorMiddleware(handleQuery)(recorder, req)
			var result ErrorResponse
			if err := json.Unmarshal(recorder.Body.Bytes(), &result); err != nil {
				t.Fatal(err)
			}
			if result.ErrorCode != test.code {
				t.Fatalf("error was lost/double-wrapped: %s", recorder.Body.String())
			}
			if recorder.Header().Get("Content-Type") != "application/json" {
				t.Fatal("error response is not JSON")
			}
		})
	}
}
