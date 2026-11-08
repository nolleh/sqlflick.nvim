local M = {}
local entries = {}
local limit = 100

function M.setup(opts)
  opts = opts or {}
  limit = opts.enabled == false and 0 or math.max(0, math.floor(tonumber(opts.max_entries) or 100))
  while #entries > limit do
    table.remove(entries)
  end
end

function M.start(sql, db)
  if limit == 0 then
    return nil
  end
  local entry = {
    sql = sql,
    connection = { id = db.id or db.name, name = db.name or db.id or db.type, type = db.type, database = db.database },
    state = "running",
    started_at = os.time(),
  }
  table.insert(entries, 1, entry)
  while #entries > limit do
    table.remove(entries)
  end
  -- Keep timing private and monotonic; no connection credentials are retained.
  return { entry = entry, started = vim.uv.hrtime() }
end

function M.finish(record, state)
  if not record or record.entry.state ~= "running" then
    return
  end
  record.entry.state = state
  record.entry.duration_ms = math.floor((vim.uv.hrtime() - record.started) / 1000000)
end

function M.list()
  return vim.deepcopy(entries)
end

return M
