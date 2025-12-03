local M = {}

local handler = nil

-- Import modules
local config = require("sqlflick.config")
local selector = require("sqlflick.selector")
local tree = require("sqlflick.tree")
local query = require("sqlflick.query")
local display = require("sqlflick.display")
local highlights = require("sqlflick.highlights")
local install = require("sqlflick.install")
local deps = require("sqlflick.deps")
local cache = require("sqlflick.cache")
local pagination = require("sqlflick.pagination")

M.selected_database = cache.load_cache("last_db")

-- Show database selection
local function show_database_selector()
  local search_buf, search_win, list_buf, list_win, selector_buf, selector_win =
    selector.create_selector_window(config.opts)

  -- Set buffer options
  vim.api.nvim_set_option_value("modifiable", true, { buf = list_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = list_buf })
  vim.api.nvim_set_option_value("filetype", "sqlflick", { buf = list_buf })

  -- Set search buffer options
  vim.api.nvim_set_option_value("modifiable", true, { buf = search_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = search_buf })

  -- Build tree structure
  local root = tree.build_tree(config.opts.databases)
  local current_line = 1
  local search_term = ""

  -- Initial render
  local items = tree.get_visible_items(root)
  selector.render_tree(list_buf, items)
  selector.update_selector_content(selector_buf, items, current_line)

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
      selector.render_tree(list_buf, items)
      if #items > 0 then
        current_line = 1
        vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
        selector.update_selector_content(selector_buf, items, current_line)
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
      selector.update_selector_content(selector_buf, items, current_line)
    end
  end, opts)

  vim.keymap.set("n", "k", function()
    if current_line > 1 then
      current_line = current_line - 1
      vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
      local items = tree.get_visible_items(root)
      items = tree.filter_items(items, search_term)
      selector.update_selector_content(selector_buf, items, current_line)
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
      selector.render_tree(list_buf, items)
      vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
      selector.update_selector_content(selector_buf, items, current_line)
    end
  end, opts)

  vim.keymap.set("n", "h", function()
    local items = tree.get_visible_items(root)
    items = tree.filter_items(items, search_term)
    local item = items[current_line]
    if item and item.is_category and item.expanded then
      item.expanded = false
      items = tree.get_visible_items(root)
      selector.render_tree(list_buf, items)
      vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
      selector.update_selector_content(selector_buf, items, current_line)
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
      selector.render_tree(list_buf, items)
      vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
      selector.update_selector_content(selector_buf, items, current_line)
    end
  end, opts)

  -- Selection and quit
  vim.keymap.set("n", "<CR>", function()
    local items = tree.get_visible_items(root)
    items = tree.filter_items(items, search_term)
    local item = items[current_line]
    if item and not item.is_category then
      M.selected_database = item.db_config
      cache.save_cache("last_db", item.db_config)
      vim.api.nvim_win_close(selector_win, true)
      vim.api.nvim_win_close(list_win, true)
      vim.api.nvim_win_close(search_win, true)
    end
  end, opts)

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(selector_win, true)
    vim.api.nvim_win_close(list_win, true)
    vim.api.nvim_win_close(search_win, true)
  end, opts)

  -- Focus search window initially
  vim.api.nvim_set_current_win(search_win)
  vim.cmd("startinsert")

  return search_buf, search_win, list_buf, list_win, selector_buf, selector_win
end

