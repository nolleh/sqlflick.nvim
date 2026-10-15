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
local completion = require("sqlflick.completion")
local statement = require("sqlflick.statement")

M.selected_database = nil

local function selected_database_or_notify()
  if M.selected_database then
    return M.selected_database
  end
  vim.notify("Select a database with :SQLFlickSelectDB before executing a query", vim.log.levels.ERROR)
  return nil
end

local active_execution = nil
local result_context = nil

local function render_result(query_text, result)
  local focus = vim.api.nvim_get_current_win()
  if
    not (
      M.display_win
      and vim.api.nvim_win_is_valid(M.display_win)
      and M.display_buf
      and vim.api.nvim_buf_is_valid(M.display_buf)
    )
  then
    M.display_buf, M.display_win = display.create_display_window()
  end
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.display_buf })
  local lines = query.format_query_results(result)
  display.map_column_navigator(M.display_buf)
  display.display_results(M.display_buf, M.display_win, result.error ~= nil, query_text, lines)
  -- Results must not take focus away from edits made while a query was running.
  if vim.api.nvim_win_is_valid(focus) then
    vim.api.nvim_set_current_win(focus)
  end
end

function M.is_running()
  return active_execution ~= nil
end

local function cancel_active(quiet)
  local execution = active_execution
  if not execution then
    return
  end
  active_execution = nil -- Invalidate callbacks before signalling the process.
  if execution.request then
    execution.request:cancel()
  end
  if execution.refresh and result_context then
    pagination.state.current_page = result_context.page
  else
    pagination.reset()
  end
  if not quiet then
    vim.notify("Query cancelled", vim.log.levels.INFO)
  end
end

function M.cancel()
  cancel_active(false)
end

local function begin_execution(query_text, db, backend, refresh)
  local target_page = refresh and pagination.state.current_page
  local target_offset = refresh and pagination.get_offset()
  cancel_active(true)
  if target_page then
    pagination.state.current_page = target_page
  end
  local execution = { query_text = query_text, database = db, refresh = refresh }
  active_execution = execution
  vim.notify("Executing query… :SQLFlickCancel to cancel", vim.log.levels.INFO)
  local function finish(result)
    if active_execution ~= execution then
      return
    end
    active_execution = nil
    execution.request = nil
    if result.error then
      if refresh and result_context then
        pagination.state.current_page = result_context.page
      else
        pagination.reset()
      end
    else
      result_context =
        { database = db, backend = backend, query_text = query_text, page = pagination.state.current_page }
    end
    render_result(query_text, result)
    vim.notify(
      result.error and "Query failed" or "Query complete",
      result.error and vim.log.levels.ERROR or vim.log.levels.INFO
    )
  end
  local function run_query()
    execution.request = M.execute(query_text, db, backend, finish)
  end
  if refresh then
    execution.request =
      M.execute_with_pagination(query_text, db, backend, pagination.get_page_size(), target_offset, finish)
  elseif not pagination.can_paginate(query_text, db) then
    pagination.reset()
    run_query()
  else
    pagination.reset()
    execution.request = M.execute_count(query_text, db, backend, function(count_result)
      if active_execution ~= execution then
        return
      end
      execution.request = nil
      if count_result.error then
        -- Only a SQL count failure may fall back. A failed/cancelled transport
        -- must not cause the SQL to run again with a fresh timeout.
        if count_result.error_code and count_result.error_code ~= "query" then
          finish(count_result)
        else
          run_query()
        end
      elseif count_result.count > pagination.get_page_size() then
        pagination.init(query_text, db, backend, count_result.count)
        execution.request = M.execute_with_pagination(query_text, db, backend, pagination.get_page_size(), 0, finish)
      else
        run_query()
      end
    end)
  end
end

local function execute_query_text(query_text, db)
  result_context = nil
  begin_execution(query_text, db, config.opts.backend, false)
end

