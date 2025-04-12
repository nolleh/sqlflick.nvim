-- This is a test configuration file
-- You can source this in your init.lua or run it directly with :luafile %

-- Add the current directory to the runtime path
vim.opt.rtp:append(".")

-- Load the plugin
local sqlsnap = require("sqlsnap")

-- Test the setup function with example databases
sqlsnap.setup({
	enabled = true,
	databases = {
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
	},
	preview = {
		width = 60,
		height = 15,
		border = "rounded",
	},
})

