local M = {}

-- Plugin configuration
M.config = {
	-- Default configuration options
	enabled = true,
	databases = {
		-- Example database configurations
		-- {
		--     name = "local_postgres",
		--     type = "postgresql",
		--     host = "localhost",
		--     port = 5432,
		--     database = "mydb",
		--     username = "user",
		--     password = "pass"
		-- },
		-- {
		--     name = "local_mysql",
		--     type = "mysql",
		--     host = "localhost",
		--     port = 3306,
		--     database = "mydb",
		--     username = "user",
		--     password = "pass"
		-- },
		-- {
		--     name = "local_sqlite",
		--     type = "sqlite",
		--     database = "/path/to/database.db"
		-- },
		{
			name = "local_redis",
			type = "redis",
			host = "localhost",
			port = 6379,
			password = "pass",
		},
	},
	-- Preview window settings
	preview = {
		width = 50,
		height = 10,
		border = "rounded",
	},
	-- Backend settings
	backend = {
		host = "localhost",
		port = 8080,
	},
}

-- Create a preview window
local function create_preview_window()
	local width = M.config.preview.width
	local height = M.config.preview.height
	local border = M.config.preview.border
	local win_width = math.floor(width * 0.3)
	local x_offset = (vim.o.columns - width) / 2
	local search_height = 1

	-- Create search input buffer and window (top of left pane)
	local search_buf = vim.api.nvim_create_buf(false, true)
	local search_win = vim.api.nvim_open_win(search_buf, true, {
		relative = "editor",
		width = win_width,
		height = search_height,
		col = x_offset,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = border,
	})

	-- Create list buffer and window (bottom of left pane)
	local list_buf = vim.api.nvim_create_buf(false, true)
	local list_win = vim.api.nvim_open_win(list_buf, true, {
		relative = "editor",
		width = win_width,
		height = height - search_height - 2, -- Adjust for search area and borders
		col = x_offset,
		row = (vim.o.lines - height) / 2 + search_height + 2,
		style = "minimal",
		border = border,
	})

	-- Create preview buffer and window (right pane)
	local preview_buf = vim.api.nvim_create_buf(false, true)
	local preview_win = vim.api.nvim_open_win(preview_buf, false, {
		relative = "editor",
		width = width - win_width - 2,
		height = height,
		col = x_offset + win_width + 2,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = border,
	})

	-- Set up search buffer
	vim.api.nvim_set_option_value("modifiable", true, { buf = search_buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = search_buf })
	vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { "" })
	vim.api.nvim_set_option_value("modifiable", false, { buf = search_buf })

	return search_buf, search_win, list_buf, list_win, preview_buf, preview_win
end

-- Tree node structure for hierarchical navigation
local TreeNode = {}
function TreeNode.new(name, is_category, db_config, parent)
	return {
		name = name,
		is_category = is_category,
		db_config = db_config,
		parent = parent,
		children = {},
		expanded = false,
		depth = parent and (parent.depth + 1) or 0,
	}
end

