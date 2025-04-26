local M = {}

local handler = nil

-- Import modules
local config = require("sqlsnap.config")
local preview = require("sqlsnap.preview")
local tree = require("sqlsnap.tree")
local query = require("sqlsnap.query")
local display = require("sqlsnap.display")
local highlights = require("sqlsnap.highlights")
local install = require("sqlsnap.install")

-- Show database selection
local function show_database_selector()
	local search_buf, search_win, list_buf, list_win, preview_buf, preview_win =
		preview.create_preview_window(config.opts)

	-- Set buffer options
	vim.api.nvim_set_option_value("modifiable", true, { buf = list_buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = list_buf })
	vim.api.nvim_set_option_value("filetype", "sqlsnap", { buf = list_buf })

	-- Set search buffer options
	vim.api.nvim_set_option_value("modifiable", true, { buf = search_buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = search_buf })

	-- Build tree structure
	local root = tree.build_tree(config.opts.databases)
	local current_line = 1
	local search_term = ""

	-- Initial render
	local items = tree.get_visible_items(root)
	preview.render_tree(list_buf, items)
	preview.update_preview_content(preview_buf, items, current_line)

	-- Set window options
	vim.api.nvim_set_option_value("cursorline", true, { win = list_win })
	vim.api.nvim_set_option_value("number", false, { win = list_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = list_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = list_win })
	vim.api.nvim_set_option_value("wrap", false, { win = list_win })

	-- Set up search input handling
	vim.api.nvim_create_autocmd("TextChangedI", {
		buffer = search_buf,
		callback = function()
			search_term = vim.api.nvim_buf_get_lines(search_buf, 0, 1, false)[1]
			items = tree.filter_items(tree.get_visible_items(root), search_term)
			preview.render_tree(list_buf, items)
			if #items > 0 then
				current_line = 1
				vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
				preview.update_preview_content(preview_buf, items, current_line)
			end
		end,
	})

	-- Handle focus movement when exiting insert mode in search
	vim.api.nvim_create_autocmd("InsertLeave", {
		buffer = search_buf,
		callback = function()
			vim.api.nvim_set_current_win(list_win)
		end,
	})

	-- Add keymap to return to search
	vim.keymap.set("n", "/", function()
		vim.api.nvim_set_current_win(search_win)
		vim.cmd("$")
	end, { buffer = list_buf, silent = true })

	-- Add 'i' keymap to also enter search mode
	vim.keymap.set("n", "i", function()
		vim.api.nvim_set_current_win(search_win)
		vim.cmd("$")
	end, { buffer = list_buf, silent = true })

	-- Set keymaps
	local opts = { buffer = list_buf, silent = true }

	-- Navigation keys
	vim.keymap.set("n", "j", function()
		local items = tree.get_visible_items(root)
		items = tree.filter_items(items, search_term)
		if current_line < #items then
			current_line = current_line + 1
			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
			preview.update_preview_content(preview_buf, items, current_line)
		end
	end, opts)

	vim.keymap.set("n", "k", function()
		if current_line > 1 then
			current_line = current_line - 1
			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
			local items = tree.get_visible_items(root)
			items = tree.filter_items(items, search_term)
			preview.update_preview_content(preview_buf, items, current_line)
		end
	end, opts)

	-- Expand/Collapse keys
	vim.keymap.set("n", "l", function()
		local items = tree.get_visible_items(root)
		items = tree.filter_items(items, search_term)
		local item = items[current_line]
		if item and item.is_category and not item.expanded then
			item.expanded = true
			items = tree.get_visible_items(root)
			preview.render_tree(list_buf, items)
			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
			preview.update_preview_content(preview_buf, items, current_line)
		end
	end, opts)

	vim.keymap.set("n", "h", function()
		local items = tree.get_visible_items(root)
		items = tree.filter_items(items, search_term)
		local item = items[current_line]
		if item and item.is_category and item.expanded then
			item.expanded = false
			items = tree.get_visible_items(root)
			preview.render_tree(list_buf, items)
			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
			preview.update_preview_content(preview_buf, items, current_line)
		elseif item and item.parent and item.parent ~= root then
			-- Find parent's index
			for i, node in ipairs(items) do
				if node == item.parent then
					current_line = i
					break
				end
			end
			item.parent.expanded = false
			items = tree.get_visible_items(root)
			preview.render_tree(list_buf, items)
			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
			preview.update_preview_content(preview_buf, items, current_line)
		end
	end, opts)

	-- Selection and quit
	vim.keymap.set("n", "<CR>", function()
		local items = tree.get_visible_items(root)
		items = tree.filter_items(items, search_term)
		local item = items[current_line]
		if item and not item.is_category then
			M.selected_database = item.db_config
			vim.api.nvim_win_close(preview_win, true)
			vim.api.nvim_win_close(list_win, true)
			vim.api.nvim_win_close(search_win, true)
		end
	end, opts)

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(preview_win, true)
		vim.api.nvim_win_close(list_win, true)
		vim.api.nvim_win_close(search_win, true)
	end, opts)

	-- Focus search window initially
	vim.api.nvim_set_current_win(search_win)
	vim.cmd("startinsert")

	return search_buf, search_win, list_buf, list_win, preview_buf, preview_win
end

