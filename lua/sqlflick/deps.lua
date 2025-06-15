local M = {}

-- Dependencies
M.dependencies = {
  {
    name = "lua-http",
    url = "https://github.com/daurnimator/lua-http",
    version = "0.4",
    install_cmd = "luarocks install http",
  },
}

-- Check if luarocks is installed
local function has_luarocks()
  local result = vim.fn.system("which luarocks")
  return vim.v.shell_error == 0
end

-- Check if dependencies are installed
function M.check_dependencies()
  local missing = {}
  for _, dep in ipairs(M.dependencies) do
    local ok, _ = pcall(require, dep.name)
    if not ok then
      table.insert(missing, dep)
    end
  end
  return missing
end

-- Install dependencies
function M.install_dependencies()
  -- First check if luarocks is installed
  if not has_luarocks() then
    vim.notify(
      "LuaRocks is not installed. Please install it first:\n"
        .. "macOS: brew install luarocks\n"
        .. "Linux: sudo apt-get install luarocks\n"
        .. "Windows: https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Windows",
      vim.log.levels.WARN
    )
    return false
  end

  local missing = M.check_dependencies()
  if #missing == 0 then
    return true
  end

  -- Use luarocks to install dependencies
  for _, dep in ipairs(missing) do
    vim.notify("Installing " .. dep.name .. "...", vim.log.levels.INFO)
    local result = vim.fn.system(dep.install_cmd)
    if vim.v.shell_error ~= 0 then
      vim.notify(
        string.format(
          "Failed to install %s: %s\nPlease install it manually using:\n%s",
          dep.name,
          result,
          dep.install_cmd
        ),
        vim.log.levels.ERROR
      )
      return false
    end
  end

  return true
end

return M
