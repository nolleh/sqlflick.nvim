# Automated tests

The `Tests` GitHub Actions workflow installs the test dependencies on clean
Ubuntu runners and runs on pull requests, pushes to `main`, and manual dispatch.
Results appear in the PR's **Checks** tab and the repository's **Actions** tab.
New commits cancel older runs for the same PR.

## Checks

| Check | Environment | Command |
| --- | --- | --- |
| Neovim | Neovim 0.10.4 and current stable, pinned Plenary | `make test` |
| Go | Current stable Go, GCC/CGO, cached module dependencies | `go test -race -count=1 -timeout=120s -v ./...` in `backend/` |
| PostgreSQL | Stable Neovim and Go, Plenary, PostgreSQL 15 service | `make test-e2e` |

These run the repository's native tests, including any new `*_spec.lua` files
under `tests/`; no substitute Neovim API runner is used by CI.

Plenary is checked out at a fixed commit into `.deps/plenary.nvim`, which the
Makefile already recognizes. The Go setup action caches dependencies using
`backend/go.sum`. Go's SQLite driver and race detector use the installed C
toolchain. The PostgreSQL service waits for health checks before tests start.
Its credentials are disposable test values and require no repository secrets.
Other database services from the local Compose file are not started.

## Local equivalents

```sh
make test
cd backend
go mod download
go test -race -count=1 -timeout=120s -v ./...
cd ..
docker compose -f tests/docker/docker-compose.yml up -d --wait postgres
make test-e2e
docker compose -f tests/docker/docker-compose.yml down
```

The E2E suite checks query display, COUNT/page refresh, client cancellation, and
a subsequent query using a real backend and PostgreSQL connection. It does not
assert cancellation in `pg_stat_activity` or exercise MySQL, Redis, or Oracle.

Once this workflow is merged to `main`, it applies to future PR events. Update
existing branches against `main` before rerunning their checks if they have
conflicts or lack the current test commands.
