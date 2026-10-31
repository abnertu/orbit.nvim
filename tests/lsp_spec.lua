-- Verify native Neovim LSP registration without starting external binaries.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.lsp")
local passed = 0
local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

check("import is inert and standard servers have a Lazy owner", function()
  assert(#feature.spec() == 0)
  orbit.setup()
  local specs = feature.spec()
  assert(#specs == 1 and specs[1][1] == "neovim/nvim-lspconfig")
  assert(specs[1].event == "VeryLazy")
  assert(specs[1].opts.servers.lua_ls and specs[1].opts.servers.pyright)
  assert(specs[1].opts.servers.ruff and specs[1].opts.servers.yamlls)
  assert(specs[1].opts.servers.roslyn == nil)
  assert(package.loaded["lspconfig"] == nil)
end)

check("unknown server flag fails schema validation before side effects", function()
  local previous = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    lsp = { servers = { roslyn = true } },
  } })
  assert(not ok and tostring(err):find("roslyn", 1, true))
  assert(vim.deep_equal(orbit.get_config(), previous))
end)

check("server failures are isolated and diagnostics remain compatible", function()
  local configured, activated, notices, diagnostic = {}, {}, {}, nil
  local old_config, old_enable = vim.lsp.config, vim.lsp.enable
  local old_diagnostic, old_notify = vim.diagnostic.config, vim.notify
  local old_blink = package.preload["blink.cmp"]

  package.preload["blink.cmp"] = function()
    return {
      get_lsp_capabilities = function(overrides, defaults)
        assert(defaults and overrides.textDocument.diagnostic.dynamicRegistration)
        return { orbit_blink_marker = true }
      end,
    }
  end
  vim.lsp.config = function(name, opts)
    configured[name] = opts
    if name == "dockerls" then
      error("injected Dockerfile registration failure")
    end
  end
  vim.lsp.enable = function(name)
    if name == "powershell_es" then
      error("injected PowerShell activation failure")
    end
    activated[#activated + 1] = name
  end
  vim.diagnostic.config = function(opts)
    diagnostic = opts
  end
  vim.notify = function(message, level)
    assert(level == vim.log.levels.WARN)
    notices[#notices + 1] = message
  end

  local ok, result = xpcall(function()
    local item = feature.spec()[1]
    return item.config(nil, item.opts)
  end, debug.traceback)

  vim.lsp.config, vim.lsp.enable = old_config, old_enable
  vim.diagnostic.config, vim.notify = old_diagnostic, old_notify
  package.loaded["blink.cmp"], package.preload["blink.cmp"] = nil, old_blink

  assert(ok, tostring(result))
  assert(#result.activated > 8)
  assert(result.failures.dockerls:find("injected Dockerfile", 1, true))
  assert(result.failures.powershell_es:find("injected PowerShell", 1, true))
  assert(#notices == 2)
  assert(not vim.tbl_contains(activated, "dockerls"))
  assert(vim.tbl_contains(activated, "lua_ls"))
  assert(configured.lua_ls.capabilities.orbit_blink_marker)
  assert(configured.lua_ls.settings.Lua.runtime.version == "LuaJIT")
  assert(configured.pyright.settings.python.analysis.typeCheckingMode == "standard")
  assert(configured.ruff.init_options.settings.configurationPreference ==
    "filesystemFirst")
  local client = { server_capabilities = { semanticTokensProvider = {} } }
  configured.lua_ls.on_init(client)
  assert(client.server_capabilities.semanticTokensProvider == nil)
  local ruff_client = { server_capabilities = { hoverProvider = true } }
  configured.ruff.on_attach(ruff_client)
  assert(ruff_client.server_capabilities.hoverProvider == false)
  local json_schema = configured.jsonls.settings.json.schemas[1]
  assert(json_schema.url == vim.uri_from_fname(
    vim.api.nvim_get_runtime_file("settings.schema.json", false)[1]))
  assert(diagnostic.underline and diagnostic.severity_sort)
  assert(diagnostic.virtual_text.severity.min == vim.diagnostic.severity.WARN)
  assert(diagnostic.signs.text[vim.diagnostic.severity.ERROR] == " ")
  assert(diagnostic.float.border == "rounded")
end)

check("second activation is idempotent", function()
  local item = feature.spec()[1]
  local result = item.config(nil, item.opts)
  assert(result.already_started == true)
end)

check("server and diagnostic changes are held until restart", function()
  orbit.setup({ modules = { lsp = {
    servers = { lua_ls = false },
    diagnostics = { virtual_text = false },
  } } })
  assert(orbit.get_config().modules.lsp.servers.lua_ls == true)
  assert(orbit.get_config().modules.lsp.diagnostics.virtual_text == true)
  local deferred = orbit.get_pending_restart()
  assert(deferred["orbit.modules.lsp.servers"].lua_ls == false)
  assert(deferred["orbit.modules.lsp.diagnostics"].virtual_text == false)
end)

print(string.format("%d native LSP tests passed.", passed))
