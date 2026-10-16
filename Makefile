PLENARY_DIR := .deps/plenary.nvim
PLENARY_REPO := https://github.com/nvim-lua/plenary.nvim.git

.PHONY: test test-e2e test-deps dev dev-user db-up db-down

test: test-deps
	nvim --headless -u NONE \
		--cmd "set rtp^=$(CURDIR)" \
		--cmd "set rtp+=$(abspath $(PLENARY_DIR))" \
		-c "runtime plugin/plenary.vim" \
		-c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }"

test-deps:
	@if [ ! -d "$(PLENARY_DIR)/.git" ]; then \
		mkdir -p "$(dir $(PLENARY_DIR))"; \
		git clone --depth 1 "$(PLENARY_REPO)" "$(PLENARY_DIR)"; \
	fi

# Runs real Neovim -> backend -> PostgreSQL checks against a running test DB.
test-e2e: test-deps
	@mkdir -p .deps/go-cache
	cd backend && GOCACHE=$(CURDIR)/.deps/go-cache go build -o $(CURDIR)/.deps/sqlflick-backend-e2e .
	SQLFLICK_E2E_BACKEND_BIN=$(CURDIR)/.deps/sqlflick-backend-e2e nvim --headless -u NONE \
		--cmd "set rtp^=$(CURDIR)" \
		--cmd "set rtp+=$(abspath $(PLENARY_DIR))" \
		-c "runtime plugin/plenary.vim" \
		-c "PlenaryBustedDirectory e2e { minimal_init = 'tests/minimal_init.lua' }"

# Launch Neovim with the local SQLFlick development configuration.
dev:
	nvim -u tests/test.lua tests/fixtures/mysql.sql

# Overlay the local plugin on the user's existing Neovim configuration.
dev-user:
	nvim --cmd "luafile $(CURDIR)/dev-load.lua" tests/fixtures/mysql.sql

db-up:
	docker compose -f tests/docker/docker-compose.yml up -d

db-down:
	docker compose -f tests/docker/docker-compose.yml down
