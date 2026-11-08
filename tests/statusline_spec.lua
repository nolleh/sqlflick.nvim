describe("Statusline UI", function()
  local statusline = require("sqlflick.statusline")
  local groups = {
    "SQLFlickStatusSeparator",
    "SQLFlickStatusIcon",
    "SQLFlickStatusName",
    "SQLFlickStatusDatabase",
    "SQLFlickStatusConfirm",
    "SQLFlickStatusRunning",
  }
  local saved

  before_each(function()
    saved = {}
    for _, name in ipairs(groups) do
      saved[name] = vim.api.nvim_get_hl(0, { name = name, link = true })
      vim.api.nvim_set_hl(0, name, {})
    end
  end)

  after_each(function()
    for name, opts in pairs(saved) do
      vim.api.nvim_set_hl(0, name, opts)
    end
  end)

  it("uses native highlights for icons and connection labels", function()
    statusline.setup()
    local fragment = statusline.render({ name = "local", database = "app", state = "confirm" })
    local rendered = vim.api.nvim_eval_statusline(fragment, { highlights = true })
    assert.equals("󰆼  local/app 󰋗 ", rendered.str)
    local used = {}
    for _, highlight in ipairs(rendered.highlights) do
      used[highlight.group] = true
    end
    for _, name in ipairs({
      "SQLFlickStatusIcon",
      "SQLFlickStatusName",
      "SQLFlickStatusDatabase",
      "SQLFlickStatusConfirm",
    }) do
      assert.is_true(used[name])
      assert.is_truthy(next(vim.api.nvim_get_hl(0, { name = name, link = false })))
    end
  end)

  it("preserves label delimiters and status-like text without parsing them", function()
    local fragment = statusline.render({ name = "prod/team%", database = "app (confirm)", state = "idle" })
    assert.equals("󰆼  prod/team%/app (confirm) ", vim.api.nvim_eval_statusline(fragment, {}).str)
    assert.is_nil(fragment:find("SQLFlickStatusConfirm", 1, true))
  end)

  it("omits the slash without a database and returns empty without selection", function()
    assert.equals("", statusline.render(nil))
    local fragment = statusline.render({ name = "local", database = "", state = "idle" })
    assert.equals("󰆼  local ", vim.api.nvim_eval_statusline(fragment, {}).str)
  end)

  it("can omit the leading separator for provider-managed boundaries", function()
    local fragment = statusline.render({ name = "local", database = "app", state = "idle" }, { separators = false })
    assert.equals("󰆼  local/app ", vim.api.nvim_eval_statusline(fragment, {}).str)
    assert.is_nil(fragment:find("SQLFlickStatusSeparator", 1, true))
  end)

  it("restores defaults on a colorscheme change without overwriting custom colors", function()
    statusline.setup()
    vim.api.nvim_set_hl(0, "SQLFlickStatusIcon", { fg = "#112233", bg = "#445566" })
    vim.api.nvim_set_hl(0, "SQLFlickStatusConfirm", {})
    vim.api.nvim_exec_autocmds("ColorScheme", {})
    local icon = vim.api.nvim_get_hl(0, { name = "SQLFlickStatusIcon" })
    assert.equals(0x112233, icon.fg)
    assert.equals(0x445566, icon.bg)
    assert.is_truthy(next(vim.api.nvim_get_hl(0, { name = "SQLFlickStatusConfirm" })))
  end)
end)
