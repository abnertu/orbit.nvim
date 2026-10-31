-- Specialized standard-server defaults. Roslyn and TypeScript tooling
-- are separate plugin owners and are intentionally not registered here.
local M = {}

local function json_settings()
  local path = require("orbit.settings").path()
  if vim.fn.has("win32") == 1 then
    path = path:gsub("^%a:", string.lower)
  end
  local schema = assert(
    vim.api.nvim_get_runtime_file("settings.schema.json", false)[1],
    "orbit.nvim settings schema is missing"
  )
  return {
    settings = { json = {
      validate = { enable = true },
      schemas = { { fileMatch = { path }, url = vim.uri_from_fname(schema) } },
    } },
  }
end

function M.get(name)
  if name == "ruff" then
    return {
      init_options = { settings = { configurationPreference = "filesystemFirst" } },
      on_attach = function(client)
        client.server_capabilities.hoverProvider = false
      end,
    }
  elseif name == "pyright" then
    return { settings = {
      pyright = { disableOrganizeImports = true, reportMissingTypeStubs = false },
      python = { analysis = {
        autoSearchPaths = true,
        diagnosticMode = "workspace",
        useLibraryCodeForTypes = true,
        typeCheckingMode = "standard",
      } },
    } }
  elseif name == "lua_ls" then
    local data = vim.fs.normalize(vim.fn.stdpath("data"))
    return { settings = { Lua = {
      codeLens = { enable = true },
      hint = {
        enable = true, paramName = "Literal", paramType = true,
        setType = true, arrayIndex = "Auto", await = true,
        semicolon = "Disable",
      },
      runtime = { version = "LuaJIT" },
      workspace = { library = {
        vim.fn.expand("$VIMRUNTIME/lua"),
        "$" .. "{3rd}/luv/library",
        vim.fs.joinpath(data, "lazy", "lazy.nvim", "lua", "lazy"),
      } },
    } } }
  elseif name == "jsonls" then
    return json_settings()
  elseif name == "yamlls" then
    return { settings = { yaml = {
      validate = true, completion = true, hover = true,
      schemaStore = { enable = false, url = "" },
    } } }
  elseif name == "powershell_es" then
    return {
      bundle_path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason",
        "packages", "powershell-editor-services"),
      shell = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell",
    }
  end
  return {}
end

return M
