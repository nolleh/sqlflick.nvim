local databases = {
  { name = "local_postgres", type = "postgresql", database = "first" },
  { name = "local_mysql", type = "mysql", database = "second" },
  dev = {
    { name = "dev_postgres", type = "postgresql", database = "dev" },
  },
  prod = {
    { name = "prod_mysql", type = "mysql", database = "prod" },
  },
}

package.loaded["sqlflick.install"] = { ensure_installed = function() end }
package.loaded["sqlflick.cache"] = {
  load_selected_id = function() end,
  save_selected_id = function() end,
}

local sqlflick = require("sqlflick")
sqlflick.setup({ databases = databases })

local function open_selector()
  vim.cmd("SQLFlickSelectDB")

  local windows = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == "editor" then
      table.insert(windows, win)
    end
  end
  assert.equals(3, #windows)

  local search_win, list_win, details_win
  for _, win in ipairs(windows) do
    local height = vim.api.nvim_win_get_height(win)
    local width = vim.api.nvim_win_get_width(win)
    if height == 1 then
      search_win = win
    elseif width < 30 then
      list_win = win
    else
      details_win = win
    end
  end
  assert.is_truthy(search_win)
  assert.is_truthy(list_win)
  assert.is_truthy(details_win)
  return search_win, list_win, details_win
end

local function press(buf, mode, lhs)
  for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if keymap.lhs:lower() == lhs:lower() then
      keymap.callback()
      return
    end
  end
  error("Missing selector keymap: " .. mode .. " " .. lhs)
end

describe("Database selector", function()
  it("resolves cached IDs from current config only when unique", function()
    local tree = require("sqlflick.tree")
    assert.equals(databases.dev[1], tree.find_database_by_id(databases, "dev_postgres"))
    local updated = { id = "production", name = "prod", password = "current-secret" }
    assert.equals(updated, tree.find_database_by_id({ updated }, "production"))
    assert.is_nil(tree.find_database_by_id(databases, "missing"))
    assert.is_nil(tree.find_database_by_id({ databases[1], databases[1] }, "local_postgres"))
  end)

  it("requires a selected database before either query command runs", function()
    sqlflick.selected_database = nil
    local original_execute = sqlflick.execute
    local original_notify = vim.notify
    local executed = false
    local notifications = {}
    sqlflick.execute = function()
      executed = true
    end
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    vim.cmd("SQLFlickExecute SELECT 1")
    vim.cmd("SQLFlickExecuteBuf")

    sqlflick.execute = original_execute
    vim.notify = original_notify
    assert.is_false(executed)
    assert.equals(2, #notifications)
    assert.matches("SQLFlickSelectDB", notifications[1])
  end)

  it("keeps the selector open while moving between its windows", function()
    local search_win, list_win, details_win = open_selector()

    vim.api.nvim_set_current_win(list_win)
    assert.is_true(vim.wait(100, function()
      return vim.api.nvim_get_current_win() == list_win
    end))
    assert.is_true(vim.api.nvim_win_is_valid(search_win))
    assert.is_true(vim.api.nvim_win_is_valid(details_win))

    press(vim.api.nvim_win_get_buf(list_win), "n", "q")
  end)

  for _, focused_window in ipairs({ "search", "list" }) do
    it("closes all selector windows when focus leaves the " .. focused_window .. " window", function()
      local original_win = vim.api.nvim_get_current_win()
      local search_win, list_win, details_win = open_selector()
      if focused_window == "list" then
        vim.api.nvim_set_current_win(list_win)
      end

      vim.api.nvim_set_current_win(original_win)
      assert.is_true(vim.wait(1000, function()
        return not vim.api.nvim_win_is_valid(search_win)
          and not vim.api.nvim_win_is_valid(list_win)
          and not vim.api.nvim_win_is_valid(details_win)
      end))
      assert.equals(original_win, vim.api.nvim_get_current_win())
    end)
  end

  it("selects the filtered database with Enter in the search input", function()
    local search_win, list_win, details_win = open_selector()
    local search_buf = vim.api.nvim_win_get_buf(search_win)

    vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { "local_mysql" })
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = search_buf })
    press(search_buf, "i", "<CR>")

    assert.equals("local_mysql", sqlflick.selected_database.name)
    assert.is_false(vim.api.nvim_win_is_valid(search_win))
    assert.is_false(vim.api.nvim_win_is_valid(list_win))
    assert.is_false(vim.api.nvim_win_is_valid(details_win))
    assert.equals("n", vim.api.nvim_get_mode().mode)
  end)

  it("expands and collapses a database group with Enter", function()
    local search_win, list_win, details_win = open_selector()
    local search_buf = vim.api.nvim_win_get_buf(search_win)
    local list_buf = vim.api.nvim_win_get_buf(list_win)

    vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { "dev" })
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = search_buf })
    assert.same({ "▶ dev" }, vim.api.nvim_buf_get_lines(list_buf, 0, -1, false))

    press(search_buf, "i", "<CR>")
    assert.same({ "▼ dev", "    dev_postgres" }, vim.api.nvim_buf_get_lines(list_buf, 0, -1, false))
    assert.is_true(vim.api.nvim_win_is_valid(details_win))

    press(list_buf, "n", "<CR>")
    assert.same({ "▶ dev" }, vim.api.nvim_buf_get_lines(list_buf, 0, -1, false))
    assert.is_true(vim.api.nvim_win_is_valid(search_win))

    press(list_buf, "n", "q")
  end)

  it("moves the filtered selection with Ctrl+n and Ctrl+p from the search input", function()
    local search_win, list_win, details_win = open_selector()
    local search_buf = vim.api.nvim_win_get_buf(search_win)
    local list_buf = vim.api.nvim_win_get_buf(list_win)

    vim.api.nvim_buf_set_lines(search_buf, 0, -1, false, { "local_" })
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = search_buf })

    press(search_buf, "i", "<C-n>")
    assert.equals(2, vim.api.nvim_win_get_cursor(list_win)[1])
    assert.equals(
      "Name: local_mysql",
      vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(details_win), 2, 3, false)[1]
    )

    press(search_buf, "i", "<C-p>")
    assert.equals(1, vim.api.nvim_win_get_cursor(list_win)[1])

    press(list_buf, "n", "<C-n>")
    press(search_buf, "i", "<CR>")
    assert.equals("local_mysql", sqlflick.selected_database.name)
  end)

  for _, closed_window in ipairs({ "search", "list", "details" }) do
    it("closes the other selector windows when the " .. closed_window .. " window closes", function()
      local search_win, list_win, details_win = open_selector()
      local windows = { search = search_win, list = list_win, details = details_win }

      vim.api.nvim_win_close(windows[closed_window], true)
      assert.is_true(vim.wait(1000, function()
        return not vim.api.nvim_win_is_valid(search_win)
          and not vim.api.nvim_win_is_valid(list_win)
          and not vim.api.nvim_win_is_valid(details_win)
      end))
    end)
  end
end)
