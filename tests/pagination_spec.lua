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
end)
