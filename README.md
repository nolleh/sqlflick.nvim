# sqlflick.nvim

A lightweight Neovim plugin for executing SQL queries with minimal setup. Designed for quick and efficient database interactions directly from your workspace.

> **Note**: This plugin is actively maintained and developed based on real-world needs. Breaking changes may occur as features are continuously improved.

## Demo

### Overview

https://github.com/user-attachments/assets/ed0bbff6-e909-499f-a12c-5f0cb2ca45cc

### Paging

https://github.com/user-attachments/assets/c86c8eac-786b-4e93-917e-4e4f34b01b56

## Why sqlflick.nvim?

- No need to leave your beloved neovim 🥰 to query!
- No external dependency (DB client)
- Flick your finger to run query, immediately
  - `<leader>ss` -> select db (for once, in session)
  - `<leader>sq` -> run query

## Features

- **Database Connection Management**

  - Pre-configure multiple database connections
  - Quick switching between different databases
  - In below screen shot, empty box is place for search to filter configuration.

    ![](./docs/images/select-db.png)

- **Query Execution**

  - Execute queries directly from your SQL buffer
  - Support for both single-line and multi-line queries

    ![](./docs/images/run_query.png)

    ![](./docs/images/multiple_line_query.png)

- **View Result with handy features**

  - Column Wrap
    - When you have large/long data that hard to catch with your eyes at once,  
       you can use `column wrap` function to break down as muliple lines.  
       Press `W` in column to toggle column wrap

![](./docs/images/column_wrap.png)

- Navigating Columns
  - For real world database, it is common table have many columns which contain many charactors.  
     It will be hard to move cursor to next column, by moving word by word.
    Use Navigating feature to fly on the columns

## Requirements

Neovim 0.10+ and curl are required for asynchronous query execution. Go is needed
to build the backend with `:SQLFlickInstall`.

## Installation

