-- Specialist providers own their own registration; no generic vim.lsp.enable().
local M = {}

---Select only a unique solution belonging to the known Roslyn targets.
---@param targets string[]
---@return string?
function M.choose_target(targets)
  if type(targets) ~= "table" or #targets == 0 then return end
  local root = vim.fs.root(targets[1], ".git")
  if not root then return end
  local match
  for name, kind in vim.fs.dir(root) do
    if kind == "file" and name:match("%.sln$") then
      if match then return end
      match = vim.fs.normalize(vim.fs.joinpath(root, name))
    end
  end
  if not match then return end
  for _, target in ipairs(targets) do
    if vim.fs.normalize(target) == match then return target end
  end
end

---Keep distinct diagnostics while suppressing exact tsserver duplicates.
function M.publish_typescript_diagnostics(err, result, ctx, config)
  if result and result.diagnostics then
    local seen, filtered = {}, {}
    for _, diagnostic in ipairs(result.diagnostics) do
      local duplicate = false
      if diagnostic.source == "tsserver" then
        for _, previous in ipairs(seen) do
          if vim.deep_equal(previous, diagnostic) then
            duplicate = true
            break
          end
        end
        if not duplicate then seen[#seen + 1] = diagnostic end
      end
      if not duplicate then filtered[#filtered + 1] = diagnostic end
    end
    result = vim.tbl_extend("force", result, { diagnostics = filtered })
  end
  return vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, config)
end

---@param opts Orbit.LspProvidersOptions
---@return table
function M.typescript_options(opts)
  local path = opts.tsserver_path ~= "" and opts.tsserver_path or
    vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages",
      "typescript-language-server", "node_modules", "typescript", "lib",
      "tsserver.js")
  local hints = opts.ts_inlay_hints
  return {
    filetypes = {
      "typescript", "typescriptreact", "javascript",
      "javascriptreact", "jsx",
    },
    on_attach = function(client)
      client.server_capabilities.semanticTokensProvider = nil
    end,
    handlers = {
      ["textDocument/publishDiagnostics"] = M.publish_typescript_diagnostics,
    },
    settings = {
      separate_diagnostic_server = true,
      code_lens = "off",
      tsserver_path = path,
      tsserver_file_preferences = {
        includeCompletionsForModuleExports = true,
        quotePreference = "auto",
        includeInlayParameterNameHintsWhenArgumentMatchesName = hints,
        includeInlayFunctionParameterTypeHints = hints,
        includeInlayVariableTypeHintsWhenTypeMatchesName = hints,
        includeInlayPropertyDeclarationTypeHints = hints,
        includeInlayEnumMemberValueHints = hints,
        includeInlayParameterNameHints = hints and "literals" or "none",
        includeInlayVariableTypeHints = hints,
        includeInlayFunctionLikeReturnTypeHints = hints,
      },
    },
  }
end

return M
