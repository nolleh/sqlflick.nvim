local M = {}

local function log_error(mes)
	print("[sqlsnap install - error]: " .. mes)
end
local function log_info(mes)
	print("[sqlsnap install]: " .. mes)
end

---@return string _ path to install dir
function M.dir()
	return vim.fn.stdpath("data") .. "/sqlsnap/bin"
end

---@return string _ path to binary
function M.bin()
	local suffix = ""
	if vim.fn.has("win32") == 1 then
		suffix = ".exe"
	end
	return M.dir() .. "/sqlsnap-backend" .. suffix
end

---@return string _ path of go source
function M.source_path()
	local p, _ = debug.getinfo(1).source:sub(2):gsub("/lua/sqlsnap/install/init.lua$", "/backend")
	return p
end

---@return string _ version of installed backend
function M.version()
	local backend_path = M.bin()
	if vim.fn.filereadable(backend_path) ~= 1 then
		return "not_installed"
	end

	local handle = io.popen(backend_path .. " -version 2>&1")
	if not handle then
		return "unknown"
	end

	local version = handle:read("*a"):gsub("%s+$", "")
	handle:close()
	return version
end

---Check if backend needs to be installed or updated
---@return boolean
function M.needs_install()
	local backend_path = M.bin()
	if vim.fn.filereadable(backend_path) ~= 1 then
		return true
	end

	-- Check if backend is executable
	if vim.fn.executable(backend_path) ~= 1 then
		return true
	end

	-- Check version
	-- local version = M.version()
	--  print("version:" .. version)
	-- if version == "not_installed" or version == "unknown" then
	-- 	return true
	-- end

	return false
end

---Build the backend binary
function M.exec()
	local install_dir = M.dir()
	local install_binary = M.bin()
	local source_dir = M.source_path()

	-- make install dir
	vim.fn.mkdir(install_dir, "p")

	-- check if go is installed
	if vim.fn.executable("go") ~= 1 then
		error("go is not installed")
	end

	-- build the backend
	log_info("Building backend...")
	local handle = vim.loop.spawn("go", {
		args = { "build", "-o", install_binary },
		cwd = source_dir,
		stdio = { nil, 1, 2 },
	}, function(code, _)
		if code == 0 then
			log_info("Successfully built backend")
		else
			log_error("Failed to build backend")
		end
	end)

	if not handle then
		error("Failed to start build process")
	end
end

---Install backend if needed
function M.ensure_installed()
	if M.needs_install() then
		log_info("Backend not found or outdated. Installing...")
		M.exec()
	end
end

return M
