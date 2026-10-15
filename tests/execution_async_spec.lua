-- Exercise command orchestration while holding transport completions pending.
-- There are no database connections, subprocesses, or timing sleeps here.
describe("Asynchronous execution commands", function()
  local saved_modules, saved_api, saved_notify
  local sqlflick, commands, pending, rendered, autocmds, notifications, focus
  local db = { id = "test", name = "test", type = "postgresql", database = "test" }
  local backend = { host = "127.0.0.1", port = 9081, timeout_ms = 500 }
  local module_names = {
    "sqlflick", "sqlflick.config", "sqlflick.cache", "sqlflick.install",
    "sqlflick.completion", "sqlflick.highlights", "sqlflick.deps",
    "sqlflick.display", "sqlflick.query", "sqlflick.handler", "sqlflick.pagination",
  }

  local function noop() end

  before_each(function()
    saved_modules = {}
    for _, name in ipairs(module_names) do
      saved_modules[name] = package.loaded[name]
    end
    commands, pending, rendered, autocmds, notifications = {}, {}, {}, {}, {}
    focus = 50
    saved_api, saved_notify = vim.api, vim.notify
    vim.api = setmetatable({
      nvim_create_user_command = function(name, callback) commands[name] = callback end,
      nvim_create_autocmd = function(event, opts) autocmds[event] = opts.callback end,
      nvim_win_is_valid = function() return true end,
      nvim_get_current_win = function() return focus end,
      nvim_buf_is_valid = function() return true end,
      nvim_set_current_win = function(win) focus = win end,
      nvim_set_option_value = noop,
      nvim_buf_set_lines = noop,
      nvim_get_mode = function() return { mode = "n" } end,
      nvim_win_get_cursor = function() return { 1, 0 } end,
      nvim_buf_get_lines = function() return { "SELECT 1;" } end,
    }, { __index = saved_api })
    vim.notify = function(message) table.insert(notifications, message) end

    package.loaded["sqlflick"] = nil
    package.loaded["sqlflick.config"] = {
      opts = { databases = { db }, backend = backend, completion = { enabled = false } },
      setup = noop,
    }
    package.loaded["sqlflick.cache"] = { load_selected_id = function() return "test" end }
    package.loaded["sqlflick.install"] = { ensure_installed = noop }
    package.loaded["sqlflick.completion"] = { setup = noop }
    package.loaded["sqlflick.highlights"] = { setup = noop }
    package.loaded["sqlflick.deps"] = {}
    package.loaded["sqlflick.display"] = {
      create_display_window = function() focus = 102; return 101, 102 end,
      map_column_navigator = noop,
      display_results = function(_, _, is_error, query, lines)
        table.insert(rendered, { is_error = is_error, query = query, result = lines })
      end,
    }
    package.loaded["sqlflick.query"] = {
      setup = noop,
      format_query_results = function(result) return result end,
    }
    local pagination = {
      state = {},
      can_paginate = function(query) return query:match("^SELECT") ~= nil end,
      get_page_size = function() return 20 end,
      is_enabled = function() return true end,
      reset = noop,
    }
    pagination.init = function(query, database)
      pagination.state = { query_text = query, database = database, current_page = 1 }
    end
    pagination.get_offset = function() return (pagination.state.current_page - 1) * 20 end
    package.loaded["sqlflick.pagination"] = pagination

    local transport = {}
    for _, method in ipairs({ "execute_query", "execute_count", "execute_query_with_pagination" }) do
      transport[method] = function(_, query, database, config, ...)
        local args = { ... }
        local callback = args[#args]
        assert.equals("function", type(callback), "command must use callback execution")
        local request = { method = method, query = query, database = database, config = config, cancels = 0 }
        if method == "execute_query_with_pagination" then request.offset = args[2] end
        function request:cancel() self.cancels = self.cancels + 1 end
        function request:complete(result) callback(result) end
        table.insert(pending, request)
        return request
      end
    end
    transport.stop = noop
    package.loaded["sqlflick.handler"] = { new = function() return transport end }
    sqlflick = require("sqlflick")
    sqlflick.setup({ databases = { db } })
  end)

  after_each(function()
    vim.api, vim.notify = saved_api, saved_notify
    for _, name in ipairs(module_names) do
      package.loaded[name] = saved_modules[name]
    end
  end)

  local function run(query)
    commands.SQLFlickExecute({ args = query or "SELECT 1;" })
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
    pending[1]:complete({ count = 21 })
    assert.equals(2, #pending)
    assert.equals("execute_query_with_pagination", pending[2].method)
    assert.equals(0, #rendered)
    pending[2]:complete({ columns = { "id" }, rows = { { 1 } } })
    assert.equals(1, #rendered)
    assert.equals(1, rendered[1].result.rows[1][1])
    assert.is_false(sqlflick.is_running())
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
    commands.SQLFlickExecuteBuf({})
    assert.equals(1, #pending)
    assert.equals(0, #rendered)
  end)

  it("cancels a pending COUNT and ignores its late successful completion", function()
    run()
    assert.equals("function", type(commands.SQLFlickCancel))
    commands.SQLFlickCancel({})
    assert.equals(1, pending[1].cancels)
    pending[1]:complete({ count = 21 })
    assert.equals(1, #pending)
    assert.equals(0, #rendered)
  end)

  it("cancels the page request after COUNT has already completed", function()
    run()
    pending[1]:complete({ count = 21 })
    commands.SQLFlickCancel({})
    assert.equals(0, pending[1].cancels)
    assert.equals(1, pending[2].cancels)
    pending[2]:complete({ columns = { "id" }, rows = { { 1 } } })
    assert.equals(0, #rendered)
  end)

  it("does not retry the original SQL when COUNT times out", function()
    run()
    pending[1]:complete({ error = "query timed out", error_code = "timeout" })
    assert.equals(1, #pending)
  end)

  it("a new execution supersedes the old one and ignores old results", function()
    run("UPDATE users SET active = 1;")
    run("UPDATE users SET active = 0;")
    assert.equals(1, pending[1].cancels)
    pending[2]:complete({ columns = { "value" }, rows = { { "new" } } })
    pending[1]:complete({ columns = { "value" }, rows = { { "old" } } })
    assert.equals(1, #rendered)
    assert.equals("new", rendered[1].result.rows[1][1])
  end)

  it("can cancel while idle without starting work", function()
    assert.equals("function", type(commands.SQLFlickCancel))
    commands.SQLFlickCancel({})
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
    autocmds.VimLeavePre()
    assert.equals(1, pending[1].cancels)
  end)

  it("preserves the user's current focus when an asynchronous result arrives", function()
    run("UPDATE users SET active = 1;")
    focus = 77 -- The user changed windows while the query was pending.
    pending[1]:complete({ columns = {}, rows = {} })
    assert.equals(77, focus)
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
