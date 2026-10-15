local pagination = require("sqlflick.pagination")

describe("pagination", function()
  before_each(function()
    pagination.reset()
  end)

  it("calculates the offset for the selected page", function()
    pagination.init("SELECT * FROM users", {}, {}, 45)
    pagination.go_to_page(3)

    assert.equals(40, pagination.get_offset())
  end)

  it("counts SQL SELECT queries, including leading comments", function()
    assert.is_true(pagination.can_paginate("  -- report\n/* note */ SELECT * FROM users", { type = "mysql" }))
    assert.is_true(pagination.can_paginate("select * from users", { type = "postgresql" }))
  end)

  it("skips count queries for mutations and Redis commands", function()
    for _, statement in ipairs({
      "UPDATE users SET active = 1",
      "INSERT INTO users VALUES (1)",
      "DELETE FROM users",
      "CREATE TABLE users (id INT)",
      "WITH changed AS (UPDATE users SET active = 1 RETURNING *) SELECT * FROM changed",
    }) do
      assert.is_false(pagination.can_paginate(statement, { type = "mysql" }))
    end
    assert.is_false(pagination.can_paginate("GET user:1", { type = "redis" }))
    assert.is_false(pagination.can_paginate("SELECT * FROM users", { type = "redis" }))
  end)
end)
