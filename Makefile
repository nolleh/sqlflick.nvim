PLENARY_DIR := .deps/plenary.nvim
PLENARY_REPO := https://github.com/nvim-lua/plenary.nvim.git

.PHONY: test test-deps dev dev-user db-up db-down

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
