-- Exercise SQLFluff project discovery through both plugin entry points.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local sqlfluff = require("orbit.sqlfluff")
local formatter = require("orbit.modules.formatter")
local linter = require("orbit.modules.linter")
local passed = 0
local temp = vim.fn.tempname()

local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

local function file(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines, path) == 0)
end

local function contains(items, value)
  return vim.tbl_contains(items, value)
end

local source = vim.fs.joinpath(temp, "project", "queries", "report.sql")
local project = vim.fs.joinpath(temp, "project")
vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p")

check("fallback uses bundled T-SQL rules and never writes a project config", function()
  assert(vim.fn.filereadable(sqlfluff.fallback_config) == 1)
  assert(contains(vim.fn.readfile(sqlfluff.fallback_config), "dialect = tsql"))
  local fmt = sqlfluff.format_args(source)
  local lint = sqlfluff.lint_args(source)
  assert(fmt[1] == "format" and lint[1] == "lint")
  assert(contains(lint, "--format=json"))
  assert(contains(fmt, "--stdin-filename") and contains(lint, source))
  assert(contains(fmt, sqlfluff.fallback_config))
  assert(contains(lint, sqlfluff.fallback_config))
  assert(fmt[#fmt] == "-" and lint[#lint] == "-")
  assert(vim.fn.filereadable(vim.fs.joinpath(project, ".sqlfluff")) == 0)
  assert(vim.fs.normalize(sqlfluff.cwd(source)) == vim.fs.normalize(project))
end)

check("unrelated config sections are ignored and valid ancestor config wins", function()
  file(vim.fs.joinpath(project, "queries", "pyproject.toml"),
    { "[tool.black]", "line-length = 88" })
  file(vim.fs.joinpath(project, "setup.cfg"), { "[flake8]", "ignore = E501" })
  assert(sqlfluff.find_config(source) == nil)
  local config = vim.fs.joinpath(project, ".sqlfluff")
  file(config, { "[sqlfluff]", "dialect = postgres" })
  assert(vim.fs.normalize(sqlfluff.find_config(source)) == vim.fs.normalize(config))
  assert(not contains(sqlfluff.format_args(source), "--config"))
  assert(not contains(sqlfluff.lint_args(source), "--config"))
  assert(vim.fs.normalize(sqlfluff.cwd(source)) == vim.fs.normalize(project),
    "repository marker must outrank nested package markers")
end)

check("TOML and INI SQLFluff sections are recognized", function()
  for index, entry in ipairs({
    { "pyproject.toml", "[tool.sqlfluff.core]" },
    { "pep8.ini", "[sqlfluff:rules]" },
    { "tox.ini", "[sqlfluff:indentation]" },
  }) do
    local dir = vim.fs.joinpath(temp, "case" .. index)
    local filename = vim.fs.joinpath(dir, "nested", "test.sql")
    local config = vim.fs.joinpath(dir, entry[1])
    file(config, { entry[2] })
    assert(vim.fs.normalize(sqlfluff.find_config(filename)) ==
      vim.fs.normalize(config), entry[1])
  end
end)

check("Conform and nvim-lint consume the same project context", function()
  orbit.setup()
  local conform_spec = formatter.spec()[1]
  local formatter_options = conform_spec.opts.formatters.sqlfluff
  assert(formatter_options.command == "sqlfluff")
  assert(formatter_options.stdin and formatter_options.require_cwd)
  assert(formatter_options.env.PYTHONUTF8 == "1")
  local ctx = { filename = source }
  assert(vim.deep_equal(formatter_options.args(nil, ctx),
    sqlfluff.format_args(source)))
  assert(formatter_options.cwd(nil, ctx) == sqlfluff.cwd(source))

  package.preload.lint = function()
    return { linters = {}, linters_by_ft = {}, try_lint = function() end }
  end
  package.preload["lint.linters.sqlfluff"] = function()
    return { cmd = "sqlfluff", stdin = true, parser = function() end }
  end
  local lint_spec = linter.spec()[1]
  lint_spec.config(nil, lint_spec.opts)
  local factory = require("lint").linters.sqlfluff
  assert(type(factory) == "function")
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buffer, source)
  vim.api.nvim_set_current_buf(buffer)
  local definition = factory()
  assert(definition.cmd == "sqlfluff" and definition.stdin)
  assert(definition.env.PYTHONUTF8 == "1")
  assert(vim.deep_equal(definition.args, sqlfluff.lint_args(source)))
  assert(definition.cwd == sqlfluff.cwd(source))
  package.loaded.lint, package.preload.lint = nil, nil
  package.loaded["lint.linters.sqlfluff"] = nil
  package.preload["lint.linters.sqlfluff"] = nil
end)

vim.fn.delete(temp, "rf")
print(string.format("%d SQLFluff project tests passed.", passed))
