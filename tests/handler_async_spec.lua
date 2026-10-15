-- Async contract: the existing query methods accept a final callback and
-- return a request with cancel(). A callback receives one result table.
local module_name = "sqlflick.handler"
local db = {
  type = "postgresql",
  host = "localhost",
  port = 5432,
  username = "user",
  password = [[pass"word']],
  database = "test",
}
local backend = { host = "127.0.0.1", port = 9081, timeout_ms = 500 }
local sql = [[SELECT "name", 'O''Brien' FROM users;]]
local methods = {
  { name = "execute_query", endpoint = "/query", response = '{"columns":["name"],"rows":[["Alice"]]}' },
  { name = "execute_count", endpoint = "/count", response = '{"count":21}' },
  { name = "execute_query_with_pagination", endpoint = "/query", response = '{"columns":["name"],"rows":[["Alice"]]}' },
}

describe("Asynchronous query requests", function()
  local saved, jobs, scheduled, handler, results

  local function flush()
    while #scheduled > 0 do
      table.remove(scheduled, 1)()
    end
  end

  local function start(method)
    local callback = function(result)
      table.insert(results, result)
    end
    if method.name == "execute_query_with_pagination" then
      return handler[method.name](handler, sql, db, backend, 20, 40, callback)
    end
    return handler[method.name](handler, sql, db, backend, callback)
  end

  before_each(function()
    saved = {
      handler = package.loaded[module_name],
      http = package.loaded.http,
      preload = package.preload.http,
      system = vim.system,
      blocking_system = vim.fn.system,
      schedule = vim.schedule,
    }
    package.loaded[module_name] = nil
    package.loaded.http = nil
    package.preload.http = function()
      return { request = function() error("blocking HTTP used by async execution") end }
    end
    jobs, scheduled, results = {}, {}, {}
    vim.fn.system = function() error("blocking vim.fn.system used by async execution") end
    vim.schedule = function(callback)
      table.insert(scheduled, callback)
    end
    vim.system = function(command, opts, on_exit)
      local job = { command = command, opts = opts, on_exit = on_exit, signals = {} }
      function job:kill(signal)
        table.insert(self.signals, signal)
      end
      function job:wait()
        error("async execution must not wait for the process")
      end
      table.insert(jobs, job)
      return job
    end
    handler = require(module_name):new(backend.port)
    handler.process = true -- Backend startup is outside this transport unit test.
  end)

  after_each(function()
    package.loaded[module_name] = saved.handler
    package.loaded.http = saved.http
    package.preload.http = saved.preload
    vim.system = saved.system
    vim.fn.system = saved.blocking_system
    vim.schedule = saved.schedule
  end)

  for _, method in ipairs(methods) do
    describe(method.name, function()
      it("returns before completion and delivers a decoded result on the main loop", function()
        local request = start(method)
        assert.equals("function", type(request.cancel))
        assert.equals(0, #results)
        assert.equals(1, #jobs)
        assert.equals("table", type(jobs[1].command))
        assert.matches(method.endpoint, jobs[1].command[#jobs[1].command], 1, true)
        local body = vim.fn.json_decode(jobs[1].opts.stdin)
        assert.equals(sql, body.query)
        assert.equals(db.password, body.config.password)
        assert.equals(backend.timeout_ms, body.timeout_ms)
        assert.equals(backend.timeout_ms, jobs[1].opts.timeout)
        if method.name == "execute_query_with_pagination" then
          assert.equals(20, body.limit)
          assert.equals(40, body.offset)
        end

        jobs[1].on_exit({ code = 0, signal = 0, stdout = method.response, stderr = "" })
        assert.equals(0, #results)
        flush()
        assert.equals(1, #results)
        assert.same(vim.fn.json_decode(method.response), results[1])
      end)

      it("cancels just this request and reports cancellation exactly once", function()
        local request = start(method)
        request:cancel()
        request:cancel()
        flush()
        assert.equals(1, #jobs[1].signals)
        assert.equals(1, #results)
        assert.equals("cancelled", results[1].error_code)
        assert.is_truthy(results[1].error)

        jobs[1].on_exit({ code = 0, signal = 0, stdout = method.response, stderr = "" })
        flush()
        assert.equals(1, #results) -- A late success must not resurrect a cancelled request.
      end)

      it("reports timeout separately from user cancellation", function()
        start(method)
        jobs[1].on_exit({ code = 124, signal = 15, stdout = "", stderr = "process timed out" })
        flush()
        assert.equals(1, #results)
        assert.equals("timeout", results[1].error_code)
        assert.is_truthy(results[1].error)
        jobs[1].on_exit({ code = 0, signal = 0, stdout = method.response, stderr = "" })
        flush()
        assert.equals(1, #results)
      end)

      it("does not terminate an already completed process when cancelled later", function()
        local request = start(method)
        jobs[1].on_exit({ code = 0, signal = 0, stdout = method.response, stderr = "" })
        flush()
        request:cancel()
        flush()
        assert.equals(0, #jobs[1].signals)
        assert.equals(1, #results)
      end)

      it("reports connection failure through the callback", function()
        start(method)
        jobs[1].on_exit({ code = 7, signal = 0, stdout = "", stderr = "connection refused" })
        flush()
        assert.equals(1, #results)
        assert.equals("transport", results[1].error_code)
        assert.is_truthy(results[1].error)
      end)

      it("reports malformed responses without throwing in the process callback", function()
        start(method)
        jobs[1].on_exit({ code = 0, signal = 0, stdout = "<html>gateway failure</html>", stderr = "" })
        flush()
        assert.equals(1, #results)
        assert.equals("invalid_response", results[1].error_code)
      end)

      it("preserves a backend SQL error as a query error", function()
        start(method)
        jobs[1].on_exit({ code = 0, signal = 0, stdout = '{"error":"column does not exist"}', stderr = "" })
        flush()
        assert.equals(1, #results)
        assert.equals("column does not exist", results[1].error)
      end)
    end)
  end

  it("cancelling one request leaves another request able to finish", function()
    local first = start(methods[1])
    start(methods[1])
    first:cancel()
    flush()
    assert.equals(1, #jobs[1].signals)
    assert.equals(0, #jobs[2].signals)
    jobs[2].on_exit({ code = 0, signal = 0, stdout = methods[1].response, stderr = "" })
    flush()
    assert.equals(2, #results)
    assert.is_nil(results[2].error)
  end)

  it("reports process startup failure without throwing from the caller", function()
    vim.system = function() error("curl executable not found") end
    start(methods[1])
    assert.equals(0, #results)
    flush()
    assert.equals(1, #results)
    assert.equals("transport", results[1].error_code)
  end)
end)
