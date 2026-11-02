-- Test Conform feature spec and asynchronous buffer ownership.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local formatter = require("orbit.modules.formatter")
local runtime = require("orbit.modules.formatter.runtime")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("feature import never loads Conform", function()
  assert(#formatter.spec() == 0)
  assert(package.loaded.conform == nil)
end)

check("formatter mapping and filetypes are configured", function()
  orbit.setup()
  local item = formatter.spec()[1]
  assert(item[1] == "stevearc/conform.nvim")
  assert(vim.deep_equal(item.event, { "BufWritePost", "BufReadPost", "InsertLeave" }))
  assert(item.keys[1][1] == "<leader>fm")
  assert(vim.deep_equal(item.keys[1].mode, { "n", "x" }))
  assert(item.opts.default_format_opts.timeout_ms == 5000)
  assert(item.opts.default_format_opts.lsp_format == "fallback")
  assert(item.opts.format_on_save == false)
  assert(item.opts.formatters_by_ft.lua[1] == "stylua")
  assert(item.opts.formatters_by_ft.sql[1] == "sqlfluff")
  assert(item.opts.formatters_by_ft.cs[1] == "csharpier")
  assert(item.opts.formatters_by_ft.markdown[2] == "markdown-toc")
  assert(package.loaded.conform == nil)
end)

check("duplicate formats are blocked and completion clears buffer ownership", function()
  local callbacks, calls = {}, 0
  package.preload.conform = function()
    return {
      format = function(opts, callback)
        assert(opts.async and opts.quiet and opts.bufnr > 0)
        calls = calls + 1
        callbacks[#callbacks + 1] = callback
      end,
    }
  end
  local buf = vim.api.nvim_create_buf(true, false)
  assert(runtime.format(buf))
  assert(runtime.is_formatting(buf))
  assert(not runtime.format(buf))
  assert(calls == 1)
  callbacks[1](nil, true)
  assert(not runtime.is_formatting(buf))
  assert(runtime.format(buf))
  callbacks[2](nil, false)
  assert(not runtime.is_formatting(buf))
  package.loaded.conform, package.preload.conform = nil, nil
end)

check("wiping a buffer cancels its pending completion", function()
  local callback
  package.preload.conform = function()
    return { format = function(_, cb)
      callback = cb
    end }
  end
  local buf = vim.api.nvim_create_buf(true, false)
  runtime.format(buf)
  assert(runtime.is_formatting(buf))
  vim.api.nvim_buf_delete(buf, { force = true })
  assert(not runtime.is_formatting(buf))
  callback(nil)
  assert(not runtime.is_formatting(buf))
  package.loaded.conform, package.preload.conform = nil, nil
end)

check("Conform returning false releases ownership and reports no start", function()
  local seen
  package.preload.conform = function()
    return { format = function(opts, callback)
      assert(opts.async and opts.quiet)
      callback("No formatters available for buffer")
      return false
    end }
  end
  local original_notify = vim.notify
  vim.notify = function(msg)
    seen = msg
  end
  local buf = vim.api.nvim_create_buf(true, false)
  local ok, err = xpcall(function()
    assert(not runtime.format(buf),
      "Orbit must preserve Conform's unavailable-formatter result")
    assert(not runtime.is_formatting(buf))
    assert(seen and seen:find("No formatters available", 1, true))
    assert(not runtime.format(-1), "invalid buffers cannot start formatting")
  end, debug.traceback)
  vim.notify = original_notify
  vim.api.nvim_buf_delete(buf, { force = true })
  package.loaded.conform, package.preload.conform = nil, nil
  assert(ok, err)
end)

check("formatter exceptions clear pending state", function()
  package.preload.conform = function()
    return { format = function()
      error("formatter fixture failure")
    end }
  end
  local buf = vim.api.nvim_create_buf(true, false)
  assert(not runtime.format(buf))
  assert(not runtime.is_formatting(buf))
  package.loaded.conform, package.preload.conform = nil, nil
end)

check("invalid timeout and restart-only options are validated", function()
  local old = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    formatter = { timeout_ms = 0 },
  } })
  assert(not ok and tostring(err):find("timeout_ms", 1, true))
  assert(vim.deep_equal(orbit.get_config(), old))
  orbit.setup({ modules = { formatter = { format_on_save = true } } })
  assert(orbit.get_config().modules.formatter.format_on_save == false)
  assert(orbit.get_pending_restart()["orbit.modules.formatter.format_on_save"] == true)
end)

print(string.format("%d formatter tests passed.", passed))
