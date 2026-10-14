local databases = {
  { name = "local_postgres", type = "postgresql", database = "first" },
  { name = "local_mysql", type = "mysql", database = "second" },
}

package.loaded["sqlflick.install"] = { ensure_installed = function() end }
package.loaded["sqlflick.cache"] = {
  load_cache = function() end,
  save_cache = function() end,
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
    if keymap.lhs == lhs then
      keymap.callback()
      return
    end
  end
  error("Missing selector keymap: " .. mode .. " " .. lhs)
end

describe("Database selector", function()
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
