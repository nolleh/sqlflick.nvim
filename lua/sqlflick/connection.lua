local M = {}

local function decode(value)
  local remainder = value:gsub("%%%x%x", "")
  if remainder:find("%%") then
    error("Invalid escape")
  end
  local decoded = value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  if decoded:find("%z") or decoded:find("[\r\n]") then
    error("Invalid character")
  end
  return decoded
end

local function encode(value)
  return (value:gsub("[^%w%-._~]", function(char)
    return string.format("%%%02X", char:byte())
  end))
end

local function sqlite_connection(value)
  local path, query = value:match("^(.-)%?(.*)$")
  path = path or value
  if path:sub(1, 12) == "jdbc:sqlite:" then
    path = path:sub(13)
  elseif path:sub(1, 10) == "sqlite:///" then
    path = path:sub(11)
  elseif path:sub(1, 5) == "file:" then
    path = path:sub(6)
    if path:sub(1, 2) == "//" then
      local authority, filename = path:match("^//([^/]*)(/.*)$")
      if authority ~= "" and authority ~= "localhost" then
        error("Unsupported file authority")
      end
      path = filename
    end
  else
    error("Unsupported SQLite URL")
  end
  if not path or path == "" or value:find("#", 1, true) then
    error("Missing SQLite filename")
  end
  path = decode(path)
  if path == ":memory:" or (query and query:find("mode=memory", 1, true)) then
    error("Memory databases cannot refer to the project's existing database")
  end
  local absolute = vim.fn.fnamemodify(path, ":p")
  local escaped = encode(absolute):gsub("%%2F", "/"):gsub("%%3A", ":")
  return {
    type = "sqlite",
    database = absolute,
    url = "file:" .. escaped .. (query and "?" .. query or ""),
  }
end

