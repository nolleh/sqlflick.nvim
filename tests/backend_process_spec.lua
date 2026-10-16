describe("Backend process discovery", function()
  local saved_handler, saved_install, saved_system, saved_kill, killed, processes

  before_each(function()
    saved_handler = package.loaded["sqlflick.handler"]
    saved_install = package.loaded["sqlflick.install"]
    saved_system = vim.fn.system
    saved_kill = vim.loop.kill
    package.loaded["sqlflick.handler"] = nil
    package.loaded["sqlflick.install"] = {
      bin = function() return "/test/bin/sqlflick-backend-e2e" end,
    }
    killed, processes = {}, {}
    vim.fn.system = function(command)
      if type(command) == "string" and command == "pgrep -f sqlflick-backend" then
        return saved_system({ "printf", "101\n102\n103\n" })
      end
      if type(command) == "table" and command[1] == "pgrep" then
        return saved_system({ "printf", "101\n102\n103\n" })
      end
      local pid = type(command) == "table" and command[3] or command:match("ps %-p (%d+)")
      return saved_system({ "printf", "%s", processes[tostring(pid)] or "" })
    end
    vim.loop.kill = function(pid)
      table.insert(killed, pid)
      return true
    end
  end)

  after_each(function()
    package.loaded["sqlflick.handler"] = saved_handler
    package.loaded["sqlflick.install"] = saved_install
    vim.fn.system = saved_system
    vim.loop.kill = saved_kill
  end)

  it("skips the Make recipe shell and selects the backend with the requested port", function()
    processes["101"] = "/bin/sh -c SQLFLICK_E2E_BACKEND_BIN=/test/bin/sqlflick-backend-e2e nvim --headless"
    processes["102"] = "/test/bin/sqlflick-backend-e2e -port 9001"
    processes["103"] = "/test/bin/sqlflick-backend-e2e -port 9081"
    require("sqlflick.handler"):new(9081):stop()
    assert.same({ 103 }, killed)
  end)

  it("does not signal a shell even when its command contains the backend port", function()
    processes["101"] = "/bin/sh -c /test/bin/sqlflick-backend-e2e -port 9081"
    require("sqlflick.handler"):new(9081):stop()
    assert.same({}, killed)
  end)

  it("does not signal a backend on another port", function()
    processes["101"] = "/test/bin/sqlflick-backend-e2e -port 9001"
    require("sqlflick.handler"):new(9081):stop()
    assert.same({}, killed)
  end)
end)
