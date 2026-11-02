-- Exercise actual pinned Trouble diagnostics and custom view configuration.
-- This test intentionally uses network and runs outside hermetic suites.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local pinned = "748ca2789044607f19786b1d837044544c55e80a"
local upstream = "https://github.com/folke/trouble.nvim.git"
local directory = vim.fn.tempname() .. " live Trouble with spaces"

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or result.stdout))
  return result.stdout or ""
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  assert(vim.fn.mkdir(directory, "p") == 1)
  run({ "git", "init", directory })
  run({ "git", "-C", directory, "fetch", "--depth", "1", upstream, pinned })
  run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
  assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pinned,
    "upstream Trouble revision mismatch")
  vim.opt.rtp:prepend(directory)

  local orbit = require("orbit")
  local diagnostics = require("orbit.modules.diagnostics_plugins")
  orbit.setup()
  assert(package.loaded.trouble == nil,
    "root setup imported Trouble before Lazy activation")
  local spec = diagnostics.spec()[1]
  assert(spec and spec[1] == "folke/trouble.nvim")
  assert(spec.cmd == "Trouble")
  local trouble = require("trouble")
  trouble.setup(spec.opts)
  assert(vim.api.nvim_get_commands({}).Trouble ~= nil,
    "real Trouble command registration missing")

  local custom = require("trouble.config").get("diagnostic_preview_float")
  assert(custom.mode == "diagnostic_preview_float")
  assert(custom.preview.type == "float")
  assert(custom.preview.border == "rounded")
  assert(custom.preview.size.width == 0.3)
  print("PASS real Trouble configuration and custom diagnostic preview mode")

  local buffer = vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace("orbit.live.trouble")
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "local value = 1" })
  vim.diagnostic.set(ns, buffer, {
    { lnum = 0, col = 0, message = "live Trouble diagnostic",
      severity = vim.diagnostic.severity.WARN },
  })
  local view = trouble.open({
    mode = "diagnostics", focus = false, auto_preview = false,
    win = { position = "bottom" },
  })
  assert(view and trouble.is_open("diagnostics"),
    "real Trouble diagnostics view did not open")
  assert(vim.wait(10000, function()
    for _, item in ipairs(trouble.get_items("diagnostics")) do
      if item.message == "live Trouble diagnostic" then return true end
    end
    return false
  end, 50), "real Trouble did not consume a Neovim diagnostic")
  -- Trouble counts an opening view as open until its first update settles.
  -- Close after the asynchronous initial view lifecycle has completed.
  assert(vim.wait(10000, function()
    return view:is_open() and not view.first_update:is_pending()
  end, 50), "Trouble initial view update did not finish")
  trouble.close("diagnostics")
  assert(vim.wait(10000, function()
    return not trouble.is_open("diagnostics")
  end, 50), "Trouble diagnostics view stayed open after close")
  vim.diagnostic.reset(ns, buffer)
  print("PASS real Trouble diagnostic source, view and close lifecycle")

  vim.api.nvim_buf_set_name(buffer, vim.fs.joinpath(directory, "symbols.lua"))
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "namespace", "class", "  method", "end" })
  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  local symbol_requests = 0
  local client_id = assert(vim.lsp.start({
    name = "orbit-symbol-fixture",
    ---@param dispatchers vim.lsp.rpc.Dispatchers
    ---@return vim.lsp.rpc.PublicClient
    cmd = function(dispatchers)
      local sequence, closing = 0, false
      return {
        request = function(method, _, callback, notify_reply)
          sequence = sequence + 1
          local id = sequence
          vim.schedule(function()
            local result
            if method == "initialize" then
              result = { capabilities = { documentSymbolProvider = true } }
            elseif method == "textDocument/documentSymbol" then
              symbol_requests = symbol_requests + 1
              local function symbol(name, kind, first, children)
                local range = { start = { line = first, character = 0 }, ["end"] = { line = 3, character = 3 } }
                return { name = name, kind = kind, range = range, selectionRange = range, children = children }
              end
              result = { symbol("OrbitNamespace", 3, 0, {
                symbol("OrbitClass", 5, 1, { symbol("OrbitMethod", 6, 2) }),
              }) }
            end
            callback(nil, result, id)
            if notify_reply then notify_reply(id) end
          end)
          return true, id
        end,
        notify = function() return true end,
        is_closing = function() return closing end,
        terminate = function()
          closing = true
          dispatchers.on_exit(0, 0)
        end,
      }
    end,
  }))
  local text = ""
  assert(vim.wait(10000, function()
    text = vim.api.nvim_eval_statusline(vim.go.statusline, { maxwidth = 300 }).str
    return text:find("OrbitNamespace", 1, true)
      and text:find("OrbitClass", 1, true) and text:find("OrbitMethod", 1, true)
  end, 20), "Trouble symbols did not reach the statusline: " .. text)
  assert(symbol_requests > 0 and text:find("  ", 1, true), text)
  assert(not text:find("\31", 1, true), "symbol boundaries leaked into the statusline")
  vim.lsp.get_client_by_id(client_id):stop(true)
  print("PASS real Trouble renders the LSP symbol path through Orbit's statusline")
end, debug.traceback)

vim.fn.delete(directory, "rf")
assert(ok, tostring(err))
print("Pinned upstream Trouble integration tests passed.")
