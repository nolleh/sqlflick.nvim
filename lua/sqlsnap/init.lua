local M = {}

-- Import modules
local config = require("sqlsnap.config")
local preview = require("sqlsnap.preview")
local tree = require("sqlsnap.tree")
local query = require("sqlsnap.query")
local debug = require("sqlsnap.debug")
local highlights = require("sqlsnap.highlights")

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

-- Show database selection
local function show_database_selector()
	local search_buf, search_win, list_buf, list_win, preview_buf, preview_win = preview.create_preview_window(config.opts)

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

	-- Set up custom highlights
	highlights.setup()

	-- Basic setup logic here
	if config.opts.enabled then
		print("SQLSnap plugin is enabled!")
	end

	-- Create debug commands
	vim.api.nvim_create_user_command("SQLSnapDebug", function()
		print("SQLSnap Debug Info:")
		print("Enabled:", config.opts.enabled)
		print("Number of databases:", #config.opts.databases)
		for _, db in ipairs(config.opts.databases) do
			print(string.format("- %s (%s)", db.name, db.type))
		end
	end, {})

	-- Create database selector command
	vim.api.nvim_create_user_command("SQLSnapSelectDB", function()
		show_database_selector()
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
			-- If debug window exists, reuse it
			if M.debug_win and vim.api.nvim_win_is_valid(M.debug_win) then
				vim.api.nvim_set_current_win(M.debug_win)
				vim.api.nvim_set_option_value("modifiable", true, { buf = M.debug_buf })
				vim.api.nvim_buf_set_lines(M.debug_buf, 2, -1, false, {})
			else
				-- Create new debug window
				local buf, win = debug.create_debug_window()
				M.debug_buf = buf
				M.debug_win = win
			end

			-- Format and display results
			local lines = query.format_query_results(result)
			debug.display_results(M.debug_buf, M.debug_win, lines)
		end
	end, { nargs = 1 })
end

return M
