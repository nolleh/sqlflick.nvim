local M = {}

local uv = vim.loop
local backend_process = nil
local backend_port = 8080

---@class Handler
---@field private process uv_process_t?
---@field private port number
local Handler = {}

---@return Handler
function Handler:new()
	local o = {
		process = nil,
		port = backend_port,
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

---Execute a query through the backend
---@param database string
---@param query string
---@param config table
---@return table result
function Handler:execute_query(database, query, config)
	self:ensure_running()

	local http = require("resty.http")
	local httpc = http.new()
	local res, err = httpc:request_uri("http://localhost:" .. tostring(self.port) .. "/query", {
		method = "POST",
		body = vim.json.encode({
			database = database,
			query = query,
			config = config,
		}),
		headers = {
			["Content-Type"] = "application/json",
		},
	})

	if err then
		error("Failed to execute query: " .. err)
	end

	if res.status ~= 200 then
		error("Query failed: " .. res.body)
	end

	return vim.json.decode(res.body)
end

---Create a new handler instance
---@return Handler
function M.new()
	return Handler:new()
end

return M

