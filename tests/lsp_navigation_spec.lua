-- Drive the original navigation keys through a real, hermetic LSP client.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.keymap.set("n", "gd", "<cmd>echo 'user definition'<cr>")
local original = vim.fn.maparg("gd", "n")
local orbit = require("orbit")
orbit.setup()
local source = vim.api.nvim_get_current_buf()
vim.keymap.set("n", "gD", "<cmd>echo 'user local declaration'<cr>", { buffer = source })
local local_original = vim.fn.maparg("gD", "n")
vim.keymap.set("n", "gy", function() return "i<CR><Esc>" end, {
  buffer = source, expr = true, replace_keycodes = false, script = true, silent = true,
})
local expression_original = vim.fn.maparg("gy", "n", false, true)
local function check_expression_mapping()
  local restored = vim.fn.maparg("gy", "n", false, true)
  for _, field in ipairs({ "callback", "expr", "noremap", "script", "replace_keycodes", "silent" }) do
    assert(restored[field] == expression_original[field], "restoration changed expression mapping field: " .. field)
  end
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys("gy", "xt", false)
  assert(vim.api.nvim_buf_line_count(source) == 1
    and vim.api.nvim_buf_get_lines(source, 0, 1, false)[1] == "<CR><Esc>",
    "restored expression mapping replaced literal keycodes")
end
vim.api.nvim_buf_set_lines(source, 0, -1, false, { "vim.api.nvim_get_current_buf()" })
local target = vim.fn.tempname() .. " builtin api.lua"
vim.fn.writefile({ "---@return integer", "function vim.api.nvim_get_current_buf() end" }, target)
local received = {}
local client_id = assert(vim.lsp.start({
  name = "orbit-navigation-fixture",
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
            result = { capabilities = {
              definitionProvider = true, declarationProvider = true,
              implementationProvider = true, typeDefinitionProvider = true, referencesProvider = true,
            } }
          else
            received[method] = (received[method] or 0) + 1
            local position = { line = 1, character = 0 }
            local location = { uri = vim.uri_from_fname(target), range = { start = position, ["end"] = position } }
            result = method == "textDocument/references" and { location } or location
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
  return client and client.initialized and vim.lsp.buf_is_attached(source, client_id)
end), "fixture LSP did not attach")
for _, item in ipairs({ { "gd", "definition" }, { "gD", "declaration" },
  { "gI", "implementation" }, { "gy", "typeDefinition" }, { "gR", "references" } }) do
  vim.api.nvim_set_current_buf(source)
  vim.api.nvim_win_set_cursor(0, { 1, 12 })
  vim.api.nvim_feedkeys(item[1], "xt", false)
  assert(vim.wait(1000, function()
    return received["textDocument/" .. item[2]] == 1 and vim.api.nvim_get_current_buf() ~= source
  end), item[1] .. " did not navigate through LSP to the builtin API definition")
  if item[1] == "gR" then
    local references = vim.fn.getqflist()
    assert(#references == 1 and references[1].lnum == 2)
  else
    assert(vim.api.nvim_win_get_cursor(0)[1] == 2, item[1] .. " jumped to the wrong line")
  end
end
vim.api.nvim_set_current_buf(source)
orbit.setup({ modules = { corekeys = { enabled = false } } })
check_expression_mapping()
local commands = require("orbit.modules.commands")
local setup = commands.setup
commands.setup = function() error("injected expression rollback") end
assert(not pcall(orbit.setup, { modules = { corekeys = { enabled = true }, commands = { name = "OrbitExpressionFail" } } }))
commands.setup = setup
check_expression_mapping()
orbit.setup({ modules = { corekeys = { enabled = true } } })
local attached = vim.fn.maparg("gd", "n", false, true).callback
local observers = #vim.api.nvim_get_autocmds({ group = "OrbitLspNavigation" })
orbit.setup({ modules = { corekeys = { save = "<F12>" } } })
assert(#vim.api.nvim_get_autocmds({ group = "OrbitLspNavigation" }) == observers,
  "reconfiguration duplicated navigation observers")
setup = commands.setup
commands.setup = function() error("injected navigation rollback") end
assert(not pcall(orbit.setup, { modules = { corekeys = { enabled = false }, commands = { name = "OrbitNavigationFail" } } }))
commands.setup = setup
assert(vim.fn.maparg("gd", "n", false, true).callback == attached, "rollback lost attached navigation")
local second_id = assert(vim.lsp.start(vim.tbl_extend("force", vim.lsp.get_client_by_id(client_id).config,
  { name = "orbit-second-navigation-fixture" })))
assert(vim.wait(1000, function() return vim.lsp.buf_is_attached(source, second_id) end))
vim.lsp.get_client_by_id(client_id):stop(true)
assert(vim.wait(1000, function() return vim.lsp.get_client_by_id(client_id) == nil end))
assert(vim.fn.maparg("gd", "n", false, true).callback == attached,
  "detaching one client removed navigation while another remained")
vim.lsp.get_client_by_id(second_id):stop(true)
assert(vim.wait(1000, function()
  return vim.fn.maparg("gd", "n") == original and vim.fn.maparg("gD", "n") == local_original
end), "last detach did not restore prior mappings")
check_expression_mapping()
orbit.setup({ modules = { corekeys = { enabled = false } } })
vim.api.nvim_set_current_buf(source)
assert(vim.fn.maparg("gd", "n") == original, "disabling lost the user's definition mapping")
assert(vim.fn.maparg("gD", "n") == local_original, "disabling lost the user's local declaration mapping")
vim.fn.delete(target)
print("PASS navigation keys use LSP, survive rollback and restore prior mappings on detach")
