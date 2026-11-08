-- Shared search/list/preview window layout used by SQLFlick selectors.
local M = {}

function M.open(opts)
  local origin = vim.api.nvim_get_current_win()
  local width = math.min(math.max(30, math.floor(vim.o.columns * 0.8)), vim.o.columns - 4)
  local height = math.min(math.max(5, math.floor(vim.o.lines * 0.6)), vim.o.lines - 6)
  if width < 20 or height < 5 then
    vim.notify("SQLFlick history needs a larger editor window", vim.log.levels.WARN)
    return
  end
  local search, search_win, list, list_win, preview, preview_win = require("sqlflick.selector").create_selector_window({
    selector = { width = width, height = height, border = opts.border or "rounded" },
  })
  local buffers, windows = { search, list, preview }, { search_win, list_win, preview_win }
  local group = vim.api.nvim_create_augroup("SQLFlickPicker" .. search, { clear = true })
  local closed, items, index = false, {}, 1
  local function write(buf, lines)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end
  local function close()
    if closed then
      return
    end
    closed = true
    vim.api.nvim_del_augroup_by_id(group)
    vim.cmd("stopinsert")
    for _, win in ipairs(windows) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    if vim.api.nvim_win_is_valid(origin) then
      vim.api.nvim_set_current_win(origin)
    end
  end
  local function show()
    write(preview, items[index] and opts.preview(items[index]) or { "No matching queries" })
    if #items > 0 then
      vim.api.nvim_win_set_cursor(list_win, { index, 0 })
    end
  end
  local function refresh()
    local term = (vim.api.nvim_buf_get_lines(search, 0, 1, false)[1] or ""):lower()
    items = {}
    local lines = {}
    for _, item in ipairs(opts.items()) do
      if opts.search(item):lower():find(term, 1, true) then
        items[#items + 1] = item
        lines[#lines + 1] = opts.label(item)
      end
    end
    index = math.max(1, math.min(index, #items))
    write(list, #lines > 0 and lines or { "No matching queries" })
    show()
  end
  local function move(delta)
    index = math.max(1, math.min(index + delta, #items))
    show()
  end
  local function choose(action)
    local item = items[index]
    if item then
      close()
      action(item)
    end
  end
  for _, buf in ipairs(buffers) do
    vim.bo[buf].bufhidden = "wipe"
    vim.keymap.set("i", "<Esc>", "<Esc>", { buffer = buf, desc = "Leave history search insert mode" })
    vim.keymap.set("n", "<Esc>", close, { buffer = buf })
    vim.keymap.set("n", "q", close, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-n>", function()
      move(1)
    end, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-p>", function()
      move(-1)
    end, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<CR>", function()
      choose(opts.accept)
    end, { buffer = buf })
    vim.keymap.set("n", "r", function()
      choose(opts.replay)
    end, { buffer = buf })
  end
  vim.keymap.set("n", "j", function()
    move(1)
  end, { buffer = list })
  vim.keymap.set("n", "k", function()
    move(-1)
  end, { buffer = list })
  vim.bo[search].modifiable = true
  vim.bo[preview].filetype = "sql"
  vim.wo[list_win].cursorline = true
  vim.wo[list_win].wrap = false
  vim.api.nvim_win_set_config(search_win, { title = " Query history ", title_pos = "center" })
  vim.api.nvim_win_set_config(preview_win, { title = " Enter: edit | r: run | Esc/q: close (normal) " })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { group = group, buffer = search, callback = refresh })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = list,
    callback = function()
      index = vim.api.nvim_win_get_cursor(list_win)[1]
      show()
    end,
  })
  vim.api.nvim_create_autocmd({ "WinClosed", "WinEnter" }, {
    group = group,
    callback = function()
      vim.schedule(function()
        if closed then
          return
        end
        local current, valid = vim.api.nvim_get_current_win(), true
        for _, win in ipairs(windows) do
          valid = valid and vim.api.nvim_win_is_valid(win)
        end
        if not valid or not vim.tbl_contains(windows, current) then
          close()
        end
      end)
    end,
  })
  refresh()
  vim.api.nvim_set_current_win(search_win)
  vim.cmd("startinsert")
end

return M
