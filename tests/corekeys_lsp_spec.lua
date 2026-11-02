-- Exercise K through a real client attachment without external language servers.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
orbit.setup()

local buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "hover_target" })
local requests = 0
local client_id = assert(vim.lsp.start({
  name = "orbit-hover-fixture",
  ---@param dispatchers vim.lsp.rpc.Dispatchers
  ---@return vim.lsp.rpc.PublicClient
  cmd = function(dispatchers)
    local closing, sequence = false, 0
    return {
      request = function(method, _, callback, notify_reply)
        sequence = sequence + 1
        local id = sequence
        vim.schedule(function()
          local result
          if method == "initialize" then
            result = { capabilities = { hoverProvider = true } }
          elseif method == "textDocument/hover" then
            requests = requests + 1
            result = { contents = { kind = "plaintext", value = "Orbit hover documentation" } }
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

assert(vim.wait(1000, function()
  local client = vim.lsp.get_client_by_id(client_id)
  return client and client.initialized and vim.lsp.buf_is_attached(buffer, client_id)
end), "fixture LSP did not attach")
-- Reconfiguration after attachment must keep the shared K mapping usable.
orbit.setup()
vim.cmd("normal K")
assert(vim.wait(1000, function() return requests == 1 end),
  "K did not send textDocument/hover after LSP attachment")

---@return boolean
local function hover_visible()
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(window).relative ~= "" then
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false)
      if vim.tbl_contains(lines, "Orbit hover documentation") then return true end
    end
  end
  return false
end
assert(vim.wait(1000, hover_visible), "K did not display hover documentation")
print("PASS K requests and displays documentation after LSP attachment")

-- The key stays inert when this buffer has no client with hover support.
local client = assert(vim.lsp.get_client_by_id(client_id))
local original_hover, calls = vim.lsp.buf.hover, 0
vim.lsp.buf.hover = function() calls = calls + 1 end
client.server_capabilities.hoverProvider = false
vim.cmd("normal K")
assert(calls == 0, "K invoked hover for a client without hover support")
client.server_capabilities.hoverProvider = true
local other_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(other_buffer)
vim.cmd("normal K")
assert(calls == 0, "K used a client attached to another buffer")
vim.lsp.buf.hover = original_hover
vim.api.nvim_set_current_buf(buffer)
vim.api.nvim_buf_delete(other_buffer, { force = true })
client:stop(true)
print("PASS K stays inert without hover support in the current buffer")
