describe("SQLFlickExecuteBuf statement extraction", function()
  local saved_modules, saved_api, saved_notify
  local commands, executed, notifications, lines, cursor, mode, sqlflick, db
  local names = {
    "sqlflick", "sqlflick.config", "sqlflick.cache", "sqlflick.install",
    "sqlflick.completion", "sqlflick.highlights", "sqlflick.deps",
    "sqlflick.display", "sqlflick.query", "sqlflick.handler", "sqlflick.pagination",
  }
  local function noop() end

  before_each(function()
    saved_modules = {}
    for _, name in ipairs(names) do saved_modules[name] = package.loaded[name] end
    saved_api, saved_notify = vim.api, vim.notify
    commands, executed, notifications = {}, {}, {}
    lines, cursor, mode = { "SELECT 1;" }, { 1, 0 }, "n"
    db = { id = "test", name = "test", type = "postgresql" }
    vim.api = setmetatable({
      nvim_create_user_command = function(name, callback) commands[name] = callback end,
      nvim_create_autocmd = noop,
      nvim_get_mode = function() return { mode = mode } end,
      nvim_win_get_cursor = function() return cursor end,
      nvim_buf_get_lines = function() return lines end,
      nvim_buf_get_mark = function(_, mark) return { mark == "<" and 1 or #lines, 0 } end,
      nvim_win_is_valid = function() return true end,
      nvim_set_current_win = noop,
      nvim_set_option_value = noop,
      nvim_buf_set_lines = noop,
    }, { __index = saved_api })
    vim.notify = function(message) table.insert(notifications, message) end
    package.loaded["sqlflick"] = nil
    package.loaded["sqlflick.config"] = {
      setup = noop,
      opts = { databases = { db }, backend = {}, completion = { enabled = false } },
    }
    package.loaded["sqlflick.cache"] = { load_selected_id = function() return "test" end }
    package.loaded["sqlflick.install"] = { ensure_installed = noop }
    package.loaded["sqlflick.completion"] = { setup = noop }
    package.loaded["sqlflick.highlights"] = { setup = noop }
    package.loaded["sqlflick.deps"] = {}
    package.loaded["sqlflick.handler"] = { new = function() return {} end }
    package.loaded["sqlflick.pagination"] = { can_paginate = function() return false end, reset = noop }
    package.loaded["sqlflick.query"] = { setup = noop, format_query_results = function() return { "ok" } end }
    package.loaded["sqlflick.display"] = {
      create_display_window = function() return 101, 102 end,
      map_column_navigator = noop, display_results = noop,
    }
    sqlflick = require("sqlflick")
    sqlflick.setup({})
    sqlflick.execute = function(query)
      table.insert(executed, query)
      return { columns = {}, rows = {} }
    end
  end)

  after_each(function()
    vim.api, vim.notify = saved_api, saved_notify
    for _, name in ipairs(names) do package.loaded[name] = saved_modules[name] end
  end)

  it("executes the complete SQL across an internal blank line", function()
    lines, cursor = { "SELECT id", "", "FROM users;" }, { 3, 2 }
    commands.SQLFlickExecuteBuf({})
    assert.equals("SELECT id\n\nFROM users;", executed[1])
  end)

  it("uses the cursor column to select one statement on a shared line", function()
    lines, cursor = { "SELECT 1; SELECT 2;" }, { 1, 12 }
    commands.SQLFlickExecuteBuf({})
    assert.equals("SELECT 2;", executed[1])
  end)

  it("does not terminate a statement inside a multiline quoted value", function()
    lines, cursor = { "SELECT 'first;", "second', 1;" }, { 2, 3 }
    commands.SQLFlickExecuteBuf({})
    assert.equals(table.concat(lines, "\n"), executed[1])
  end)

  it("does not send an unterminated statement to the backend", function()
    lines = { "SELECT 'unfinished;" }
    commands.SQLFlickExecuteBuf({})
    assert.equals(0, #executed)
    assert.matches("Unterminated", notifications[1], 1, true)
  end)

  it("does not send comments alone to the backend", function()
    lines = { "-- just a comment;" }
    commands.SQLFlickExecuteBuf({})
    assert.equals(0, #executed)
  end)

  it("keeps explicit visual selections unchanged", function()
    lines, mode = { "SELECT 1;", "SELECT 2;" }, "V"
    commands.SQLFlickExecuteBuf({})
    assert.equals("SELECT 1;\nSELECT 2;", executed[1])
  end)

  it("runs only the current Redis command", function()
    db.type = "redis"
    lines, cursor = { "SET key value", "GET key" }, { 2, 0 }
    commands.SQLFlickExecuteBuf({})
    assert.equals("GET key", executed[1])
  end)
end)
