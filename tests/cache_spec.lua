describe("selected database cache", function()
  local original_stdpath
  local directory
  local file_path
  local cache

  before_each(function()
    directory = vim.fn.tempname()
    vim.fn.mkdir(directory, "p")
    file_path = directory .. "/sqlflick_cache.json"
    original_stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(name)
      if name == "data" then
        return directory
      end
      return original_stdpath(name)
    end
    package.loaded["sqlflick.cache"] = nil
    cache = require("sqlflick.cache")
  end)

  after_each(function()
    package.loaded["sqlflick.cache"] = nil
    vim.fn.stdpath = original_stdpath
    vim.fn.delete(directory, "rf")
  end)

  local function read_file()
    local file = assert(io.open(file_path, "r"))
    local contents = file:read("*a")
    file:close()
    return contents
  end

  it("discards legacy connection data without restoring its selection", function()
    local file = assert(io.open(file_path, "w"))
    file:write('{"last_db":{"name":"production","password":"legacy-secret"}}')
    file:close()

    assert.is_nil(cache.load_selected_id())
    local contents = read_file()
    assert.is_nil(contents:find("legacy-secret", 1, true))
    assert.same({ version = 2 }, vim.fn.json_decode(contents))
  end)

  it("stores only a version and identifier with restricted permissions", function()
    assert.is_true(cache.save_selected_id("production"))
    assert.same({ version = 2, last_db_id = "production" }, vim.fn.json_decode(read_file()))
    assert.equals("production", cache.load_selected_id())
    assert.equals(384, bit.band(vim.loop.fs_stat(file_path).mode, 511))
  end)

  it("does not restore an invalid or unsupported cache", function()
    local file = assert(io.open(file_path, "w"))
    file:write("not json")
    file:close()

    assert.is_nil(cache.load_selected_id())
    assert.same({ version = 2 }, vim.fn.json_decode(read_file()))
  end)

  it("removes unexpected connection data from a versioned cache", function()
    local file = assert(io.open(file_path, "w"))
    file:write('{"version":2,"last_db_id":"production","last_db":{"password":"secret"}}')
    file:close()

    assert.is_nil(cache.load_selected_id())
    assert.same({ version = 2 }, vim.fn.json_decode(read_file()))
  end)

  it("removes a non-string cached identifier", function()
    local file = assert(io.open(file_path, "w"))
    file:write('{"version":2,"last_db_id":{"password":"secret"}}')
    file:close()

    assert.is_nil(cache.load_selected_id())
    assert.same({ version = 2 }, vim.fn.json_decode(read_file()))
  end)
end)
