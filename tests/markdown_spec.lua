-- Hermetic Markdown preview Lazy build and cross-platform command contracts.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.markdown")
local runtime = require("orbit.modules.markdown.runtime")
local passed = 0

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. name .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. name)
end

check("Markdown import is inert and preview is command/filetype lazy", function()
  assert(#feature.spec() == 0)
  orbit.setup()
  local specs = feature.spec()
  assert(#specs == 1)
  local spec = specs[1]
  assert(spec[1] == "iamcco/markdown-preview.nvim")
  assert(vim.deep_equal(spec.cmd,
    { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" }))
  assert(vim.deep_equal(spec.ft, { "markdown" }))
  assert(spec.keys[1][1] == "<leader>mp")
  assert(spec.keys[1][2] == "<cmd>MarkdownPreviewToggle<cr>")
  assert(type(spec.build) == "function")
  assert(package.loaded["markdown-preview"] == nil)
end)

check("platform names and executable paths preserve Linux/Windows/macOS", function()
  assert(runtime.platform_name(true, false, "x86_64") == "win")
  assert(runtime.platform_name(false, false, "x86_64") == "linux")
  assert(runtime.platform_name(false, true, "arm64") == "macos-arm64")
  assert(runtime.platform_name(false, true, "x86_64") == "macos")
  assert(runtime.executable("C:/with spaces", "win"):match("markdown%-preview%-win%.exe$"))
  assert(runtime.executable("/tmp/with spaces", "linux"):match("markdown%-preview%-linux$"))
end)

local temp = vim.fn.tempname() .. " preview with spaces"
local app = vim.fs.joinpath(temp, "app")
vim.fn.mkdir(vim.fs.joinpath(app, "bin"), "p")
vim.fn.writefile({ '{"version":"1.2.3"}' },
  vim.fs.joinpath(temp, "package.json"))
local platform = runtime.platform_name(vim.fn.has("win32") == 1,
  vim.fn.has("mac") == 1, vim.uv.os_uname().machine)
local binary = runtime.executable(temp, platform)
vim.fn.writefile({ "fixture binary" }, binary)
local original_system = vim.system

check("build callback waits for the installer and verifies the new version", function()
  local calls, checks = {}, 0
  vim.system = function(argv, opts)
    calls[#calls + 1] = { argv = argv, opts = opts }
    if argv[1] == binary then
      checks = checks + 1
      return { wait = function(_, timeout)
        assert(timeout == 10000)
        return { code = 0, stdout = checks == 1 and "old\n" or "1.2.3\n" }
      end }
    end
    assert(opts.cwd == app and opts.text == true)
    if platform == "win" then
      assert(vim.deep_equal(argv,
        { "cmd.exe", "/d", "/c", ".\\install.cmd", "v1.2.3" }))
    else
      assert(vim.deep_equal(argv, { "bash", "./install.sh", "v1.2.3" }))
    end
    return { wait = function(_, timeout)
      assert(timeout == 120000)
      return { code = 0, stdout = "" }
    end }
  end
  feature.spec()[1].build({ dir = temp })
  assert(#calls == 3 and checks == 2)
  runtime.build_preview({ dir = temp })
  assert(#calls == 4 and checks == 3,
    "a matching binary must skip the installer")
  vim.system = original_system
end)

check("unlaunchable preview binaries are rebuilt before verification", function()
  local checks, installs = 0, 0
  vim.system = function(argv)
    if argv[1] == binary then
      checks = checks + 1
      if checks == 1 then error("fixture spawn failure") end
      return { wait = function() return { code = 0, stdout = "1.2.3\n" } end }
    end
    installs = installs + 1
    return { wait = function() return { code = 0 } end }
  end
  runtime.build_preview({ dir = temp })
  assert(checks == 2 and installs == 1)
  vim.system = original_system
end)

check("installer errors and mismatched output do not report success", function()
  vim.system = function(argv)
    if argv[1] == binary then
      return { wait = function() return { code = 0, stdout = "old\n" } end }
    end
    return { wait = function() return { code = 7, stderr = "fixture failed" } end }
  end
  local ok, err = pcall(runtime.build_preview, { dir = temp })
  assert(not ok and tostring(err):find("fixture failed", 1, true))
  vim.system = function(argv)
    if argv[1] == binary then
      return { wait = function() return { code = 0, stdout = "old\n" } end }
    end
    return { wait = function() return { code = 0 } end }
  end
  ok, err = pcall(runtime.build_preview, { dir = temp })
  assert(not ok and tostring(err):find("expected executable version", 1, true))
  vim.system = original_system
end)

check("invalid versions are rejected before invoking an installer", function()
  vim.fn.writefile({ '{"version":"1.2.3 & bad"}' },
    vim.fs.joinpath(temp, "package.json"))
  vim.system = function() error("unexpected process") end
  local ok, err = pcall(runtime.build_preview, { dir = temp })
  assert(not ok and tostring(err):find("version is invalid", 1, true))
  vim.system = original_system
end)

check("settings validate and defer restart-only preview changes", function()
  local before = orbit.get_config()
  local ok, err = pcall(orbit.setup, { modules = {
    markdown = { build_timeout = 999 },
  } })
  assert(not ok and tostring(err):find("build_timeout", 1, true))
  assert(vim.deep_equal(orbit.get_config(), before))
  orbit.setup({ modules = { markdown = { preview = false } } })
  assert(orbit.get_config().modules.markdown.preview)
  assert(orbit.get_pending_restart()["orbit.modules.markdown.preview"] == false)
  local snapshot = feature.capture()
  feature.setup({ preview = false })
  assert(#feature.spec() == 0)
  feature.restore(snapshot)
  assert(#feature.spec() == 1)
end)

vim.fn.delete(temp, "rf")
print(string.format("%d Markdown preview tests passed.", passed))
