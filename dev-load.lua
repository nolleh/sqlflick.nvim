-- Development loader for sqlflick.nvim.
-- It pins this checkout before the user's plugin manager initializes, allowing
-- the existing Neovim configuration to provide the normal SQLFlick options.

local plugin_path = vim.fn.expand("<sfile>:p:h")

vim.opt.runtimepath:prepend(plugin_path)

-- Preload the local module so Lazy uses this checkout when the SQL FileType
-- event loads the user's sqlflick.nvim spec.
require("sqlflick")
