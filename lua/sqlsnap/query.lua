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
        return nil
    end

    return result
end

-- Format query results as a table
function M.format_query_results(result)
    if not result or not result.columns or not result.rows then
        return { "No results" }
    end

    -- Calculate column widths
    local col_widths = {}
    for i, col in ipairs(result.columns) do
        col_widths[i] = #col
        for _, row in ipairs(result.rows) do
            local val = tostring(row[i] or "")
            col_widths[i] = math.max(col_widths[i], #val)
        end
    end

    -- Format header
    local lines = {}
    local header = "│ "
    local separator = "├─"
    for i, col in ipairs(result.columns) do
        header = header .. string.format("%-" .. col_widths[i] .. "s │ ", col)
        separator = separator .. string.rep("─", col_widths[i]) .. "─┼─"
    end

    -- Replace last ┼ with ┤
    separator = separator:sub(1, -3) .. "┤"

    -- Add top border
    table.insert(lines, "┌─" .. string.rep("─", #header - 3) .. "┐")
    table.insert(lines, header)
    table.insert(lines, separator)

    -- Format rows
    for _, row in ipairs(result.rows) do
        local line = "│ "
        for i, val in ipairs(row) do
            line = line .. string.format("%-" .. col_widths[i] .. "s │ ", tostring(val or ""))
        end
        table.insert(lines, line)
    end

    -- Add bottom border
    table.insert(lines, "└─" .. string.rep("─", #header - 3) .. "┘")

    return lines
end

return M 