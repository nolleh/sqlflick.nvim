-- Development loader for sqlflick.nvim.
-- It pins this checkout before the user's plugin manager initializes, allowing
-- the existing Neovim configuration to provide the normal SQLFlick options.

local plugin_path = vim.fn.expand("<sfile>:p:h")

vim.opt.runtimepath:prepend(plugin_path)

-- Lazy resets runtimepath during setup. Pin deferred requires as well as the
-- entry point so newly added modules cannot disappear or come from an older
-- installed copy after that reset. Compile loaders without executing modules.
local lua_path = plugin_path .. "/lua"
for _, path in ipairs(vim.fn.globpath(lua_path .. "/sqlflick", "**/*.lua", false, true)) do
  local name = path:sub(#lua_path + 2):gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")
  package.preload[name] = assert(loadfile(path))
end

-- Preload the local module so Lazy uses this checkout when the SQL FileType
-- event loads the user's sqlflick.nvim spec.
require("sqlflick")
