local M = {}

M.opts = {
  -- Default configuration options
  enabled = true,
  use_lua_http = false,
  databases = {
    -- Example database configurations
    -- {
    --     name = "local_postgres",
    --     type = "postgresql",
    --     host = "localhost",
    --     port = 5432,
    --     database = "mydb",
    --     username = "user",
    --     password = "pass"
    -- },
    -- {
    --     name = "local_mysql",
    --     type = "mysql",
    --     host = "localhost",
    --     port = 3306,
    --     database = "mydb",
    --     username = "user",
    --     password = "pass"
    -- },
    -- {
    --     name = "local_sqlite",
    --     type = "sqlite",
    --     database = "/path/to/database.db"
    -- },
    -- {
    -- 	name = "local_redis",
    -- 	type = "redis",
    -- 	host = "localhost",
    -- 	port = 6379,
    -- 	password = "pass",
    -- },
    -- {
    --     name = "local_oracle",
    --     type = "oracle",
    --     host = "localhost",
    --     port = 1521,
    --     database = "orclpdb1", -- service name
    --     username = "user",
    --     password = "pass"
    -- },
  },
  -- Selector window settings
  selector = {
    width = 60,
    height = 15,
    border = "rounded",
  },
  -- Display window settings
  display = {
    position = "bottom", -- "bottom" or "right"
    size = {
      height = 0.2, -- 20% of total height when position is "bottom"
      width = 0.3, -- 30% of total width when position is "right"
    },
    size_absolute = {
      height = nil, -- Absolute height in lines, overrides size.height when set
      width = nil, -- Absolute width in columns, overrides size.width when set
    },
    column = {
      min_width = 8, -- column's minimum width size for guarentees readability
      max_width = 100, -- column's maximum width size. If user configured over 200, 200 is applied.
    },
  },
  -- Backend settings
  backend = {
    host = "localhost",
    port = 9081,
  },
  -- Pagination settings
  pagination = {
    page_size = 20, -- Default number of rows per page
  },
}

local function show_deprecation_popup(msg)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(msg, "\n"))
  local width = 60
  local height = 5
  local opts = {
    style = "minimal",
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    border = "double",
  }

  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.api.nvim_set_current_win(win)
  -- vim.cmd("stopinsert")
  -- vim.api.nvim_win_set_cursor(win, {1, 0})

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true })
end

function M.setup(opts)
  if opts.preview then
    -- show_deprecation_popup(
    -- 	"The 'preview' config has changed to 'selector'.\nSee: https://github.com/nolleh/sqlflick.nvim/wiki/Migration-Guide"
    -- )
    vim.notify(
      "The 'preview' config has changed to 'selector'.\n"
        .. "See: https://github.com/nolleh/sqlflick.nvim/wiki/Migration-Guide#rename-configuration-of-preview",
      vim.log.levels.WARN
    )
  end
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

return M
