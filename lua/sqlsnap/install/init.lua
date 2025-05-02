local M = {}

local function log_error(mes)
	print("[sqlsnap install - error]: " .. mes)
end
local function log_info(mes)
	print("[sqlsnap install]: " .. mes)
end

-- Compare semantic versions
-- Returns:
--   1 if v1 > v2
--   0 if v1 == v2
--  -1 if v1 < v2
local function compare_versions(v1, v2)
	local function split_version(v)
		local major, minor, patch = v:match("(%d+)%.(%d+)%.(%d+)")
		if not major then
			return nil
		end
		return tonumber(major), tonumber(minor), tonumber(patch)
	end

	local m1, n1, p1 = split_version(v1)
	local m2, n2, p2 = split_version(v2)

	if not m1 or not m2 then
		return 0
	end -- Invalid version format

	if m1 > m2 then
		return 1
	elseif m1 < m2 then
		return -1
	elseif n1 > n2 then
		return 1
	elseif n1 < n2 then
		return -1
	elseif p1 > p2 then
		return 1
	elseif p1 < p2 then
		return -1
	else
		return 0
	end
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
	local version = M.version()
	if version == "not_installed" or version == "unknown" then
		return true
	end

	-- Compare with current plugin version
	local plugin_version = "1.0.0" -- This should match the VERSION in main.go
	if compare_versions(plugin_version, version) > 0 then
		vim.notify(
			string.format("Backend version %s is outdated. Current version is %s", version, plugin_version),
			vim.log.levels.INFO
		)
		return true
	end

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
