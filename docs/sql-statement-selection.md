# SQL statement selection

In normal mode, `:SQLFlickExecuteBuf` (default `<leader>sq`) executes the SQL
statement containing the cursor. Statements end at semicolons outside comments
and quoted text; blank lines do not end a statement. The cursor's byte column
selects the correct statement when several statements share a line.

The scanner preserves the selected SQL, including comments, strings, and internal
newlines. Only whitespace at the outer boundaries is trimmed. A final semicolon
is optional.

## Boundaries

- A cursor on a terminating semicolon selects the preceding statement.
- Whitespace after a semicolon belongs to the following statement.
- Trailing whitespace, empty statements, and comments alone do not execute SQL.
- Unterminated quoted text or block comments report an error instead of sending
  incomplete SQL. An incomplete later statement does not block a complete one
  selected earlier in the buffer.
- Explicit visual selection bypasses automatic statement extraction.
- Redis remains line-based: the current line is one command.

## Quoting and comments

All SQL dialects recognize single-quoted strings, double-quoted text, doubled
quote escapes, `--` line comments, and `/* ... */` block comments.

The selected database type determines additional rules:

| Database | Additional handling |
| --- | --- |
| PostgreSQL | Nested block comments, `$$...$$` / `$tag$...$tag$`, and backslash escapes in `E'...'` |
| MySQL | Backtick identifiers, backslash escapes in strings, `#` comments, whitespace required after `--` |
| SQLite | Backtick and bracket identifiers |
| Oracle | Alternative quoted strings such as `q'[it’s; text]'` |

PostgreSQL ordinary strings assume the default `standard_conforming_strings=on`.
MySQL assumes its default string escaping rules; server SQL-mode overrides such
as `NO_BACKSLASH_ESCAPES` are not discovered automatically.

This is a lexical scanner, not a complete SQL parser. It does not group unquoted
semicolons in compound SQL/procedural blocks, interpret MySQL `DELIMITER` commands,
or handle SQL-client script directives. Use explicit selection for such blocks.
It does not validate SQL grammar or change pagination's LIMIT detection.

## Verification

- 51 scanner cases pass with the actual Lua module under Lua 5.3 (texlua),
  without Neovim API substitutes.
- 7 command-flow cases pass under Lua 5.4 with Neovim API substitutes. Six of
  those cases failed against the old line-based extraction.
- Existing quote-preservation (18) and pagination (3) tests also pass under that
  substitute environment.
- Native Neovim/Plenary and real database execution were not available in the
  authoring environment. Run `make test` there before merging.

This change is frontend-only; it requires no backend rebuild.
