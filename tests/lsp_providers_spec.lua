-- Specialist LSP providers have independent activation and diagnostics contracts.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local owner = require("orbit.modules.lsp_providers")
local runtime = require("orbit.modules.lsp_providers.runtime")
local passed = 0
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

check("provider import is inert and is independent of generic LSP", function()
  assert(#owner.spec() == 0)
  orbit.setup()
  local specs = owner.spec()
  assert(#specs == 2)
  assert(specs[1][1] == "seblyng/roslyn.nvim")
  assert(specs[1].ft[1] == "cs")
  assert(specs[1].event[1] == "BufReadPre *.cs")
  assert(specs[1].opts.filewatching == "roslyn")
  assert(type(specs[1].opts.choose_target) == "function")
  assert(specs[2][1] == "pmizio/typescript-tools.nvim")
  assert(specs[2].ft[1] == "typescript")
  assert(specs[2].dependencies[2] == "neovim/nvim-lspconfig")
  assert(type(specs[2].opts) == "function")
  assert(package.loaded["typescript-tools"] == nil)
end)

check("Roslyn selects one matching solution and rejects ambiguous targets", function()
  local project = vim.fn.tempname()
  vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p")
  local first = vim.fs.joinpath(project, "First.sln")
  local second = vim.fs.joinpath(project, "Second.sln")
  vim.fn.writefile({ "" }, first)
  assert(runtime.choose_target({ first }) == first)
  assert(runtime.choose_target({ vim.fs.joinpath(project, "Other.sln") }) == nil)
  vim.fn.writefile({ "" }, second)
  assert(runtime.choose_target({ first, second }) == nil)
  vim.fn.delete(project, "rf")
  assert(runtime.choose_target({}) == nil)
end)

check("Roslyn prefers the repository solution in a Git worktree", function()
  local project = vim.fn.tempname()
  vim.fn.mkdir(vim.fs.joinpath(project, "src"), "p")
  vim.fn.writefile({ "gitdir: elsewhere" }, vim.fs.joinpath(project, ".git"))
  local root_solution = vim.fs.joinpath(project, "Root.sln")
  local nested_solution = vim.fs.joinpath(project, "src", "Nested.sln")
  vim.fn.writefile({ "" }, root_solution)
  vim.fn.writefile({ "" }, nested_solution)
  assert(runtime.choose_target({ nested_solution, root_solution }) == root_solution)
  vim.fn.delete(project, "rf")
end)

check("TypeScript options preserve server capabilities and parser preferences", function()
  local item = owner.spec()[2]
  local opts = item.opts()
  assert(opts.filetypes[2] == "typescriptreact")
  assert(opts.settings.separate_diagnostic_server == true)
  assert(opts.settings.code_lens == "off")
  assert(opts.settings.tsserver_file_preferences.includeCompletionsForModuleExports)
  assert(opts.settings.tsserver_file_preferences.includeInlayParameterNameHints ==
    "literals")
  assert(opts.settings.tsserver_file_preferences
    .includeInlayVariableTypeHintsWhenTypeMatchesName == true)
  local disabled = runtime.typescript_options(vim.tbl_extend("force",
    vim.deepcopy(orbit.get_config().modules.lsp_providers),
    { ts_inlay_hints = false, tsserver_path = "custom/tsserver.js" }))
  assert(disabled.settings.tsserver_path == "custom/tsserver.js")
  assert(disabled.settings.tsserver_file_preferences
    .includeInlayVariableTypeHintsWhenTypeMatchesName == false)
  assert(opts.settings.tsserver_path:find("tsserver.js", 1, true))
  assert(opts.handlers["textDocument/publishDiagnostics"] ==
    runtime.publish_typescript_diagnostics)
  local client = { server_capabilities = { semanticTokensProvider = {} } }
  opts.on_attach(client)
  assert(client.server_capabilities.semanticTokensProvider == nil)
end)

check("TypeScript diagnostics remove only exact duplicates from tsserver", function()
  local seen
  local original = vim.lsp.diagnostic.on_publish_diagnostics
  vim.lsp.diagnostic.on_publish_diagnostics = function(err, result, context, config)
    seen = result.diagnostics
    return "handled"
  end
  local data = {
    uri = "file:///fixture.ts",
    diagnostics = {
      { source = "tsserver", message = "Repeated", range = { start = { line = 1 } } },
      { source = "tsserver", message = "Repeated", range = { start = { line = 1 } } },
      { source = "tsserver", message = "Repeated", range = { start = { line = 2 } } },
      { source = "typescript", message = "Repeated", range = { start = { line = 1 } } },
    },
  }
  local ok, result = pcall(runtime.publish_typescript_diagnostics,
    nil, data, { client_id = 1 }, {})
  vim.lsp.diagnostic.on_publish_diagnostics = original
  assert(ok and result == "handled")
  assert(#seen == 3)
  assert(seen[1].range.start.line == 1 and seen[2].range.start.line == 2)
  assert(seen[3].source == "typescript")
  assert(#data.diagnostics == 4, "provider input was mutated")
end)

check("provider options are restart-only and invalid keys are rejected", function()
  local current = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    lsp_providers = { unsupported = true },
  } })
  assert(not ok and tostring(err):find("unsupported", 1, true))
  assert(vim.deep_equal(orbit.get_config(), current))
  orbit.setup({ modules = { lsp_providers = { roslyn = false } } })
  assert(orbit.get_config().modules.lsp_providers.roslyn)
  assert(orbit.get_pending_restart()["orbit.modules.lsp_providers.roslyn"] == false)
end)

print(string.format("%d specialist LSP provider tests passed.", passed))
