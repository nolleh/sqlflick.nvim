local M = {}

-- Store table data for manipulation (word wrapping, etc.)
M.table_data = nil

M.MAX_COLUMN_WIDTH = 200 -- Maximum width for any column
M.MIN_COLUMN_WIDTH = 0 -- Minimum width for readability

function M.setup(opts)
  M.MAX_COLUMN_WIDTH = math.min(opts.display.column.max_width, M.MAX_COLUMN_WIDTH)
  M.MIN_COLUMN_WIDTH = math.max(opts.display.column.min_width, M.MIN_COLUMN_WIDTH)
end

-- Helper function to truncate text and add ellipsis if needed
local function truncate_text(text, max_width)
  local str = tostring(text or "")
  if vim.fn.strdisplaywidth(str) <= max_width then
    return str
  end

  -- Find a good truncation point (prefer word boundaries)
  local truncated = ""
  local width = 0
  for char in str:gmatch(".") do
    local char_width = vim.fn.strdisplaywidth(char)
    if width + char_width + 3 > max_width then -- +3 for "..."
      break
    end
    truncated = truncated .. char
    width = width + char_width
  end

  return truncated .. "..."
end

-- Helper function to wrap text for a specific column
local function wrap_text(text, max_width)
  local str = tostring(text or "")
  if vim.fn.strdisplaywidth(str) <= max_width then
    return { str }
  end

  local lines = {}
  local current_line = ""
  local current_width = 0

  -- Split by words and wrap
  for word in str:gmatch("%S+") do
    local word_width = vim.fn.strdisplaywidth(word)

    if current_width + word_width + 1 > max_width and current_line ~= "" then
      table.insert(lines, current_line)
      current_line = word
      current_width = word_width
    else
      if current_line ~= "" then
        current_line = current_line .. " " .. word
        current_width = current_width + word_width + 1
      else
        current_line = word
        current_width = word_width
      end
    end
  end

  if current_line ~= "" then
    table.insert(lines, current_line)
  end

  return #lines > 0 and lines or { "" }
end

-- Format query results as a table
function M.format_query_results(result)
  local lines = {}
  if result.error then
    table.insert(lines, "Error executing query:")
    table.insert(lines, result.error)
    return lines
  end

  if not result then
    return { "No results" }
  end

  -- Handle DDL commands (like DROP TABLE) that return userdata
  if type(result.columns) == "userdata" then
    return { "Command executed successfully" }
  end

  if not result.columns or not result.rows then
    return { "No results" }
  end

  -- Store table data for later manipulation
  M.table_data = {
    columns = result.columns,
    rows = result.rows,
    wrapped_columns = {}, -- Track which columns are wrapped
  }

  local col_widths = {}
  for i, col in ipairs(result.columns) do
    local header_width = vim.fn.strdisplaywidth(col)
    local max_data_width = 0

    for _, row in ipairs(result.rows) do
      local val = tostring(row[i] or "")
      max_data_width = math.max(max_data_width, vim.fn.strdisplaywidth(val))
    end

    local ideal_width = math.max(header_width, max_data_width)
    col_widths[i] = math.max(M.MIN_COLUMN_WIDTH, math.min(M.MAX_COLUMN_WIDTH, ideal_width))
  end

  for i, width in ipairs(col_widths) do
    col_widths[i] = width + 2 -- Add 2 spaces of padding
  end

  local function create_line(left, mid, right)
    local line = left
    for i, width in ipairs(col_widths) do
      line = line .. string.rep("─", width)
      line = line .. (i < #col_widths and mid or right)
    end
    return line
  end

  local top = create_line("┌", "┬", "┐")
  local mid = create_line("├", "┼", "┤")
  local bot = create_line("└", "┴", "┘")

  local header = "│"
  for i, col in ipairs(result.columns) do
    local truncated_col = truncate_text(col, col_widths[i] - 2) -- -2 for padding
    local padded_col = " "
      .. truncated_col
      .. string.rep(" ", col_widths[i] - vim.fn.strdisplaywidth(truncated_col) - 1)
    header = header .. padded_col .. "│"
  end

  table.insert(lines, top)
  table.insert(lines, header)
  table.insert(lines, mid)

  -- Format rows
  for _, row in ipairs(result.rows) do
    local line = "│"
    for i, val in ipairs(row) do
      local truncated_val = truncate_text(val, col_widths[i] - 2) -- -2 for padding
      local padded_val = " "
        .. truncated_val
        .. string.rep(" ", col_widths[i] - vim.fn.strdisplaywidth(truncated_val) - 1)
      line = line .. padded_val .. "│"
    end
    table.insert(lines, line)
  end

  table.insert(lines, bot)

  return lines
end

function M.get_column_under_cursor()
  if not M.table_data then
    return nil
  end

  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor_pos[1]
  local col_num = cursor_pos[2] + 1 -- Convert to 1-based

  local lines = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)
  if #lines == 0 then
    return nil
  end

  local line = lines[1]

  -- Skip if not a data line (check for │ characters)
  if not line:match("│") then
    return nil
  end

  local separator_positions = {}
  local start_pos = 1
  while true do
    local pos = line:find("│", start_pos)
    if not pos then
      break
    end
    table.insert(separator_positions, pos)
    start_pos = pos + 1
  end

  -- Need at least 2 separators to have 1 column
  if #separator_positions < 2 then
    return nil
  end

  -- Find which column the cursor is in
  for i = 1, #separator_positions - 1 do
    local left_border = separator_positions[i]
    local right_border = separator_positions[i + 1]

    if col_num > left_border and col_num < right_border then
      return i -- Column index (1-based)
    end
  end

  return nil
