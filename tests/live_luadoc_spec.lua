-- Real LuaLS and LazyDev must resolve annotation-only libraries and offer typed completion.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local server = vim.env.ORBIT_LUA_LANGUAGE_SERVER or vim.fn.exepath("lua-language-server")
assert(server ~= "" and vim.fn.executable(server) == 1, "lua-language-server is required")
local workspace = vim.fn.tempname() .. " LuaDoc"
assert(vim.fn.mkdir(workspace, "p") == 1)
local locked = vim.json.decode(table.concat(vim.fn.readfile(root .. "/lazy-lock.json"), "\n"))
local plugins = vim.env.ORBIT_TYPE_PLUGIN_ROOT or (workspace .. "/plugins")
local sources = { "folke/lazy.nvim", "folke/lazydev.nvim", "folke/snacks.nvim" }
for _, repository in ipairs(sources) do
  local name = repository:match("[^/]+$")
  local directory = plugins .. "/" .. name
  if not vim.env.ORBIT_TYPE_PLUGIN_ROOT then
    for _, argv in ipairs({
      { "git", "init", directory },
      {
        "git",
        "-C",
        directory,
        "fetch",
        "--depth",
        "1",
        "https://github.com/" .. repository .. ".git",
        locked[name].commit,
      },
      { "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" },
    }) do
      local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
      assert(result.code == 0, tostring(result.stderr))
    end
  end
  assert(vim.fn.isdirectory(directory .. "/lua") == 1, "missing type library: " .. directory)
  vim.opt.rtp:append(directory)
end
if vim.env.ORBIT_TYPE_PLUGIN_ROOT then
  for name, kind in vim.fs.dir(plugins) do
    if kind == "directory" then
      vim.opt.rtp:append(plugins .. "/" .. name)
    end
  end
end

require("orbit").setup()
local spec = require("orbit.modules.completion").spec()[1]
local lazydev = spec.dependencies[3].opts
lazydev.library = vim.list_extend(vim.deepcopy(lazydev.library), { root .. "/lua" })
require("lazydev").setup(lazydev)
assert(vim.wait(5000, function()
  local ok, events = pcall(vim.api.nvim_get_autocmds, { group = "lazydev" })
  return ok and #events > 0
end, 10))

-- Keep the repository's LuaLS configuration in the reproduction.
vim.fn.writefile(vim.fn.readfile(root .. "/.luarc.json"), workspace .. "/.luarc.json")
local path = workspace .. "/options.lua"
local lines = {
  "---@type LazySpec",
  "local specs = {}",
  "---@type LazyPluginSpec",
  "local plugin = {}",
  "---@alias NotifierOptions snacks.notifier.Config",
  "---@class TypedOptions",
  "---@field notifier NotifierOptions",
  "---@field picker snacks.picker.Config",
  "---@type TypedOptions",
  "local typed = {}",
  "---@type Orbit.Config",
  "local orbit = {}",
  "---@type snacks.Config",
  "local snacks = {}",
  "return specs, plugin, typed, orbit, snacks",
}
vim.fn.writefile(lines, path)
vim.cmd.edit(vim.fn.fnameescape(path))
vim.bo.filetype = "lua"
local buffer = vim.api.nvim_get_current_buf()
local settings = require("orbit.modules.lsp.servers").get("lua_ls").settings
local id = assert(vim.lsp.start({
  name = "lua_ls",
  cmd = { server },
  root_dir = workspace,
  settings = settings,
}))
local client = assert(vim.lsp.get_client_by_id(id))
local ok, err = xpcall(function()
  assert(
    vim.wait(30000, function()
      return client.initialized
    end, 20),
    "LuaLS did not initialize"
  )

  ---@param expression string
  ---@param field string
  local function complete(expression, field)
    local source = vim.list_slice(lines, 1, #lines - 1)
    source[#source + 1] = expression
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, source)
    local found = false
    assert(
      vim.wait(30000, function()
        local reply = client:request_sync("textDocument/completion", {
          textDocument = { uri = vim.uri_from_bufnr(buffer) },
          position = { line = #source - 1, character = #expression },
        }, 5000, buffer)
        local result = reply and reply.result
        for _, item in ipairs(result and (result.items or result) or {}) do
          if item.label == field then
            found = true
          end
        end
        return found
      end, 100),
      "missing typed completion: " .. expression .. field
    )
    print("PASS typed completion " .. expression .. field)
  end

  complete("plugin.", "dependencies")
  complete("snacks.", "picker")
  complete("typed.notifier.", "timeout")
  complete("typed.picker.", "layout")
  complete("orbit.modules.terminal.", "horizontal_size")
  local manifest =
    vim.json.decode(table.concat(vim.fn.readfile(root .. "/lua/orbit/modules/manifest.json"), "\n"))
  for _, name in ipairs(manifest.order) do
    complete("orbit.modules." .. name .. ".", "enabled")
  end

  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  assert(
    vim.wait(10000, function()
      for _, diagnostic in ipairs(vim.diagnostic.get(buffer)) do
        if diagnostic.code == "undefined-doc-name" then
          return false
        end
      end
      return true
    end, 100),
    "annotation-only types remain undefined"
  )
  print("PASS LazySpec, alias and class-member types resolve without loading their plugins")
  assert(package.loaded.snacks == nil, "type completion must not activate Snacks")
end, debug.traceback)
client:stop(true)
vim.fn.delete(workspace, "rf")
assert(ok, err)
