# sqlsnap.nvim

A Neovim plugin for SQL query. quickly, lightly.
This project purposed on run query to any DBMS without any verbose preparation.  
quickly, without any hurdle.

## Installation

Using [Lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "nolleh/sqlsnap.nvim",
    config = function()
        require("sqlsnap").setup({
        })
    end
}
```
