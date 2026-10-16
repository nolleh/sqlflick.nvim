local statement = require("sqlflick.statement")

local cases = {
  { name = "statement without a final semicolon", text = "SELECT <cursor>1" },
  { name = "blank lines inside SQL", text = "SELECT id, name\n\nFROM users\nWHERE <cursor>active = true;" },
  { name = "first statement on one line", text = "SELECT <cursor>1; SELECT 2;", expected = "SELECT 1;" },
  { name = "second statement on one line", text = "SELECT 1; SELECT <cursor>2;", expected = "SELECT 2;" },
  { name = "cursor on terminating semicolon", text = "SELECT 1<cursor>; SELECT 2;", expected = "SELECT 1;" },
  { name = "whitespace after a semicolon belongs to the next statement", text = "SELECT 1;<cursor> SELECT 2;", expected = "SELECT 2;" },
  { name = "trailing whitespace does not rerun the last statement", text = "SELECT 1; <cursor> ", error = "No SQL statement" },
  { name = "line comment semicolons", text = "SELECT id -- ignored;\nFROM <cursor>users;" },
  { name = "leading comments remain in the query", text = "-- report;\nSELECT <cursor>1;" },
  { name = "block comment semicolons", text = "SELECT /* ignored; */ <cursor>1;" },
  { name = "nested PostgreSQL block comments", text = "SELECT /* outer /* inner; */ still; outer */ <cursor>1;" },
  { name = "single quoted semicolons", text = "SELECT 'hello; world', <cursor>1;" },
  { name = "doubled apostrophes", text = "SELECT 'O''Brien; junior', <cursor>1;" },
  { name = "quoted identifier semicolons", text = 'SELECT "semi;colon", <cursor>id FROM users;' },
  { name = "doubled identifier quotes", text = 'SELECT "a"";b", <cursor>id FROM users;' },
  { name = "multiline string with a semicolon at line end", text = "SELECT 'first;\n\nsecond', <cursor>1;" },
  { name = "dollar quoted procedure", text = "DO $$ BEGIN\nPERFORM <cursor>1;\nPERFORM 2;\nEND; $$; SELECT 3;", expected = "DO $$ BEGIN\nPERFORM 1;\nPERFORM 2;\nEND; $$;" },
  { name = "tagged dollar quote", text = "SELECT $body$a; $$; <cursor>b$body$;" },
  { name = "dollar tags match case sensitively", text = "SELECT $body$a; $BODY$; <cursor>b$body$;" },
  { name = "dollars inside identifiers do not open quotes", text = "SELECT foo$tag$; SELECT <cursor>2;", expected = "SELECT 2;" },
  { name = "PostgreSQL escape string", text = [[SELECT E'it\'s; here', <cursor>1;]] },
  { name = "standard PostgreSQL strings do not backslash-escape quotes", text = [[SELECT 'path\'; SELECT <cursor>2;]], expected = "SELECT 2;" },
  { name = "uppercase escape prefix", text = [[SELECT e'it\'s; here', <cursor>1;]] },
  { name = "an incomplete later statement does not block the current one", text = "SELECT <cursor>1; SELECT 'unfinished", expected = "SELECT 1;" },
  { name = "comment-only input", text = "-- just a <cursor>comment;\n/* another; */", error = "No SQL statement" },
  { name = "empty input", text = "<cursor>", error = "No SQL statement" },
  { name = "whitespace-only input", text = " \n<cursor>\n ", error = "No SQL statement" },
  { name = "empty statements are skipped before SQL", text = ";; SELECT <cursor>1;", expected = "SELECT 1;" },
  { name = "cursor on an empty statement does not execute its neighbor", text = "<cursor>; SELECT 1;", error = "No SQL statement" },
  { name = "unfinished string is rejected", text = "SELECT '<cursor>unfinished;", error = "Unterminated" },
  { name = "unfinished identifier is rejected", text = 'SELECT "<cursor>unfinished;', error = "Unterminated" },
  { name = "unfinished block comment is rejected", text = "SELECT 1 /* <cursor>unfinished;", error = "Unterminated" },
  { name = "unfinished dollar quote is rejected", text = "SELECT $body$<cursor>unfinished;", error = "Unterminated" },
  { name = "line comments may end at EOF", text = "SELECT <cursor>1 -- comment;" },
  { name = "CRLF line comments", text = "SELECT 1 -- ignored;\r\nFROM <cursor>users;" },
  { name = "UTF-8 text before the cursor", text = "SELECT '한글;🙂'; SELECT <cursor>'안녕';", expected = "SELECT '안녕';" },
  { name = "MySQL backtick identifiers", dialect = "mysql", text = "SELECT `a``;b`, <cursor>1;" },
  { name = "MySQL backslashes do not escape identifier delimiters", dialect = "mysql", text = [[SELECT `path\`; SELECT <cursor>2;]], expected = "SELECT 2;" },
  { name = "MySQL escaped string quote", dialect = "mysql", text = [[SELECT 'it\'s; here', <cursor>1;]] },
  { name = "MySQL hash comments", dialect = "mysql", text = "SELECT 1 # ignored;\nFROM <cursor>users;" },
  { name = "MySQL double dash requires following whitespace", dialect = "mysql", text = "SELECT 5--2; SELECT <cursor>3;", expected = "SELECT 3;" },
  { name = "SQLite bracket identifiers", dialect = "sqlite", text = "SELECT [semi;colon], <cursor>1;" },
  { name = "SQLite backtick identifiers", dialect = "sqlite", text = "SELECT `semi;colon`, <cursor>1;" },
  { name = "Oracle alternative quote", dialect = "oracle", text = "SELECT q'[it's; text]', <cursor>1 FROM dual;" },
  { name = "comment markers inside strings remain literal", text = "SELECT '--; /* $$ */', <cursor>1;" },
  { name = "quotes inside comments do not open literals", text = "/* ' ; \" $$ */ SELECT <cursor>1;" },
  { name = "dollar quote tags allow digits after the first character", text = "SELECT $body_1$a; <cursor>b$body_1$;" },
  { name = "PostgreSQL parameter markers are not dollar quote tags", text = "SELECT $1; SELECT <cursor>2;", expected = "SELECT 2;" },
}

describe("SQL statement selection", function()
  for _, case in ipairs(cases) do
    it(case.name, function()
      local cursor = assert(case.text:find("<cursor>", 1, true))
      local text = case.text:gsub("<cursor>", "")
      local result, err = statement.extract(text, cursor, case.dialect)
      if case.error then
        assert.is_nil(result)
        assert.matches(case.error, err, 1, true)
      else
        assert.equals(case.expected or text, result)
        assert.is_nil(err)
      end
    end)
  end

  it("converts Neovim byte columns and line numbers correctly", function()
    local lines = { "SELECT '한글;';", "", "SELECT '🙂', 2;" }
    assert.equals("SELECT '🙂', 2;", statement.at_cursor(lines, 3, #"SELECT '🙂', "))
  end)

  it("selects a statement when the cursor is on its internal blank line", function()
    assert.equals("SELECT id\n\nFROM users;", statement.at_cursor({ "SELECT id", "", "FROM users;" }, 2, 0))
  end)

  it("keeps Redis commands line-based", function()
    local lines = { "SET key 'hello; world'", "GET key" }
    assert.equals(lines[1], statement.at_cursor(lines, 1, 10, "redis"))
    assert.equals(lines[2], statement.at_cursor(lines, 2, 0, "redis"))
  end)
end)
