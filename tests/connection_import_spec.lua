describe("Visual connection imports", function()
  local sqlflick, saved, cached, input_callback, notices, origin, buffer, initial_windows, commands, autocmds
  local modules =
    { "sqlflick", "sqlflick.config", "sqlflick.cache", "sqlflick.install", "sqlflick.completion", "sqlflick.handler" }
  local function noop() end
  local function press_enter()
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
      if map.lhs == "<CR>" then
        map.callback()
        return
      end
    end
    error("picker did not open")
  end
  local function picker_lines()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not initial_windows[win] and vim.api.nvim_win_get_height(win) > 1 then
        local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
        if table.concat(lines, "\n"):find("imported", 1, true) then
          return lines
        end
      end
    end
    return {}
  end

  before_each(function()
    saved = { input = vim.ui.input, notify = vim.notify }
    for _, name in ipairs(modules) do
      saved[name] = package.loaded[name]
    end
    package.loaded["sqlflick"] = nil
    package.loaded["sqlflick.config"] = nil
    package.loaded["sqlflick.install"] = { ensure_installed = noop }
    package.loaded["sqlflick.completion"] = { setup = noop }
    package.loaded["sqlflick.handler"] = {
      new = function()
        return { stop = noop }
      end,
    }
    package.loaded["sqlflick.cache"] = {
      load_selected_id = noop,
      save_selected_id = function(id)
        table.insert(cached, id or false)
      end,
    }
    cached, notices = {}, {}
    vim.ui.input = function(opts, callback)
      assert.is_nil(opts.default:find("secret", 1, true))
      input_callback = callback
    end
    vim.notify = function(message)
      notices[#notices + 1] = message
    end
    origin = vim.api.nvim_get_current_win()
    initial_windows = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      initial_windows[win] = true
    end
    commands = vim.api.nvim_get_commands({})
    autocmds = {}
    for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
      if autocmd.id then
        autocmds[autocmd.id] = true
      end
    end
    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(origin, buffer)
    vim.bo[buffer].filetype = "yaml"
    sqlflick = require("sqlflick")
    sqlflick.setup({ databases = {}, database_url = false, completion = { enabled = false } })
    sqlflick.execute = function()
      error("import must not execute queries")
    end
  end)

  after_each(function()
    vim.cmd("stopinsert")
    vim.cmd("normal! " .. string.char(27))
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not initial_windows[win] and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    vim.wait(20, function()
      return false
    end)
    for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
      if autocmd.id and not autocmds[autocmd.id] then
        pcall(vim.api.nvim_del_autocmd, autocmd.id)
      end
    end
    for name in pairs(vim.api.nvim_get_commands({})) do
      if not commands[name] then
        vim.api.nvim_del_user_command(name)
      end
    end
    pcall(vim.keymap.del, "x", "<leader>sa")
    vim.api.nvim_set_current_win(origin)
    vim.api.nvim_buf_delete(buffer, { force = true })
    vim.ui.input, vim.notify = saved.input, saved.notify
    for _, name in ipairs(modules) do
      package.loaded[name] = saved[name]
    end
  end)

  it("imports a character selection from a YAML file and selects it without caching credentials", function()
    local url = "mysql://app:secret@localhost/app"
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "url: '" .. url .. "' # other text" })
    vim.api.nvim_win_set_cursor(origin, { 1, 6 })
    vim.cmd("normal! v" .. (#url - 1) .. "l")
    local mapping = vim.fn.maparg("<leader>sa", "x", false, true)
    mapping.callback()
    assert.equals(0, #cached)
    assert.is_nil(sqlflick.selected_database)
    input_callback("imported mysql")
    assert.is_truthy(table.concat(picker_lines(), "\n"):find("imported mysql", 1, true))
    press_enter()
    assert.equals("mysql", sqlflick.selected_database.type)
    assert.equals("secret", sqlflick.selected_database.password)
    assert.same({ false }, cached)
  end)

  it("uses Visual marks for the range command without including surrounding text", function()
    local url = "postgres://app:secret@localhost/app"
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "url: '" .. url .. "'" })
    vim.api.nvim_win_set_cursor(origin, { 1, 6 })
    vim.cmd("normal! v" .. (#url - 1) .. "l" .. string.char(27))
    vim.cmd("'<,'>SQLFlickAddConnection")
    input_callback("imported postgres")
    press_enter()
    assert.equals(url, sqlflick.selected_database.url)
  end)

  it("keeps the selection unchanged and adds nothing when naming is cancelled", function()
    local prior = { name = "existing" }
    sqlflick.selected_database = prior
    sqlflick.add_connection("redis://localhost/2")
    input_callback(nil)
    assert.equals(prior, sqlflick.selected_database)
    assert.equals(0, #cached)
    assert.same({}, picker_lines())
  end)

  it("rejects invalid URLs without displaying credentials or prompting", function()
    input_callback = nil
    sqlflick.add_connection("unsupported://app:secret@localhost/app")
    assert.is_nil(input_callback)
    assert.equals(1, #notices)
    assert.is_nil(notices[1]:find("secret", 1, true))
  end)

  it("rejects names already used inside configured groups", function()
    sqlflick.setup({ databases = { dev = { { name = "taken", type = "sqlite", database = "app.db" } } } })
    sqlflick.add_connection("redis://localhost/2")
    input_callback("taken")
    assert.equals(1, #notices)
    assert.same({}, picker_lines())
  end)

  it("accepts quoted URLs and retains session connections across setup", function()
    sqlflick.add_connection('  "redis://localhost/2"  ')
    input_callback("imported redis")
    press_enter()
    sqlflick.setup({})
    vim.cmd("SQLFlickSelectDB")
    assert.is_truthy(table.concat(picker_lines(), "\n"):find("imported redis", 1, true))
  end)

  it("requires a selection for the command", function()
    input_callback = nil
    vim.cmd("SQLFlickAddConnection")
    assert.is_nil(input_callback)
    assert.equals(1, #notices)
  end)

  it("respects an exclusive selection without dropping the final URL character", function()
    local saved_selection = vim.o.selection
    vim.o.selection = "exclusive"
    local url = "redis://localhost/2"
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { url .. " # comment" })
    vim.api.nvim_win_set_cursor(origin, { 1, 0 })
    vim.cmd("normal! v" .. #url .. "l")
    local mapping = vim.fn.maparg("<leader>sa", "x", false, true)
    mapping.callback()
    vim.o.selection = saved_selection
    input_callback("imported exclusive")
    press_enter()
    assert.equals("2", sqlflick.selected_database.database)
  end)
end)
