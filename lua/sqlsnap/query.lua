local M = {}

-- Format query results as a table
function M.format_query_results(result)
	-- Handle error case
	-- print(dump(result))
	if result.error then
		return { "Error: " .. result.error }
	end

	if not result then
		return { "No results" }
	end

	if not result.columns or not result.rows then
		return { "No results" }
	end

	-- Handle DDL commands (like DROP TABLE) that return userdata
	if type(result.columns) == "userdata" then
		return { "Command executed successfully" }
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
