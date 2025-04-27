local M = {}

-- Create display window with tabs
function M.create_display_window()
	-- Create new buffer
	local buf = vim.api.nvim_create_buf(false, true)

	-- Get display configuration
	local config = require("sqlsnap.config").opts.display
	local position = config.position or "bottom"

	-- Calculate window dimensions
	local win_height, win_width
	if config.size_absolute.height then
		win_height = config.size_absolute.height
	else
		win_height = math.floor(vim.o.lines * config.size.height)
	end

	if config.size_absolute.width then
		win_width = config.size_absolute.width
	else
		win_width = math.floor(vim.o.columns * config.size.width)
	end

	-- Create split based on position
	if position == "bottom" then
		vim.cmd(win_height .. "split")
		vim.cmd("wincmd J") -- Move to bottom
	else
		vim.cmd(win_width .. "vsplit")
		vim.cmd("wincmd L") -- Move to right
	end

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	-- Set window options
	vim.api.nvim_set_option_value("number", true, { win = win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = win })
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
	vim.api.nvim_set_option_value("winhighlight", "Normal:Normal,FloatBorder:Normal", { win = win })

	-- Create tab line with padding
	local tab_line = "▎ Results "
	vim.api.nvim_buf_set_lines(buf, 0, 1, false, { tab_line })

	-- Highlight tab line with custom highlights
	vim.api.nvim_buf_add_highlight(buf, -1, "SQLSnapTabLineSel", 0, 0, #tab_line)

	-- Add separator line below tab
	vim.api.nvim_buf_set_lines(buf, 1, 2, false, { string.rep("─", vim.api.nvim_win_get_width(win)) })
	vim.api.nvim_buf_add_highlight(buf, -1, "SQLSnapTabLineFill", 1, 0, -1)

	-- Add keymaps
	local opts = { buffer = buf, noremap = true, silent = true }
	vim.keymap.set("n", "q", function()
		vim.cmd("wincmd p")
		vim.api.nvim_win_close(win, true)
	end, opts)

	return buf, win
end

-- Display query results in display window
function M.display_results(buf, win, error, query, results)
	-- Set buffer content
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

	local lines = {}

	-- Convert results to strings if it's an array
	local function normalize_string(str)
		-- Convert to string if needed
		str = tostring(str)
		-- Replace any Windows-style newlines with Unix-style
		str = string.gsub(str, "\r\n", "\n")
		-- Remove trailing whitespace from each line
		str = string.gsub(str, "%s+\n", "\n")
		-- Remove trailing whitespace at the end
		str = string.gsub(str, "%s+$", "")
		return str
	end

	if type(query) == "table" then
		for _, queryline in ipairs(query) do
			local str = normalize_string(queryline)
			local query_lines = vim.split(str, "\n", { plain = true })
			vim.list_extend(lines, query_lines)
		end
	else
		local str = normalize_string(query)
		local query_lines = vim.split(str, "\n", { plain = true })
		vim.list_extend(lines, query_lines)
	end
	local query_lines = #lines

	if type(results) == "table" then
		for _, result in ipairs(results) do
			local str = normalize_string(result)
			local result_lines = vim.split(str, "\n", { plain = true })
			vim.list_extend(lines, result_lines)
		end
	else
		local str = normalize_string(results)
		local result_lines = vim.split(str, "\n", { plain = true })
		vim.list_extend(lines, result_lines)
	end

	vim.api.nvim_buf_set_lines(buf, 2, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	-- Apply syntax highlighting
	local ns_id = vim.api.nvim_create_namespace("sqlsnap")
	for i, line in ipairs(lines) do
		local row = i + 2 -- Account for tab line and separator
		if error then
			-- print(string.format("Processing line %d of %d total lines (query_lines: %d)", i, #lines, query_lines))
			if i > query_lines then
				-- print(string.format("Applying error highlight to line %d", row))
				-- Use SQLSnapError highlight group for error messages
				vim.api.nvim_buf_add_highlight(buf, ns_id, "SQLSnapError", row - 1, 0, -1)
			else
				-- Highlight query lines normally
				vim.api.nvim_buf_add_highlight(buf, ns_id, "SQLSnapCell", row - 1, 0, -1)
			end
		else
			if i <= 3 then
				-- Header line
				vim.api.nvim_buf_add_highlight(buf, ns_id, "SQLSnapHeader", row, 0, -1)
			else
				-- Data cells
				vim.api.nvim_buf_add_highlight(buf, ns_id, "SQLSnapCell", row, 0, -1)
			end
		end
	end

	-- Set buffer options
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("filetype", "sqlsnap", { buf = buf })
end

return M
