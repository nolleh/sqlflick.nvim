# Async execution test guide

## Test suites

| File                                | Cases | Coverage                                                                    |
| ----------------------------------- | ----: | --------------------------------------------------------------------------- |
| `tests/handler_async_spec.lua`      |    29 | Async transport, readiness, cancellation, timeouts, errors, event callbacks |
| `tests/execution_async_spec.lua`    |    14 | Command flow, COUNT/page sequencing, stale results, focus, shutdown         |
| `backend/execution_context_test.go` |    11 | Request contexts, deadlines, cancellation, cleanup, success                 |
| `backend/pools_test.go`             |     7 | Pool reuse, limits, concurrency, expiry, identity, SQLite cancellation      |
| `e2e/postgres_spec.lua`             |     3 | Real query results, COUNT/page refresh, cancellation, subsequent query      |

## Run tests

Run the Neovim/Plenary suite:

```sh
make test
```

Run the backend suite with the race detector:

```sh
cd backend
go test -race -count=1 -timeout=60s ./...
```

Run the PostgreSQL end-to-end suite against the `postgres` service in
`tests/docker/docker-compose.yml`:

```sh
make test-e2e
```

This builds the backend in `.deps/`, starts it on an available local port, and
runs headless Neovim through the real curl transport and result UI. It uses
read-only SQL and stops the backend afterward. The defaults match the Docker
Compose PostgreSQL service. Set `SQLFLICK_E2E_PG_HOST`, `SQLFLICK_E2E_PG_PORT`,
`SQLFLICK_E2E_PG_DATABASE`, `SQLFLICK_E2E_PG_USER`, and
`SQLFLICK_E2E_PG_PASSWORD` to use another PostgreSQL instance.

## Current verification

The async Lua suites and existing plugin tests passed with Neovim 0.12.5. The
backend suite passed with the race detector (68 tests), and all three
PostgreSQL E2E cases passed against the Docker Compose service.

The E2E cancellation case verifies that the client can cancel a query and run
another query afterward. To confirm that PostgreSQL has stopped the cancelled
statement, repeat with a longer `pg_sleep` query and inspect
`pg_stat_activity`. Cancellation behavior also depends on each database
driver; MySQL, SQLite, Redis, and Oracle are not covered by this E2E suite.
