local M = {}

function M.setup()
	-- Tab line highlights
	vim.api.nvim_set_hl(0, "SQLSnapTabLine", { bg = "#3c3836", fg = "#a89984" })
	vim.api.nvim_set_hl(0, "SQLSnapTabLineSel", { bg = "#504945", fg = "#ebdbb2", bold = true })
	vim.api.nvim_set_hl(0, "SQLSnapTabLineFill", { bg = "#3c3836" })

	-- Content highlights
	vim.api.nvim_set_hl(0, "SQLSnapHeader", { fg = "#83a598", bold = true })
	vim.api.nvim_set_hl(0, "SQLSnapHeaderSep", { fg = "#504945" })
	vim.api.nvim_set_hl(0, "SQLSnapCell", { fg = "#ebdbb2" })
	vim.api.nvim_set_hl(0, "SQLSnapError", { fg = "#ef9a9a" })
end

return M
