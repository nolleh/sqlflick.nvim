-- Exercise real Neovim commands, buffers, windows, and autocmds while holding
-- transport completions pending. No database connection or subprocess is needed.
describe("Asynchronous execution commands", function()
  local saved_modules, saved_notify, saved_confirm, initial_win, test_buf, autocmds_before
  local sqlflick, pending, rendered, notifications
  local db = {
    id = "test",
    name = "test",
    type = "postgresql",
    database = "test",
    host = "db.example.com",
    port = 5432,
    password = "test-secret-not-for-display",
  }
  local backend = { host = "127.0.0.1", port = 9081, timeout_ms = 500 }
  local module_names = {
    "sqlflick",
    "sqlflick.config",
    "sqlflick.cache",
    "sqlflick.install",
    "sqlflick.completion",
    "sqlflick.highlights",
    "sqlflick.deps",
    "sqlflick.display",
    "sqlflick.query",
    "sqlflick.handler",
    "sqlflick.pagination",
    "sqlflick.history",
  }

  local function noop() end

  before_each(function()
    saved_modules = {}
    for _, name in ipairs(module_names) do
      saved_modules[name] = package.loaded[name]
    end
    pending, rendered, notifications = {}, {}, {}
    saved_notify = vim.notify
    saved_confirm = vim.fn.confirm
    vim.fn.confirm = function()
      return 1
    end
    initial_win = vim.api.nvim_get_current_win()
    autocmds_before = {}
    for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = { "VimLeavePre", "FileType" } })) do
      if autocmd.id then
        autocmds_before[autocmd.id] = true
      end
    end
    test_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(initial_win, test_buf)
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, { "SELECT 1;" })
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    package.loaded["sqlflick"] = nil
    package.loaded["sqlflick.history"] = nil
    package.loaded["sqlflick.config"] = {
      opts = {
        databases = { db },
        backend = backend,
        completion = { enabled = false },
        selector = { width = 60, height = 15, border = "rounded" },
        pagination = { page_size = 20 },
        selector = { width = 60, height = 15, border = "rounded" },
      },
      setup = noop,
    }
    package.loaded["sqlflick.cache"] = {
      save_selected_id = noop,
      load_selected_id = function()
        return "test"
      end,
      save_selected_id = noop,
    }
    package.loaded["sqlflick.install"] = { ensure_installed = noop }
    package.loaded["sqlflick.completion"] = { setup = noop }
    package.loaded["sqlflick.highlights"] = { setup = noop }
    package.loaded["sqlflick.deps"] = {}
    package.loaded["sqlflick.display"] = {
      create_display_window = function()
        local buf = vim.api.nvim_create_buf(false, true)
        local win = vim.api.nvim_open_win(buf, true, {
          relative = "editor",
          row = 1,
          col = 1,
          width = 20,
          height = 3,
          style = "minimal",
        })
        return buf, win
      end,
      map_column_navigator = noop,
      display_results = function(_, _, is_error, query, lines)
        table.insert(rendered, { is_error = is_error, query = query, result = lines })
      end,
    }
    package.loaded["sqlflick.query"] = {
      setup = noop,
      format_query_results = function(result)
        return result
      end,
    }
    local pagination = {
      state = {},
      can_paginate = function(query)
        return query:match("^SELECT") ~= nil
      end,
      get_page_size = function()
        return 20
      end,
      set_page_size = noop,
      is_enabled = function()
        return true
      end,
      reset = noop,
    }
    pagination.init = function(query, database)
      pagination.state = { query_text = query, database = database, current_page = 1 }
    end
    pagination.get_offset = function()
      return (pagination.state.current_page - 1) * 20
    end
    package.loaded["sqlflick.pagination"] = pagination

    local transport = {}
    for _, method in ipairs({ "execute_query", "execute_count", "execute_query_with_pagination" }) do
      transport[method] = function(_, query, database, config, ...)
        local args = { ... }
        local callback = args[#args]
        assert.equals("function", type(callback), "command must use callback execution")
        local request = { method = method, query = query, database = database, config = config, cancels = 0 }
        if method == "execute_query_with_pagination" then
          request.offset = args[2]
        end
        function request:cancel()
          self.cancels = self.cancels + 1
        end
        function request:complete(result)
          callback(result)
        end
        table.insert(pending, request)
        return request
      end
    end
    transport.stop = noop
    package.loaded["sqlflick.handler"] = {
      new = function()
        return transport
      end,
    }
    sqlflick = require("sqlflick")
    sqlflick.setup({ databases = { db } })
  end)

  after_each(function()
    sqlflick.cancel()
    if sqlflick.display_win and vim.api.nvim_win_is_valid(sqlflick.display_win) then
      vim.api.nvim_win_close(sqlflick.display_win, true)
    end
    for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = { "VimLeavePre", "FileType" } })) do
      if autocmd.id and not autocmds_before[autocmd.id] then
        vim.api.nvim_del_autocmd(autocmd.id)
      end
    end
    for _, name in ipairs({
      "SQLFlickDebug",
      "SQLFlickHistory",
      "SQLFlickSelectDB",
      "SQLFlickAddConnection",
      "SQLFlickInstall",
      "SQLFlickRestart",
      "SQLFlickRefreshSchema",
      "SQLFlickCancel",
      "SQLFlickExecute",
      "SQLFlickExecuteBuf",
    }) do
      vim.api.nvim_del_user_command(name)
    end
    if vim.api.nvim_win_is_valid(initial_win) then
      vim.api.nvim_set_current_win(initial_win)
    end
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
    vim.notify = saved_notify
    vim.fn.confirm = saved_confirm
    for _, name in ipairs(module_names) do
      package.loaded[name] = saved_modules[name]
    end
  end)

  local function run(query)
    vim.api.nvim_cmd({ cmd = "SQLFlickExecute", args = { query or "SELECT 1;" } }, {})
  end

  it("records a single user query across count and page requests", function()
    local history = require("sqlflick.history")
    run()
    assert.equals(1, #history.list())
    assert.equals("running", history.list()[1].state)
    pending[1]:complete({ count = 21 })
    pending[2]:complete({ columns = {}, rows = {} })
    assert.equals(1, #history.list())
    assert.equals("success", history.list()[1].state)
    assert.is_nil(history.list()[1].connection.password)
    sqlflick.refresh_current_page()
    assert.equals(1, #history.list())
  end)

  it("records failures and cancellations but ignores rejected confirmation", function()
    local history = require("sqlflick.history")
    vim.fn.confirm = function()
      return 2
    end
    run()
    assert.equals(0, #history.list())
    vim.fn.confirm = function()
      return 1
    end
    run("UPDATE users SET active=1;")
    pending[1]:complete({ error = "failed" })
    assert.equals("failed", history.list()[1].state)
    run()
    sqlflick.cancel()
    pending[2]:complete({ count = 0 })
    assert.equals("cancelled", history.list()[1].state)
    assert.equals(2, #history.list())
  end)

  local function history_action(key)
    vim.cmd("SQLFlickHistory")
    local search = vim.api.nvim_get_current_buf()
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(search, "n")) do
      if map.lhs == key then
        map.callback()
        return
      end
    end
    error("history action missing: " .. key)
  end

  it("restores editable SQL without executing or changing the selection", function()
    run("UPDATE users SET active=1;")
    sqlflick.cancel()
    local other = { id = "other", name = "other" }
    sqlflick.selected_database = other
    history_action("<CR>")
    local buf = vim.api.nvim_get_current_buf()
    assert.equals("sql", vim.bo[buf].filetype)
    assert.is_true(vim.bo[buf].modifiable)
    assert.same({ "UPDATE users SET active=1;" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.same(other, sqlflick.selected_database)
    assert.equals(1, #pending)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("keeps history open after insert Escape so normal-mode actions remain available", function()
    run("UPDATE users SET active=1;")
    sqlflick.cancel()
    for _, action in ipairs({ "<CR>", "r", "<Esc>" }) do
      local count = #vim.api.nvim_list_wins()
      vim.cmd("SQLFlickHistory")
      local search = vim.api.nvim_get_current_buf()
      local keys = vim.api.nvim_replace_termcodes("i<Esc>", true, false, true)
      vim.api.nvim_feedkeys(keys, "xt", false)
      assert.equals("n", vim.api.nvim_get_mode().mode)
      assert.is_true(vim.api.nvim_buf_is_valid(search))
      assert.equals(count + 3, #vim.api.nvim_list_wins())
      keys = vim.api.nvim_replace_termcodes(action, true, false, true)
      vim.api.nvim_feedkeys(keys, "xt", false)
      assert.equals(count, #vim.api.nvim_list_wins())
      assert.is_false(vim.api.nvim_buf_is_valid(search))
      if action == "<CR>" then
        local restored = vim.api.nvim_get_current_buf()
        assert.same({ "UPDATE users SET active=1;" }, vim.api.nvim_buf_get_lines(restored, 0, -1, false))
        vim.api.nvim_buf_delete(restored, { force = true })
      elseif action == "r" then
        assert.equals(2, #pending)
        sqlflick.cancel()
      end
    end
  end)

  it("filters SQL literally and cleans up all picker windows on acceptance", function()
    run("UPDATE users SET label='100%';")
    sqlflick.cancel()
    run("UPDATE users SET label='other';")
    sqlflick.cancel()
    local count = #vim.api.nvim_list_wins()
    vim.cmd("SQLFlickHistory")
    local search = vim.api.nvim_get_current_buf()
    assert.equals(count + 3, #vim.api.nvim_list_wins())
    vim.api.nvim_buf_set_lines(search, 0, -1, false, { "100%" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = search })
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(search, "n")) do
      if map.lhs == "<CR>" then
        map.callback()
        break
      end
    end
    assert.equals(count, #vim.api.nvim_list_wins())
    local restored = vim.api.nvim_get_current_buf()
    assert.same({ "UPDATE users SET label='100%';" }, vim.api.nvim_buf_get_lines(restored, 0, -1, false))
    assert.is_false(vim.api.nvim_buf_is_valid(search))
    vim.api.nvim_buf_delete(restored, { force = true })
  end)

  it("replays on the original connection after explicit confirmation", function()
    run("UPDATE users SET active=1;")
    sqlflick.cancel()
    sqlflick.selected_database = { id = "other", name = "other" }
    vim.fn.confirm = function(message, _, default)
      assert.is_truthy(message:find("test/test", 1, true))
      assert.is_truthy(message:find("UPDATE users SET active=1;", 1, true))
      assert.equals(2, default)
      return 1
    end
    history_action("r")
    assert.equals(2, #pending)
    assert.same(db, pending[2].database)
    assert.equals("running", require("sqlflick.history").list()[1].state)
  end)

  it("does not replay a missing connection or a declined confirmation", function()
    run("UPDATE users SET active=1;")
    sqlflick.cancel()
    vim.fn.confirm = function()
      return 2
    end
    history_action("r")
    assert.equals(1, #pending)
    package.loaded["sqlflick.config"].opts.databases = {}
    vim.fn.confirm = function()
      error("must not confirm a missing connection")
    end
    history_action("r")
    assert.equals(1, #pending)
  end)

  it("replays history on an imported SQLite file with a memory journal", function()
    local original_input = vim.ui.input
    vim.ui.input = function(_, callback)
      callback("imported sqlite")
    end
    local ok, err = pcall(sqlflick.add_connection, "file:./app.db?_journal_mode=memory")
    vim.ui.input = original_input
    assert.is_true(ok, err)
    local search = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(search, 0, -1, false, { "imported sqlite" })
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = search })
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(search, "n")) do
      if map.lhs == "<CR>" then
        map.callback()
        break
      end
    end
    local imported = sqlflick.selected_database
    assert.equals("imported sqlite", imported.name)
    run("UPDATE items SET active=1;")
    sqlflick.cancel()
    history_action("r")
    assert.equals(2, #pending)
    assert.equals(imported, pending[2].database)
    assert.matches("_journal_mode=memory", pending[2].database.url, 1, true)
    assert.is_nil(require("sqlflick.history").list()[1].connection.url)
  end)

  it("reports the selected cached connection before confirmation", function()
    assert.same({ name = "test", database = "test", state = "confirm" }, sqlflick.status())
    vim.fn.confirm = function()
      return 2
    end
    run()
    assert.equals("confirm", sqlflick.status().state)
  end)

  it("reports running and idle connection states", function()
    run()
    assert.same({
      name = "test",
      database = "test",
      state = "running",
      running = { name = "test", database = "test", is_selected = true },
    }, sqlflick.status())
    pending[1]:complete({ count = 1 })
    pending[2]:complete({ columns = {}, rows = {} })
    assert.same({ name = "test", database = "test", state = "idle" }, sqlflick.status())
  end)

  it("returns an empty status without a selected connection", function()
    sqlflick.selected_database = nil
    assert.is_nil(sqlflick.status())
    assert.equals("", sqlflick.statusline())
  end)

  it("sanitizes control characters and statusline percent signs", function()
    sqlflick.selected_database = { name = "prod%\nname", database = "app%db" }
    assert.equals("prod%\nname", sqlflick.status().name)
    local rendered_status = vim.api.nvim_eval_statusline(sqlflick.statusline(), {}).str
    assert.equals("󰆼  prod% name/app%db ", rendered_status)
  end)

  it("returns independent credential-free snapshots", function()
    local status = sqlflick.status()
    assert.is_nil(status.password)
    assert.is_nil(status.host)
    status.name = "changed"
    assert.equals("test", sqlflick.status().name)
    assert.equals("test", db.name)

    run()
    status = sqlflick.status()
    status.running.name = "changed"
    assert.equals("test", sqlflick.status().running.name)
    assert.is_nil(status.running.password)
  end)

  it("shows the cached target with q as cancel and cancellation as the default", function()
    vim.fn.confirm = function(message, choices, default)
      assert.is_truthy(message:find("Name: test", 1, true))
      assert.is_truthy(message:find("Type: postgresql", 1, true))
      assert.is_truthy(message:find("Host: db.example.com", 1, true))
      assert.is_truthy(message:find("Port: 5432", 1, true))
      assert.is_truthy(message:find("Database: test", 1, true))
      assert.is_nil(message:find(db.password, 1, true))
      assert.equals("&Run\n&Quit (cancel)", choices)
      assert.equals(2, default)
      assert.equals(0, #pending)
      assert.equals(0, #rendered)
      assert.is_false(sqlflick.is_running())
      return 2
    end
    run()
    assert.equals(0, #pending)
  end)

  for _, choice in ipairs({ 0, 2 }) do
    for _, command in ipairs({ "SQLFlickExecute", "SQLFlickExecuteBuf" }) do
      it("sends no COUNT or query after confirmation choice " .. choice .. " in " .. command, function()
        local confirmations = 0
        vim.fn.confirm = function()
          confirmations = confirmations + 1
          return choice
        end
        local windows = #vim.api.nvim_list_wins()
        for _ = 1, 2 do
          if command == "SQLFlickExecute" then
            run()
          else
            vim.cmd(command)
          end
        end
        assert.equals(2, confirmations) -- Cancellation must not acknowledge the connection.
        assert.equals(0, #pending)
        assert.equals(0, #rendered)
        assert.is_false(sqlflick.is_running())
        assert.equals(windows, #vim.api.nvim_list_wins())
        assert.equals(initial_win, vim.api.nvim_get_current_win())
      end)
    end
  end

  it("also blocks write statements when confirmation is cancelled", function()
    vim.fn.confirm = function()
      return 2
    end
    run("UPDATE users SET active = 1;")
    assert.equals(0, #pending)
  end)

  it("asks once across both query commands after approval", function()
    local confirmations = 0
    vim.fn.confirm = function()
      confirmations = confirmations + 1
      return 1
    end
    run()
    vim.cmd("SQLFlickExecuteBuf")
    assert.equals(1, confirmations)
    assert.equals(2, #pending)
  end)

  it("does not ask after explicitly selecting even the cached database", function()
    vim.cmd("SQLFlickSelectDB")
    local search_buf = vim.api.nvim_get_current_buf()
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(search_buf, "n")) do
      if map.lhs == "<CR>" then
        map.callback()
        break
      end
    end
    vim.fn.confirm = function()
      error("explicit selection must skip confirmation")
    end
    assert.equals("idle", sqlflick.status().state)
    run()
    assert.equals(1, #pending)
  end)

  it("returns from the query command while COUNT is still pending", function()
    run()
    assert.equals(1, #pending)
    assert.equals("execute_count", pending[1].method)
    assert.equals(0, #rendered)
    assert.is_true(sqlflick.is_running())
  end)

  it("starts the first page only after COUNT completes and renders only completed results", function()
    run()
    assert.equals("Executing query… :SQLFlickCancel to cancel", notifications[#notifications])
    pending[1]:complete({ count = 21 })
    assert.equals(2, #pending)
    assert.equals("execute_query_with_pagination", pending[2].method)
    assert.equals(0, #rendered)
    pending[2]:complete({ columns = { "id" }, rows = { { 1 } } })
    assert.equals(1, #rendered)
    assert.equals(1, rendered[1].result.rows[1][1])
    assert.is_false(sqlflick.is_running())
    assert.equals("Query complete", notifications[#notifications])
  end)

  it("runs write statements asynchronously without COUNT", function()
    run("UPDATE users SET active = 1;")
    assert.equals(1, #pending)
    assert.equals("execute_query", pending[1].method)
    assert.equals(0, #rendered)
    pending[1]:complete({ columns = {}, rows = {} })
    assert.equals(1, #rendered)
  end)

  it("supports the buffer execution command without waiting for a result", function()
    vim.cmd("SQLFlickExecuteBuf")
    assert.equals(1, #pending)
    assert.equals("SELECT 1;", pending[1].query)
    assert.equals(0, #rendered)
  end)

  it("cancels a pending COUNT and ignores its late successful completion", function()
    run()
    assert.is_truthy(vim.api.nvim_get_commands({}).SQLFlickCancel)
    vim.cmd("SQLFlickCancel")
    assert.equals(1, pending[1].cancels)
    pending[1]:complete({ count = 21 })
    assert.equals(1, #pending)
    assert.equals(0, #rendered)
    assert.equals("Query cancelled", notifications[#notifications])
    assert.equals("idle", sqlflick.status().state)
  end)

  it("cancels the page request after COUNT has already completed", function()
    run()
    pending[1]:complete({ count = 21 })
    vim.cmd("SQLFlickCancel")
    assert.equals(0, pending[1].cancels)
    assert.equals(1, pending[2].cancels)
    pending[2]:complete({ columns = { "id" }, rows = { { 1 } } })
    assert.equals(0, #rendered)
  end)

  it("does not retry the original SQL when COUNT times out", function()
    run()
    pending[1]:complete({ error = "query timed out", error_code = "timeout" })
    assert.equals(1, #pending)
    assert.equals(1, #rendered)
    assert.is_true(rendered[1].is_error)
    assert.is_false(sqlflick.is_running())
    assert.equals("Query failed", notifications[#notifications])
  end)

  it("a new execution supersedes the old one and ignores old results", function()
    run("UPDATE users SET active = 1;")
    run("UPDATE users SET active = 0;")
    assert.equals(1, pending[1].cancels)
    pending[2]:complete({ columns = { "value" }, rows = { { "new" } } })
    pending[1]:complete({ columns = { "value" }, rows = { { "old" } } })
    assert.equals(1, #rendered)
    assert.equals("new", rendered[1].result.rows[1][1])
    assert.equals("Query complete", notifications[#notifications])
  end)

  it("can cancel while idle without starting work", function()
    assert.is_truthy(vim.api.nvim_get_commands({}).SQLFlickCancel)
    vim.cmd("SQLFlickCancel")
    assert.equals(0, #pending)
  end)

  it("pins a running execution to its original database", function()
    run()
    sqlflick.selected_database = { id = "other", name = "other", type = "mysql", database = "other" }
    assert.same({
      name = "other",
      database = "other",
      state = "running",
      running = { name = "test", database = "test", is_selected = false },
    }, sqlflick.status())
    assert.equals("󰆼  other/other 󰑮 test/test ", vim.api.nvim_eval_statusline(sqlflick.statusline(), {}).str)
    pending[1]:complete({ count = 21 })
    assert.same(db, pending[2].database)
  end)

  it("refreshes pages asynchronously using the result's database", function()
    run()
    pending[1]:complete({ count = 21 })
    pending[2]:complete({ columns = { "id" }, rows = { { 1 } } })
    sqlflick.selected_database = { id = "other", type = "mysql", database = "other" }
    sqlflick.refresh_current_page()
    assert.equals(3, #pending)
    assert.equals("execute_query_with_pagination", pending[3].method)
    assert.same(db, pending[3].database)
    assert.equals(1, #rendered)
    pending[3]:complete({ columns = { "id" }, rows = { { 21 } } })
    assert.equals(2, #rendered)
    assert.equals(21, rendered[2].result.rows[1][1])
  end)

  it("cancels the pending request when Neovim exits", function()
    run("UPDATE users SET active = 1;")
    vim.api.nvim_exec_autocmds("VimLeavePre", {})
    assert.equals(1, pending[1].cancels)
  end)

  it("preserves the user's current focus when an asynchronous result arrives", function()
    run("UPDATE users SET active = 1;")
    vim.cmd("vsplit")
    local focus = vim.api.nvim_get_current_win()
    pending[1]:complete({ columns = {}, rows = {} })
    assert.not_equals(focus, sqlflick.display_win)
    assert.equals(focus, vim.api.nvim_get_current_win())
    vim.cmd("close")
  end)

  it("keeps the newly requested page when superseding an in-flight page refresh", function()
    run()
    pending[1]:complete({ count = 61 })
    pending[2]:complete({ columns = { "id" }, rows = { { 1 } } })
    local state = package.loaded["sqlflick.pagination"].state
    state.current_page = 2
    sqlflick.refresh_current_page()
    assert.equals(20, pending[3].offset)
    state.current_page = 3
    sqlflick.refresh_current_page()
    assert.equals(1, pending[3].cancels)
    assert.equals(40, pending[4].offset)
    pending[3]:complete({ columns = { "id" }, rows = { { 21 } } })
    pending[4]:complete({ columns = { "id" }, rows = { { 41 } } })
    assert.equals(2, #rendered)
    assert.equals(41, rendered[2].result.rows[1][1])
  end)
end)
