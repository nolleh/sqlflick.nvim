local M = {}

local function identifier_char(c)
  local byte = c:byte()
  return byte ~= nil and (c:match("[%w_$]") ~= nil or byte >= 128)
end

local function dollar_tag(text, i)
  if i > 1 and identifier_char(text:sub(i - 1, i - 1)) then return nil end
  if text:sub(i + 1, i + 1) == "$" then return "$$" end
  local j = i + 1
  local first = text:sub(j, j)
  if not (first:match("[%a_]") or (first:byte() or 0) >= 128) then return nil end
  repeat j = j + 1 until not identifier_char(text:sub(j, j)) or text:sub(j, j) == "$"
  if text:sub(j, j) == "$" then return text:sub(i, j) end
end

local function selected(text, first, last, has_sql)
  if not has_sql then return nil, "No SQL statement at cursor" end
  return (text:sub(first, last):gsub("^%s+", ""):gsub("%s+$", ""))
end

---Find the statement containing a 1-based byte offset. SQL text is not rewritten.
---A terminator belongs to the preceding statement; following whitespace belongs
---to the next one. Later incomplete statements cannot invalidate an earlier one.
---@param text string
---@param cursor integer
---@param dialect? string
---@return string|nil query
---@return string|nil error
function M.extract(text, cursor, dialect)
  if type(cursor) ~= "number" or cursor < 1 or cursor > #text + 1 or cursor % 1 ~= 0 then
    return nil, "Cursor outside SQL text"
  end
  dialect = dialect or "postgresql"
  local postgres = dialect == "postgresql" or dialect == "postgres" or dialect == "pgsql"
  local mysql = dialect == "mysql"
  local sqlite = dialect == "sqlite"
  local state, i, first, has_sql = "normal", 1, 1, false
  local closer, escapes, doubled, tag, depth
  local q_closers = { ["["] = "]", ["{"] = "}", ["("] = ")", ["<"] = ">" }

  while i <= #text do
    local c, pair = text:sub(i, i), text:sub(i, i + 1)
    if state == "line_comment" then
      if c == "\n" or c == "\r" then state = "normal" end
      i = i + 1
    elseif state == "block_comment" then
      if postgres and pair == "/*" then
        depth, i = depth + 1, i + 2
      elseif pair == "*/" then
        depth, i = depth - 1, i + 2
        if depth == 0 then state = "normal" end
      else
        i = i + 1
      end
    elseif state == "quoted" then
      if escapes and c == "\\" then
        i = i + 2
      elseif c == closer then
        if doubled and text:sub(i + 1, i + 1) == closer then
          i = i + 2
        else
          state, i = "normal", i + 1
        end
      else
        i = i + 1
      end
    elseif state == "dollar" then
      local ending = text:find(tag, i, true)
      if not ending then return nil, "Unterminated dollar-quoted SQL text" end
      state, i = "normal", ending + #tag
    elseif state == "oracle_quote" then
      if pair == closer .. "'" then state, i = "normal", i + 2
      else i = i + 1 end
    else
      local after_dash = text:sub(i + 2, i + 2)
      if pair == "--" and (not mysql or after_dash == "" or after_dash:byte() <= 32) then
        state, i = "line_comment", i + 2
      elseif mysql and c == "#" then
        state, i = "line_comment", i + 1
      elseif pair == "/*" then
        state, depth, i = "block_comment", 1, i + 2
      elseif c == "'" or c == '"' or ((mysql or sqlite) and c == "`") or (sqlite and c == "[") then
        local prefix = text:sub(i - 1, i - 1)
        escapes = (mysql and c ~= "`") or (postgres and c == "'" and (prefix == "E" or prefix == "e")
          and (i <= 2 or not identifier_char(text:sub(i - 2, i - 2))))
        closer, doubled = c == "[" and "]" or c, c ~= "["
        state, has_sql, i = "quoted", true, i + 1
      elseif postgres and c == "$" and dollar_tag(text, i) then
        tag = dollar_tag(text, i)
        state, has_sql, i = "dollar", true, i + #tag
      elseif dialect == "oracle" and (c == "q" or c == "Q") and text:sub(i + 1, i + 1) == "'"
        and (i == 1 or not identifier_char(text:sub(i - 1, i - 1))) then
        local opening = text:sub(i + 2, i + 2)
        closer = q_closers[opening] or opening
        state, has_sql, i = "oracle_quote", true, i + 3
      elseif c == ";" then
        if cursor <= i then return selected(text, first, i, has_sql) end
        first, has_sql, i = i + 1, false, i + 1
      else
        if not c:match("%s") then has_sql = true end
        i = i + 1
      end
    end
  end
  if state ~= "normal" and state ~= "line_comment" then
    return nil, "Unterminated SQL quote or block comment"
  end
  return selected(text, first, #text, has_sql)
end

---Neovim supplies a 1-based row and a 0-based byte column.
function M.at_cursor(lines, row, col, dialect)
  if not lines[row] or col < 0 or col > #lines[row] then
    return nil, "Cursor outside SQL buffer"
  end
  if dialect == "redis" then
    return selected(lines[row], 1, #lines[row], lines[row]:find("%S") ~= nil)
  end
  local cursor = col + 1
  for i = 1, row - 1 do cursor = cursor + #lines[i] + 1 end
  return M.extract(table.concat(lines, "\n"), cursor, dialect)
end

return M
