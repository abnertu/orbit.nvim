-- Exercise the statusline symbol path that Orbit reads from real Trouble.
-- This test intentionally uses network and runs outside hermetic suites.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local lock = dofile(root .. "/tests/support/live_lock.lua")
local directory = vim.fn.tempname() .. " live Trouble with spaces"
-- Narrow status lines hide symbols, so draw a wide one.
vim.o.columns = 160

local ok, err = xpcall(function()
  lock.checkout("trouble.nvim", "folke/trouble.nvim", directory)
  vim.opt.rtp:prepend(directory)

  local orbit = require("orbit")
  local diagnostics = require("orbit.modules.diagnostics_plugins")
  -- Drawing both bars in this headless fixture can crash Windows Neovim 0.12.5,
  -- as in the statusline suite. This suite checks only the statusline.
  orbit.setup({ modules = { tabline = { enabled = false } } })
  assert(package.loaded.trouble == nil, "root setup imported Trouble before Lazy activation")
  local spec = diagnostics.spec()[1]
  require("trouble").setup(spec.opts)

  local buffer = vim.api.nvim_get_current_buf()

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
                local range =
                  { start = { line = first, character = 0 }, ["end"] = { line = 3, character = 3 } }
                return {
                  name = name,
                  kind = kind,
                  range = range,
                  selectionRange = range,
                  children = children,
                }
              end
              result = {
                symbol("OrbitNamespace", 3, 0, {
                  symbol("OrbitClass", 5, 1, { symbol("OrbitMethod", 6, 2) }),
                }),
              }
            end
            callback(nil, result, id)
            if notify_reply then
              notify_reply(id)
            end
          end)
          return true, id
        end,
        notify = function()
          return true
        end,
        is_closing = function()
          return closing
        end,
        terminate = function()
          closing = true
          dispatchers.on_exit(0, 0)
        end,
      }
    end,
  }))
  local text = ""
  assert(
    vim.wait(10000, function()
      text = vim.api.nvim_eval_statusline(vim.go.statusline, { maxwidth = 300 }).str
      return text:find("OrbitNamespace", 1, true)
        and text:find("OrbitClass", 1, true)
        and text:find("OrbitMethod", 1, true)
    end, 20),
    "Trouble symbols did not reach the statusline: " .. text
  )
  assert(symbol_requests > 0 and text:find("  ", 1, true), text)
  assert(not text:find("\31", 1, true), "symbol boundaries leaked into the statusline")
  vim.lsp.get_client_by_id(client_id):stop(true)
  print("PASS real Trouble renders the LSP symbol path through Orbit's statusline")
end, debug.traceback)

vim.fn.delete(directory, "rf")
assert(ok, tostring(err))
print("Pinned upstream Trouble integration tests passed.")
