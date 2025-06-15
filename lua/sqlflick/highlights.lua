local M = {}

function M.setup()
  -- Tab line highlights
  vim.api.nvim_set_hl(0, "SQLFlickTabLine", { bg = "#3c3836", fg = "#a89984" })
  vim.api.nvim_set_hl(0, "SQLFlickTabLineSel", { bg = "#504945", fg = "#ebdbb2", bold = true })
  vim.api.nvim_set_hl(0, "SQLFlickTabLineFill", { bg = "#3c3836" })

  -- Content highlights
  vim.api.nvim_set_hl(0, "SQLFlickHeader", { fg = "#83a598", bold = true })
  vim.api.nvim_set_hl(0, "SQLFlickHeaderSep", { fg = "#504945" })
  vim.api.nvim_set_hl(0, "SQLFlickCell", { fg = "#ebdbb2" })
  vim.api.nvim_set_hl(0, "SQLFlickError", { fg = "#ef9a9a" })
end

return M
