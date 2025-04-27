local M = {}

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
			-- Check if curl is available
			local curl_check = vim.fn.system("which curl")
			if vim.v.shell_error ~= 0 then
				vim.notify("Neither lua-http nor curl is available. Please install one of them.", vim.log.levels.ERROR)
				return nil
			end

			-- Use curl as fallback
			local cmd = string.format(
				'curl -s -X %s -H "Content-Type: application/json" -d "%s" %s',
				method,
				opts.body:gsub('"', '\\"'),
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
	-- Try to find existing process
	local pgrep = vim.fn.system("pgrep -f sqlsnap-backend")
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

---@class Handler
---@field private process uv.uv_process_t?
---@field private port number
local Handler = {}

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

	local backend_path = vim.fn.stdpath("data") .. "/sqlsnap/bin/sqlsnap-backend"
	if vim.fn.filereadable(backend_path) ~= 1 then
		error("Backend binary not found. Please run :SqlSnapInstall first")
	end

	local handle, _ = uv.spawn(backend_path, {
		args = { "-port", tostring(self.port) },
		stdio = { nil, nil, nil },
	}, function(code, _)
		if code ~= 0 then
			print("[sqlsnap] Backend process exited with code: " .. tostring(code))
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
	local running, _, pid = check_existing_process()
	if running then
		vim.fn.system("kill -SIGTERM " .. pid)
		self.process = nil
		print("stopped...", pid)
	end
end

function Handler:restart()
	self:stop()
	self:ensure_running()
end

---Execute a query through the backend
---@param query string
---@param db_config table
---@param backend_config table
---@return table result
function Handler:execute_query(query, db_config, backend_config)
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
	-- Ensure single quotes are preserved
	json_str = json_str:gsub('\\"', "'")

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

---Create a new handler instance
---@return Handler
function M.new(port)
	return Handler:new(port)
end

return M
