local M = {}
local uv = vim.loop
local cache_file = vim.fn.stdpath("data") .. "/sqlflick_cache.json"
local cache_version = 2

local function write_cache(selected_id)
  local contents = vim.fn.json_encode({ version = cache_version, last_db_id = selected_id })
  local temp_file = string.format("%s.%d.%s.tmp", cache_file, vim.fn.getpid(), uv.hrtime())
  local fd, open_error = uv.fs_open(temp_file, "w", 384) -- 0600
  if not fd then
    vim.notify("Failed to write SQLFlick cache: " .. open_error, vim.log.levels.ERROR)
    return false
  end

  local written, write_error = uv.fs_write(fd, contents, -1)
  uv.fs_close(fd)
  if written ~= #contents then
    uv.fs_unlink(temp_file)
    vim.notify("Failed to write SQLFlick cache: " .. (write_error or "incomplete write"), vim.log.levels.ERROR)
    return false
  end

  local renamed, rename_error = uv.fs_rename(temp_file, cache_file)
  if not renamed then
    uv.fs_unlink(temp_file)
    vim.notify("Failed to write SQLFlick cache: " .. rename_error, vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.load_selected_id()
  local file = io.open(cache_file, "r")
  if not file then
    return nil
  end

  local contents = file:read("*a")
  file:close()
  local decoded, value = pcall(vim.fn.json_decode, contents)
  if not decoded or type(value) ~= "table" or value.version ~= cache_version then
    -- Discard old full connection configs, including any stored password.
    write_cache(nil)
    return nil
  end

  for key in pairs(value) do
    if key ~= "version" and key ~= "last_db_id" then
      write_cache(nil)
      return nil
    end
  end

  if value.last_db_id ~= nil and type(value.last_db_id) ~= "string" then
    write_cache(nil)
    return nil
  end
  if value.last_db_id == nil or value.last_db_id == "" then
    return nil
  end
  return value.last_db_id
end

function M.save_selected_id(id)
  return write_cache(id)
end

return M