end

function M.toggle_column_wrap(column_index)
  if not M.table_data then
    vim.notify("No table data available", vim.log.levels.WARN)
    return
  end

  if column_index < 1 or column_index > #M.table_data.columns then
    vim.notify("Invalid column index", vim.log.levels.WARN)
    return
  end

  M.table_data.wrapped_columns[column_index] = not M.table_data.wrapped_columns[column_index]

  local new_result = {
    columns = M.table_data.columns,
    rows = M.table_data.rows,
  }

  local formatted_lines = M.format_query_results_with_wrapping(new_result)

  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

  -- Find where the table starts (after the query and separator lines)
  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local table_start = 3 -- Default: skip tab line, separator, and one more

  for i, line in ipairs(all_lines) do
    if line:match("^┌") then -- Top border of table
      table_start = i
      break
    end
  end

  vim.api.nvim_buf_set_lines(buf, table_start - 1, -1, false, formatted_lines)

  -- Reapply highlights to preserve syntax highlighting
  local ns_id = vim.api.nvim_create_namespace("sqlflick")
  vim.api.nvim_buf_clear_namespace(buf, ns_id, table_start - 1, -1)

  for i, line in ipairs(formatted_lines) do
    local row = table_start - 1 + i
    if line:match("^┌") or line:match("^├") then
      vim.hl.range(buf, ns_id, "SQLFlickHeader", { row - 1, 0 }, { row - 1, -1 })
    elseif line:match("^└") or line:match("^╟") then
      -- Border lines (including row separators)
      vim.hl.range(buf, ns_id, "SQLFlickHeaderSep", { row - 1, 0 }, { row - 1, -1 })
    elseif line:match("^│") then
      -- Check if it's a header line (contains column names)
      local is_header = false
      for _, col_name in ipairs(M.table_data.columns) do
        if line:match(vim.pesc(col_name)) then
          is_header = true
          break
        end
      end

      if is_header then
        vim.hl.range(buf, ns_id, "SQLFlickHeader", { row - 1, 0 }, { row - 1, -1 })
      else
        vim.hl.range(buf, ns_id, "SQLFlickCell", { row - 1, 0 }, { row - 1, -1 })
      end
    end
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- local status = M.table_data.wrapped_columns[column_index] and "wrapped" or "unwrapped"
  -- vim.notify(string.format("Column '%s' %s", M.table_data.columns[column_index], status), vim.log.levels.INFO)
