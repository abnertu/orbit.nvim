-- Run the real SQLFluff executable through Orbit's Conform and nvim-lint
-- owners for INI, TOML and bundled fallback configurations.
-- This suite requires Git, network and SQLFluff; missing tools fail it.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local pins = {
  { "https://github.com/stevearc/conform.nvim.git", "3543d000dafbc41cc7761d860cfdb24e82154f75" },
  { "https://github.com/mfussenegger/nvim-lint.git", "52107ce2076a27a285af781248e2c59bad817cd0" },
}
local workspace = vim.fn.tempname() .. " live sqlfluff with spaces"

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or result.stdout))
  return result.stdout or ""
end

---@param project string
---@param files table<string, string[]>
local function write(project, files)
  for name, lines in pairs(files) do
    local path = vim.fs.joinpath(project, name)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    assert(vim.fn.writefile(lines, path) == 0)
  end
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.executable("sqlfluff") == 1, "SQLFluff is required on PATH")
  print("SQLFluff: " .. vim.trim(run({ "sqlfluff", "--version" })))
  for index, pin in ipairs(pins) do
    local directory = vim.fs.joinpath(workspace, "plugin" .. index)
    assert(vim.fn.mkdir(directory, "p") == 1)
    run({ "git", "init", directory })
    run({ "git", "-C", directory, "fetch", "--depth", "1", pin[1], pin[2] })
    run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pin[2])
    vim.opt.rtp:prepend(directory)
  end

  require("orbit").setup()
  local formatter = require("orbit.modules.formatter").spec()[1]
  formatter.config(formatter, formatter.opts)
  local linter = require("orbit.modules.linter").spec()[1]
  linter.config(linter, linter.opts)
  local conform, lint = require("conform"), require("lint")

  local cases = {
    {
      name = "INI project",
      files = {
        [".git/HEAD"] = { "ref: refs/heads/main" },
        [".sqlfluff"] = {
          "[sqlfluff]", "dialect = ansi",
          "[sqlfluff:rules:capitalisation.keywords]", "capitalisation_policy = upper",
        },
        ["queries/report.sql"] = { "select a from b" },
      },
      formatted = "SELECT a FROM b",
      code = "CP01",
    },
    {
      name = "TOML project",
      files = {
        [".git/HEAD"] = { "ref: refs/heads/main" },
        ["pyproject.toml"] = {
          "[tool.sqlfluff.core]", 'dialect = "ansi"',
          "[tool.sqlfluff.rules.capitalisation.keywords]", 'capitalisation_policy = "lower"',
        },
        ["sql/report.sql"] = { "SELECT a FROM b" },
      },
      formatted = "select a from b",
      code = "CP01",
    },
    {
      name = "bundled T-SQL fallback",
      files = {
        [".git/HEAD"] = { "ref: refs/heads/main" },
        ["report.sql"] = { "select top 1 a from b" },
      },
      formatted = "SELECT TOP 1 a FROM b",
      code = "CP01",
    },
  }

  for index, case in ipairs(cases) do
    local project = vim.fs.joinpath(workspace, "project " .. index)
    write(project, case.files)
    local sql
    for name in pairs(case.files) do
      if name:match("%.sql$") then sql = vim.fs.joinpath(project, name) end
    end
    vim.cmd.edit(vim.fn.fnameescape(sql))
    vim.bo.filetype = "sql"
    local buffer = vim.api.nvim_get_current_buf()

    local ns = lint.get_namespace("sqlfluff")
    lint.try_lint("sqlfluff")
    assert(vim.wait(60000, function()
      return #vim.diagnostic.get(buffer, { namespace = ns }) > 0
    end, 100), case.name .. ": real SQLFluff lint published no diagnostics")
    local codes = vim.tbl_map(function(item) return item.code end,
      vim.diagnostic.get(buffer, { namespace = ns }))
    assert(vim.list_contains(codes, case.code), case.name .. " codes: " .. vim.inspect(codes))
    for _, code in ipairs(codes) do
      assert(not tostring(code):match("^PRS"), case.name .. " failed to parse: " .. vim.inspect(codes))
    end

    local formatted = conform.format({ bufnr = buffer, formatters = { "sqlfluff" },
      async = false, timeout_ms = 60000 })
    assert(formatted, case.name .. ": Conform did not run SQLFluff")
    local text = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1]
    assert(text == case.formatted, case.name .. " formatted to " .. vim.inspect(text))
    vim.bo[buffer].modified = false
    print("PASS real SQLFluff lint and format with " .. case.name)
  end
end, debug.traceback)

vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Real SQLFluff integration tests passed.")
