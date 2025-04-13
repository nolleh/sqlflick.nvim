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



SQLSnapTabLine: For the tab line background
SQLSnapTabLineSel: For the active tab (bold and brighter)
SQLSnapTabLineFill: For the tab line separator
SQLSnapHeader: For table headers (blue-ish color)
SQLSnapHeaderSep: For table borders and separators
SQLSnapCell: For table data cells
