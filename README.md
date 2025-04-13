# SQLSnap.nvim

A Neovim plugin for SQL query management.

## Installation

Using [Lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "nolleh/sqlsnap.nvim",
    config = function()
        require("sqlsnap").setup({
            -- Configuration options here
            enabled = true,
        })
    end
}
```

## Configuration

Default configuration:

```lua
{
    enabled = true,
}
```

## Features

- Basic SQL query management (coming soon)
- More features to be added...

## License

MIT

## develop

```
ln -sf "$(pwd)" ~/.config/nvim/lua/plugins/sqlsnap
nvim -c  "luafile test.lua"

```

```lua

   {
       dir = "~/.config/nvim/lua/plugins/sqlsnap",
       config = function()
           require("sqlsnap").setup({
               enabled = true,
           })
       end
   }

```


