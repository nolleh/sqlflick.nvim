local M = {}

local config = require("sqlflick.config")

-- Pagination state
M.state = {
  enabled = false,
  current_page = 1,
  page_size = config.opts.pagination.page_size or 20, -- Default page size from config
  total_rows = 0,
  total_pages = 1,
  query_text = "",
  db_config = nil,
  backend_config = nil,
  original_result = nil, -- Store full result for reference
}

-- Initialize pagination state
function M.init(query_text, db_config, backend_config, total_rows)
  -- Update page_size from config
  M.state.page_size = config.opts.pagination.page_size or 20
  M.state.enabled = true
  M.state.current_page = 1
  M.state.query_text = query_text
  M.state.db_config = db_config
  M.state.backend_config = backend_config
  M.state.total_rows = total_rows
  M.state.total_pages = math.ceil(total_rows / M.state.page_size)
  M.state.original_result = nil
end

-- Reset pagination state
function M.reset()
  M.state.enabled = false
  M.state.current_page = 1
  M.state.total_rows = 0
  M.state.total_pages = 1
  M.state.query_text = ""
  M.state.db_config = nil
  M.state.backend_config = nil
  M.state.original_result = nil
end

-- Check if pagination is enabled
function M.is_enabled()
  return M.state.enabled
end

-- Get current page
function M.get_current_page()
  return M.state.current_page
end

-- Get total pages
function M.get_total_pages()
  return M.state.total_pages
end

-- Get page size
function M.get_page_size()
  return M.state.page_size
end

-- Set page size
function M.set_page_size(size)
  if size > 0 then
    M.state.page_size = size
    if M.state.enabled then
      M.state.total_pages = math.ceil(M.state.total_rows / M.state.page_size)
      if M.state.current_page > M.state.total_pages then
        M.state.current_page = M.state.total_pages
      end
    end
  end
end

-- Navigate to next page
function M.next_page()
  if not M.state.enabled then
    return false
  end
  if M.state.current_page < M.state.total_pages then
    M.state.current_page = M.state.current_page + 1
    return true
  end
  return false
end

-- Navigate to previous page
function M.prev_page()
  if not M.state.enabled then
    return false
  end
  if M.state.current_page > 1 then
    M.state.current_page = M.state.current_page - 1
    return true
  end
  return false
end

-- Navigate to first page
function M.first_page()
  if not M.state.enabled then
    return false
  end
  if M.state.current_page ~= 1 then
    M.state.current_page = 1
    return true
  end
  return false
end

-- Navigate to last page
function M.last_page()
  if not M.state.enabled then
    return false
  end
  if M.state.current_page ~= M.state.total_pages then
    M.state.current_page = M.state.total_pages
    return true
  end
  return false
end

-- Navigate to specific page
function M.go_to_page(page)
  if not M.state.enabled then
    return false
  end
  if page >= 1 and page <= M.state.total_pages then
    M.state.current_page = page
    return true
  end
  return false
end

-- Skip pages forward
function M.skip_pages_forward(count)
  if not M.state.enabled then
    return false
  end
  local new_page = math.min(M.state.current_page + count, M.state.total_pages)
  if new_page ~= M.state.current_page then
    M.state.current_page = new_page
    return true
  end
  return false
end

-- Skip pages backward
function M.skip_pages_backward(count)
  if not M.state.enabled then
    return false
  end
  local new_page = math.max(M.state.current_page - count, 1)
  if new_page ~= M.state.current_page then
    M.state.current_page = new_page
    return true
  end
  return false
end

-- Calculate offset for current page
function M.get_offset()
  return (M.state.current_page - 1) * M.state.page_size
end

-- Generate progress bar
function M.generate_progress_bar(current, total, width)
  if total == 0 then
    return string.rep("░", width)
  end
  local filled = math.floor((current / total) * width)
  local bar = string.rep("█", filled) .. string.rep("░", width - filled)
  return bar
end

-- Get pagination info string
function M.get_info_string()
  if not M.state.enabled then
    return ""
  end
  local start_row = (M.state.current_page - 1) * M.state.page_size + 1
  local end_row = math.min(M.state.current_page * M.state.page_size, M.state.total_rows)
  local progress_bar = M.generate_progress_bar(M.state.current_page, M.state.total_pages, 20)
  local percentage = M.state.total_pages > 0 and math.floor((M.state.current_page / M.state.total_pages) * 100) or 0

  return string.format(
    "📄 Page %d/%d [Rows %d-%d of %d] %s %d%%",
    M.state.current_page,
    M.state.total_pages,
    start_row,
    end_row,
    M.state.total_rows,
    progress_bar,
    percentage
  )
end

return M
