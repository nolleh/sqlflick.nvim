local M = {}
local function clean(value)
  return (tostring(value or ""):gsub("%c", " "))
end
local function target(item)
  return clean(item.connection.name) .. "/" .. clean(item.connection.database)
end

function M.open(config, replay)
  local history = require("sqlflick.history")
  local icons = { success = "✓", failed = "✗", cancelled = "⨯", running = "…" }
  require("sqlflick.picker").open({
    border = config.selector.border,
    items = history.list,
    search = function(item)
      return target(item) .. " " .. item.sql
    end,
    label = function(item)
      return icons[item.state] .. " " .. os.date("%H:%M", item.started_at) .. " " .. clean(item.sql)
    end,
    preview = function(item)
      local lines = {
        "-- Connection: " .. target(item),
        "-- Status: " .. item.state .. (item.duration_ms and (" | " .. item.duration_ms .. " ms") or ""),
        "-- Executed: " .. os.date("%Y-%m-%d %H:%M:%S", item.started_at),
        "",
      }
      vim.list_extend(lines, vim.split(item.sql, "\n", { plain = true }))
      return lines
    end,
    accept = function(item)
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(0, buf)
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "hide"
      vim.bo[buf].swapfile = false
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(item.sql, "\n", { plain = true }))
      vim.bo[buf].filetype = "sql"
      vim.b[buf].sqlflick_history_connection = item.connection.id
      vim.notify("Restored SQL from " .. target(item) .. ". Check your selected connection before executing.")
    end,
    replay = replay,
  })
end

return M
