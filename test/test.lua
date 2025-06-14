-- This is a test configuration file
-- You can source this in your init.lua or run it directly with :luafile %

-- Add the current directory to the runtime path
vim.opt.rtp:append(".")
-- print("Handler module:", vim.inspect(require("sqlflick.handler")))

-- Load the plugin
local sqlflick = require("sqlflick")

-- Test the setup function with example databases
sqlflick.setup({
	enabled = true,
	databases = {
		-- Environment category with nested databases
		dev = {
			{
				name = "dev_postgres",
				type = "postgresql",
				host = "localhost",
				port = 5432,
				database = "test_db",
				username = "test_user",
				password = "test_password",
			},
			{
				name = "dev_mysql",
				type = "mysql",
				host = "localhost",
				port = 3306,
				database = "dev_db",
				username = "dev_user",
				password = "dev_password",
			},
		},
		-- Environment category with nested databases
		prod = {
			{
				name = "prod_postgres",
				type = "postgresql",
				host = "prod.host",
				port = 5432,
				database = "prod_db",
				username = "prod_user",
				password = "prod_password",
			},
		},
		-- Direct database configurations (no category)
		{
			name = "local_postgres",
			type = "postgresql",
			host = "localhost",
			port = 5432,
			database = "test_db",
			username = "test_user",
			password = "test_password",
		},
		{
			name = "local_mysql",
			type = "mysql",
			host = "localhost",
			port = 3306,
			database = "test_db",
			username = "test_user",
			password = "test_password",
		},
		{
			name = "local_redis",
			type = "redis",
			host = "localhost",
			port = 6379,
		},
		{
			name = "local_sqlite",
			type = "sqlite",
			database = "test.db",
		},
	},
	preview = {
		width = 60,
		height = 20,
		border = "rounded",
	},
	backend = {
		host = "localhost",
		port = 9091,
	},
})
