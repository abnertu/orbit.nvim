-- Test Noice feature ownership without downloading external plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local orbit = require("orbit")
local messages = require("orbit.modules.messages")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

check("message module imports without plugin startup side effects", function()
  assert(#messages.spec() == 0)
  assert(package.loaded.noice == nil)
end)

check("restart-only message options build one VeryLazy Noice spec", function()
  orbit.setup({ modules = { messages = {
    cmdline = false, popupmenu = false,
    hover = false, doc_max_width = 72,
    doc_max_height = 18,
  } } })
  assert(package.loaded.noice == nil)
  local spec = messages.spec()
  assert(#spec == 1 and spec[1][1] == "folke/noice.nvim")
  assert(spec[1].event == "VeryLazy")
  assert(vim.deep_equal(spec[1].dependencies, { "MunifTanjim/nui.nvim" }))
  assert(type(spec[1].opts) == "function")
  assert(type(spec[1].config) == "function")
  local opts = spec[1].opts()
  assert(opts.cmdline.enabled == false)
  assert(opts.messages.enabled == true)
  assert(opts.popupmenu.enabled == false)
  assert(opts.popupmenu.backend == "nui")
  assert(opts.lsp.hover.enabled == false)
  assert(opts.lsp.signature.opts.border == "single")
  assert(opts.lsp.message.enabled == false)
  assert(opts.lsp.hover.opts.size.max_width <= 72)
  assert(opts.lsp.hover.opts.size.max_height <= 18)
end)

check("formatter and ignored-message routes keep their behavior", function()
  local opts = messages.spec()[1].opts()
  local formatter, ignored, progress = unpack(opts.routes)
  assert(formatter.view == "formatter_progress")
  assert(formatter.opts.timeout == 5000)
  assert(formatter.filter.event == "notify")
  assert(not formatter.filter.cond({ opts = {} }))
  assert(formatter.filter.cond({ opts = { orbit_formatter = false } }))
  assert(ignored.view == "notify")
  assert(ignored.filter.event == "msg_show")
  assert(ignored.opts.skip == true and #ignored.filter.any >= 7)
  assert(progress.filter.kind == "progress")
  assert(progress.opts.skip == true and #progress.filter.any >= 2)
  assert(opts.presets.command_palette and opts.presets.bottom_search)
  assert(opts.lsp.override["vim.lsp.util.stylize_markdown"])
  assert(opts.views.formatter_progress.format[1].hl_group ==
    "NoiceLspProgressSpinner")
end)

check("external Noice is required only when its config callback runs", function()
  local setup_count = 0
  package.preload.noice = function()
    return {
      setup = function(opts)
        setup_count = setup_count + 1
        assert(opts.cmdline.enabled == false)
        assert(opts.routes[1].filter.event == "notify")
      end,
    }
  end
  local spec = messages.spec()[1]
  spec.config(spec, spec.opts())
  assert(setup_count == 1)
  package.preload.noice = nil
  package.loaded.noice = nil
end)

check("disabled owner removes its Lazy spec and restores accepted config", function()
  local snapshot = messages.capture()
  messages.setup({ enabled = false })
  assert(#messages.spec() == 0)
  messages.restore(snapshot)
  assert(#messages.spec() == 1)
end)

check("runtime settings cannot restart activated message plugins", function()
  orbit.setup({ modules = { messages = { enabled = false } } })
  assert(orbit.get_config().modules.messages.enabled == true)
  assert(orbit.get_pending_restart()
    ["orbit.modules.messages.enabled"] == false)
end)

print(string.format("%d Noice owner tests passed.", passed))
