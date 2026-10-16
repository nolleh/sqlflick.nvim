---@class Handler
---@field private process uv.uv_process_t?
---@field private port number
local Handler = {}

local uv = vim.loop

-- Try to load lua-http, fall back to curl if not available
local http
local ok, _ = pcall(function()
  http = require("http")
end)

-- ok = false

if not ok then
  -- Fallback to using curl
  http = {
    request = function(method, url, opts)
      local curl_check = vim.fn.system("which curl")
      if vim.v.shell_error ~= 0 then
        vim.notify("Neither lua-http nor curl is available. Please install one of them.", vim.log.levels.ERROR)
        return nil
      end

      local cmd = string.format(
        'curl -s -X %s -H "Content-Type: application/json" -d %s %s',
        method,
        vim.fn.shellescape(opts.body),
        url
      )
      local response = vim.fn.system(cmd)
      if vim.v.shell_error ~= 0 then
        vim.notify("Failed to execute curl command", vim.log.levels.ERROR)
        return nil
      end
      return { body = response }
    end,
  }
  -- vim.notify("Using curl as fallback HTTP client", vim.log.levels.INFO)
end

---Check if backend process is already running
---@return boolean, number?, number? _ is running, port number if found, pid if found
local function check_existing_process()
  local pgrep = vim.fn.system("pgrep -f sqlflick-backend")
  if vim.v.shell_error ~= 0 then
    return false
  end

  -- Extract the first PID from the output (in case there are multiple)
  local pid = pgrep:match("(%d+)")
  if not pid then
    return false
  end
  pid = tonumber(pid)

  -- Check what port it's running on
  local ps_out = vim.fn.system(string.format("ps -p %s -o command=", pid))
  local port = ps_out:match("-port%s+(%d+)")

  return true, tonumber(port), pid
end