local function parse(value)
  if value:match("^file:") or value:match("^sqlite:") or value:match("^jdbc:sqlite:") then
    return sqlite_connection(value)
  end
  if value:match("^jdbc:oracle:thin:") then
    local credentials, address = value:match("^jdbc:oracle:thin:(.-)@//(.+)$")
    if not address or address:find("?", 1, true) then
      error("Unsupported Oracle JDBC URL")
    end
    local user, password = credentials:match("^([^/]+)/(.+)$")
    if credentials ~= "" and not user then
      error("Invalid Oracle credentials")
    end
    value = "oracle://" .. (user and encode(user) .. ":" .. encode(password) .. "@" or "") .. address
  end
  local jdbc = value:sub(1, 5) == "jdbc:"
  local url = jdbc and value:sub(6) or value
  local scheme, rest = url:match("^(%a+)://(.*)$")
  local types = {
    postgresql = "postgresql",
    postgres = "postgresql",
    mysql = "mysql",
    redis = "redis",
    rediss = "redis",
    oracle = "oracle",
  }
  local db_type = types[scheme]
  if not db_type or (jdbc and db_type ~= "postgresql" and db_type ~= "mysql") then
    error("Unsupported scheme")
  end
  if url:find("[%s#]") then
    error("Invalid URL")
  end
  local location, query = rest:match("^(.-)%?(.*)$")
  location = location or rest
  local authority, path = location:match("^([^/]*)(.*)$")
  local params = {}
  for pair in (query or ""):gmatch("[^&]+") do
    local key, val = pair:match("^([^=]+)=(.*)$")
    if not key then
      error("Invalid parameter")
    end
    key, val = decode(key:gsub("%+", " ")), decode(val:gsub("%+", " "))
    if params[key] ~= nil then
      error("Duplicate parameter")
    end
    params[key] = val
  end
  if jdbc and db_type == "postgresql" then
    local names = {
      user = "user",
      password = "password",
      sslmode = "sslmode",
      sslcert = "sslcert",
      sslkey = "sslkey",
      sslrootcert = "sslrootcert",
      connectTimeout = "connect_timeout",
      currentSchema = "search_path",
      ApplicationName = "application_name",
      options = "options",
    }
    local converted = {}
    for key, val in pairs(params) do
      local target = names[key]
      if key == "ssl" and (val == "true" or val == "false") then
        target, val = "sslmode", val == "true" and "verify-full" or "disable"
      end
      if not target or converted[target] ~= nil then
        error("Unsupported JDBC parameter")
      end
      converted[target] = val
    end
    params = converted
    local pairs_encoded = {}
    for key, val in pairs(params) do
      pairs_encoded[#pairs_encoded + 1] = encode(key) .. "=" .. encode(val)
    end
    table.sort(pairs_encoded)
    url = "postgresql://" .. location .. (#pairs_encoded > 0 and "?" .. table.concat(pairs_encoded, "&") or "")
  elseif jdbc then
    local converted = {}
    for key, val in pairs(params) do
      if key == "connectTimeout" or key == "socketTimeout" then
        if not val:match("^%d+$") then
          error("Invalid JDBC timeout")
        end
        if key == "socketTimeout" then
          converted.writeTimeout = val .. "ms"
        end
        key, val = key == "connectTimeout" and "timeout" or "readTimeout", val .. "ms"
      elseif key == "sslMode" then
        local modes = { DISABLED = "false", REQUIRED = "skip-verify", VERIFY_IDENTITY = "true" }
        key, val = "tls", modes[val]
        if not val then
          error("Unsupported JDBC TLS mode")
        end
      elseif key ~= "user" and key ~= "password" then
        error("Unsupported JDBC parameter")
      end
      converted[key] = val
    end
    params = converted
    local encoded = {}
    for key, val in pairs(params) do
      encoded[#encoded + 1] = encode(key) .. "=" .. encode(val)
    end
    table.sort(encoded)
    url = "mysql://" .. location .. (#encoded > 0 and "?" .. table.concat(encoded, "&") or "")
  end
  local userinfo, address = authority:match("^(.-)@([^@]*)$")
  address = address or authority
  local username, password
  if userinfo then
    if userinfo:find("@", 1, true) then
      error("Invalid user information")
    end
    username, password = userinfo:match("^([^:]*):(.*)$")
    username = decode(username or userinfo)
    password = password and decode(password) or nil
  end
  local host, port
  if address:sub(1, 1) == "[" then
    host, port = address:match("^%[([^%]]+)%]:(%d+)$")
    if not host then
      host = address:match("^%[([^%]]+)%]$")
      port = host and "" or nil
    end
  else
    host, port = address:match("^([^:,]*):?(%d*)$")
  end
  if not host then
    error("Invalid or multiple hosts")
  end
  host = db_type == "postgresql" and params.host or decode(host)
  port = db_type == "postgresql" and params.port or port
  if host:find(",", 1, true) or port:find(",", 1, true) then
    error("Multiple hosts are unsupported")
  end
  if port ~= "" and (not port:match("^%d+$") or tonumber(port) < 1 or tonumber(port) > 65535) then
    error("Invalid port")
  end
  local database = decode(path:gsub("^/", ""))
  if db_type == "postgresql" then
    database = params.dbname or database
  elseif db_type == "redis" then
    database = params.db or (database ~= "" and database or "0")
    if not database:match("^%d+$") then
      error("Invalid Redis database number")
    end
  elseif database:find("/", 1, true) then
    error("Invalid database name")
  end
  local defaults = { mysql = 3306, redis = 6379, oracle = 1521 }
  if db_type == "oracle" and (host == "" or database == "") then
    error("Oracle host and service name are required")
  end
  return {
    type = db_type,
    host = host ~= "" and host or (db_type ~= "postgresql" and "localhost" or nil),
    port = port ~= "" and tonumber(port) or defaults[db_type],
    database = database,
    username = (db_type == "postgresql" or db_type == "mysql") and params.user or username,
    password = (db_type == "postgresql" or db_type == "mysql") and params.password or password,
    url = url,
  }
end

-- Never include the input in diagnostics: it may contain credentials.
function M.from_url(value, source)
  source = source or "DATABASE_URL"
  if type(value) ~= "string" or value == "" then
    return nil, source .. " is empty"
  end
  local ok, connection = pcall(parse, value)
  if not ok then
    return nil,
      "Invalid or unsupported "
        .. source
        .. "; expected a supported PostgreSQL, MySQL, SQLite, Redis, or Oracle connection URL"
  end
  connection.name = source
  connection.id = "env:" .. source
  return connection
end

return M
