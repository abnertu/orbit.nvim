-- Exercise real pinned Noice and NUI through the orbit Lazy config callback.
-- Requires Git and network; this test is separate from hermetic validation.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local dependencies = {
  {
    name = "nui",
    source = "https://github.com/MunifTanjim/nui.nvim.git",
    revision = "10fc361835c856ba4233ef5ea135b919bf3dce97",
  },
  {
    name = "noice",
    source = "https://github.com/folke/noice.nvim.git",
    revision = "7bfd942445fb63089b59f97ca487d605e715f155",
  },
}
local workspace = vim.fn.tempname() .. " live noice with spaces"

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) .. " failed: "
    .. tostring(result.stderr or result.stdout or result.code))
  return result.stdout or ""
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(workspace, "p") == 1)
  for _, dependency in ipairs(dependencies) do
    local directory = vim.fs.joinpath(workspace, dependency.name)
    run({ "git", "init", directory })
    run({ "git", "-C", directory, "fetch", "--depth", "1",
      dependency.source, dependency.revision })
    run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
    assert(run({ "git", "-C", directory, "rev-parse", "HEAD" })
      :gsub("%s+$", "") == dependency.revision,
      "upstream " .. dependency.name .. " revision mismatch")
    vim.opt.rtp:prepend(directory)
  end

  local orbit = require("orbit")
  local messages = require("orbit.modules.messages")
  orbit.setup({ modules = { messages = {
    cmdline = false, messages = false, popupmenu = false,
    hover = false, signature = false, progress = false,
  } } })
  assert(package.loaded.noice == nil,
    "normal orbit setup unexpectedly imported Noice")
  local spec = messages.spec()[1]
  assert(spec and spec[1] == "folke/noice.nvim")
  assert(type(spec.opts) == "function" and type(spec.config) == "function")
  local opts = spec.opts()
  assert(opts.routes[1].view == "formatter_progress")
  spec.config(spec, opts)

  -- The upstream plugin defers setup until VimEnter when loaded early.
  if vim.v.vim_did_enter == 0 then
    vim.api.nvim_exec_autocmds("VimEnter", {})
  end
  assert(vim.wait(10000, function()
    return require("noice.config").is_running()
  end, 20), "real Noice did not activate after its Lazy config callback")

  local config = require("noice.config").options
  assert(config.cmdline.enabled == false)
  assert(config.popupmenu.enabled == false)
  assert(config.lsp.hover.enabled == false)
  assert(config.routes[1].view == "formatter_progress")
  assert(config.routes[1].filter.cond({
    opts = { orbit_formatter = true },
  }), "real Noice lost the formatter progress route")
  assert(vim.api.nvim_get_commands({}).Noice ~= nil,
    "real Noice command was not registered")
  print("PASS pinned upstream Noice and NUI checkout")
  print("PASS real Noice Lazy activation and command")
  print("PASS real Noice merged formatter progress route")

  -- Exercise the real notify -> router -> NUI rendering path, not just
  -- the configured route predicate. The formatter route must display
  -- a floating mini view containing the actual notification text.
  local router = require("noice.message.router")
  local formatter_view = assert(router._routes[1] and router._routes[1].view,
    "real formatter progress view was not registered")
  local progress_text = "Orbit live formatter progress"
  vim.notify(progress_text, vim.log.levels.INFO, {
    orbit_formatter = true,
    orbit_formatter_icon = "*",
  })
  router.update()
  local popup = formatter_view.view and formatter_view.view._nui
  assert(popup and popup.winid and vim.api.nvim_win_is_valid(popup.winid),
    "formatter progress did not open a real NUI window")
  assert(vim.api.nvim_win_get_buf(popup.winid) == popup.bufnr,
    "formatter progress popup did not own its rendered buffer")
  assert(vim.api.nvim_win_get_config(popup.winid).relative ~= "",
    "formatter progress rendered in a normal window")
  local rendered = table.concat(vim.api.nvim_buf_get_lines(
    popup.bufnr, 0, -1, false), "\n")
  assert(rendered:find(progress_text, 1, true)
    and rendered:find("*", 1, true),
    "real formatter progress popup lost its message or icon: "
      .. vim.inspect(rendered))
  print("PASS real Noice formatter notification renders in a floating NUI popup")

  router.dismiss()
  require("noice").disable()
end, debug.traceback)

vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Live Noice integration tests passed.")
