local M = {}

M.default_config = {
	-- Default configuration options
	enabled = true,
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
		{
			name = "local_redis",
			type = "redis",
			host = "localhost",
			port = 6379,
			password = "pass",
		},
	},
	-- Preview window settings
	preview = {
		width = 50,
		height = 10,
		border = "rounded",
	},
	-- Backend settings
	backend = {
		host = "localhost",
		port = 8080,
	},
}

M.opts = vim.deepcopy(M.default_config)

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

return M

