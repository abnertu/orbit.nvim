-- Verify pinned real Conform formatting through Orbit's Lazy callback.
-- Network-backed validation is intentionally separate from hermetic tests.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local pinned = "3543d000dafbc41cc7761d860cfdb24e82154f75"
local source = "https://github.com/stevearc/conform.nvim.git"
local directory = vim.fn.tempname() .. " live conform with spaces"
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
    "Conform checkout did not match pinned upstream revision")
  vim.opt.rtp:prepend(directory)

  local orbit = require("orbit")
  local formatter = require("orbit.modules.formatter")
  local runtime = require("orbit.modules.formatter.runtime")
  orbit.setup()
  assert(package.loaded.conform == nil, "root setup eagerly loaded Conform")

  local spec = formatter.spec()[1]
  assert(spec and spec[1] == "stevearc/conform.nvim")
  assert(type(spec.config) == "function")
  assert(spec.opts.default_format_opts.lsp_format == "fallback")
  assert(spec.opts.formatters_by_ft.sql[1] == "sqlfluff")

  -- Extend the actual module spec with native Lua-only fixture formatters.
  -- The regular SQL/Python/Lua formatter declarations remain intact.
  spec.opts.formatters_by_ft.orbit_fixture = { "trim_whitespace" }
  spec.opts.formatters_by_ft.orbit_delayed = { "orbit_delayed" }
  spec.opts.formatters.orbit_delayed = {
    format = function(_, _, lines, callback)
      vim.defer_fn(function()
        local formatted = vim.tbl_map(function(line)
          return line:gsub("%s+$", "")
        end, lines)
        callback(nil, formatted)
      end, 100)
    end,
  }
  spec.config(spec, spec.opts)
  local conform = require("conform")
  assert(vim.deep_equal(conform.formatters_by_ft.orbit_fixture,
    { "trim_whitespace" }))
  assert(conform.formatters_by_ft.sql[1] == "sqlfluff")
  assert(conform.default_format_opts.timeout_ms == 5000)
  assert(conform.default_format_opts.lsp_format == "fallback")
  print("PASS pinned real Conform Lazy config and language tool declarations")

  local first = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(first, vim.fn.tempname() .. ".orbitfixture")
  vim.api.nvim_set_option_value("filetype", "orbit_fixture", { buf = first })
  vim.api.nvim_buf_set_lines(first, 0, -1, false,
    { "one   ", "two\t", "three" })
  assert(conform.get_formatter_info("trim_whitespace", first).available,
    "upstream native trim_whitespace formatter is unavailable")
  assert(runtime.format(first), "Orbit rejected the real formatting request")
  assert(vim.wait(10000, function()
    return not runtime.is_formatting(first)
      and vim.deep_equal(vim.api.nvim_buf_get_lines(first, 0, -1, false),
        { "one", "two", "three" })
  end, 20), "real Conform did not modify the specified buffer")
  print("PASS real upstream native Lua formatting via Orbit async callback")

  local delayed = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(delayed, vim.fn.tempname() .. ".orbitdelay")
  vim.api.nvim_set_option_value("filetype", "orbit_delayed", { buf = delayed })
  vim.api.nvim_buf_set_lines(delayed, 0, -1, false, { "slow    " })
  assert(runtime.format(delayed))
  assert(runtime.is_formatting(delayed),
    "asynchronous formatting ownership was released too early")
  assert(not runtime.format(delayed),
    "a second format request should not run concurrently")
  assert(vim.wait(10000, function()
    return not runtime.is_formatting(delayed)
      and vim.deep_equal(vim.api.nvim_buf_get_lines(delayed, 0, -1, false),
        { "slow" })
  end, 20), "deferred Conform completion did not clean up its buffer state")
  print("PASS real upstream deferred formatter and duplicate request guard")

  local wiped = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(wiped, vim.fn.tempname() .. ".orbitwiped")
  vim.api.nvim_set_option_value("filetype", "orbit_delayed", { buf = wiped })
  vim.api.nvim_buf_set_lines(wiped, 0, -1, false, { "obsolete    " })
  assert(runtime.format(wiped))
  assert(runtime.is_formatting(wiped))
  vim.api.nvim_buf_delete(wiped, { force = true })
  assert(not runtime.is_formatting(wiped),
    "wiping a buffer did not release ownership before async completion")
  -- The upstream formatter may still finish; its callback must remain safe.
  assert(vim.wait(1000, function()
    return not runtime.is_formatting(wiped)
  end, 20))
  vim.api.nvim_buf_delete(first, { force = true })
  vim.api.nvim_buf_delete(delayed, { force = true })
  print("PASS buffer wipe releases Orbit formatter ownership")
end, debug.traceback)

vim.fn.delete(directory, "rf")
assert(ok, tostring(err))
print("Pinned upstream Conform integration tests passed.")
