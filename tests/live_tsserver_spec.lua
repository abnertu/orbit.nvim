-- Run real tsserver through Orbit's TypeScript-tools provider.
-- Requires Git, network, Node.js and npm; missing tools fail the test.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local windows = vim.fn.has("win32") == 1
local pins = {
  { "https://github.com/pmizio/typescript-tools.nvim.git", "c2f5910074103705661e9651aa841e0d7eea9932" },
  { "https://github.com/nvim-lua/plenary.nvim.git", "74b06c6c75e4eeb3108ec01852001636d85a932b" },
  { "https://github.com/neovim/nvim-lspconfig.git", "d8d2fda7aae57030452ce8cd6e770b1eb704514e" },
}
-- TypeScript 7.x ships no lib/tsserver.js, which typescript-tools requires.
local typescript_version = "5.9.3"
local workspace = vim.fn.tempname() .. " live tsserver with spaces"

local function run(argv, cwd)
  local result = vim.system(argv, { text = true, timeout = 300000, cwd = cwd }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or "") .. tostring(result.stdout or ""))
  return result.stdout or ""
end

local function wait(predicate, message)
  assert(vim.wait(120000, predicate, 100), message)
end

local ok, err = xpcall(function()
  local npm = windows and "npm.cmd" or "npm"
  for _, tool in ipairs({ "git", "node", npm }) do
    assert(vim.fn.executable(tool) == 1, tool .. " is required on PATH")
  end
  for index, pin in ipairs(pins) do
    local directory = vim.fs.joinpath(workspace, "plugin" .. index)
    assert(vim.fn.mkdir(directory, "p") == 1)
    run({ "git", "init", directory })
    run({ "git", "-C", directory, "fetch", "--depth", "1", pin[1], pin[2] })
    run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pin[2])
    vim.opt.rtp:prepend(directory)
  end

  local project = vim.fs.joinpath(vim.fs.normalize(vim.uv.fs_realpath(workspace)), "project")
  assert(vim.fn.mkdir(project, "p") == 1)
  -- cmd.exe drops the quotes around npm.cmd when another argument has spaces.
  assert(vim.fn.writefile({ "{}" }, vim.fs.joinpath(project, "package.json")) == 0)
  run({ npm, "install", "--no-audit", "--no-fund", "typescript@" .. typescript_version }, project)
  local tsserver = vim.fs.joinpath(project, "node_modules", "typescript", "lib", "tsserver.js")
  assert(vim.uv.fs_stat(tsserver), "TypeScript did not install " .. tsserver)
  assert(vim.fn.writefile({ '{ "compilerOptions": { "strict": true } }' },
    vim.fs.joinpath(project, "tsconfig.json")) == 0)
  local source = vim.fs.joinpath(project, "main.ts")
  assert(vim.fn.writefile({
    "function add(left: number, right: number) { return left + right; }",
    "const total = add(1, 2);",
    "const wrong: string = total;",
  }, source) == 0)

  require("orbit").setup({ modules = { lsp_providers = { tsserver_path = tsserver } } })
  -- Generic registration must leave TypeScript to the specialist provider.
  local generic = require("orbit.modules.lsp").spec()[1]
  local activation = generic.config(generic, generic.opts)
  assert(not vim.tbl_contains(activation.activated, "ts_ls"),
    "generic LSP registered ts_ls: " .. vim.inspect(activation.activated))
  local provider
  for _, item in ipairs(require("orbit.modules.lsp_providers").spec()) do
    if item[1] == "pmizio/typescript-tools.nvim" then provider = item end
  end
  assert(provider, "Orbit did not declare TypeScript tools")
  require("typescript-tools").setup(provider.opts())
  print("PASS Orbit configures typescript-tools with tsserver " .. typescript_version)

  vim.cmd("filetype on")
  vim.cmd.edit(vim.fn.fnameescape(source))
  local buffer = vim.api.nvim_get_current_buf()
  local client
  wait(function()
    client = vim.lsp.get_clients({ bufnr = buffer, name = "typescript-tools" })[1]
    return client ~= nil and client.initialized
  end, "typescript-tools did not attach")
  for _, other in ipairs(vim.lsp.get_clients({ bufnr = buffer })) do
    assert(other.name ~= "ts_ls", "a generic ts_ls client attached")
  end
  assert(client.server_capabilities.semanticTokensProvider == nil,
    "TypeScript provider kept semantic tokens")
  print("PASS typescript-tools attaches alone without semantic tokens")

  local diagnostic
  wait(function()
    for _, item in ipairs(vim.diagnostic.get(buffer)) do
      if item.lnum == 2 and tostring(item.code) == "2322" then diagnostic = item end
    end
    return diagnostic ~= nil
  end, "tsserver did not report the type error: " .. vim.inspect(vim.diagnostic.get(buffer)))
  print("PASS real tsserver reports a diagnostic: " .. diagnostic.message)

  local hints
  wait(function()
    local response = client:request_sync("textDocument/inlayHint", {
      textDocument = vim.lsp.util.make_text_document_params(buffer),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 3, character = 0 } },
    }, 10000, buffer)
    hints = response and response.result or {}
    return #hints > 0
  end, "tsserver returned no inlay hints")
  local labels = {}
  for _, hint in ipairs(hints) do
    local label = hint.label
    if type(label) == "table" then
      label = table.concat(vim.tbl_map(function(part) return part.value end, label))
    end
    labels[#labels + 1] = vim.trim(label)
  end
  assert(vim.tbl_contains(labels, "left:") and vim.tbl_contains(labels, "right:"),
    "missing parameter name hints: " .. vim.inspect(labels))
  print("PASS real tsserver returns inlay hints")

  client:stop()
  wait(function() return client:is_stopped() end, "typescript-tools did not stop")
end, debug.traceback)

for _, client in ipairs(vim.lsp.get_clients()) do pcall(function() client:stop(true) end) end
vim.wait(2000, function() return #vim.lsp.get_clients() == 0 end, 50)
vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Real tsserver integration tests passed.")
