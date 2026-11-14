local connection = require("sqlflick.connection")

describe("PostgreSQL connection URLs", function()
  for _, scheme in ipairs({ "postgresql", "postgres", "jdbc:postgresql" }) do
    it("reads " .. scheme .. " credentials and preserves TLS", function()
      local db = assert(connection.from_url(scheme .. "://app:p%40ss@localhost:5432/app_dev?sslmode=require"))
      assert.equals("postgresql", db.type)
      assert.equals("app", db.username)
      assert.equals("p@ss", db.password)
      assert.equals("localhost", db.host)
      assert.equals(5432, db.port)
      assert.equals("app_dev", db.database)
      assert.matches("sslmode=require", db.url, 1, true)
    end)
  end

  it("keeps unspecified fields absent so the driver can use its defaults", function()
    local db = assert(connection.from_url("postgresql:///app"))
    assert.is_nil(db.host)
    assert.is_nil(db.port)
    assert.is_nil(db.username)
    assert.equals("app", db.database)
  end)

  it("supports IPv6 and percent-encoded database names", function()
    local db = assert(connection.from_url("postgres://app@[::1]:5432/app%20dev"))
    assert.equals("::1", db.host)
    assert.equals("app dev", db.database)
  end)

  it("supports IPv6 without an explicit port", function()
    local db = assert(connection.from_url("postgres://app@[::1]/app"))
    assert.equals("::1", db.host)
    assert.is_nil(db.port)
  end)

  it("displays query parameters that override the URL endpoint", function()
    local db = assert(connection.from_url("postgres://old@localhost/old?host=remote&port=5433&user=new&dbname=new"))
    assert.equals("remote", db.host)
    assert.equals(5433, db.port)
    assert.equals("new", db.username)
    assert.equals("new", db.database)
  end)

  it("translates supported JDBC options to PostgreSQL parameters", function()
    local db = assert(
      connection.from_url(
        "jdbc:postgresql://localhost/app?user=app&password=s%40fe&ssl=true&connectTimeout=5&currentSchema=public"
      )
    )
    assert.equals("s@fe", db.password)
    assert.matches("sslmode=verify%-full", db.url)
    assert.matches("connect_timeout=5", db.url, 1, true)
    assert.matches("search_path=public", db.url, 1, true)
  end)

  for _, value in ipairs({
    "mongodb://user:secret@localhost/app",
    "postgres://user:secret@localhost:bad/app",
    "postgres://user:secret@localhost:65536/app",
    "postgres://user:secret@host1,host2/app",
    "postgres://user:secret@localhost/app?host=host1,host2",
    "postgres://user:secret%ZZ@localhost/app",
    "postgres://user:secret@localhost/app#fragment",
    "postgres://user:secret@localhost/app?sslmode=require&sslmode=disable",
    "jdbc:postgresql://user:secret@localhost/app?socketFactory=custom",
    "postgres://user:secret@other@localhost/app",
    "postgres://app@[::1]5432/app",
  }) do
    it("rejects unsupported or invalid input without exposing credentials: case " .. _, function()
      local db, err = connection.from_url(value)
      assert.is_nil(db)
      assert.is_nil(err:find("secret", 1, true))
    end)
  end
end)

