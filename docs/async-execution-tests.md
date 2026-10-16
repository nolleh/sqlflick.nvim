# Asynchronous execution and validation

Query commands execute through asynchronous curl jobs, with cancellation and
per-request timeouts propagated into database operations. Programmatic calls
without a callback and schema omni-completion retain their synchronous APIs.

## Behavior and usage

- Requires Neovim 0.10+ and curl. Updating the backend requires Go.
- Use `:SQLFlickCancel` to cancel the active COUNT, query, or page request.
- `backend.timeout_ms` defaults to 30000 ms; accepted values are integer
  milliseconds from 1 to 3600000. Each COUNT/page HTTP request has its own budget.
- A new execution supersedes the old one. Late callbacks are ignored and cannot
  start another stage or overwrite newer results.
- Timeout/transport failure never triggers fallback execution of the SQL.
  Ordinary SQL errors from COUNT may still fall back to the original SELECT.
- Results preserve the user's current window focus. Pagination stays attached to
  the database that produced the result, even after database selection changes.
- Startup uses bounded, asynchronous `/health` probes. SQL is never retried on
  ambiguous transport failure. Health protocol 1 is required.
- Rebuild with `:SQLFlickInstall`, wait for completion, and then run
  `:SQLFlickRestart`. Backend/install version is prepared as `0.7.0`.

The handler methods accept a final callback and return a request with `cancel()`.
Callbacks run on the main loop once. Results retain their existing shape; error
results include an `error` message and an `error_code`: `cancelled`, `timeout`,
`transport`, `invalid_response`, or the backend's `query` error.

## Connection lifecycle

Driver wrappers contain per-request state. Their `Connect` methods lease shared
`sql.DB` / Redis pools keyed by complete connection identity, including credentials.
`Close` returns the lease instead of shutting down the pool. Cache keys hash the
connection identity rather than retaining passwords as map keys.

The cache has at most 16 pools. Each SQL/Redis pool has at most 5 active connections
and 2 idle connections; SQLite allows one connection. A 5-minute idle period or
capacity pressure evicts unused pools on the next acquisition. Active pools are
never evicted; if all slots are active, another connection configuration receives
an error instead of allocating more pools. Private SQLite `:memory:` databases
remain request-local so state cannot leak between requests.

## Tests

| File                                | Cases | Focus                                                                                             |
| ----------------------------------- | ----: | ------------------------------------------------------------------------------------------------- |
| `tests/handler_async_spec.lua`      |    29 | Async transport, startup, cancellation, timeout, fast event callbacks, errors, quote preservation |
| `tests/execution_async_spec.lua`    |    14 | Command/COUNT/page sequencing, stale callbacks, DB selection, focus, shutdown                     |
| `backend/execution_context_test.go` |    11 | Request context, deadlines, cancellation, cleanup, success                                        |
| `backend/pools_test.go`             |     7 | Pool reuse, caps, concurrency, expiry, identity, SQLite cancellation/reuse                        |
| `e2e/postgres_spec.lua`             |     3 | Real backend/PostgreSQL query display, COUNT and page refresh, cancel and rerun                   |

The 43 async Lua tests now run through Plenary in headless Neovim. The command
tests exercise real Neovim user commands, buffers, windows, and autocmds while
holding transport completions pending. The handler tests use Neovim's event
loop for scheduled callbacks and stub only process execution and delayed
readiness retries. All 43 async tests and the existing 18 quote-preservation
tests passed with Neovim 0.12.5. The backend suite also passed with Go's race
detector (68 tests). These tests do not establish live database cancellation
behavior or compatibility with every supported Neovim version.

Run the PostgreSQL end-to-end suite against the healthy `postgres` service from
`tests/docker/docker-compose.yml` with `make test-e2e`. It builds a temporary
backend in `.deps/`, starts it on a local port, and runs headless Neovim with
the real curl transport and result UI. The suite uses read-only SQL and stops
the backend afterward. Override the connection with `SQLFLICK_E2E_PG_HOST`,
`SQLFLICK_E2E_PG_PORT`, `SQLFLICK_E2E_PG_DATABASE`, `SQLFLICK_E2E_PG_USER`, and
`SQLFLICK_E2E_PG_PASSWORD` if needed. The default connection matches the Docker
Compose PostgreSQL service. The 3 end-to-end cases passed against that service.

## Before merging

With the native tools and dependencies installed:

```sh
make test
make test-e2e
cd backend
go test -race -count=1 -timeout=60s ./...
```

For a PostgreSQL check, configure `backend.timeout_ms = 1000`, execute
`WITH wait AS MATERIALIZED (SELECT pg_sleep(30)) SELECT * FROM wait;`, and confirm
that editing remains responsive and timeout is reported. Increase the timeout,
repeat the query, and cancel it with `:SQLFlickCancel`; inspect `pg_stat_activity`
to confirm database work ends. Then execute `SELECT 1` to check continued use.
Also check rapid query/page changes and database switching while COUNT is pending.

Cancellation asks the driver to stop work and does not roll back committed writes.
Live cancellation behavior remains to be checked for PostgreSQL, MySQL, SQLite,
Redis, and Oracle; it depends on each database driver's cancellation support.