-- Setup function that will be called by users
function M.setup(opts)
	-- Set up configuration
	config.setup(opts)

	-- Ensure backend is installed
	install.ensure_installed()

	-- Set up custom highlights
	highlights.setup()

	-- Create display commands
	vim.api.nvim_create_user_command("SQLSnapDebug", function()
		print("SQLSnap Debug Info:")
		print("Enabled:", config.opts.enabled)
		-- print("Backend version:", install.version())
		print("Backend source dir:", install.source_path())
		print("Backend install path:", install.bin())
		print("Number of databases:", #config.opts.databases)
		for _, db in ipairs(config.opts.databases) do
			print(string.format("- %s (%s)", db.name, db.type))
		end
	end, {})

	-- Create database selector command
	vim.api.nvim_create_user_command("SQLSnapSelectDB", function()
		show_database_selector()
	end, {})

	-- Create install command
	vim.api.nvim_create_user_command("SQLSnapInstall", function()
		install.exec()
		M.restart()
	end, {})

	-- Add default key mappings for SQLSnapExecuteBuf
	local function setup_query_mappings()
		vim.keymap.set(
			"n",
			"<leader>sq",
			":SQLSnapExecuteBuf<CR>",
			{ silent = true, desc = "Execute SQL query on current line", buffer = true }
		)
		vim.keymap.set(
			"v",
			"<leader>sq",
			":SQLSnapExecuteBuf<CR>",
			{ silent = true, desc = "Execute selected SQL query", buffer = true }
		)
		vim.keymap.set(
			"n",
			"<leader>ss",
			":SQLSnapSelectDB<CR>",
			{ silent = true, desc = "Select DB from configuration" }
		)
	end

	-- Set up mappings for SQL and query-related file types
	vim.api.nvim_create_autocmd("FileType", {
		pattern = {
			"sql",
			"pgsql",
			"mysql",
			"sqlite",
			"hql",
			"cql",
			"plsql",
			"tsql",
			"ddl",
			"dml",
		},
		callback = setup_query_mappings,
	})

	vim.api.nvim_create_user_command("SQLSnapRestart", function()
		M.restart()
	end, {})

	-- Create query execution command
	vim.api.nvim_create_user_command("SQLSnapExecute", function(opts)
		local query_text = opts.args
		if #config.opts.databases == 0 then
			vim.notify("No databases configured", vim.log.levels.ERROR)
			return
		end

		-- Use the selected database or default to the first one
		local db = M.selected_database or config.opts.databases[1]
		local result = query.execute_query(query_text, db, config.opts.backend)

		if result then
			-- If display window exists, reuse it
			if M.display_win and vim.api.nvim_win_is_valid(M.display_win) then
				vim.api.nvim_set_current_win(M.display_win)
				vim.api.nvim_set_option_value("modifiable", true, { buf = M.display_buf })
				vim.api.nvim_buf_set_lines(M.display_buf, 2, -1, false, {})
			else
				-- Create new display window
				local buf, win = display.create_display_window()
				M.display_buf = buf
				M.display_win = win
			end

			-- Format and display results
			local lines = query.format_query_results(result)
			display.display_results(M.display_buf, M.display_win, query_text, lines)
		end
	end, { nargs = 1 })

	-- Create file-based query execution command
	vim.api.nvim_create_user_command("SQLSnapExecuteBuf", function()
		if #config.opts.databases == 0 then
			vim.notify("No databases configured", vim.log.levels.ERROR)
			return
		end

		local query_text = ""
		local mode = vim.api.nvim_get_mode().mode

		if mode == "v" or mode == "V" then
			-- Visual mode: get selected text
			local start_pos = vim.api.nvim_buf_get_mark(0, "<")
			local end_pos = vim.api.nvim_buf_get_mark(0, ">")
			local lines = vim.api.nvim_buf_get_lines(0, start_pos[1] - 1, end_pos[1], false)
			query_text = table.concat(lines, "\n")
		else
			-- Normal mode: get current line
			local line = vim.api.nvim_get_current_line()
			query_text = line
		end

		if query_text == "" then
			vim.notify("No query text found", vim.log.levels.ERROR)
			return
		end

		-- Use the selected database or default to the first one
		local db = M.selected_database or config.opts.databases[1]
		local result = M.execute(query_text, db, config.opts.backend)

		if result then
			-- If display window exists, reuse it
			if M.display_win and vim.api.nvim_win_is_valid(M.display_win) then
				vim.api.nvim_set_current_win(M.display_win)
				vim.api.nvim_set_option_value("modifiable", true, { buf = M.display_buf })
				vim.api.nvim_buf_set_lines(M.display_buf, 2, -1, false, {})
			else
				-- Create new display window
				local buf, win = display.create_display_window()
				M.display_buf = buf
				M.display_win = win
			end

			-- Format and display results
			local lines = query.format_query_results(result)
			display.display_results(M.display_buf, M.display_win, query_text, lines)
		end
	end, {})

	if handler then
		return
	end
	handler = require("sqlsnap.handler").new(config.opts.backend.port)
end

---Execute a query
---@param query_text string
---@param database table
---@param backend_config table
function M.execute(query_text, database, backend_config)
	if not handler then
		M.setup()
	end

	handler = require("sqlsnap.handler").new(config.opts.backend.port)
	return handler:execute_query(query_text, database, backend_config)
end

---Install the backend binary
function M.install()
	require("sqlsnap.install").exec()
end

function M.restart()
	if not handler then
		M.setup()
	end
	handler = require("sqlsnap.handler").new(config.opts.backend.port)
	return handler:restart()
end

---Stop the backend process
function M.stop()
	if handler then
		handler:stop()
		handler = nil
	end
end

return M
