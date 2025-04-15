local M = {}

local uv = vim.loop
local backend_process = nil

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

	local backend_path = vim.fn.stdpath("data") .. "/sqlsnap/bin/sqlsnap-backend"
	if vim.fn.filereadable(backend_path) ~= 1 then
		error("Backend binary not found. Please run :SqlSnapInstall first")
	end

	-- vim.schedule(function()
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
	-- end)
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