describe("Database URL detection", function()
  local cases = {
    { "mysql://app:p%40ss@localhost:3307/app?parseTime=true&tls=true", "mysql", "app", 3307 },
    {
      "jdbc:mysql://localhost/app?user=app&password=p%40ss&connectTimeout=2000&sslMode=VERIFY_IDENTITY",
      "mysql",
      "app",
      3306,
    },
    { "redis://default:p%40ss@localhost:6380/2", "redis", "2", 6380 },
    { "rediss://default:p%40ss@localhost/3", "redis", "3", 6379 },
    { "redis://localhost", "redis", "0", 6379 },
    { "redis://localhost/1?db=4", "redis", "4", 6379 },
    { "oracle://app:p%40ss@localhost/appservice?SSL=enable", "oracle", "appservice", 1521 },
    { "jdbc:oracle:thin:app/p@ssword@//localhost:1521/appservice", "oracle", "appservice", 1521 },
  }
  for _, case in ipairs(cases) do
    it("detects connection type for " .. case[1]:match("^[^:]+"), function()
      local db = assert(connection.from_url(case[1], "SQFLK_DB_URL"))
      assert.equals(case[2], db.type)
      assert.equals(case[3], db.database)
      assert.equals(case[4], db.port)
      assert.equals("env:SQFLK_DB_URL", db.id)
      assert.is_nil(db.url:match("^jdbc:"))
    end)
  end

  it("translates JDBC MySQL options and credentials", function()
    local db = assert(
      connection.from_url(
        "jdbc:mysql://localhost/app?user=app&password=p%40ss&connectTimeout=2000&socketTimeout=3000&sslMode=REQUIRED"
      )
    )
    assert.equals("app", db.username)
    assert.equals("p@ss", db.password)
    assert.matches("timeout=2000ms", db.url, 1, true)
    assert.matches("readTimeout=3000ms", db.url, 1, true)
    assert.matches("writeTimeout=3000ms", db.url, 1, true)
    assert.matches("tls=skip%-verify", db.url)
  end)

  for _, prefix in ipairs({ "file:", "sqlite:///", "jdbc:sqlite:" }) do
    it("resolves relative SQLite files for " .. prefix, function()
      local db = assert(connection.from_url(prefix .. "data/app%20dev.db?mode=ro"))
      assert.equals("sqlite", db.type)
      assert.equals(vim.fn.getcwd() .. "/data/app dev.db", db.database)
      assert.equals("file:" .. vim.fn.getcwd() .. "/data/app%20dev.db?mode=ro", db.url)
    end)
  end

  it("recognizes absolute SQLite paths", function()
    for _, value in ipairs({ "file:///tmp/app.db", "file://localhost/tmp/app.db", "sqlite:////tmp/app.db" }) do
      local db = assert(connection.from_url(value))
      assert.equals("/tmp/app.db", db.database)
    end
  end)

  it("allows a memory journal on a file-backed SQLite database", function()
    for _, options in ipairs({
      "_journal_mode=memory",
      "_journal_mode=MEMORY",
      "mode=rw&_journal_mode=memory",
      "application=mode%3Dmemory",
    }) do
      local db = assert(connection.from_url("file:./app.db?" .. options))
      assert.equals("sqlite", db.type)
      assert.equals(vim.fn.getcwd() .. "/app.db", db.database)
      assert.matches(options, db.url, 1, true)
    end
  end)

  it("rejects the exact memory mode including percent-encoded parameters", function()
    for _, options in ipairs({ "mode=memory", "cache=shared&mode=memory", "%6Dode=memory", "mode=%6Demory" }) do
      assert.is_nil(connection.from_url("file:./app.db?" .. options))
    end
  end)

  for _, value in ipairs({
    "redis://localhost/not-a-number",
    "redis://localhost/-1",
    "redis://localhost/1/2",
    "jdbc:mysql://localhost/app?useSSL=true",
    "jdbc:mysql://host1,host2/app",
    "file://remote/tmp/app.db",
    "sqlite:///",
    "jdbc:sqlite::memory:",
    "jdbc:oracle:thin:@host:1521:SID",
    "mongodb://localhost/app",
  }) do
    it("rejects unsupported connection form " .. _, function()
      assert.is_nil(connection.from_url(value))
    end)
  end
end)

