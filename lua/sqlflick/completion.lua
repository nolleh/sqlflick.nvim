local M = {}

local max_schema_attempts = 3

local state = {
  get_database = function()
    return nil
  end,
  fetch_schema = function()
    return nil, "schema fetcher is not configured"
  end,
  schemas = {},
  failures = {},
  notify = function(message, level)
    vim.notify(message, level)
  end,
}

local keywords = {
  "SELECT",
  "FROM",
  "WHERE",
  "JOIN",
  "LEFT",
  "RIGHT",
  "INNER",
  "OUTER",
  "FULL",
  "CROSS",
  "ON",
  "AS",
  "AND",
  "OR",
  "NOT",
  "NULL",
  "IS",
  "IN",
  "EXISTS",
  "BETWEEN",
  "LIKE",
  "GROUP",
  "BY",
  "HAVING",
  "ORDER",
  "ASC",
  "DESC",
  "LIMIT",
  "OFFSET",
  "INSERT",
  "INTO",
  "VALUES",
  "UPDATE",
  "SET",
  "DELETE",
  "CREATE",
  "ALTER",
  "DROP",
  "TABLE",
  "VIEW",
  "DISTINCT",
  "UNION",
  "ALL",
  "CASE",
  "WHEN",
  "THEN",
  "ELSE",
  "END",
}

local reserved_words = {}
for _, keyword in ipairs(keywords) do
  reserved_words[keyword:lower()] = true
end

local function database_key(database)
  return table.concat({
    database.type or "",
    database.name or "",
    database.host or "",
    database.port or "",
    database.database or "",
    database.username or "",
  }, "\0")
end

local function supports_schema(database)
  return database and (database.type == "postgresql" or database.type == "mysql" or database.type == "sqlite")
end

local function load_schema(force)
  local database = state.get_database()
  if not supports_schema(database) then
    return nil, database and ("schema completion is not supported for " .. database.type) or "no database selected"
  end

  local key = database_key(database)
  if not force then
    if state.schemas[key] then
      return state.schemas[key]
    end
    local failure = state.failures[key]
    if failure and failure.disabled then
      return nil, failure.error
    end
  end

  local schema, err = state.fetch_schema(database)
  if not schema then
    local failure = state.failures[key] or { attempts = 0 }
    failure.attempts = failure.attempts + 1
    failure.error = err or "failed to load schema"
    failure.disabled = failure.attempts >= max_schema_attempts
    state.failures[key] = failure

    if failure.disabled and not failure.notified then
      failure.notified = true
      state.notify(
        string.format("SQL schema completion is disabled after %d failed attempts. ", max_schema_attempts)
          .. "Resolve the database/backend issue, then run :SQLFlickRefreshSchema.",
        vim.log.levels.WARN
      )
    end

    return nil, failure.error
  end

  schema.tables = schema.tables or {}
  state.schemas[key] = schema
  state.failures[key] = nil
  return schema
end

local function strip_identifier(identifier)
  return (identifier:gsub('["`]', ""))
end

local function sanitize_sql(sql)
  return sql:gsub("%-%-[^\n]*", " "):gsub("/%*.-%*/", " "):gsub("'[^']*'", " ")
end

local function relation_references(sql)
  local normalized = sanitize_sql(sql):lower():gsub("%s+", " ")
  local relations = {}

  local function collect(clause)
    local pattern = "%f[%a]" .. clause .. '%f[%A]%s+([%w_$%."`]+)%s*([%w_$]*)%s*([%w_$]*)'
    for table_name, first_alias, second_alias in normalized:gmatch(pattern) do
      table_name = strip_identifier(table_name)
      local alias = first_alias == "as" and second_alias or first_alias
      if alias == "" or reserved_words[alias] then
        alias = nil
      end
      table.insert(relations, {
        name = table_name,
        alias = alias,
      })
    end
  end

  collect("from")
  collect("join")
  return relations
end

local function table_index(schema)
  local index = {}
  for _, item in ipairs(schema.tables or {}) do
    local name = item.name:lower()
    index[name] = index[name] or item
    if item.schema and item.schema ~= "" then
      index[(item.schema .. "." .. item.name):lower()] = item
    end
  end
  return index
end

local function referenced_tables(sql, schema)
  local index = table_index(schema)
  local tables = {}
  for _, relation in ipairs(relation_references(sql)) do
    local item = index[relation.name]
    if item then
      table.insert(tables, {
        table = item,
        alias = relation.alias,
        reference = relation.name,
      })
    end
  end
  return tables
end