-- Build tree structure from databases config
local function build_tree(databases)
	local root = TreeNode.new("root", true, nil, nil)
	root.expanded = true

	-- First pass: Create category nodes
	for key, value in pairs(databases) do
		if type(key) == "string" then
			-- This is a category
			local category = TreeNode.new(key, true, nil, root)
			root.children[#root.children + 1] = category

			-- Add databases under this category
			for _, db in ipairs(value) do
				local db_node = TreeNode.new(db.name, false, db, category)
				category.children[#category.children + 1] = db_node
			end
		elseif type(key) == "number" then
			-- This is a direct database entry
			local db = value
			local db_node = TreeNode.new(db.name, false, db, root)
			root.children[#root.children + 1] = db_node
		end
	end

	return root
end

-- Flatten tree to visible items
local function get_visible_items(root)
	local items = {}
	local function traverse(node)
		if node ~= root then -- Skip root node
			items[#items + 1] = node
		end
		if node.expanded and node.children then
			for _, child in ipairs(node.children) do
				traverse(child)
			end
		end
	end
	traverse(root)
	return items
end

-- Show database selection
local function show_database_selector()
	local search_buf, search_win, list_buf, list_win, preview_buf, preview_win = create_preview_window()

	-- Set buffer options
	vim.api.nvim_set_option_value("modifiable", true, { buf = list_buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = list_buf })
	vim.api.nvim_set_option_value("filetype", "sqlsnap", { buf = list_buf })

	-- Set search buffer options
	vim.api.nvim_set_option_value("modifiable", true, { buf = search_buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = search_buf })

	-- Build tree structure
	local root = build_tree(M.config.databases)
	local current_line = 1
	local search_term = ""

	-- Function to filter items based on search term
	local function filter_items(items, term)
		if term == "" then
			return items
		end
		local filtered = {}
		for _, item in ipairs(items) do
			if string.find(string.lower(item.name), string.lower(term)) then
				filtered[#filtered + 1] = item
			end
		end
		return filtered
	end

	-- Function to render tree
	local function render_tree()
		local items = get_visible_items(root)
		items = filter_items(items, search_term)
		local lines = {}
		for _, item in ipairs(items) do
			local prefix = string.rep("  ", item.depth)
			if item.is_category then
				prefix = prefix .. (item.expanded and "▼ " or "▶ ")
			else
				prefix = prefix .. "  "
			end
			lines[#lines + 1] = prefix .. item.name
		end

		vim.api.nvim_set_option_value("modifiable", true, { buf = list_buf })
		vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
		vim.api.nvim_set_option_value("modifiable", false, { buf = list_buf })

		return items
	end

	-- Function to update preview content
	local function update_preview_content(items, idx)
		if not items[idx] or items[idx].is_category then
			vim.api.nvim_set_option_value("modifiable", true, { buf = preview_buf })
			vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, {})
			vim.api.nvim_set_option_value("modifiable", false, { buf = preview_buf })
			return
		end

		local db = items[idx].db_config
		local preview_lines = {
			"Database Configuration:",
			"",
			"Name: " .. db.name,
			"Type: " .. db.type,
			"Host: " .. (db.host or "N/A"),
			"Port: " .. (db.port or "N/A"),
			"Database: " .. (db.database or "N/A"),
			"Username: " .. (db.username or "N/A"),
		}

		vim.api.nvim_set_option_value("modifiable", true, { buf = preview_buf })
		vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, preview_lines)
		vim.api.nvim_set_option_value("modifiable", false, { buf = preview_buf })
	end

	-- Initial render
	local items = render_tree()
	update_preview_content(items, current_line)

	-- Set window options
	vim.api.nvim_set_option_value("cursorline", true, { win = list_win })
	vim.api.nvim_set_option_value("number", false, { win = list_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = list_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = list_win })
	vim.api.nvim_set_option_value("wrap", false, { win = list_win })

	-- Set up search input handling
	-- vim.api.nvim_create_autocmd("TextChanged", {
	-- 	buffer = search_buf,
	-- 	callback = function()
	-- 		search_term = vim.api.nvim_buf_get_lines(search_buf, 0, 1, false)[1]
	-- 		items = render_tree()
	-- 		if #items > 0 then
	-- 			current_line = 1
	-- 			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
	-- 			update_preview_content(items, current_line)
	-- 		end
	-- 	end,
	-- })

	vim.api.nvim_create_autocmd("TextChangedI", {
		buffer = search_buf,
		callback = function()
			search_term = vim.api.nvim_buf_get_lines(search_buf, 0, 1, false)[1]
			items = render_tree()
			if #items > 0 then
				current_line = 1
				vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
				update_preview_content(items, current_line)
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
		-- vim.cmd("startinsert")
	end, { buffer = list_buf, silent = true })

	-- Add 'i' keymap to also enter search mode
	vim.keymap.set("n", "i", function()
		vim.api.nvim_set_current_win(search_win)
		vim.cmd("$")
		-- vim.cmd("startinsert")
	end, { buffer = list_buf, silent = true })

	-- Set keymaps
	local opts = { buffer = list_buf, silent = true }

	-- Navigation keys
	vim.keymap.set("n", "j", function()
		local items = get_visible_items(root)
		items = filter_items(items, search_term)
		if current_line < #items then
			current_line = current_line + 1
			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
			update_preview_content(items, current_line)
		end
	end, opts)

	vim.keymap.set("n", "k", function()
		if current_line > 1 then
			current_line = current_line - 1
			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
			local items = get_visible_items(root)
			items = filter_items(items, search_term)
			update_preview_content(items, current_line)
		end
	end, opts)

	-- Expand/Collapse keys
	vim.keymap.set("n", "l", function()
		local items = get_visible_items(root)
		items = filter_items(items, search_term)
		local item = items[current_line]
		if item and item.is_category and not item.expanded then
			item.expanded = true
			items = render_tree()
			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
			update_preview_content(items, current_line)
		end
	end, opts)

	vim.keymap.set("n", "h", function()
		local items = get_visible_items(root)
		items = filter_items(items, search_term)
		local item = items[current_line]
		if item and item.is_category and item.expanded then
			item.expanded = false
			items = render_tree()
			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
			update_preview_content(items, current_line)
		elseif item and item.parent and item.parent ~= root then
			-- Find parent's index
			for i, node in ipairs(items) do
				if node == item.parent then
					current_line = i
					break
				end
			end
			item.parent.expanded = false
			items = render_tree()
			vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
			update_preview_content(items, current_line)
		end
	end, opts)

	-- Selection and quit
	vim.keymap.set("n", "<CR>", function()
		local items = get_visible_items(root)
		items = filter_items(items, search_term)
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

-- Execute SQL query using backend
local function execute_query(query, db_config)
	local url = string.format("http://%s:%d/query", M.config.backend.host, M.config.backend.port)

	local data = {
		database = db_config.type,
		query = query,
		config = {
			host = db_config.host,
			port = db_config.port,
			user = db_config.username,
			password = db_config.password,
			dbname = db_config.database,
		},
	}

	local response = vim.fn.system(
		string.format("curl -s -X POST -H \"Content-Type: application/json\" -d '%s' %s", vim.fn.json_encode(data), url)
	)

	local result = vim.fn.json_decode(response)
	if result.error then
		vim.notify("Query failed: " .. result.error, vim.log.levels.ERROR)
		return nil
	end

	return result
end

-- Create debug window with tabs
local function create_debug_window()
	-- Create new buffer
	local buf = vim.api.nvim_create_buf(false, true)

	-- Split the window vertically on the right side
	vim.cmd("vsplit")
	vim.cmd("wincmd L") -- Move to the rightmost window
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	-- Set window options
	vim.api.nvim_set_option_value("number", true, { win = win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = win })
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = win })

	-- Create tab line
	local tab_line = "Results"
	vim.api.nvim_buf_set_lines(buf, 0, 1, false, { tab_line })

	-- Highlight tab line
	vim.api.nvim_buf_add_highlight(buf, -1, "TabLineSel", 0, 0, #tab_line)

	-- Add keymaps
	local opts = { buffer = buf, noremap = true, silent = true }
	vim.keymap.set("n", "q", function()
		-- Return to previous window before closing
		vim.cmd("wincmd p")
		vim.api.nvim_win_close(win, true)
	end, opts)

	return buf, win
end

-- Format query results as a table
local function format_query_results(result)
	if not result or not result.columns or not result.rows then
		return { "No results" }
	end

	-- Calculate column widths
	local col_widths = {}
	for i, col in ipairs(result.columns) do
		col_widths[i] = #col
		for _, row in ipairs(result.rows) do
			local val = tostring(row[i] or "")
			col_widths[i] = math.max(col_widths[i], #val)
		end
	end

	-- Format header
	local lines = {}
	local header = "| "
	local separator = "|-"
	for i, col in ipairs(result.columns) do
		header = header .. string.format("%-" .. col_widths[i] .. "s | ", col)
		separator = separator .. string.rep("-", col_widths[i]) .. "-|-"
	end
	table.insert(lines, header)
	table.insert(lines, separator)

	-- Format rows
	for _, row in ipairs(result.rows) do
		local line = "| "
		for i, val in ipairs(row) do
			line = line .. string.format("%-" .. col_widths[i] .. "s | ", tostring(val or ""))
		end
		table.insert(lines, line)
	end

	return lines
end

-- Setup function that will be called by users
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Basic setup logic here
	if M.config.enabled then
		print("SQLSnap plugin is enabled!")
	end

	-- Create debug commands
	vim.api.nvim_create_user_command("SQLSnapDebug", function()
		print("SQLSnap Debug Info:")
		print("Enabled:", M.config.enabled)
		print("Number of databases:", #M.config.databases)
		for _, db in ipairs(M.config.databases) do
			print(string.format("- %s (%s)", db.name, db.type))
		end
	end, {})

	-- Create database selector command
	vim.api.nvim_create_user_command("SQLSnapSelectDB", function()
		show_database_selector()
	end, {})

	-- Create query execution command
	vim.api.nvim_create_user_command("SQLSnapExecute", function(opts)
		local query = opts.args
		if #M.config.databases == 0 then
			vim.notify("No databases configured", vim.log.levels.ERROR)
			return
		end

		-- Use the selected database or default to the first one
		local db = M.selected_database or M.config.databases[1]
		local result = execute_query(query, db)

		if result then
			-- If debug window exists, reuse it
			if M.debug_win and vim.api.nvim_win_is_valid(M.debug_win) then
				vim.api.nvim_set_current_win(M.debug_win)
				vim.api.nvim_set_option_value("modifiable", true, { buf = M.debug_buf })
				vim.api.nvim_buf_set_lines(M.debug_buf, 1, -1, false, {})
			else
				-- Create new debug window
				local buf, win = create_debug_window()
				M.debug_buf = buf
				M.debug_win = win
			end

			-- Format and display results
			local lines = format_query_results(result)

			-- Set buffer content
			vim.api.nvim_set_option_value("modifiable", true, { buf = M.debug_buf })
			vim.api.nvim_buf_set_lines(M.debug_buf, 1, -1, false, lines)
			vim.api.nvim_set_option_value("modifiable", false, { buf = M.debug_buf })

			-- Set buffer options
			vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.debug_buf })
			vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = M.debug_buf })
			vim.api.nvim_set_option_value("filetype", "sqlsnap", { buf = M.debug_buf })
		end
	end, { nargs = 1 })
end

return M
