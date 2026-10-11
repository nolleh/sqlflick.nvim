local module_name = "sqlflick.handler"
local db = {
  type = "postgresql",
  host = "localhost",
  port = 5432,
  username = "user",
  password = [[pass"word']],
  database = "test",
}
local backend = { host = "localhost", port = 9081 }
local queries = {
  [[SELECT "name" FROM users;]],
  [[SELECT 'hello', 'O''Brien' FROM users;]],
  [[SELECT "name", 'hello' FROM "User Accounts";]],
}
local methods = {
  "execute_query",
  "execute_count",
  "execute_query_with_pagination",
}

for _, transport in ipairs({ "http", "curl" }) do
  describe("Query quote preservation over " .. transport, function()
    local saved_handler, saved_http, saved_preload, saved_system
    local received

    before_each(function()
      saved_handler = package.loaded[module_name]
      saved_http = package.loaded.http
      saved_preload = package.preload.http
      saved_system = vim.fn.system
      package.loaded[module_name] = nil
      package.loaded.http = nil
      received = nil

      if transport == "http" then
        package.preload.http = function()
          return {
            request = function(_, _, opts)
              received = vim.fn.json_decode(opts.body)
              return { body = '{"count":1}' }
            end,
          }
        end
      else
        package.preload.http = function()
          error("force curl fallback")
        end
        vim.fn.system = function(cmd)
          if cmd == "which curl" then
            vim.v.shell_error = 0
            return "curl"
          end
          -- Run the generated command through a real shell, replacing curl
          -- with a function that returns its body argument without networking.
          local capture = [[
curl() {
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      shift
      printf '%s' "$1"
      return
    fi
    shift
  done
}
]]
          local body = saved_system({ "/bin/sh", "-c", capture .. cmd })
          assert.equals(0, vim.v.shell_error)
          received = vim.fn.json_decode(body)
          return '{"count":1}'
        end
      end
    end)

    after_each(function()
      package.loaded[module_name] = saved_handler
      package.loaded.http = saved_http
      package.preload.http = saved_preload
      vim.fn.system = saved_system
    end)

    for _, method in ipairs(methods) do
      for _, query in ipairs(queries) do
        it("preserves quotes in " .. method .. ": " .. query, function()
          local handler = require(module_name):new(backend.port)
          handler.process = true
          handler[method](handler, query, db, backend, 20, 0)

          assert.equals(query, received.query)
          assert.equals(db.password, received.config.password)
          if method == "execute_query_with_pagination" then
            assert.equals(20, received.limit)
            assert.equals(0, received.offset)
          end
        end)
      end
    end
  end)
end
