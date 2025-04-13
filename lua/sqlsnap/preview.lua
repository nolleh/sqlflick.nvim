local M = {}

-- Create a preview window
function M.create_preview_window(config)
	local width = config.preview.width
	local height = config.preview.height
	local border = config.preview.border
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

-- Update preview content
function M.update_preview_content(preview_buf, items, idx)
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

-- Render tree in list buffer
function M.render_tree(list_buf, items)
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
end

return M

