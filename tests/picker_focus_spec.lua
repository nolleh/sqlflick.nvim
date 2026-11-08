describe("Picker focus", function()
  local original, origin, windows_before, buffers_before

  before_each(function()
    original = vim.api.nvim_get_current_win()
    windows_before, buffers_before = {}, {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      windows_before[win] = true
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      buffers_before[buf] = true
    end
    vim.cmd("tabnew")
    origin = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(original)
    -- Let pending WinEnter/WinClosed cleanup finish before removing fixtures.
    vim.wait(20, function()
      return false
    end)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not windows_before[win] and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if not buffers_before[buf] and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end)

  local function open_float()
    return vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
      relative = "editor",
      width = 20,
      height = 3,
      row = 1,
      col = 1,
      style = "minimal",
    })
  end

  local function open_picker(accept, replay)
    local old = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      old[win] = true
    end
    require("sqlflick.picker").open({
      items = function()
        return { "SELECT 1" }
      end,
      search = function(item)
        return item
      end,
      label = function(item)
        return item
      end,
      preview = function(item)
        return { item }
      end,
      accept = accept or function() end,
      replay = replay or function() end,
    })
    local windows, buffers = {}, {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not old[win] then
        windows[#windows + 1] = win
        buffers[#buffers + 1] = vim.api.nvim_win_get_buf(win)
      end
    end
    assert.equals(3, #windows)
    return windows, buffers
  end

  local function assert_cleaned(windows, buffers)
    assert.is_true(vim.wait(200, function()
      for _, win in ipairs(windows) do
        if vim.api.nvim_win_is_valid(win) then
          return false
        end
      end
      return true
    end))
    for _, buf in ipairs(buffers) do
      assert.is_false(vim.api.nvim_buf_is_valid(buf))
    end
  end

  it("lets Neovim return to the previous editor after closing a current float", function()
    vim.cmd("vsplit")
    vim.api.nvim_set_current_win(origin)
    local floating = open_float()
    vim.api.nvim_win_close(floating, true)
    assert.equals(origin, vim.api.nvim_get_current_win())
  end)

  it("lets Neovim keep a destination when closing an inactive float", function()
    vim.cmd("vsplit")
    local destination = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(origin)
    local floating = open_float()
    vim.api.nvim_set_current_win(destination)
    vim.api.nvim_win_close(floating, true)
    assert.equals(destination, vim.api.nvim_get_current_win())
  end)

  it("preserves the destination editor when navigation dismisses all three picker windows", function()
    vim.cmd("vsplit")
    local destination = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(origin)
    local windows, buffers = open_picker()
    vim.api.nvim_set_current_win(destination)
    assert_cleaned(windows, buffers)
    assert.equals(destination, vim.api.nvim_get_current_win())
  end)

  it("preserves the destination tab when navigation dismisses the picker", function()
    vim.cmd("tabnew")
    local destination = vim.api.nvim_get_current_win()
    local tab = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_set_current_win(origin)
    local windows, buffers = open_picker()
    vim.api.nvim_set_current_win(destination)
    assert_cleaned(windows, buffers)
    assert.equals(destination, vim.api.nvim_get_current_win())
    assert.equals(tab, vim.api.nvim_get_current_tabpage())
  end)

  for _, key in ipairs({ "q", "<CR>", "r" }) do
    it("returns to origin before explicit picker action " .. key, function()
      vim.cmd("vsplit")
      vim.api.nvim_set_current_win(origin)
      local called = false
      local function action()
        called = true
        assert.equals(origin, vim.api.nvim_get_current_win())
      end
      local windows, buffers = open_picker(action, action)
      local search = vim.api.nvim_get_current_buf()
      local invoked = false
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(search, "n")) do
        if map.lhs == key then
          invoked = true
          map.callback()
          break
        end
      end
      assert.is_true(invoked)
      assert_cleaned(windows, buffers)
      assert.equals(origin, vim.api.nvim_get_current_win())
      assert.equals(key ~= "q", called)
    end)
  end
end)
