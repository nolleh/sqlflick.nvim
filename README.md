# sqlsnap.nvim

A lightweight Neovim plugin for executing SQL queries with minimal setup. Designed for quick and efficient database interactions directly from your workspace.

> **Note**: This plugin is actively maintained and developed based on real-world needs. Breaking changes may occur as features are continuously improved.

## Features

- **Database Connection Management**

  - Pre-configure multiple database connections
  - Quick switching between different databases

    ![](./docs/images/select-db.png)

- **Query Execution**

  - Execute queries directly from your SQL buffer
  - Support for both single-line and multi-line queries

    ![](./docs/images/run_query.png)

## Installation

Using [Lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "nolleh/sqlsnap.nvim",
    config = function()
        require("sqlsnap").setup({
            -- Configuration options (see below)
        })
    end
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

| Command             | Mode | Key Binding  | Description                |
| ------------------- | ---- | ------------ | -------------------------- |
| `SQLSnapSelectDB`   | n    | `<leader>ss` | Select database connection |
| `SQLSnapExecuteBuf` | n    | `<leader>sq` | Execute current line query |
| `SQLSnapExecuteBuf` | v    | `<leader>sq` | Execute selected query     |

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

Visit our [GitHub repository](https://github.com/nolleh/sqlsnap.nvim) to:

- Open an issue
- Submit a pull request
- Start a discussion
- Star the project to show your support
