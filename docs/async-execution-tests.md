# Async execution: tests first

This branch adds failing specifications, not the feature implementation. It starts
from main at `ba8384fbae1be3b835d150ee6d74f6ee18c95f8e` (v0.6.5).

## Expected behavior

- Query execution returns control to Neovim while the request is pending.
- Regular queries, COUNT, and page requests all use asynchronous transport.
- The existing handler methods accept a final callback and return a request with
  `cancel()`. Calls without a callback retain their existing behavior.
- Request bodies use JSON through stdin and an argument array, preserving quotes.
- `backend.timeout_ms` bounds each HTTP request, is sent as `timeout_ms`, and is
  enforced in the backend database context as well as the transport.
- Callbacks run on the main loop exactly once, including cancellation, timeout,
  process startup failure, connection failure, and malformed responses.
- Callback results retain the existing result shape. Client-side errors include
  an `error` message and an `error_code` of `cancelled`, `timeout`,
  `transport`, or `invalid_response`.
- `:SQLFlickCancel` cancels the active stage, including an in-flight COUNT.
  Cancelling while idle is harmless.
- Cancellation and timeout never trigger fallback execution of the original SQL.
- A new execution supersedes the previous execution. Late responses cannot render
  stale results or start another stage.
- An execution and its page refreshes retain their original database even if the
  user selects another database.
- Closing Neovim cancels pending execution.
- Cancelling one request does not cancel another request.

The callback contract is exercised through public commands and handler methods;
the tests do not prescribe a new controller module or internal state layout.

## Test groups

| File | Cases | Focus |
| --- | ---: | --- |
| `tests/handler_async_spec.lua` | 23 | Nonblocking transport, cancellation, timeout, errors, quote preservation |
| `tests/execution_async_spec.lua` | 12 | Command, COUNT, page, stale response, DB selection, and exit behavior |
| `backend/execution_context_test.go` | 9 | Context propagation, cancellation, deadline, cleanup, successful responses |

The Lua transport tests hold process completion callbacks until explicitly fired.
The command tests hold HTTP results pending. Neither suite needs a database,
real curl process, or timing sleeps. The Go tests use a context-aware bounded
probe and channels, with watchdogs to prevent hanging the runner.

## Run

With Neovim and Plenary available:

```sh
make test
```

With the Go toolchain and module dependencies available:

```sh
cd backend
go test -race -run TestHandleExecution_ -count=1 -timeout=30s ./...
```

These new tests are expected to fail on this branch until production code is
implemented. They must not be disabled or changed to pending tests to make CI
green.

## Validation in the authoring environment

- Existing quote-preservation tests: 18 passed under Lua 5.4 with Neovim API
  substitutes, including shell handling.
- New Lua tests: 35 failed against the current production implementation, because
  transport is synchronous and command execution does not supply callbacks.
- Native `make test`: blocked while fetching Plenary by the unavailable network
  proxy; Neovim is also absent.
- Go tests: not executed because a Go compiler is not installed. The executable
  named `go` in this image is not the Go language toolchain.

The Lua substitute run verifies the expected initial failures, not native
Neovim scheduling or end-to-end database cancellation.

## Before shipping the implementation

Run the native suites and confirm real database cancellation, timeout, and
connection reuse. The current backend shares mutable driver instances by DB
type; request isolation must be addressed before enabling overlapping requests.
Cancellation requests a stop; it does not promise rollback of committed writes.