-- Show database selection
local function show_database_selector()
  local original_mode = vim.api.nvim_get_mode().mode
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
  local closing = false
  local selector_group = vim.api.nvim_create_augroup("SQLFlickSelector" .. search_win, { clear = true })

  local function close_selector()
    if closing then
      return
    end
    closing = true
    vim.api.nvim_del_augroup_by_id(selector_group)
    for _, win in ipairs({ selector_win, list_win, search_win }) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    if original_mode == "n" then
      vim.cmd("stopinsert")
    end
  end

  for _, win in ipairs({ search_win, list_win, selector_win }) do
    vim.api.nvim_create_autocmd("WinClosed", {
      group = selector_group,
      pattern = tostring(win),
      callback = function()
        vim.schedule(close_selector)
      end,
    })
  end

  vim.api.nvim_create_autocmd("WinLeave", {
    group = selector_group,
    callback = function()
      vim.schedule(function()
        if closing then
          return
        end
        local current_win = vim.api.nvim_get_current_win()
        if current_win ~= search_win and current_win ~= list_win and current_win ~= selector_win then
          close_selector()
        end
      end)
    end,
  })

  local function select_current_database()
    local items = tree.filter_items(tree.get_visible_items(root), search_term)
    local item = items[current_line]
    if item and item.is_category then
      item.expanded = not item.expanded
      items = tree.filter_items(tree.get_visible_items(root), search_term)
      selector.render_tree(list_buf, items)
      selector.update_selector_content(selector_buf, items, current_line)
    elseif item then
      M.selected_database = item.db_config
      local id = item.db_config.id or item.db_config.name
      if tree.find_database_by_id(config.opts.databases, id) then
        cache.save_selected_id(id)
      else
        cache.save_selected_id(nil)
      end
      close_selector()
    end
  end

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
    group = selector_group,
    buffer = search_buf,
    callback = function()
      search_term = vim.api.nvim_buf_get_lines(search_buf, 0, 1, false)[1]
      items = tree.filter_items(tree.get_visible_items(root), search_term)
      selector.render_tree(list_buf, items)
      if #items > 0 then
        current_line = 1
        vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
        selector.update_selector_content(selector_buf, items, current_line)
      else
        selector.update_selector_content(selector_buf, items, 1)
      end
    end,
  })

  -- Handle focus movement when exiting insert mode in search
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = selector_group,
    buffer = search_buf,
    callback = function()
      vim.schedule(function()
        if not closing and vim.api.nvim_win_is_valid(list_win) and vim.api.nvim_get_current_win() == search_win then
          vim.api.nvim_set_current_win(list_win)
        end
      end)
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
  local function move_selection(offset)
    local visible_items = tree.filter_items(tree.get_visible_items(root), search_term)
    local next_line = current_line + offset
    if next_line >= 1 and next_line <= #visible_items then
      current_line = next_line
      vim.api.nvim_win_set_cursor(list_win, { current_line, 0 })
      selector.update_selector_content(selector_buf, visible_items, current_line)
    end
  end

  vim.keymap.set("n", "j", function()
    move_selection(1)
  end, opts)

  vim.keymap.set("n", "k", function()
    move_selection(-1)
  end, opts)

  for _, buf in ipairs({ search_buf, list_buf }) do
    local modes = buf == search_buf and { "n", "i" } or { "n" }
    for _, mode in ipairs(modes) do
      vim.keymap.set(mode, "<C-n>", function()
        move_selection(1)
      end, { buffer = buf, silent = true })
      vim.keymap.set(mode, "<C-p>", function()
        move_selection(-1)
      end, { buffer = buf, silent = true })
    end
  end

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
  vim.keymap.set("n", "<CR>", select_current_database, opts)
  vim.keymap.set("i", "<CR>", select_current_database, { buffer = search_buf, silent = true })
  vim.keymap.set("n", "<CR>", select_current_database, { buffer = search_buf, silent = true })
  for _, buf in ipairs({ search_buf, list_buf, selector_buf }) do
    vim.keymap.set("n", "q", close_selector, { buffer = buf, silent = true })
  end

  -- Focus search window initially
  vim.api.nvim_set_current_win(search_win)
  vim.cmd("startinsert")

  return search_buf, search_win, list_buf, list_win, selector_buf, selector_win
end

