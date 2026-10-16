-- Exercise real Neovim commands, buffers, windows, and autocmds while holding
-- transport completions pending. No database connection or subprocess is needed.
describe("Asynchronous execution commands", function()
  local saved_modules, saved_notify, initial_win, test_buf, autocmds_before
  local sqlflick, pending, rendered, notifications
  local db = { id = "test", name = "test", type = "postgresql", database = "test" }
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
  }

  local function noop() end

  before_each(function()
    saved_modules = {}
    for _, name in ipairs(module_names) do
      saved_modules[name] = package.loaded[name]
    end
    pending, rendered, notifications = {}, {}, {}
    saved_notify = vim.notify
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
    package.loaded["sqlflick.config"] = {
      opts = {
        databases = { db },
        backend = backend,
        completion = { enabled = false },
        pagination = { page_size = 20 },
      },
      setup = noop,
    }
    package.loaded["sqlflick.cache"] = {
      load_selected_id = function()
        return "test"
      end,
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
      "SQLFlickSelectDB",
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
    for _, name in ipairs(module_names) do
      package.loaded[name] = saved_modules[name]
    end
  end)

  local function run(query)
    vim.api.nvim_cmd({ cmd = "SQLFlickExecute", args = { query or "SELECT 1;" } }, {})
  end

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
    sqlflick.selected_database = { id = "other", type = "mysql", database = "other" }
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
