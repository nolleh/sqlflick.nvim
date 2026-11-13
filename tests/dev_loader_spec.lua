describe("Development loader", function()
  it("loads environment connections after the plugin manager changes runtimepath", function()
    local script = [[
      local root = vim.fn.getcwd()
      dofile(root .. "/dev-load.lua")
      vim.opt.runtimepath:remove(root)
      vim.env.SQFLK_DB_URL = nil
      vim.env.DATABASE_URL = "postgresql://app@localhost/app?sslmode=require"
      local config = require("sqlflick.config")
      config.setup({})
      local db = require("sqlflick.tree").find_database_by_id(config.opts.databases, "env:DATABASE_URL")
      assert(db and db.database == "app" and db.type == "postgresql")
    ]]
    local result = vim
      .system({
        vim.v.progpath,
        "--headless",
        "-u",
        "NONE",
        "-i",
        "NONE",
        "-c",
        "lua " .. script,
        "-c",
        "qa",
      }, { text = true, timeout = 5000 })
      :wait()
    assert.equals(0, result.code, result.stderr)
    assert.is_nil(result.stderr:find("Error", 1, true), result.stderr)
  end)
end)