-- Setup function that will be called by users
function M.setup(opts)
  config.setup(opts)
  pagination.set_page_size(config.opts.pagination.page_size)
  M.selected_database = tree.find_database_by_id(config.opts.databases, cache.load_selected_id())

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

  completion.setup({
    get_database = function()
      return M.selected_database
    end,
    fetch_schema = function(database, callback)
      return M.fetch_schema(database, config.opts.backend, callback)
    end,
  })

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
      { silent = true, desc = "Execute SQL statement at cursor", buffer = true }
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
    if config.opts.completion.enabled then
      completion.attach(0)
    end
  end

  local sql_filetypes = {
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
  }

  -- Set up mappings for SQL and query-related file types
  vim.api.nvim_create_autocmd("FileType", {
    pattern = sql_filetypes,
    callback = setup_query_mappings,
  })
  if vim.tbl_contains(sql_filetypes, vim.bo.filetype) then
    setup_query_mappings()
  end

  vim.api.nvim_create_user_command("SQLFlickRestart", function()
    M.restart()
  end, {})

  vim.api.nvim_create_user_command("SQLFlickRefreshSchema", function()
    completion.refresh(function(schema, err)
      if not schema then
        vim.notify("Failed to refresh SQL schema: " .. err, vim.log.levels.ERROR)
        return
      end
      vim.notify(string.format("SQL schema refreshed (%d tables/views)", #schema.tables), vim.log.levels.INFO)
    end)
  end, {})

  vim.api.nvim_create_user_command("SQLFlickCancel", function()
    M.cancel()
  end, {})

  -- Create query execution command
  vim.api.nvim_create_user_command("SQLFlickExecute", function(opts)
    local query_text = opts.args
    local db = selected_database_or_notify()
    if not db then
      return
    end

    execute_query_text(query_text, db)
  end, { nargs = 1 })

  -- Create file-based query execution command
  vim.api.nvim_create_user_command("SQLFlickExecuteBuf", function()
    local db = selected_database_or_notify()
    if not db then
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
      -- Normal mode: split only on semicolons outside comments/quoted text.
      local cursor = vim.api.nvim_win_get_cursor(0)
      local all_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local err
      query_text, err = statement.at_cursor(all_lines, cursor[1], cursor[2], db.type)
      if not query_text then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end
    end

    if query_text == "" then
      vim.notify("No query text found", vim.log.levels.ERROR)
      return
    end

    execute_query_text(query_text, db)
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
function M.execute(query_text, database, backend_config, callback)
  if not handler then
    M.setup()
  end

  return handler:execute_query(query_text, database, backend_config, callback)
end

---Execute a count query
---@param query_text string
---@param database table
---@param backend_config table
---@return { count?: number, error?: string }
function M.execute_count(query_text, database, backend_config, callback)
  if not handler then
    M.setup()
  end

  return handler:execute_count(query_text, database, backend_config, callback)
end

---Execute a query with pagination
---@param query_text string
---@param database table
---@param backend_config table
---@param limit number|nil
---@param offset number|nil
function M.execute_with_pagination(query_text, database, backend_config, limit, offset, callback)
  if not handler then
    M.setup()
  end

  return handler:execute_query_with_pagination(query_text, database, backend_config, limit, offset, callback)
end

---Fetch schema metadata for completion.
---@param database table
---@param backend_config table
---@param callback fun(result: table)|nil
---@return table|nil schema_or_request
---@return string|nil error
function M.fetch_schema(database, backend_config, callback)
  if not handler then
    handler = require("sqlflick.handler"):new(config.opts.backend.port)
  end
  return handler:fetch_schema(database, backend_config, callback)
end

---Refresh current page (reload current page data)
function M.refresh_current_page()
  if not pagination.is_enabled() or not result_context then
    return
  end
  local context = result_context
  begin_execution(context.query_text, context.database, context.backend, true)
end

---Install the backend binary
function M.install()
  require("sqlflick.install").exec()
end

function M.restart()
  cancel_active(true)
  if not handler then
    M.setup()
  end
  return handler:restart()
end

---Stop the backend process
function M.stop()
  cancel_active(true)
  if handler then
    handler:stop()
    handler = nil
  end
end

return M
