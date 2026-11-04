describe("Development loader", function()
  it("pins deferred modules after the plugin manager resets runtimepath", function()
    local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
    local runtimepath = vim.o.runtimepath
    local loaded, preloaded = {}, {}
    for name, module in pairs(package.loaded) do
      if name == "sqlflick" or name:match("^sqlflick%.") then
        loaded[name] = module
        package.loaded[name] = nil
      end
    end
    for name, loader in pairs(package.preload) do
      if name == "sqlflick" or name:match("^sqlflick%.") then
        preloaded[name] = loader
      end
    end

    local ok, err = pcall(function()
      dofile(root .. "/dev-load.lua")
      assert.is_nil(package.loaded["sqlflick.statusline"])
      vim.o.runtimepath = vim.env.VIMRUNTIME
      local api = require("sqlflick")
      api.selected_database = { name = "local", database = "test" }
      local rendered = vim.api.nvim_eval_statusline(api.statusline(), {}).str
      assert.equals("󰆼  local/test ", rendered)
      local source = debug.getinfo(require("sqlflick.statusline").render, "S").source
      assert.equals("@" .. root .. "/lua/sqlflick/statusline.lua", source)
    end)

    vim.o.runtimepath = runtimepath
    for name in pairs(package.loaded) do
      if name == "sqlflick" or name:match("^sqlflick%.") then
        package.loaded[name] = nil
      end
    end
    for name in pairs(package.preload) do
      if name == "sqlflick" or name:match("^sqlflick%.") then
        package.preload[name] = nil
      end
    end
    for name, module in pairs(loaded) do
      package.loaded[name] = module
    end
    for name, loader in pairs(preloaded) do
      package.preload[name] = loader
    end
    assert.is_true(ok, err)
  end)
end)
