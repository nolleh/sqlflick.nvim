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



To test the plugin, you can now:
Make sure the symbolic link is created correctly:
Apply to init.lua
Run
sqlsnap
You can test the plugin in two ways:
Quick Test (using the test file):
Apply to init.lua
Run
"
Full Test (using Lazy.nvim):
Add the contents of test_config.lua to your Lazy.nvim configuration
Restart Neovim
The plugin should be loaded and you can use:
:SQLSnapSelectDB to open the database selector
:SQLSnapDebug to see debug information