-- Setup function that will be called by users
function M.setup(opts)
  config.setup(opts)

  -- Check and install dependencies
  if config.use_lua_http then
    if not deps.install_dependencies() then
      vim.notify("Failed to install required dependencies. Please install them manually.", vim.log.levels.ERROR)
      return
    end
  end

  install.ensure_installed()

  highlights.setup()

  query.setup(config.opts)

  -- Create display commands
  vim.api.nvim_create_user_command("SQLFlickDebug", function()
    print("SQLFlick Debug Info:")
    print("Enabled:", config.opts.enabled)
    print("Backend version: ", install.version())
    print("Backend source dir:", install.source_path())
    print("Backend install path:", install.bin())
    print("Backend port:", config.opts.backend.port)
    print("Number of databases:", #config.opts.databases)
    for _, db in ipairs(config.opts.databases) do
      print(string.format("- %s (%s)", db.name, db.type))
    end
  end, {})

  -- Create database selector command
  vim.api.nvim_create_user_command("SQLFlickSelectDB", function()
    show_database_selector()
  end, {})

  -- Create install command
  vim.api.nvim_create_user_command("SQLFlickInstall", function()
    install.exec()
    M.restart()
  end, {})

  -- Add VimLeavePre autocmd to stop backend when Neovim is closed
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.stop()
    end,
  })

  local selected_text = function()
    local mode = vim.api.nvim_get_mode().mode
    local opts = {}
    -- \22 is an escaped version of <c-v>
    if mode == "v" or mode == "V" or mode == "\22" then
      opts.type = mode
    end
    return vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), opts)
  end

  -- Add default key mappings for SQLFlickExecuteBuf
  local function setup_query_mappings()
    vim.keymap.set(
      "n",
      "<leader>sq",
      ":SQLFlickExecuteBuf<CR>",
      { silent = true, desc = "Execute SQL query on current line", buffer = true }
    )
    vim.keymap.set("v", "<leader>sq", function()
      -- Get visual selection range
      local query_text = table.concat(selected_text(), "\n")
      vim.api.nvim_cmd({
        cmd = "SQLFlickExecute",
        args = { query_text },
      }, {})
    end, { silent = true, desc = "Execute selected SQL query", buffer = true })
    vim.keymap.set("n", "<leader>ss", ":SQLFlickSelectDB<CR>", { silent = true, desc = "Select DB from configuration" })
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

  vim.api.nvim_create_user_command("SQLFlickRestart", function()
    M.restart()
  end, {})

  -- Create query execution command
  vim.api.nvim_create_user_command("SQLFlickExecute", function(opts)
    local query_text = opts.args
    if #config.opts.databases == 0 then
      vim.notify("No databases configured", vim.log.levels.ERROR)
      return
    end

    -- Use the selected database or default to the first one
    local db = M.selected_database or config.opts.databases[1]

    -- First, try to get page_size + 1 rows to check if pagination is needed
    local page_size = pagination.get_page_size()
    local check_result = M.execute_with_pagination(query_text, db, config.opts.backend, page_size + 1, 0)

    if not check_result or check_result.error then
      -- If pagination query fails, fall back to normal query
      check_result = M.execute(query_text, db, config.opts.backend)
    end

    if check_result then
      local total_rows = 0
      local result

      if check_result.rows then
        local fetched_rows = #check_result.rows

        -- If we got more than page_size rows, pagination is needed
        if fetched_rows > page_size then
          -- Enable pagination and fetch first page only (limit to page_size)
          -- We'll estimate total_rows based on fetched_rows, but it will be updated
          total_rows = fetched_rows -- This is an estimate, will be updated when we reach last page
          pagination.init(query_text, db, config.opts.backend, total_rows)
          -- Fetch first page only (limit to page_size, not page_size + 1)
          result = M.execute_with_pagination(query_text, db, config.opts.backend, page_size, 0)
          -- Use only first page_size rows from result (in case backend returns more)
          if result.rows and #result.rows > page_size then
            local limited_rows = {}
            for i = 1, page_size do
              table.insert(limited_rows, result.rows[i])
            end
            result.rows = limited_rows
          end
        else
          -- No pagination needed, use the result as is
          total_rows = fetched_rows
          result = check_result
          pagination.reset()
        end
      else
        result = check_result
      end

      if M.display_win and vim.api.nvim_win_is_valid(M.display_win) then
        vim.api.nvim_set_current_win(M.display_win)
        vim.api.nvim_set_option_value("modifiable", true, { buf = M.display_buf })
        vim.api.nvim_buf_set_lines(M.display_buf, 2, -1, false, {})
      else
        local buf, win = display.create_display_window()
        M.display_buf = buf
        M.display_win = win
      end

      local lines = query.format_query_results(result)
      local error = result.error ~= nil and true or false
      display.map_column_navigator()
      display.display_results(M.display_buf, M.display_win, error, query_text, lines)

      -- Update total_rows if pagination is enabled and we got more data
      if pagination.is_enabled() and result.rows then
        local current_page_rows = #result.rows
        local current_page = pagination.get_current_page()
        local page_size = pagination.get_page_size()
        -- If we're on the last page and got fewer rows than page_size, update total_rows
        if current_page_rows < page_size and current_page == pagination.get_total_pages() then
          local estimated_total = (current_page - 1) * page_size + current_page_rows
          pagination.state.total_rows = estimated_total
          pagination.state.total_pages = math.ceil(estimated_total / page_size)
        end
      end
    end
  end, { nargs = 1 })

  -- Create file-based query execution command
  vim.api.nvim_create_user_command("SQLFlickExecuteBuf", function()
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
      -- Normal mode: parse query containing cursor
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      local all_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

      local start_line = cursor_line
      while start_line > 1 do
        local prev_line = all_lines[start_line - 1]
        if prev_line:match("^%s*$") or prev_line:match(";%s*$") then
          break
        end
        start_line = start_line - 1
      end

      local end_line = cursor_line
      while end_line < #all_lines do
        local next_line = all_lines[end_line]
        if next_line:match("^%s*$") or next_line:match(";%s*$") then
          break
        end
        end_line = end_line + 1
      end

      -- Extract the query
      local query_lines = {}
      for i = start_line, end_line do
        table.insert(query_lines, all_lines[i])
      end
      query_text = table.concat(query_lines, "\n")
    end

    if query_text == "" then
      vim.notify("No query text found", vim.log.levels.ERROR)
      return
    end

    -- Use the selected database or default to the first one
    local db = M.selected_database or config.opts.databases[1]

    -- First, try to get page_size + 1 rows to check if pagination is needed
    local page_size = pagination.get_page_size()
    local check_result = M.execute_with_pagination(query_text, db, config.opts.backend, page_size + 1, 0)

    if not check_result or check_result.error then
      -- If pagination query fails, fall back to normal query
      check_result = M.execute(query_text, db, config.opts.backend)
    end

    if check_result then
      local total_rows = 0
      local result

      if check_result.rows then
        local fetched_rows = #check_result.rows

        -- If we got more than page_size rows, pagination is needed
        if fetched_rows > page_size then
          -- Enable pagination and fetch first page only (limit to page_size)
          -- We'll estimate total_rows based on fetched_rows, but it will be updated
          total_rows = fetched_rows -- This is an estimate, will be updated when we reach last page
          pagination.init(query_text, db, config.opts.backend, total_rows)
          -- Fetch first page only (limit to page_size, not page_size + 1)
          result = M.execute_with_pagination(query_text, db, config.opts.backend, page_size, 0)
          -- Use only first page_size rows from result (in case backend returns more)
          if result.rows and #result.rows > page_size then
            local limited_rows = {}
            for i = 1, page_size do
              table.insert(limited_rows, result.rows[i])
            end
            result.rows = limited_rows
          end
        else
          -- No pagination needed, use the result as is
          total_rows = fetched_rows
          result = check_result
          pagination.reset()
        end
      else
        result = check_result
      end

      if M.display_win and vim.api.nvim_win_is_valid(M.display_win) then
        vim.api.nvim_set_current_win(M.display_win)
        vim.api.nvim_set_option_value("modifiable", true, { buf = M.display_buf })
        vim.api.nvim_buf_set_lines(M.display_buf, 2, -1, false, {})
      else
        local buf, win = display.create_display_window()
        M.display_buf = buf
        M.display_win = win
      end

      local lines = query.format_query_results(result)
      local error = result.error ~= nil and true or false
      display.map_column_navigator()
      display.display_results(M.display_buf, M.display_win, error, query_text, lines)

      -- Update total_rows if pagination is enabled and we got more data
      if pagination.is_enabled() and result.rows then
        local current_page_rows = #result.rows
        local current_page = pagination.get_current_page()
        local page_size = pagination.get_page_size()
        -- If we're on the last page and got fewer rows than page_size, update total_rows
        if current_page_rows < page_size and current_page == pagination.get_total_pages() then
          local estimated_total = (current_page - 1) * page_size + current_page_rows
          pagination.state.total_rows = estimated_total
          pagination.state.total_pages = math.ceil(estimated_total / page_size)
        end
      end
    end
  end, {})

  if handler then
    return
  end
  handler = require("sqlflick.handler"):new(config.opts.backend.port)