---@param port number
---@return Handler
function Handler:new(port)
  local o = {
    process = nil,
    port = port,
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

---Start the backend process if not already running
function Handler:ensure_running()
  local is_running, _, _ = check_existing_process()
  if is_running then
    return
  end

  local backend_path = vim.fn.stdpath("data") .. "/sqlflick/bin/sqlflick-backend"
  if vim.fn.filereadable(backend_path) ~= 1 then
    error("Backend binary not found. Please run :SQLFlickInstall first")
  end

  local handle, _ = uv.spawn(backend_path, {
    args = { "-port", tostring(self.port) },
    stdio = { nil, nil, nil },
  }, function(code, _)
    if code ~= 0 then
      print("[sqlflick] Backend process exited with code: " .. tostring(code))
    end
    self.process = nil
  end)

  if not handle then
    error("Failed to start backend process")
  end

  self.process = handle
end

---Stop the backend process if running
function Handler:stop()
  local pending = {}
  for request in pairs(self.requests or {}) do
    table.insert(pending, request)
  end
  for _, request in ipairs(pending) do
    request:cancel()
  end
  if self.process then
    pcall(self.process.kill, self.process, 15)
    self.process = nil
  end
  self.ready, self.starting = false, false
end

function Handler:restart()
  self:stop()
  self:ensure_running()
end

local function request_error(code, message)
  return { error_code = code, error = message }
end

-- A callback opts into async execution. Legacy synchronous callers (including
-- omni-completion) retain their existing API.
function Handler:request_async(endpoint, query, db_config, backend_config, limit, offset, callback)
  local timeout = backend_config.timeout_ms or 30000
  if type(timeout) ~= "number" or timeout < 1 or timeout > 3600000 or timeout % 1 ~= 0 then
    timeout = 30000
  end
  local data = {
    database = db_config.type,
    query = query,
    timeout_ms = timeout,
    limit = limit,
    offset = offset,
    config = {
      host = db_config.host,
      port = db_config.port,
      user = db_config.username,
      password = db_config.password,
      dbname = db_config.database,
    },
  }
  local request = { done = false, job = nil }
  self.requests = self.requests or {}
  self.requests[request] = true
  local function finish(result)
    if request.done then
      return
    end
    request.done = true
    self.requests[request] = nil
    vim.schedule(function()
      callback(result)
    end)
  end
  function request:cancel()
    if self.done then
      return
    end
    local job = self.job
    finish(request_error("cancelled", "Query cancelled"))
    if job then
      pcall(job.kill, job, 15)
    end
  end
  local base_url = string.format("http://%s:%d", backend_config.host, backend_config.port)
  local function send()
    if request.done then
      return
    end
    local ok, job = pcall(vim.system, {
      "curl",
      "--silent",
      "--show-error",
      "--request",
      "POST",
      "--header",
      "Content-Type: application/json",
      "--data-binary",
      "@-",
      base_url .. endpoint,
    }, { text = true, stdin = vim.fn.json_encode(data), timeout = timeout }, function(response)
      vim.schedule(function()
        if request.done then
          return
        end
        if response.code == 124 then
          finish(request_error("timeout", "Query timed out"))
        elseif response.code ~= 0 then
          self.ready = false
          finish(
            request_error("transport", response.stderr ~= "" and response.stderr or "Failed to connect to backend")
          )
        else
          local decoded, result = pcall(vim.fn.json_decode, response.stdout)
          if
            not decoded
            or type(result) ~= "table"
            or (result.error ~= nil and type(result.error) ~= "string")
            or (endpoint == "/count" and not result.error and type(result.count) ~= "number")
          then
            finish(request_error("invalid_response", "Backend returned an invalid response"))
          else
            finish(result)
          end
        end
      end)
    end)
    if ok then
      request.job = job
    else
      finish(request_error("transport", tostring(job)))
    end
  end

  -- Probe readiness asynchronously before sending SQL. Only GET probes retry:
  -- a write query must never be replayed after an ambiguous transport failure.
  if self.ready then
    send()
  else
    local attempts = 0
    local function probe()
      if request.done then
        return
      end
      attempts = attempts + 1
      local ok, job = pcall(vim.system, {
        "curl",
        "--silent",
        "--show-error",
        base_url .. "/health",
      }, { text = true, timeout = 250 }, function(response)
        vim.schedule(function()
          if request.done then
            return
          end
          local decoded, health = pcall(vim.fn.json_decode, response.stdout)
          if response.code == 0 and decoded and type(health) == "table" and health.protocol == 1 then
            self.ready, self.starting = true, false
            send()
            return
          end
          if response.code == 0 then
            finish(
              request_error("transport", "Backend version is incompatible. Run :SQLFlickInstall, then :SQLFlickRestart")
            )
            return
          end
          if not self.process then
            local backend_path = require("sqlflick.install").bin()
            if vim.fn.filereadable(backend_path) ~= 1 then
              finish(request_error("transport", "Backend binary not found. Run :SQLFlickInstall"))
              return
            end
            self.starting = true
            local handle
            handle = uv.spawn(backend_path, {
              args = { "-port", tostring(self.port) },
              stdio = { nil, nil, nil },
            }, function()
              if self.process == handle then
                self.process, self.ready, self.starting = nil, false, false
              end
              if handle and not handle:is_closing() then
                handle:close()
              end
            end)
            if not handle then
              finish(request_error("transport", "Failed to start backend process"))
              return
            end
            self.process = handle
          end
          if attempts >= 10 then
            finish(request_error("transport", "Backend did not become ready. Run :SQLFlickRestart"))
          else
            vim.defer_fn(probe, 100)
          end
        end)
      end)
      if ok then
        request.job = job
      else
        finish(request_error("transport", tostring(job)))
      end
    end
    probe()
  end
  return request
end

---Execute a query through the backend
---@param query string
---@param db_config table
---@param backend_config table
---@return table result
function Handler:execute_query(query, db_config, backend_config, callback)
  if type(callback) == "function" then
    return self:request_async("/query", query, db_config, backend_config, nil, nil, callback)
  end
  if not self.process then
    self:ensure_running()
  end

  local url = string.format("http://%s:%d/query", backend_config.host, backend_config.port)

  -- Create the data structure
  local data = {
    database = db_config.type,
    query = query,
    config = {
      host = db_config.host,
      port = db_config.port,
      user = db_config.username,
      password = db_config.password,
      dbname = db_config.database,
    },
  }

  -- Encode the data without escaping backslashes
  local json_str = vim.fn.json_encode(data)
  -- Remove the extra escaping of backslashes
  json_str = json_str:gsub("\\\\", "\\")

  -- Use HTTP client (either lua-http or curl fallback)
  local response = http.request("POST", url, {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = json_str,
  })

  if not response then
    vim.notify("Failed to connect to backend", vim.log.levels.ERROR)
    return { error = "Failed to connect to backend" }
  end

  local result = vim.fn.json_decode(response.body)
  if result.error then
    vim.notify("Query failed: " .. result.error, vim.log.levels.ERROR)
    return result
  end

  return result
end

---Execute a count query through the backend
---@param query string
---@param db_config table
---@param backend_config table
---@return { count?: number, error?: string }
function Handler:execute_count(query, db_config, backend_config, callback)
  if type(callback) == "function" then
    return self:request_async("/count", query, db_config, backend_config, nil, nil, callback)
  end
  if not self.process then
    self:ensure_running()
  end

  local url = string.format("http://%s:%d/count", backend_config.host, backend_config.port)

  local data = {
    database = db_config.type,
    query = query,
    config = {
      host = db_config.host,
      port = db_config.port,
      user = db_config.username,
      password = db_config.password,
      dbname = db_config.database,
    },
  }

  local json_str = vim.fn.json_encode(data)
  json_str = json_str:gsub("\\\\", "\\")

  local response = http.request("POST", url, {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = json_str,
  })

  if not response then
    vim.notify("Failed to connect to backend", vim.log.levels.ERROR)
    return { error = "Failed to connect to backend" }
  end

  local result = vim.fn.json_decode(response.body)
  if result.error then
    vim.notify("Count query failed: " .. result.error, vim.log.levels.ERROR)
    return { error = result.error }
  end

  return { count = result.count or 0 }
end

---Execute a query with pagination through the backend
---@param query string
---@param db_config table
---@param backend_config table
---@param limit number|nil
---@param offset number|nil
---@return table result
function Handler:execute_query_with_pagination(query, db_config, backend_config, limit, offset, callback)
  if type(callback) == "function" then
    return self:request_async("/query", query, db_config, backend_config, limit, offset, callback)
  end
  if not self.process then
    self:ensure_running()
  end

  local url = string.format("http://%s:%d/query", backend_config.host, backend_config.port)

  -- Create the data structure
  local data = {
    database = db_config.type,
    query = query,
    config = {
      host = db_config.host,
      port = db_config.port,
      user = db_config.username,
      password = db_config.password,
      dbname = db_config.database,
    },
  }

  if limit then
    data.limit = limit
  end
  if offset then
    data.offset = offset
  end

  -- Encode the data without escaping backslashes
  local json_str = vim.fn.json_encode(data)
  -- Remove the extra escaping of backslashes
  json_str = json_str:gsub("\\\\", "\\")

  local response = http.request("POST", url, {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = json_str,
  })

  if not response then
    vim.notify("Failed to connect to backend", vim.log.levels.ERROR)
    return { error = "Failed to connect to backend" }
  end

  local result = vim.fn.json_decode(response.body)
  if result.error then
    vim.notify("Query failed: " .. result.error, vim.log.levels.ERROR)
    return result
  end

  return result
end

---Fetch relational schema metadata through the backend.
---@param db_config table
---@param backend_config table
---@return table|nil schema
---@return string|nil error
function Handler:fetch_schema(db_config, backend_config)
  if not self.process then
    self:ensure_running()
  end

  local url = string.format("http://%s:%d/schema", backend_config.host, backend_config.port)
  local data = {
    database = db_config.type,
    config = {
      host = db_config.host,
      port = db_config.port,
      user = db_config.username,
      password = db_config.password,
      dbname = db_config.database,
    },
  }

  local response = http.request("POST", url, {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = vim.fn.json_encode(data),
  })
  if not response then
    return nil, "failed to connect to backend"
  end

  local decoded, result = pcall(vim.fn.json_decode, response.body)
  if not decoded then
    return nil, "backend returned an invalid schema response"
  end
  if result.error then
    return nil, result.error
  end
  return result
end

return Handler