describe("Environment connection configuration", function()
  local saved_config, saved_env, saved_sqflk_env, saved_notify, config, warnings
  before_each(function()
    saved_config = package.loaded["sqlflick.config"]
    saved_env, saved_notify = vim.env.DATABASE_URL, vim.notify
    saved_sqflk_env = vim.env.SQFLK_DB_URL
    vim.env.SQFLK_DB_URL = nil
    package.loaded["sqlflick.config"] = nil
    config = require("sqlflick.config")
    warnings = {}
    vim.notify = function(message)
      warnings[#warnings + 1] = message
    end
    vim.env.DATABASE_URL = "postgres://app@localhost/app?sslmode=require"
  end)
  after_each(function()
    package.loaded["sqlflick.config"] = saved_config
    vim.env.DATABASE_URL, vim.notify = saved_env, saved_notify
    vim.env.SQFLK_DB_URL = saved_sqflk_env
  end)

  it("adds a named picker connection alongside configured groups", function()
    config.setup({ databases = { development = { { name = "manual", type = "sqlite", database = "test.db" } } } })
    local tree = require("sqlflick.tree")
    local db = tree.find_database_by_id(config.opts.databases, "env:DATABASE_URL")
    assert.equals("DATABASE_URL", db.name)
    assert.equals(2, #tree.build_tree(config.opts.databases).children)
  end)

  it("uses SQFLK_DB_URL instead of DATABASE_URL when both are set", function()
    vim.env.SQFLK_DB_URL = "postgres://app@dedicated/tool_db?sslmode=require"
    config.setup({})
    assert.equals(1, #config.opts.databases)
    local db = config.opts.databases[1]
    assert.equals("SQFLK_DB_URL", db.name)
    assert.equals("env:SQFLK_DB_URL", db.id)
    assert.equals("dedicated", db.host)
    assert.equals("tool_db", db.database)
  end)

  for _, case in ipairs({
    { "mysql://app@localhost/app", "mysql" },
    { "redis://localhost/2", "redis" },
    { "file:./app.db?_journal_mode=memory", "sqlite" },
    { "oracle://app:pass@localhost/service", "oracle" },
  }) do
    it("adds a picker connection with inferred type " .. case[2], function()
      vim.env.SQFLK_DB_URL = case[1]
      config.setup({})
      local tree = require("sqlflick.tree")
      local db = tree.find_database_by_id(config.opts.databases, "env:SQFLK_DB_URL")
      assert.equals(case[2], db.type)
      assert.equals("SQFLK_DB_URL", tree.build_tree(config.opts.databases).children[1].name)
    end)
  end

  it("falls back to DATABASE_URL when SQFLK_DB_URL is empty", function()
    vim.env.SQFLK_DB_URL = ""
    config.setup({})
    assert.equals("DATABASE_URL", config.opts.databases[1].name)
  end)

  it("does not fall back when the dedicated value is invalid", function()
    vim.env.SQFLK_DB_URL = "mongodb://app:secret@dedicated/tool_db"
    config.setup({ databases = { { name = "manual" } } })
    assert.equals(1, #config.opts.databases)
    assert.equals("manual", config.opts.databases[1].name)
    assert.equals(1, #warnings)
    assert.matches("SQFLK_DB_URL", warnings[1], 1, true)
    assert.is_nil(warnings[1]:find("secret", 1, true))
  end)

  it("replaces the previous environment entry when the source changes", function()
    config.setup({})
    vim.env.SQFLK_DB_URL = "postgres://app@dedicated/tool_db"
    config.setup({})
    assert.equals(1, #config.opts.databases)
    assert.equals("SQFLK_DB_URL", config.opts.databases[1].name)
    vim.env.SQFLK_DB_URL = nil
    config.setup({})
    assert.equals(1, #config.opts.databases)
    assert.equals("DATABASE_URL", config.opts.databases[1].name)
  end)

  it("does not fall back after a dedicated connection name collision", function()
    vim.env.SQFLK_DB_URL = "postgres://app@dedicated/tool_db"
    config.setup({ databases = { { name = "SQFLK_DB_URL" } } })
    assert.equals(1, #config.opts.databases)
    assert.equals(1, #warnings)
    assert.matches("SQFLK_DB_URL", warnings[1], 1, true)
  end)

  it("refreshes on repeated setup without accumulating entries", function()
    config.setup({})
    vim.env.DATABASE_URL = "postgres://app@remote/other"
    config.setup({})
    assert.equals(1, #config.opts.databases)
    assert.equals("other", config.opts.databases[1].database)
    vim.env.DATABASE_URL = nil
    config.setup({})
    assert.equals(0, #config.opts.databases)
  end)

  it("can disable environment discovery", function()
    vim.env.SQFLK_DB_URL = "postgres://app@dedicated/tool_db"
    config.setup({ database_url = false })
    assert.equals(0, #config.opts.databases)
  end)

  it("ignores an unset or empty variable", function()
    for _, value in ipairs({ false, "" }) do
      vim.env.DATABASE_URL = value or nil
      config.setup({})
      assert.equals(0, #config.opts.databases)
    end
    assert.equals(0, #warnings)
  end)

  it("warns without exposing an invalid URL or blocking manual connections", function()
    vim.env.DATABASE_URL = "mongodb://user:secret@localhost/app"
    config.setup({ databases = { { name = "manual" } } })
    assert.equals(1, #config.opts.databases)
    assert.equals(1, #warnings)
    assert.is_nil(warnings[1]:find("secret", 1, true))
  end)

  it("does not introduce an ambiguous name or ID", function()
    config.setup({ databases = { { name = "DATABASE_URL" } } })
    assert.equals(1, #config.opts.databases)
    assert.equals(1, #warnings)
  end)
end)
