local M = {}
local initialized = false
local defaults = {}

local function highlight(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local function mix(first, second, first_weight)
  local result = 0
  local weight = first_weight / 100
  for _, shift in ipairs({ 16, 8, 0 }) do
    local scale = 2 ^ shift
    local first_channel = math.floor(first / scale) % 256
    local second_channel = math.floor(second / scale) % 256
    result = result + math.floor(first_channel * weight + second_channel * (1 - weight)) * scale
  end
  return result
end

local function set_highlights()
  local normal, bar = highlight("Normal"), highlight("StatusLine")
  local foreground = highlight("CursorLineNr").fg or bar.fg or normal.fg or 0xffffff
  local background = bar.bg or normal.bg
  local surface = mix(foreground, background or foreground, 7)
  local accent = highlight("DiagnosticInfo").fg or highlight("Special").fg or foreground
  accent = mix(accent, surface, 85)
  local groups = {
    SQLFlickStatusSeparator = { fg = accent, bg = background },
    SQLFlickStatusIcon = { fg = normal.bg or background or 0x000000, bg = accent },
    SQLFlickStatusName = { fg = mix(foreground, surface, 85), bg = surface },
    SQLFlickStatusDatabase = { fg = foreground, bg = surface },
    SQLFlickStatusConfirm = { fg = highlight("DiagnosticWarn").fg or foreground, bg = surface },
    SQLFlickStatusRunning = { fg = highlight("DiagnosticOk").fg or foreground, bg = surface },
  }
  for name, opts in pairs(groups) do
    local current = highlight(name)
    if not next(current) or (defaults[name] and vim.deep_equal(current, defaults[name])) then
      vim.api.nvim_set_hl(0, name, opts)
    end
    defaults[name] = opts
  end
end

function M.setup()
  set_highlights()
  local group = vim.api.nvim_create_augroup("SQLFlickStatusline", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      set_highlights()
      vim.cmd("redrawstatus")
    end,
  })
  initialized = true
end

local function label(value)
  return (value:gsub("%c", " "):gsub("%%", "%%%%"))
end

local function target(status)
  local result = "%#SQLFlickStatusName# " .. label(status.name)
  if status.database ~= "" then
    result = result .. "/%#SQLFlickStatusDatabase#" .. label(status.database)
  end
  return result
end

---@class SQLFlickStatuslineOptions
---@field separators? boolean Include the rounded leading separator (default: true)

---@param status SQLFlickStatus?
---@param opts? SQLFlickStatuslineOptions
---@return string
function M.render(status, opts)
  if not status then
    return ""
  end
  if not initialized then
    M.setup()
  end

  local separators = not opts or opts.separators ~= false
  local result = separators and "%#SQLFlickStatusSeparator#" or ""
  result = result .. "%#SQLFlickStatusIcon#󰆼 " .. target(status)
  if status.state == "confirm" then
    result = result .. " %#SQLFlickStatusConfirm#󰋗"
  end
  if status.running then
    result = result .. " %#SQLFlickStatusRunning#󰑮"
    if not status.running.is_selected then
      result = result .. target(status.running)
    end
  end
  return result .. " %*"
end

return M
