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

	-- Create a floating window
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = (vim.o.columns - width) / 2,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = border,
	})

	return buf, win
end

-- Show database selection
local function show_database_selector()
	local buf, win = create_preview_window()

	-- Set buffer options
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "filetype", "sqlsnap")

	-- Add database options
	local lines = { "Select a database:" }
	for _, db in ipairs(M.config.databases) do
		table.insert(lines, string.format("%d. %s (%s)", #lines, db.name, db.type))
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Hide cursor completely
	vim.api.nvim_win_set_option(win, "cursorline", false)
	vim.api.nvim_win_set_option(win, "cursorcolumn", false)
	vim.api.nvim_win_set_option(win, "number", false)
	vim.api.nvim_win_set_option(win, "relativenumber", false)
	vim.api.nvim_win_set_option(win, "signcolumn", "no")
	vim.api.nvim_win_set_option(win, "wrap", false)

	local current_line = 1

	-- Add arrow indicator
	local function update_arrow_indicator(line)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		vim.api.nvim_buf_set_option(buf, "modifiable", true)
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		for i, content in ipairs(lines) do
			if i == line then
				lines[i] = "→ " .. content:gsub("^→%s*", ""):gsub("^%s*", "")
			else
				lines[i] = "  " .. content:gsub("^→%s*", ""):gsub("^%s*", "")
			end
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(buf, "modifiable", false)
		current_line = line
	end

	-- Initialize arrow indicator
	update_arrow_indicator(1)

	-- Set keymaps using vim.keymap.set
	local opts = { buffer = buf, silent = true }

	-- Navigation keys
	vim.keymap.set("n", "j", function()
		if current_line < #lines then
			current_line = current_line + 1
			update_arrow_indicator(current_line)
		end
	end, opts)

	vim.keymap.set("n", "k", function()
		if current_line > 1 then
			current_line = current_line - 1
			update_arrow_indicator(current_line)
		end
	end, opts)

	-- Selection and quit
	vim.keymap.set("n", "<CR>", function()
		if current_line > 1 then
			M.selected_database = M.config.databases[current_line - 1]
			vim.api.nvim_win_close(win, true)
		end
	end, opts)

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, opts)

	-- Block unwanted keys
	local keys_to_block = { "h", "l", "w", "b", "e", "0", "$", "gg", "G", "i", "a", "o", "O", "x", "d", "y", "p" }
	for _, key in ipairs(keys_to_block) do
		vim.keymap.set("n", key, "<Nop>", opts)
	end

	return buf, win
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
			-- Create a new buffer to show results
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
			vim.api.nvim_buf_set_option(buf, "filetype", "sqlsnap")

			-- Format and display results
			local lines = {}
			table.insert(lines, "Query Results:")
			table.insert(lines, table.concat(result.columns, " | "))
			table.insert(lines, string.rep("-", 80))
			for _, row in ipairs(result.rows) do
				local row_str = {}
				for _, value in ipairs(row) do
					table.insert(row_str, tostring(value))
				end
				table.insert(lines, table.concat(row_str, " | "))
			end

			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.api.nvim_open_win(buf, true, {
				relative = "editor",
				width = 80,
				height = 20,
				col = (vim.o.columns - 80) / 2,
				row = (vim.o.lines - 20) / 2,
				style = "minimal",
				border = "rounded",
			})
		end
	end, { nargs = 1 })
end

return M
