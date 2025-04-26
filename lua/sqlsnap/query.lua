local M = {}

-- Execute SQL query using backend
function M.execute_query(query, db_config, backend_config)
	local url = string.format("http://%s:%d/query", backend_config.host, backend_config.port)

	local data = {
		database = db_config.type,
		query = query,
		config = {
			host = db_config.host,
			port = db_config.port,
			user = db_config.username,
			password = db_config.password,
			dbname = db_config.database,
		},
	}

	local response = vim.fn.system(
		string.format("curl -s -X POST -H \"Content-Type: application/json\" -d '%s' %s", vim.fn.json_encode(data), url)
	)

	local result = vim.fn.json_decode(response)
	if result.error then
		vim.notify("Query failed: " .. result.error, vim.log.levels.ERROR)
		return result -- Return the error result instead of nil
	end

	return result
end

-- Format query results as a table
function M.format_query_results(result)
	-- Handle error case
	if result.error then
		return { "Error: " .. result.error }
	end

	if not result then
		return { "No results" }
	end

	if not result.columns or not result.rows then
		return { "No results" }
	end

	-- Calculate column widths
	local col_widths = {}
	for i, col in ipairs(result.columns) do
		col_widths[i] = vim.fn.strdisplaywidth(col)
		for _, row in ipairs(result.rows) do
			local val = tostring(row[i] or "")
			col_widths[i] = math.max(col_widths[i], vim.fn.strdisplaywidth(val))
		end
	end

	-- Add some padding
	for i, width in ipairs(col_widths) do
		col_widths[i] = width + 2 -- Add 2 spaces of padding
	end

	-- Format header
	local lines = {}

	local function create_line(left, mid, right)
		local line = left
		for i, width in ipairs(col_widths) do
			line = line .. string.rep("─", width)
			line = line .. (i < #col_widths and mid or right)
		end
		return line
	end

	-- Create borders
	local top = create_line("┌", "┬", "┐")
	local mid = create_line("├", "┼", "┤")
	local bot = create_line("└", "┴", "┘")

	-- Create header
	local header = "│"
	for i, col in ipairs(result.columns) do
		header = header .. string.format("%-" .. col_widths[i] .. "s", " " .. col .. " ") .. "│"
	end

	table.insert(lines, top)
	table.insert(lines, header)
	table.insert(lines, mid)

	-- Format rows
	for _, row in ipairs(result.rows) do
		local line = "│"
		for i, val in ipairs(row) do
			line = line .. string.format("%-" .. col_widths[i] .. "s", " " .. tostring(val or "") .. " ") .. "│"
		end
		table.insert(lines, line)
	end

	table.insert(lines, bot)

	return lines
end

return M
