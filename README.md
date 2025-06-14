# sqlflick.nvim

A lightweight Neovim plugin for executing SQL queries with minimal setup. Designed for quick and efficient database interactions directly from your workspace.

> **Note**: This plugin is actively maintained and developed based on real-world needs. Breaking changes may occur as features are continuously improved.

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

## Installation

Using [Lazy.nvim](https://github.com/folke/lazy.nvim):

> [!NOTE]
> When update the plugin and if there is some problem, recommend to run `SQLFlickInstall`

```lua
{
    "nolleh/sqlflick.nvim",
    config = function()
        require("sqlflick").setup({
            -- Configuration options (see below)
        })
    end,
    -- recommended load plugin option
    cmd = { "SQLFlickSelectDB", "SQLFlickExecute", "SQLFlickExecuteBuf", "SQLFlickInstall", "SQLFlickRestart" },
    ft = { "sql" },
}
```

## Configuration

```lua
{
    -- Database connections
    databases = {
        -- {
        --     name = "local_mysql",
        --     type = "mysql",
        --     host = "localhost",
        --     port = 3306,
        --     database = "mydb",
        --     username = "user",
        --     password = "pass"
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
            width = 0.3,  -- 30% of total width when position is "right"
        },
        size_absolute = {
            height = nil, -- Absolute height in lines
            width = nil,  -- Absolute width in columns
        },
    },

    -- Backend settings
    backend = {
        host = "localhost",
        port = 8080,
    },
}
```

## Key Mappings

The following mappings are available for SQL-related file types (e.g., `.sql`, `.pgsql`, `.mysql`):

| Command              | Mode | Key Binding  | Description                |
| -------------------- | ---- | ------------ | -------------------------- |
| `SQLFlickSelectDB`   | n    | `<leader>ss` | Select database connection |
| `SQLFlickExecuteBuf` | n    | `<leader>sq` | Execute current line query |
| `SQLFlickExecute`    | v    | `<leader>sq` | Execute selected query     |

## Supported Database

| Database   | Support | Planned | Remark |
| ---------- | ------- | ------- | ------ |
| MySql      | ✅      |         |        |
| PostgreSQL | ✅      |         |        |
| SQLLite3   | ✅      |         |        |
| Redis      | ✅      |         |        |
| Oracle DB  |         | ✅      |        |
| Mongo DB   |         | ✅      |        |
| Dynamo DB  |         | ✅      |        |

## Trouble Shoot

> [!NOTE]
> When update the plugin and if there is some problem, recommend to run `SQLFlickInstall`

If this is not sufficient to your situation and it occured after update the plugin, plz refer [WIKI/Migration-Guide](https://github.com/nolleh/sqlflick.nvim/wiki/Migration-Guide)

## Contributing

We welcome and appreciate contributions from the community! Here's how you can help:

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
