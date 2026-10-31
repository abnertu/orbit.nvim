-- Verify T-SQL syntax fallback through Neovim's real syntax subsystem.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.cmd("syntax on")
local orbit = require("orbit")
local fallback = require("orbit.modules.treesitter_plugins.sql_syntax")
local runtime = require("orbit.modules.treesitter_plugins.runtime")
local passed = 0
local buffers = {}
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end
local function new_buffer(ft, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  buffers[#buffers + 1] = buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
  return buf
end
local function syntax_name(buf, row, col)
  return vim.api.nvim_buf_call(buf, function()
    return vim.fn.synIDattr(vim.fn.synID(row, col, true), "name")
  end)
end

orbit.setup()
local opts = orbit.get_config().modules.treesitter_plugins
check("SQL fallback has a real query and T-SQL syntax asset", function()
  assert(opts.sql_dialect == "tsql")
  assert(opts.sql_syntax_fallback and opts.sql_markdown_fenced_fallback)
  assert(vim.fn.filereadable(vim.fs.joinpath(root, "syntax", "tsql.vim")) == 1)
  local query = vim.fn.readfile(vim.fs.joinpath(root, "after", "queries",
    "sql", "highlights.scm"))
  assert(table.concat(query, "\n"):find("keyword_disable", 1, true))
end)

check("SQL fallback preserves parser-recovery highlight groups", function()
  local buf = new_buffer("sql", {
    "GO 2",
    "BEGIN TRY",
    "SELECT @@ROWCOUNT, @UserId FROM [dbo].[Users];",
    "SELECT ISNULL(a, 0);",
  })
  assert(fallback.apply(buf, opts))
  assert(vim.b[buf].sql_type_override == "tsql")
  assert(vim.b[buf].current_syntax == "tsql")
  assert(syntax_name(buf, 1, 1) == "tsqlBatchSeparator")
  assert(syntax_name(buf, 1, 4) == "tsqlBatchCount")
  assert(syntax_name(buf, 2, 7) == "tsqlKeyword")
  assert(syntax_name(buf, 3, 8) == "tsqlSystemVariable")
  assert(syntax_name(buf, 3, 20) == "tsqlVariable")
  assert(syntax_name(buf, 3, 33) == "tsqlBracketIdentifier")
  assert(syntax_name(buf, 4, 8) == "tsqlBuiltinFunction")
end)

check("pre-existing local and global SQL dialects are not overwritten", function()
  local explicit = new_buffer("sql", { "SELECT 1;" })
  vim.b[explicit].sql_type_override = "sqloracle"
  fallback.apply(explicit, opts)
  assert(vim.b[explicit].sql_type_override == "sqloracle")
  local previous = vim.g.sql_type_default
  vim.g.sql_type_default = "sqloracle"
  local global = new_buffer("sql", { "SELECT 1;" })
  fallback.apply(global, opts)
  assert(vim.b[global].sql_type_override == nil)
  vim.g.sql_type_default = previous
end)

check("Markdown fences receive the SQL dialect without losing other mappings", function()
  local previous = vim.g.markdown_fenced_languages
  vim.g.markdown_fenced_languages = { "python", "sql" }
  local buf = new_buffer("markdown", {
    "# SQL", string.rep(string.char(96), 3) .. "sql",
    "BEGIN TRY",
    string.rep(string.char(96), 3),
  })
  assert(fallback.apply(buf, opts))
  assert(vim.deep_equal(vim.g.markdown_fenced_languages,
    { "python", "sql=tsql" }))
  assert(vim.b[buf].current_syntax == "markdown")
  assert(syntax_name(buf, 3, 7) == "tsqlKeyword")
  vim.g.markdown_fenced_languages = previous
end)

check("explicit Markdown SQL dialect remains authoritative", function()
  local original = vim.g.markdown_fenced_languages
  vim.g.markdown_fenced_languages = { "sql", "sql=sqloracle", "lua" }
  local buf = new_buffer("markdown", {
    string.rep(string.char(96), 3) .. "sql", "SELECT 1;",
    string.rep(string.char(96), 3),
  })
  fallback.apply(buf, opts)
  assert(vim.deep_equal(vim.g.markdown_fenced_languages,
    { "sql=sqloracle", "lua" }))
  vim.g.markdown_fenced_languages = original
end)

check("disabled fallback leaves dialect and syntax unchanged", function()
  local buf = new_buffer("sql", { "SELECT 1;" })
  local disabled = vim.deepcopy(opts)
  disabled.sql_syntax_fallback = false
  assert(not fallback.apply(buf, disabled))
  assert(vim.b[buf].sql_type_override == nil)
  local markdown = new_buffer("markdown", {
    string.rep(string.char(96), 3) .. "sql", "SELECT 1;",
    string.rep(string.char(96), 3),
  })
  disabled.sql_syntax_fallback = true
  disabled.sql_markdown_fenced_fallback = false
  assert(not fallback.apply(markdown, disabled))
end)

check("FileType parser owner restores syntax after a failed parser start", function()
  local original = vim.treesitter.start
  vim.treesitter.start = function() error("parser missing") end
  runtime.setup()
  local buf = new_buffer("sql", { "GO 2", "BEGIN TRY" })
  vim.treesitter.start = original
  assert(vim.b[buf].current_syntax == "tsql")
  assert(vim.wait(200, function()
    return syntax_name(buf, 1, 1) == "tsqlBatchSeparator"
  end))
end)

check("invalid SQL settings fail before runtime activation and restart fields defer", function()
  local before = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    treesitter_plugins = { sql_dialect = "" },
  } })
  assert(not ok and tostring(err):find("sql_dialect", 1, true))
  assert(vim.deep_equal(orbit.get_config(), before))
  orbit.setup({ modules = {
    treesitter_plugins = { sql_syntax_fallback = false },
  } })
  assert(orbit.get_config().modules.treesitter_plugins.sql_syntax_fallback)
  assert(orbit.get_pending_restart()
    ["orbit.modules.treesitter_plugins.sql_syntax_fallback"] == false)
end)

for _, buf in ipairs(buffers) do
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end
print(string.format("%d SQL syntax fallback tests passed.", passed))