Using [Lazy.nvim](https://github.com/folke/lazy.nvim):

> [!NOTE]
> When update the plugin and if there is some problem, recommend to run `SQLFlickInstall`

```lua
{
    "nolleh/sqlflick.nvim",
    config = function()
        require("sqlflick").setup({
            databases = {
                {
                    id = "local-mysql",
                    name = "local_mysql",
                    type = "mysql",
                    host = "localhost",
                    port = 3306,
                    database = "mydb",
                    username = "user",
                    password = vim.env.MY_DB_PASSWORD,
                },
            },
        })
    end,
    -- recommended load plugin option
    cmd = { "SQLFlickSelectDB", "SQLFlickExecute", "SQLFlickExecuteBuf", "SQLFlickCancel", "SQLFlickInstall", "SQLFlickRestart", "SQLFlickRefreshSchema" },
    -- If you want to load/enable the plugin only for specific file_type, use this
    ft = { "sql", "pgsql" },
}
```

Set `MY_DB_PASSWORD` in Neovim's environment before loading the plugin. You can
choose any environment variable name. Avoid putting a literal password in a
tracked configuration file.

After updating to the new cache format, run `:SQLFlickSelectDB` once before
executing a query. The old cache contained complete connection settings and is
discarded; the new cache stores only a version and the selected database ID.
If the configured ID cannot be found or is duplicated, select a database again.
Without an explicit `id`, the connection's `name` is used as its cache ID.

## Configuration

[full-configuration](./lua/sqlflick/config.lua)  
[example-configuration](./tests/test.lua)

```lua
{
    -- Database connections
    databases = {
        -- {
        --     id = "local-mysql",
        --     name = "local_mysql",
        --     type = "mysql",
        --     host = "localhost",
        --     port = 3306,
        --     database = "mydb",
        --     username = "user",
        --     password = vim.env.MY_DB_PASSWORD,
        -- },
    },

    -- DBSelector window settings
    selector = {
        width = 60,
        height = 15,
        border = "rounded",
    },

    -- Display window settings
    display = {
        position = "bottom", -- "bottom" or "right"
        size = {
            height = 0.2, -- 20% of total height when position is "bottom"
            width = 0.3,  -- 30% of total width when position is "right"
        },
        size_absolute = {
            height = nil, -- Absolute height in lines
            width = nil,  -- Absolute width in columns
        },
    },

    -- Backend settings
    backend = {
        host = "127.0.0.1",
        port = 9081, -- use an available local port
        timeout_ms = 30000, -- Per request, including database execution
    },

    -- Native schema-aware completion
    completion = {
        enabled = true,
    },
}
```

## Asynchronous query execution

Query commands return immediately so you can keep editing while SQL runs.
Use `:SQLFlickCancel` to stop the active query, COUNT, or page request. Starting a
new query cancels the previous one; late responses cannot replace newer results.
Result arrival preserves your current window focus.

Set `backend.timeout_ms` to change the per-request timeout (default 30000 ms,
range 1–3600000). COUNT and the following page query each have their own timeout.
Cancellation is propagated to the database driver; it does not roll back writes
that have already committed. Connection pools are reused per connection setting
and have bounded capacity.

After updating from an older backend, run `:SQLFlickInstall`, wait for the build
to finish, then run `:SQLFlickRestart`. Schema omni-completion and programmatic
query calls without a callback retain their existing synchronous behavior.

## SQL completion

SQL buffers use Neovim's native omni-completion. In insert mode, press
`<C-x><C-o>` to complete:

- tables and views after `FROM` and `JOIN`;
- columns in `SELECT`, `WHERE`, `ON`, and other expressions;
- columns scoped by aliases such as `u.` in `FROM users u`;
- SQL keywords when no schema-specific context applies.

PostgreSQL, MySQL, and SQLite schemas are loaded on first use and cached in
memory. Run `:SQLFlickRefreshSchema` after adding or removing tables, views, or
columns. After three consecutive schema fetch failures, automatic schema
requests pause until `:SQLFlickRefreshSchema` is run. Redis and Oracle continue
to use query execution without schema-aware completion.

For implementation details, usage examples, known limitations, and future
directions, see the [SQL Completion wiki guide](https://github.com/nolleh/sqlflick.nvim/wiki/SQL-Completion).

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for release notes and version history.

## Key Mappings

The following mappings are available for SQL-related file types (e.g., `.sql`, `.pgsql`, `.mysql`):

| Command              | Mode | Key Binding  | Description                |
| -------------------- | ---- | ------------ | -------------------------- |
| `SQLFlickSelectDB`   | n    | `<leader>ss` | Select database connection |
| `SQLFlickExecuteBuf` | n    | `<leader>sq` | Execute current line query |
| `SQLFlickExecute`    | v    | `<leader>sq` | Execute selected query     |

In the database selector, type to filter connections, use `<C-n>` and `<C-p>`
to move through the list, and press Enter in the search input to select the
highlighted database.

Completion is available in insert mode with Neovim's native `<C-x><C-o>`
mapping. `:SQLFlickRefreshSchema` reloads metadata for the selected database.

The following mappings are available in specific pages. (not user command)

| name               | mode | Key binding | runnable view | description                                           |
| ------------------ | ---- | ----------- | ------------- | ----------------------------------------------------- |
| Toggle column wrap | n    | `W`         | result view   | Place your cursor to long data column, to toggle wrap |
| Navigate column    | n    | `c{i}`      | result view   | Navigate cursor to specified column number            |
| Previous column    | n    | `[c`        | result view   | Navigate cursor to previous column                    |
| Next column        | n    | `]c`        | result view   | Navigate cursor to next column                        |

## Supported Database

| Database   | Support | Planned | Remark |
| ---------- | ------- | ------- | ------ |
| MySql      | ✅      |         |        |
| PostgreSQL | ✅      |         |        |
| sqlite     | ✅      |         |        |
| Redis      | ✅      |         |        |
| Oracle DB  | ✅      |         |        |
| Mongo DB   |         | ✅      |        |
| Dynamo DB  |         | ✅      |        |

## Trouble Shoot

### Migration

> [!NOTE]
> When update the plugin and if there is some problem, recommend to run `SQLFlickInstall`

If this is not sufficient to your situation and it occured after update the plugin, plz refer [WIKI/Migration-Guide](https://github.com/nolleh/sqlflick.nvim/wiki/Migration-Guide)

### Debug Command

You can use debug command with `:SQLFlickDebug` after plugin is loaded, which will print similar information with following.

```bash
SQLFlick Debug Info:
Enabled: true
Backend version:  0.3.1
Backend install path: /Users/nolleh/.local/share/nvim/sqlflick/bin/sqlflick-backend
Backend port: 9091
Number of databases: 4
- local_postgres (postgresql)
- local_mysql (mysql)
- local_redis (redis)
- local_sqlite (sqlite)

```

## Contributing

We welcome and appreciate contributions from the community! Here's how you can help:

GitHub Actions runs Neovim/Plenary, Go race tests, and PostgreSQL end-to-end
checks for pull requests and pushes to `main`; see the [CI guide](./docs/ci.md).

Run the plugin tests with `make test`. To run the PostgreSQL end-to-end tests,
start the Compose database and run `make test-e2e`; see the
[async execution test guide](./docs/async-execution-tests.md) for coverage and
connection settings.

- **Bug Reports**: Found a bug? Please open an issue with detailed steps to reproduce.
- **Feature Requests**: Have an idea for a new feature? Open an issue to discuss it.
- **Code Contributions**: Submit a pull request with a clear description of your changes
- **Documentation**: Help improve our documentation by fixing typos, adding examples, or clarifying instructions.

Before contributing, please read our [Contributing Guidelines](CONTRIBUTING.md) (if available) and ensure your code follows our coding standards.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Feedback

Your feedback is valuable to us! Here are the ways you can contribute to the project's development:

Visit our [GitHub repository](https://github.com/nolleh/sqlflick.nvim) to:

- Open an issue
- Submit a pull request
- Start a discussion
- Star the project to show your support