local function matches_base(word, base)
  return base == "" or word:lower():sub(1, #base) == base:lower()
end

local function add_match(matches, seen, word, kind, menu, base)
  local key = word:lower()
  if not seen[key] and matches_base(word, base) then
    seen[key] = true
    table.insert(matches, {
      word = word,
      abbr = word,
      kind = kind,
      menu = menu,
      icase = 1,
    })
  end
end

local function is_table_context(prefix)
  local tail = sanitize_sql(prefix):lower():gsub("%s+", " ")
  return tail:match('%f[%a]from%f[%A]%s+[%w_$%."`]*$') or tail:match('%f[%a]join%f[%A]%s+[%w_$%."`]*$')
end

local function qualifier_at_cursor(prefix)
  return sanitize_sql(prefix):lower():match("([%w_$]+)%.[%w_$]*$")
end

local function add_keywords(matches, seen, base)
  for _, keyword in ipairs(keywords) do
    add_match(matches, seen, keyword, "k", "[keyword]", base)
  end
end

---Build native completion items for a SQL statement.
---@param sql string full current SQL statement
---@param cursor_offset number number of bytes before the cursor
---@param schema table|nil cached schema payload
---@param base string current completion base
---@return table[]
function M.complete(sql, cursor_offset, schema, base)
  base = base or ""
  local prefix = sql:sub(1, cursor_offset)
  local matches = {}
  local seen = {}

  if is_table_context(prefix) then
    if schema then
      for _, item in ipairs(schema.tables or {}) do
        local menu = string.format("[%s]", item.type or "table")
        if item.schema and item.schema ~= "" then
          menu = menu .. " " .. item.schema
        end
        add_match(matches, seen, item.name, "t", menu, base)
      end
    end
    if #matches == 0 then
      add_keywords(matches, seen, base)
    end
    return matches
  end

  local qualifier = qualifier_at_cursor(prefix)
  if qualifier and schema then
    for _, reference in ipairs(referenced_tables(sql, schema)) do
      local table_name = reference.table.name:lower()
      local short_reference = reference.reference:match("([^.]+)$")
      if qualifier == reference.alias or qualifier == table_name or qualifier == short_reference then
        for _, column in ipairs(reference.table.columns or {}) do
          add_match(matches, seen, column.name, "f", "[column] " .. reference.table.name, base)
        end
      end
    end
    return matches
  end

  if schema then
    local tables = referenced_tables(sql, schema)
    if #tables == 0 then
      for _, item in ipairs(schema.tables or {}) do
        table.insert(tables, { table = item })
      end
    end

    for _, reference in ipairs(tables) do
      for _, column in ipairs(reference.table.columns or {}) do
        add_match(matches, seen, column.name, "f", "[column] " .. reference.table.name, base)
      end
    end
  end

  add_keywords(matches, seen, base)
  return matches
end

function M.find_start(line, cursor_column)
  local start = cursor_column
  while start > 0 and line:sub(start, start):match("[%w_$]") do
    start = start - 1
  end
  return start
end

local function current_statement()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current_line = lines[cursor[1]] or ""

  local before_lines = {}
  for index = 1, cursor[1] - 1 do
    table.insert(before_lines, lines[index])
  end
  table.insert(before_lines, current_line:sub(1, cursor[2]))

  local after_lines = { current_line:sub(cursor[2] + 1) }
  for index = cursor[1] + 1, #lines do
    table.insert(after_lines, lines[index])
  end

  local before = table.concat(before_lines, "\n")
  local after = table.concat(after_lines, "\n")
  local statement_start = (before:match(".*();") or 0) + 1
  local next_semicolon = after:find(";", 1, true)
  local statement_end = next_semicolon and (#before + next_semicolon - 1) or (#before + #after)
  local sql = (before .. after):sub(statement_start, statement_end)

  return sql, #before - statement_start + 1
end

---Neovim omnifunc entry point. Invoke with <C-x><C-o> in insert mode.
function M.omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    return M.find_start(line, vim.api.nvim_win_get_cursor(0)[2])
  end

  local schema = load_schema(false)
  local sql, cursor_offset = current_statement()
  return M.complete(sql, cursor_offset, schema, base)
end

function M.attach(buffer)
  vim.api.nvim_set_option_value("omnifunc", "v:lua.sqlflick_completion_omnifunc", { buf = buffer })
end

function M.refresh()
  local database = state.get_database()
  if database then
    local key = database_key(database)
    state.schemas[key] = nil
    state.failures[key] = nil
  end
  return load_schema(true)
end

function M.clear()
  state.schemas = {}
  state.failures = {}
end

function M.setup(opts)
  state.get_database = opts.get_database
  state.fetch_schema = opts.fetch_schema
  state.notify = opts.notify or function(message, level)
    vim.notify(message, level)
  end
end

-- Function options cannot resolve require() expressions, so keep the global
-- surface to one stable bridge and leave the implementation in this module.
_G.sqlflick_completion_omnifunc = M.omnifunc

return M
