local M = {}

-- Create display window with tabs
function M.create_display_window()
  -- Create new buffer
  local buf = vim.api.nvim_create_buf(false, true)

  local config = require("sqlflick.config").opts.display
  local position = config.position or "bottom"

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

  local ns_id = vim.api.nvim_create_namespace("sqlflick")
  vim.hl.range(buf, ns_id, "SQLFlickTabLineSel", { 0, 0 }, { 0, #tab_line })

  -- Add separator line below tab
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { string.rep("─", vim.api.nvim_win_get_width(win)) })
  vim.hl.range(buf, ns_id, "SQLFlickTabLineFill", { 1, 0 }, { 1, -1 })

  -- Add keymaps
  local opts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("n", "q", function()
    vim.cmd("wincmd p")
    vim.api.nvim_win_close(win, true)
  end, opts)

  -- Add column wrapping toggle keymap
  vim.keymap.set("n", "W", function()
    local query = require("sqlflick.query")
    local column_index = query.get_column_under_cursor()
    if column_index then
      query.toggle_column_wrap(column_index)
    else
      vim.notify("Place cursor on a table column to toggle wrapping", vim.log.levels.WARN)
    end
  end, vim.tbl_extend("force", opts, { desc = "Toggle column word wrapping" }))

  -- Add help keymap
  vim.keymap.set("n", "?", function()
    local help_lines = {
      "SQLFlick Results - Keybindings:",
      "",
      "q - Close results window",
      "W - Toggle word wrapping for column under cursor",
      "? - Show this help",
      "",
      "Note: Place cursor on any table column and press 'W' to toggle wrapping.",
      "Long text will be broken into multiple lines within the column.",
    }

    local help_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = help_buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = help_buf })

    -- Create floating window for help
    local help_win = vim.api.nvim_open_win(help_buf, true, {
      relative = "editor",
      width = 60,
      height = #help_lines,
      row = math.floor((vim.o.lines - #help_lines) / 2),
      col = math.floor((vim.o.columns - 60) / 2),
      style = "minimal",
      border = "rounded",
      title = " Help ",
      title_pos = "center",
    })

    -- Add close keymap for help window
    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(help_win, true)
    end, { buffer = help_buf, noremap = true, silent = true })

    vim.keymap.set("n", "<Esc>", function()
      vim.api.nvim_win_close(help_win, true)
    end, { buffer = help_buf, noremap = true, silent = true })
  end, vim.tbl_extend("force", opts, { desc = "Show help" }))

  return buf, win
end

-- Display query results in display window
function M.display_results(buf, _, error, query, results)
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

  local ns_id = vim.api.nvim_create_namespace("sqlflick")
  for i, _ in ipairs(lines) do
    local row = i + 2 -- Account for tab line and separator
    if error then
      -- print(string.format("Processing line %d of %d total lines (query_lines: %d)", i, #lines, query_lines))
      if i > query_lines then
        -- print(string.format("Applying error highlight to line %d", row))
        vim.hl.range(buf, ns_id, "SQLFlickError", { row - 1, 0 }, { row - 1, -1 })
      else
        vim.hl.range(buf, ns_id, "SQLFlickCell", { row - 1, 0 }, { row - 1, -1 })
      end
    else
      if i > query_lines and i < query_lines + 4 then
        vim.hl.range(buf, ns_id, "SQLFlickHeader", { row - 1, 0 }, { row - 1, -1 })
      else
        vim.hl.range(buf, ns_id, "SQLFlickCell", { row - 1, 0 }, { row - 1, -1 })
      end
    end
  end

  -- Set buffer options
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "sqlflick", { buf = buf })
end

return M
