-- Run with `make test-e2e` against the PostgreSQL service in tests/docker.
-- The backend, curl transport, database, commands, and result UI are real.
describe("PostgreSQL execution end to end", function()
  local backend_job, sqlflick, db, original_cache, original_install, source_win

  local function wait_for_result()
    assert.is_true(sqlflick.is_running(), "the command did not start an asynchronous request")
    assert.is_true(
      vim.wait(10000, function()
        return not sqlflick.is_running()
      end, 20),
      "query did not finish"
    )
    assert.is_true(vim.api.nvim_win_is_valid(sqlflick.display_win), "result window was not created")
    return vim.api.nvim_buf_get_lines(sqlflick.display_buf, 0, -1, false)
  end

  local function execute(query)
    vim.api.nvim_cmd({ cmd = "SQLFlickExecute", args = { query } }, {})
    return wait_for_result()
  end

  before_each(function()
    local bin = assert(vim.env.SQLFLICK_E2E_BACKEND_BIN, "build the backend with make test-e2e")
    local listener = assert(vim.loop.new_tcp())
    assert(listener:bind("127.0.0.1", 0))
    local port = listener:getsockname().port
    listener:close()
    backend_job = vim.system({ bin, "-port", tostring(port) }, { text = true })
    local health = "http://127.0.0.1:" .. port .. "/health"
    assert.is_true(
      vim.wait(5000, function()
        local response = vim.fn.system({ "curl", "--silent", "--max-time", "1", health })
        return vim.v.shell_error == 0 and response:find('"protocol":1', 1, true) ~= nil
      end, 50),
      "backend did not become ready"
    )

    original_cache = package.loaded["sqlflick.cache"]
    original_install = package.loaded["sqlflick.install"]
    package.loaded["sqlflick.cache"] = {
      load_selected_id = function()
        return "e2e_postgres"
      end,
    }
    package.loaded["sqlflick.install"] = {
      ensure_installed = function() end,
      bin = function()
        return bin
      end,
    }
    db = {
      id = "e2e_postgres",
      name = "e2e_postgres",
      type = "postgresql",
      host = vim.env.SQLFLICK_E2E_PG_HOST or "127.0.0.1",
      port = tonumber(vim.env.SQLFLICK_E2E_PG_PORT) or 5432,
      database = vim.env.SQLFLICK_E2E_PG_DATABASE or "test_db",
      username = vim.env.SQLFLICK_E2E_PG_USER or "test_user",
      password = vim.env.SQLFLICK_E2E_PG_PASSWORD or "test_password",
    }
    source_win = vim.api.nvim_get_current_win()
    sqlflick = require("sqlflick")
    sqlflick.setup({
      databases = { db },
      backend = { host = "127.0.0.1", port = port, timeout_ms = 5000 },
      pagination = { page_size = 2 },
      completion = { enabled = false },
    })
    assert.same(db, sqlflick.selected_database)
  end)

  after_each(function()
    if sqlflick then
      sqlflick.stop()
    end
    if backend_job then
      backend_job:kill(15)
      backend_job:wait(1000)
    end
    if source_win and vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_set_current_win(source_win)
    end
    if sqlflick and sqlflick.display_win and vim.api.nvim_win_is_valid(sqlflick.display_win) then
      vim.api.nvim_win_close(sqlflick.display_win, true)
    end
    package.loaded["sqlflick.cache"] = original_cache
    package.loaded["sqlflick.install"] = original_install
  end)

  it("executes a query and renders the database result", function()
    local lines = execute("SELECT 42 AS answer")
    assert.is_truthy(table.concat(lines, "\n"):find("42", 1, true))
    assert.equals(42, require("sqlflick.query").table_data.rows[1][1])
  end)

  it("counts rows, fetches a page, and refreshes the next page", function()
    local lines = execute("SELECT generate_series(1, 5) AS value")
    local pagination = require("sqlflick.pagination")
    assert.is_true(pagination.is_enabled(), table.concat(lines, "\n"))
    assert.equals(3, pagination.get_total_pages())
    assert.equals(2, #require("sqlflick.query").table_data.rows)
    assert.equals(1, require("sqlflick.query").table_data.rows[1][1])

    assert.is_true(pagination.next_page())
    sqlflick.refresh_current_page()
    wait_for_result()
    assert.equals(3, require("sqlflick.query").table_data.rows[1][1])
    assert.equals(4, require("sqlflick.query").table_data.rows[2][1])
  end)

  it("cancels an active query and accepts a subsequent query", function()
    execute("SELECT 1 AS ready") -- Complete the readiness probe before cancellation.
    vim.api.nvim_cmd({
      cmd = "SQLFlickExecute",
      args = {
        "WITH delayed AS (SELECT pg_sleep(2)) SELECT 1 AS value FROM delayed",
      },
    }, {})
    assert.is_true(sqlflick.is_running())
    vim.wait(100, function()
      return false
    end)
    vim.cmd("SQLFlickCancel")
    assert.is_false(sqlflick.is_running())
    execute("SELECT 7 AS value")
    assert.equals(7, require("sqlflick.query").table_data.rows[1][1])
  end)
end)
