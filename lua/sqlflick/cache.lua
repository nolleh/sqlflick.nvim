local M = {}
local cache_file = vim.fn.stdpath("data") .. "/sqlflick_cache.json"

function M.save_cache_table(tbl)
  local f = io.open(cache_file, "w")
  if f then
    f:write(vim.fn.json_encode(tbl))
    f:close()
  end
end

function M.load_cache(key)
  local f = io.open(cache_file, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local cache = vim.fn.json_decode(content) or {}
    if key ~= nil then
      return cache[key]
    else
      return cache
    end
  end
  return key and nil or {}
end

function M.save_cache(key, value)
  local cache = M.load_cache()
  cache[key] = value
  M.save_cache_table(cache)
end

return M
