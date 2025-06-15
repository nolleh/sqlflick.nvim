local M = {}

local config = require("sqlflick.config")

-- Tree node structure for hierarchical navigation
local TreeNode = {}
function TreeNode.new(name, is_category, db_config, parent)
  return {
    name = name,
    is_category = is_category,
    db_config = db_config,
    parent = parent,
    children = {},
    expanded = false,
    depth = (parent and parent.depth and (parent.depth + 1)) or 0,
  }
end

-- Build tree structure from databases config
function M.build_tree(databases)
  local root = {
    name = "Databases",
    is_category = true,
    expanded = true,
    children = {},
  }

  -- First pass: Create category nodes
  for key, value in pairs(databases) do
    if type(key) == "string" then
      -- This is a category
      local category = TreeNode.new(key, true, nil, root)
      root.children[#root.children + 1] = category

      -- Add databases under this category
      for _, db in ipairs(value) do
        local db_node = TreeNode.new(db.name, false, db, category)
        category.children[#category.children + 1] = db_node
      end
    elseif type(key) == "number" then
      -- This is a direct database entry
      local db = value
      local db_node = TreeNode.new(db.name, false, db, root)
      root.children[#root.children + 1] = db_node
    end
  end

  return root
end

-- Flatten tree to visible items
function M.get_visible_items(root)
  local items = {}
  local function traverse(node)
    if node ~= root then -- Skip root node
      items[#items + 1] = node
    end
    if node.expanded and node.children then
      for _, child in ipairs(node.children) do
        traverse(child)
      end
    end
  end
  traverse(root)
  return items
end

-- Filter items based on search term
function M.filter_items(items, term)
  if term == "" then
    return items
  end
  local filtered = {}
  for _, item in ipairs(items) do
    if string.find(string.lower(item.name), string.lower(term)) then
      filtered[#filtered + 1] = item
    end
  end
  return filtered
end

return M
