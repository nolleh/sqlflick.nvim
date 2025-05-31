local M = {}

M.opts = {
	-- Default configuration options
	enabled = true,
	use_lua_http = false,
	databases = {
		-- Example database configurations
		-- {
		--     name = "local_postgres",
		--     type = "postgresql",
		--     host = "localhost",
		--     port = 5432,
		--     database = "mydb",
		--     username = "user",
		--     password = "pass"
		-- },
		-- {
		--     name = "local_mysql",
		--     type = "mysql",
		--     host = "localhost",
		--     port = 3306,
		--     database = "mydb",
		--     username = "user",
		--     password = "pass"
		-- },
		-- {
		--     name = "local_sqlite",
		--     type = "sqlite",
		--     database = "/path/to/database.db"
		-- },
		-- {
		-- 	name = "local_redis",
		-- 	type = "redis",
		-- 	host = "localhost",
		-- 	port = 6379,
		-- 	password = "pass",
		-- },
	},
	-- Preview window settings
	preview = {
		width = 60,
		height = 15,
		border = "rounded",
	},
	-- Display window settings
	display = {
		position = "bottom", -- "bottom" or "right"
		size = {
			height = 0.2, -- 20% of total height when position is "bottom"
			width = 0.3, -- 30% of total width when position is "right"
		},
		size_absolute = {
			height = nil, -- Absolute height in lines, overrides size.height when set
			width = nil, -- Absolute width in columns, overrides size.width when set
		},
	},
	-- Backend settings
	backend = {
		host = "localhost",
		port = 8080,
	},
}

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

return M
