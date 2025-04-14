local M = {}

-- Create display window with tabs
function M.create_display_window()
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
function M.display_results(buf, win, query, results)
	-- Set buffer content
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

	local lines = {}
	table.insert(lines, query)

	-- Convert results to strings if it's an array
	if type(results) == "table" then
		for _, result in ipairs(results) do
			table.insert(lines, tostring(result))
		end
	else
		table.insert(lines, tostring(results))
	end

	vim.api.nvim_buf_set_lines(buf, 2, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	-- Apply syntax highlighting
	local ns_id = vim.api.nvim_create_namespace("sqlsnap")
	for i, line in ipairs(lines) do
		local row = i + 2 -- Account for tab line and separator
		if i <= 3 then
			-- Header line
			vim.api.nvim_buf_add_highlight(buf, ns_id, "SQLSnapHeader", row, 0, -1)
		else
			-- Data cells
			vim.api.nvim_buf_add_highlight(buf, ns_id, "SQLSnapCell", row, 0, -1)
		end
	end

	-- Set buffer options
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("filetype", "sqlsnap", { buf = buf })
end

return M