end

---Execute a query
---@param query_text string
---@param database table
---@param backend_config table
function M.execute(query_text, database, backend_config)
  if not handler then
    M.setup()
  end

  handler = require("sqlflick.handler"):new(config.opts.backend.port)
  return handler:execute_query(query_text, database, backend_config)
end

---Execute a query with pagination
---@param query_text string
---@param database table
---@param backend_config table
---@param limit number|nil
---@param offset number|nil
function M.execute_with_pagination(query_text, database, backend_config, limit, offset)
  if not handler then
    M.setup()
  end

  handler = require("sqlflick.handler"):new(config.opts.backend.port)
  return handler:execute_query_with_pagination(query_text, database, backend_config, limit, offset)
end

---Refresh current page (reload current page data)
function M.refresh_current_page()
  if not pagination.is_enabled() then
    return
  end

  local db = M.selected_database or config.opts.databases[1]
  if not db then
    return
  end

  local query_text = pagination.state.query_text
  local page_size = pagination.get_page_size()
  local offset = pagination.get_offset()

  local result = M.execute_with_pagination(query_text, db, config.opts.backend, page_size, offset)

  if result and M.display_buf and M.display_win and vim.api.nvim_win_is_valid(M.display_win) then
    vim.api.nvim_set_current_win(M.display_win)
    vim.api.nvim_set_option_value("modifiable", true, { buf = M.display_buf })
    vim.api.nvim_buf_set_lines(M.display_buf, 2, -1, false, {})

    local lines = query.format_query_results(result)
    local error = result.error ~= nil and true or false
    display.map_column_navigator()
    display.display_results(M.display_buf, M.display_win, error, query_text, lines)
  end
end

---Install the backend binary
function M.install()
  require("sqlflick.install").exec()
end

function M.restart()
  if not handler then
    M.setup()
  end
  handler = require("sqlflick.handler"):new(config.opts.backend.port)
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
