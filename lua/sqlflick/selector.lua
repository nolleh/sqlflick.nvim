local M = {}

function M.create_selector_window(opt_config)
	local width = opt_config.selector.width
	local height = opt_config.selector.height
	local border = opt_config.selector.border
	local win_width = math.floor(width * 0.3)
	local x_offset = (vim.o.columns - width) / 2
	local search_height = 1

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

	local list_buf = vim.api.nvim_create_buf(false, true)
	local list_win = vim.api.nvim_open_win(list_buf, true, {
		relative = "editor",
		width = win_width,
		height = height - search_height - 2,
		col = x_offset,
		row = (vim.o.lines - height) / 2 + search_height + 2,
		style = "minimal",
		border = border,
	})

	local selector_buf = vim.api.nvim_create_buf(false, true)
	local selector_win = vim.api.nvim_open_win(selector_buf, false, {
		relative = "editor",
		width = width - win_width - 2,
		height = height,
		col = x_offset + win_width + 2,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = border,
	})

	vim.api.nvim_set_option_value("modifiable", true, { buf = search_buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = search_buf })
	vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { "" })
	vim.api.nvim_set_option_value("modifiable", false, { buf = search_buf })

	vim.api.nvim_set_option_value("modifiable", true, { buf = list_buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = list_buf })
	vim.api.nvim_set_option_value("filetype", "sqlflick", { buf = list_buf })

	return search_buf, search_win, list_buf, list_win, selector_buf, selector_win
end

function M.update_selector_content(selector_buf, items, idx)
	if not items[idx] or items[idx].is_category then
		vim.api.nvim_set_option_value("modifiable", true, { buf = selector_buf })
		vim.api.nvim_buf_set_lines(selector_buf, 0, -1, false, {})
		vim.api.nvim_set_option_value("modifiable", false, { buf = selector_buf })
		return
	end

	local db = items[idx].db_config
	local selector_lines = {
		"Database Configuration:",
		"",
		"Name: " .. db.name,
		"Type: " .. db.type,
		"Host: " .. (db.host or "N/A"),
		"Port: " .. (db.port or "N/A"),
		"Database: " .. (db.database or "N/A"),
		"Username: " .. (db.username or "N/A"),
	}

	vim.api.nvim_set_option_value("modifiable", true, { buf = selector_buf })
	vim.api.nvim_buf_set_lines(selector_buf, 0, -1, false, selector_lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = selector_buf })
end

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
