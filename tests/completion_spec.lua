local completion = require("sqlflick.completion")

local schema = {
  tables = {
    {
      schema = "public",
      name = "users",
      type = "table",
      columns = {
        { name = "id", data_type = "integer" },
        { name = "name", data_type = "text" },
        { name = "email", data_type = "text" },
      },
    },
    {
      schema = "public",
      name = "orders",
      type = "table",
      columns = {
        { name = "id", data_type = "integer" },
        { name = "user_id", data_type = "integer" },
      },
    },
    {
      schema = "public",
      name = "products",
      type = "view",
      columns = {
        { name = "id", data_type = "integer" },
        { name = "price", data_type = "numeric" },
      },
    },
  },
}

local function at_cursor(sql)
  local start = assert(sql:find("<cursor>", 1, true))
  return sql:gsub("<cursor>", ""), start - 1
end

local function words(items)
  local result = {}
  for _, item in ipairs(items) do
    result[item.word] = true
  end
  return result
end

local function set_current_sql(sql)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buffer)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { sql })
  vim.api.nvim_win_set_cursor(0, { 1, #sql })
end

describe("SQL completion", function()
  before_each(function()
    completion.clear()
    completion.setup({
      get_database = function()
        return nil
      end,
      fetch_schema = function()
        return nil, "schema fetcher is not configured"
      end,
      notify = function() end,
    })
  end)

  it("suggests tables and views after FROM", function()
    local sql, cursor = at_cursor("SELECT * FROM ord<cursor>")
    local result = completion.complete(sql, cursor, schema, "ord")

    assert.equals(1, #result)
    assert.equals("orders", result[1].word)
  end)

  it("resolves aliases declared with AS", function()
    local sql, cursor = at_cursor("SELECT u.na<cursor> FROM users AS u")
    local result = words(completion.complete(sql, cursor, schema, "na"))

    assert.is_true(result.name)
    assert.is_nil(result.email)
  end)

  it("resolves JOIN aliases", function()
    local sql, cursor = at_cursor("SELECT * FROM orders o JOIN products p ON p.pr<cursor>")
    local result = words(completion.complete(sql, cursor, schema, "pr"))

    assert.is_true(result.price)
    assert.is_nil(result.user_id)
  end)

  it("limits unqualified columns to referenced tables", function()
    local sql, cursor = at_cursor("SELECT * FROM users WHERE em<cursor>")
    local result = words(completion.complete(sql, cursor, schema, "em"))

    assert.is_true(result.email)
    assert.is_nil(result.price)
  end)

  it("falls back to SQL keywords without a schema", function()
    local sql, cursor = at_cursor("SEL<cursor>")
    local result = words(completion.complete(sql, cursor, nil, "SEL"))

    assert.is_true(result.SELECT)
  end)

  it("falls back to keywords in table context when schema loading is unavailable", function()
    local sql, cursor = at_cursor("SELECT * FROM <cursor>")
    local result = words(completion.complete(sql, cursor, nil, ""))

    assert.is_true(result.SELECT)
  end)

  it("finds the completion start after a qualifier", function()
    assert.equals(9, completion.find_start("SELECT u.na", 11))
  end)

  it("registers an omnifunc Neovim can call", function()
    completion.attach(0)

    assert.equals(0, vim.api.nvim_eval(vim.bo.omnifunc .. "(1, '')"))
  end)

  it("retries a failed schema fetch and caches a later success", function()
    local fetches = 0
    completion.setup({
      get_database = function()
        return { type = "sqlite", name = "test", database = ":memory:" }
      end,
      fetch_schema = function()
        fetches = fetches + 1
        if fetches == 1 then
          return nil, "backend is starting"
        end
        return schema
      end,
      notify = function() end,
    })

    set_current_sql("SELECT * FROM us")

    assert.equals(0, #completion.omnifunc(0, "us"))
    assert.equals("users", completion.omnifunc(0, "us")[1].word)
    assert.equals("users", completion.omnifunc(0, "us")[1].word)
    assert.equals(2, fetches)
  end)

  it("stops after three failures and refresh re-enables schema fetching", function()
    local fetches = 0
    local notifications = {}
    completion.setup({
      get_database = function()
        return { type = "sqlite", name = "test", database = ":memory:" }
      end,
      fetch_schema = function()
        fetches = fetches + 1
        if fetches <= 3 then
          return nil, "backend is unavailable"
        end
        return schema
      end,
      notify = function(message)
        table.insert(notifications, message)
      end,
    })

    set_current_sql("SELECT * FROM us")

    completion.omnifunc(0, "us")
    completion.omnifunc(0, "us")
    completion.omnifunc(0, "us")
    completion.omnifunc(0, "us")

    assert.equals(3, fetches)
    assert.equals(1, #notifications)
    assert.matches("SQLFlickRefreshSchema", notifications[1], 1, true)

    local refreshed = completion.refresh()
    assert.equals(4, fetches)
    assert.equals("users", refreshed.tables[1].name)
    assert.equals("users", completion.omnifunc(0, "us")[1].word)
    assert.equals(4, fetches)
    assert.equals(1, #notifications)
  end)
end)
