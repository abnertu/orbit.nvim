-- Verify actual pinned nvim-lint diagnostic publication via the Orbit event owner.
-- Uses Git --version as a portable process, not a mocked plugin.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local pinned = "52107ce2076a27a285af781248e2c59bad817cd0"
local source = "https://github.com/mfussenegger/nvim-lint.git"
local directory = vim.fn.tempname() .. " live nvim lint with spaces"

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) .. " failed: "
    .. tostring(result.stderr or result.stdout or result.code))
  return result.stdout or ""
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(directory, "p") == 1)
  run({ "git", "init", directory })
  run({ "git", "-C", directory, "fetch", "--depth", "1", source, pinned })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pinned,
    "nvim-lint checkout revision mismatch")
  vim.opt.rtp:prepend(directory)

  local orbit = require("orbit")
  local module = require("orbit.modules.linter")
  orbit.setup()
  assert(package.loaded.lint == nil, "root setup imported nvim-lint")
  local spec = module.spec()[1]
  assert(spec and spec[1] == "mfussenegger/nvim-lint")
  assert(type(spec.config) == "function")
  assert(spec.opts.linters_by_ft.sql[1] == "sqlfluff")
  assert(vim.tbl_contains(spec.opts.skip_while_editing, "sqlfluff"))

  -- Replace only the test invocation with a portable native command. The
  -- real plugin still launches Git, parses stdout and publishes diagnostics.
  local parsed = 0
  spec.opts.debounce_ms = 35
  spec.opts.linters_by_ft.orbitlint = { "sqlfluff" }
  spec.opts.linters.sqlfluff = {
    cmd = "git",
    args = { "--version" },
    stdin = false,
    append_fname = false,
    parser = function(output, bufnr)
      assert(output:find("git version", 1, true), "unexpected Git output")
      assert(vim.api.nvim_buf_is_valid(bufnr))
      parsed = parsed + 1
      return {
        {
          lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN,
          message = "live nvim-lint process output",
          source = "orbit-lint-live",
        },
      }
    end,
  }
  spec.config(spec, spec.opts)
  local lint = require("lint")
  assert(vim.deep_equal(lint.linters_by_ft.orbitlint, { "sqlfluff" }))
  assert(type(lint.try_lint) == "function")
  print("PASS real upstream nvim-lint setup and owned autocommand group")

  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. ".orbitlint")
  vim.api.nvim_set_option_value("filetype", "orbitlint", { buf = buffer })
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "SQL test fixture" })
  local ns = lint.get_namespace("sqlfluff")
  local runs = 0
  vim.api.nvim_create_autocmd("User", {
    pattern = "NvimLintRunPost",
    callback = function() runs = runs + 1 end,
  })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer, modeline = false })
  vim.wait(250, function() return false end, 15)
  assert(parsed == 0 and runs == 0,
    "SQLFluff executed on the skipped TextChanged event")
  assert(#vim.diagnostic.get(buffer, { namespace = ns }) == 0)
  print("PASS SQLFluff edit event does not start a real linter process")

  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buffer, modeline = false })
  assert(vim.wait(10000, function()
    local ds = vim.diagnostic.get(buffer, { namespace = ns })
    return #ds == 1 and ds[1].message == "live nvim-lint process output"
  end, 20), "real nvim-lint did not publish a parsed diagnostic")
  assert(parsed == 1 and runs == 1,
    "lint command and User event should run exactly once")
  print("PASS actual Git subprocess stdout published through vim.diagnostic")

  -- A later edit-only event cancels a pending write lint for this buffer.
  vim.diagnostic.reset(ns, buffer)
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buffer, modeline = false })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buffer, modeline = false })
  vim.wait(250, function() return false end, 15)
  assert(parsed == 1 and runs == 1,
    "last edit event did not replace the pending write lint")
  assert(#vim.diagnostic.get(buffer, { namespace = ns }) == 0)
  print("PASS per-buffer debounce respects last-event kind")

  local wiped = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_option_value("filetype", "orbitlint", { buf = wiped })
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = wiped, modeline = false })
  vim.api.nvim_buf_delete(wiped, { force = true })
  vim.wait(250, function() return false end, 15)
  assert(parsed == 1 and runs == 1,
    "wiping a buffer did not cancel its scheduled linter")
  print("PASS buffer wipe cancels real nvim-lint scheduling")
  vim.api.nvim_buf_delete(buffer, { force = true })
end, debug.traceback)

vim.fn.delete(directory, "rf")
assert(ok, tostring(err))
print("Pinned upstream nvim-lint integration tests passed.")
