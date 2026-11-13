# sqlflick.nvim

<p align="center">
  <img src="./docs/images/sqlflick-banner.jpg" alt="SQLFlick mascot holding an SQL document beside the sqlflick logo" width="800" />
</p>

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
  - Execute the SQL statement at the cursor, including statements with internal blank lines
  - Split at semicolons outside strings, quoted identifiers, and comments
  - See [SQL statement selection](./docs/sql-statement-selection.md) for dialect rules and limits

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

During `setup()`, SQLFlick reads `vim.env.SQFLK_DB_URL` first. If it is unset or
empty, SQLFlick reads `vim.env.DATABASE_URL` instead. The selected variable adds
one connection to `:SQLFlickSelectDB`, named after that variable, alongside your
configured databases:

```sh
export SQFLK_DB_URL='postgresql://app@localhost:5432/app_dev?sslmode=require'
nvim
```

`DATABASE_URL` can be used in the same way when `SQFLK_DB_URL` is unset or empty.
If a nonempty `SQFLK_DB_URL` is invalid, unsupported, or conflicts with a manually
configured connection, SQLFlick warns and does not fall back to `DATABASE_URL`.

The URL prefix determines the database type. Network connections support a
single host, percent-encoded credentials, and IPv6 addresses:

| Database   | Supported input examples                                                                                                  |
| ---------- | ------------------------------------------------------------------------------------------------------------------------- |
| PostgreSQL | `postgresql://user:pass@localhost:5432/app?sslmode=require`, `postgres://...`, `jdbc:postgresql://...`                    |
| MySQL      | `mysql://user:pass@localhost:3306/app?parseTime=true&tls=true`, `jdbc:mysql://localhost:3306/app?user=user&password=pass` |
| Redis      | `redis://default:pass@localhost:6379/2`, `rediss://...` for TLS                                                           |
| SQLite     | `file:./data/app.db?mode=ro`, `sqlite:///data/app.db`, `sqlite:////absolute/path/app.db`, `jdbc:sqlite:./data/app.db`     |
| Oracle     | `oracle://user:pass@localhost:1521/service`, `jdbc:oracle:thin:user/pass@//localhost:1521/service`                        |

Native connection options are passed to the corresponding Go driver. MySQL URLs
use go-sql-driver/mysql option names (such as `tls`, `parseTime`, and `timeout`);
Redis URLs preserve authentication, database number, and TLS. Redis pool limits
and cancellation settings remain managed by SQLFlick. Oracle URLs use go-ora
connection options. Driver-specific options are not interchangeable across
languages.

SQLite relative paths are resolved against Neovim's current working directory
during `setup()`, then sent as absolute file URIs to the backend. `file:` inputs
are interpreted as SQLite connections. In the SQLAlchemy-style syntax, three
slashes denote a relative path and four denote an absolute path. In-memory
databases are not supported by environment discovery.

PostgreSQL JDBC parameters supported here are `user`, `password`,
`sslmode`, `ssl`, `sslcert`, `sslkey`, `sslrootcert`, `connectTimeout`,
`currentSchema`, `ApplicationName`, and `options`; unsupported JDBC parameters
produce a warning instead of being silently discarded. JDBC `ssl=true` maps to
`sslmode=verify-full`, and `ssl=false` maps to `sslmode=disable`.

MySQL JDBC supports `user`, `password`, `connectTimeout`, `socketTimeout`, and
`sslMode`. Timeouts are milliseconds; `socketTimeout` applies to both reads and
writes. Supported `sslMode` values are `DISABLED`, `REQUIRED` (TLS without
certificate verification), and `VERIFY_IDENTITY` (verified TLS). Other JDBC
options produce a warning. Oracle JDBC support is limited to the Thin
single-host service-name form shown above, with optional inline credentials
and no JDBC query options; SID, TNS, and descriptor forms are not supported.
Credentials supplied separately by an application are not discovered.

URLs requiring multiple hosts, scheme-less DSNs (such as MySQL's
`user:pass@tcp(host)/db`), and SQLAlchemy `+driver` prefixes are not currently
supported by environment discovery. Use the existing `databases` configuration
for connections that cannot be expressed using the supported URL forms.

Set `database_url = false` in `setup()` to disable this feature. Missing or empty
variables add nothing; invalid or unsupported values produce a warning and leave
manual connections available. The selected variable's name and `env:`-prefixed ID
(for example, `SQFLK_DB_URL` and `env:SQFLK_DB_URL`) identify this connection.
Conflicting manual connection names or IDs prevent the environment entry from
being added. Only its ID is cached, never the
connection URL. This reads Neovim's process environment; `.env` files are not
loaded automatically. After changing either environment variable, call `setup()` again
to refresh the entry. Update the backend with `:SQLFlickInstall` and
`:SQLFlickRestart` when upgrading to use URL connections.

When a connection is restored from cache, the first query command asks you to
confirm its name, type, host, port, and database. Choose `Run` (`r`) to execute;
`Quit` (`q`), Enter (the default), or Esc cancels without sending the query or
opening a result window. A cancelled confirmation appears again on the next
attempt. After approval, subsequent queries in the same session do not ask again.
Selecting a connection with `:SQLFlickSelectDB` also skips this confirmation.
This applies to both `:SQLFlickExecute` and `:SQLFlickExecuteBuf`.

## Configuration

[full-configuration](./lua/sqlflick/config.lua)  
[example-configuration](./tests/test.lua)

```lua
{
    -- Read SQFLK_DB_URL first, then DATABASE_URL; infer DB type from the URL.
    database_url = true,

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

| Command              | Mode | Key Binding  | Description                 |
| -------------------- | ---- | ------------ | --------------------------- |
| `SQLFlickSelectDB`   | n    | `<leader>ss` | Select database connection  |
| `SQLFlickExecuteBuf` | n    | `<leader>sq` | Execute statement at cursor |
| `SQLFlickExecute`    | v    | `<leader>sq` | Execute selected query      |

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

GitHub Actions runs Neovim/Plenary and Go race tests for pull requests and pushes
to `main`. PostgreSQL end-to-end tests run on explicit manual request; see the
[CI guide](./docs/ci.md).

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