end

-- Format query results with column wrapping support
function M.format_query_results_with_wrapping(result)
  local lines = {}
  if result.error then
    table.insert(lines, "Error executing query:")
    table.insert(lines, result.error)
    return lines
  end

  if not result or not result.columns or not result.rows then
    return { "No results" }
  end

  -- Handle DDL commands
  if type(result.columns) == "userdata" then
    return { "Command executed successfully" }
  end

  -- Calculate column widths, considering wrapped columns
  local col_widths = {}
  for i, col in ipairs(result.columns) do
    local header_width = vim.fn.strdisplaywidth(col)
    local max_data_width = 0

    if M.table_data and M.table_data.wrapped_columns[i] then
      -- For wrapped columns, use a reasonable fixed width
      max_data_width = 50
    else
      for _, row in ipairs(result.rows) do
        local val = tostring(row[i] or "")
        max_data_width = math.max(max_data_width, vim.fn.strdisplaywidth(val))
      end
    end

    local ideal_width = math.max(header_width, max_data_width)
    col_widths[i] = math.max(M.MIN_COLUMN_WIDTH, math.min(M.MAX_COLUMN_WIDTH, ideal_width)) + 2
  end

  -- Format header and borders
  local function create_line(left, mid, right)
    local line = left
    for i, width in ipairs(col_widths) do
      line = line .. string.rep("─", width)
      line = line .. (i < #col_widths and mid or right)
    end
    return line
  end

  local top = create_line("┌", "┬", "┐")
  local mid = create_line("├", "┼", "┤")
  local bot = create_line("└", "┴", "┘")
  local row_sep = create_line("╟", "╫", "╢") -- Row separator for wrapped content

  -- Create header
  local header = "│"
  for i, col in ipairs(result.columns) do
    local truncated_col = truncate_text(col, col_widths[i] - 2)
    local padded_col = " "
      .. truncated_col
      .. string.rep(" ", col_widths[i] - vim.fn.strdisplaywidth(truncated_col) - 1)
    header = header .. padded_col .. "│"
  end

  table.insert(lines, top)
  table.insert(lines, header)
  table.insert(lines, mid)

  -- Check if any columns are wrapped to determine if we need row separators
  local has_wrapped_columns = false
  if M.table_data then
    for _, is_wrapped in pairs(M.table_data.wrapped_columns) do
      if is_wrapped then
        has_wrapped_columns = true
        break
      end
    end
  end

  -- Format rows with wrapping support
  for row_idx, row in ipairs(result.rows) do
    local row_lines = {}
    local max_wrapped_lines = 1

    -- First pass: determine how many lines this row will need
    for i, val in ipairs(row) do
      if M.table_data and M.table_data.wrapped_columns[i] then
        local wrapped = wrap_text(val, col_widths[i] - 2)
        row_lines[i] = wrapped
        max_wrapped_lines = math.max(max_wrapped_lines, #wrapped)
      else
        local truncated_val = truncate_text(val, col_widths[i] - 2)
        row_lines[i] = { truncated_val }
      end
    end

    -- Second pass: create the actual lines
    for line_idx = 1, max_wrapped_lines do
      local line = "│"
      for i = 1, #result.columns do
        local text = row_lines[i][line_idx] or ""
        local padded_text = " " .. text .. string.rep(" ", col_widths[i] - vim.fn.strdisplaywidth(text) - 1)
        line = line .. padded_text .. "│"
      end
      table.insert(lines, line)
    end

    -- Add row separator between rows (but not after the last row) when wrapping is active
    if has_wrapped_columns and row_idx < #result.rows then
      table.insert(lines, row_sep)
    end
  end

  table.insert(lines, bot)
  return lines
end

return M
