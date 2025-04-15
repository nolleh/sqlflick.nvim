local M = {}

local uv = vim.loop
local backend_process = nil

---Check if backend process is already running
---@return boolean, number? _ is running, port number if found
local function check_existing_process()
	-- Try to find existing process
	local pgrep = vim.fn.system("pgrep -f sqlsnap-backend")
	if vim.v.shell_error ~= 0 then
		return false
	end

	-- Check what port it's running on
	local ps_out = vim.fn.system(string.format("ps -p %s -o command=", pgrep:gsub("\n", "")))
	local port = ps_out:match("-port%s+(%d+)")

	return true, tonumber(port)
end

---@class Handler
---@field private process uv_process_t?
---@field private port number
---@field private starting boolean
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
	if self.process then
		return
	end

	-- Check if process is already running
	local is_running, existing_port = check_existing_process()
	if is_running then
		if existing_port == self.port then
			-- Process already running on our port, just mark it as running
			self.process = true
			return
		else
			vim.fn.system("pkill -f sqlsnap-backend")
			vim.loop.sleep(100)
		end
	end

	local backend_path = vim.fn.stdpath("data") .. "/sqlsnap/bin/sqlsnap-backend"
	if vim.fn.filereadable(backend_path) ~= 1 then
		error("Backend binary not found. Please run :SqlSnapInstall first")
	end

	local handle, pid = uv.spawn(backend_path, {
		args = { "-port", tostring(self.port) },
		stdio = { nil, 1, 2 },
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
	if self.process then
		self.process:kill()
		self.process = nil
	end
end

function Handler:restart()
	self:stop()
	self:ensure_running()
end

---Execute a query through the backend
---@param database string
---@param query string
---@param config table
---@return table result
function Handler:execute_query(query, db_config, backend_config)
	if not self.process then
		self:ensure_running()
	end

	-- local data = vim.json.encode({
	-- 	database = database,
	-- 	query = query,
	-- 	config = config,
	-- })
	--
	-- local curl_cmd = string.format(
	-- 	"curl -s -X POST -H 'Content-Type: application/json' -d '%s' http://localhost:%d/query",
	-- 	data,
	-- 	self.port
	-- )
	--
	-- local response = vim.fn.system(curl_cmd)
	-- local result = vim.json.decode(response)
	--
	-- if result.error then
	-- 	error("Query failed: " .. result.error)
	-- end
	--
	-- if not self.process then
	-- 	error("Backend process stopped unexpectedly")
	-- end
	--
	-- return result
	local url = string.format("http://%s:%d/query", backend_config.host, backend_config.port)

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

	local response = vim.fn.system(
		string.format("curl -s -X POST -H \"Content-Type: application/json\" -d '%s' %s", vim.fn.json_encode(data), url)
	)

	local result = vim.fn.json_decode(response)
	if result.error then
		vim.notify("Query failed: " .. result.error, vim.log.levels.ERROR)
		return nil
	end

	return result
end

---Create a new handler instance
---@return Handler
function M.new(port)
	return Handler:new(port)
end

return M
