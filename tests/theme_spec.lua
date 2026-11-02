-- Verify theme application, highlight ownership, rollback and persistence.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local feature = require("orbit.modules.theme")
local runtime = require("orbit.modules.theme.runtime")
local commands = require("orbit.modules.commands")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

local function hl(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local directory = vim.fn.tempname() .. " theme settings"
vim.fn.mkdir(directory, "p")
local settings = directory .. "/settings.json"

check("setup is inert until the colorscheme plugin starts the runtime", function()
  orbit.setup({ modules = { theme = { colorscheme = "habamax" }, commands = { path = settings } } })
  assert(vim.g.colors_name == nil, "setup must not apply a scheme before plugin activation")
  local spec = feature.spec()[1]
  assert(spec[1] == "folke/tokyonight.nvim" and spec.lazy == false and spec.priority == 1000)
  assert(package.loaded.tokyonight == nil)
end)

check("plugin start applies the scheme and Orbit overrides", function()
  package.loaded.tokyonight = { setup = function() end }
  local spec = feature.spec()[1]
  spec.config(spec, spec.opts)
  package.loaded.tokyonight = nil
  assert(vim.g.colors_name == "habamax")
  assert(hl("FloatBorder").fg == hl("Function").fg, "FloatBorder must use the scheme's blue")
  assert(hl("DiagnosticUnderlineError").sp == hl("DiagnosticError").fg)
  assert(hl("SnacksPickerMatch").bold)
  assert(hl("CursorLineNr").fg == runtime.palette().white,
    "current line number must use Orbit's foreground")
end)

check("overrides survive a later colorscheme change", function()
  vim.cmd.colorscheme("lunaperche")
  assert(hl("FloatBorder").fg == runtime.palette().blue)
  assert(hl("SnacksPickerMatch").bold)
  assert(#vim.api.nvim_get_autocmds({ group = "OrbitTheme" }) == 1)
end)

check("reapplying highlights never derives a new palette from Orbit overrides", function()
  local before = runtime.palette()
  for _ = 1, 3 do runtime.apply_highlights() end
  assert(vim.deep_equal(runtime.palette(), before), "repeated highlights changed the palette")
  assert(hl("DiagnosticInfo").fg == before.green and hl("DiagnosticHint").fg == before.purple)
  assert(hl("OrbitStFill").bg == before.statusline_bg)
  assert(hl("OrbitTbActive").bg ~= hl("OrbitTbInactive").bg)
end)

check("diagnostic underlines follow terminal undercurl support", function()
  local term, program = vim.env.TERM, vim.env.TERM_PROGRAM
  vim.env.TERM, vim.env.TERM_PROGRAM = "xterm", ""
  runtime.apply_highlights()
  local plain = hl("DiagnosticUnderlineError")
  assert(plain.underline and not plain.undercurl)
  vim.env.TERM = "xterm-kitty"
  runtime.apply_highlights()
  local curved = hl("DiagnosticUnderlineError")
  assert(curved.undercurl and not curved.underline)
  vim.env.TERM, vim.env.TERM_PROGRAM = term, program
  runtime.apply_highlights()
end)

check("changing the configured scheme applies it once", function()
  orbit.setup({ modules = { theme = { colorscheme = "desert" }, commands = { path = settings } } })
  assert(vim.g.colors_name == "desert")
  assert(#vim.api.nvim_get_autocmds({ group = "OrbitTheme" }) == 1)
end)

check("later module failure restores the previous scheme", function()
  local accepted = orbit.get_config()
  local prior = commands.setup
  commands.setup = function() error("injected theme rollback") end
  local ok, err = pcall(orbit.setup, { modules = {
    theme = { colorscheme = "habamax" }, commands = { path = settings, name = "OrbitThemeFail" },
  } })
  commands.setup = prior
  assert(not ok and tostring(err):find("injected theme rollback", 1, true))
  assert(vim.g.colors_name == "desert", "rollback must restore the prior scheme")
  assert(vim.deep_equal(orbit.get_config(), accepted))
end)

check("disabling overrides removes the observer and the override values", function()
  orbit.setup({ modules = { theme = { colorscheme = "desert", highlights = false },
    commands = { path = settings } } })
  assert(not pcall(vim.api.nvim_get_autocmds, { group = "OrbitTheme" }))
  assert(not hl("SnacksPickerMatch").bold, "scheme reload must clear Orbit overrides")
  orbit.setup({ modules = { theme = { colorscheme = "desert" }, commands = { path = settings } } })
  assert(hl("SnacksPickerMatch").bold)
end)

check("an unknown scheme warns and keeps the current scheme", function()
  local notify, warned = vim.notify, nil
  vim.notify = function(message) warned = message end
  orbit.setup({ modules = { theme = { colorscheme = "orbit-missing-scheme" },
    commands = { path = settings } } })
  vim.notify = notify
  assert(warned and warned:find("orbit-missing-scheme", 1, true))
  assert(vim.g.colors_name == "desert")
  orbit.setup({ modules = { theme = { colorscheme = "desert" }, commands = { path = settings } } })
end)

check("saving a selection requires an existing settings file", function()
  local saved, err = runtime.persist("habamax")
  assert(not saved and err:find("open settings", 1, true))
  assert(vim.uv.fs_stat(settings) == nil, "persisting must not create settings")
end)

check("selection saves to existing settings and keeps other values", function()
  assert(vim.fn.writefile({ '{"$schema": "x", "modules": {"editor": {"shiftwidth": 4}}}' },
    settings) == 0)
  local select, notify = vim.ui.select, vim.notify
  vim.ui.select = function(_, _, callback) callback("habamax") end
  vim.notify = function() end
  require("orbit.modules.keymaps.theme").select()
  vim.ui.select, vim.notify = select, notify
  assert(vim.g.colors_name == "habamax")
  local saved = vim.json.decode(table.concat(vim.fn.readfile(settings), "\n"))
  assert(saved.modules.theme.colorscheme == "habamax")
  assert(saved.modules.editor.shiftwidth == 4 and saved["$schema"] == "x")
  local loaded = require("orbit.settings").read(settings)
  assert(loaded.modules.theme.colorscheme == "habamax")
end)

check("invalid saves leave the settings file unchanged", function()
  local before = table.concat(vim.fn.readfile(settings, "b"), "\n")
  local ok, err = require("orbit.settings").update(settings,
    { "modules", "theme", "colorscheme" }, "")
  assert(not ok and tostring(err):find("colorscheme", 1, true))
  assert(table.concat(vim.fn.readfile(settings, "b"), "\n") == before)
  assert(#vim.fn.glob(directory .. "/*.tmp", false, true) == 0, "temporary file leaked")
end)

check("default Tokyo Night restores editor, syntax, bar and plugin color roles", function()
  local colors = directory .. "/colors"
  vim.fn.mkdir(colors, "p")
  vim.fn.writefile({ "highlight clear", "set background=dark", "let g:colors_name = 'tokyonight-night'" },
    colors .. "/tokyonight-night.vim")
  vim.opt.rtp:prepend(directory)
  orbit.setup({ modules = { theme = { colorscheme = "tokyonight-night" }, commands = { path = settings } } })
  assert(hl("Normal").fg == 0xa9b1d6 and hl("Normal").bg == 0x1a1b26)
  assert(hl("CursorLineNr").fg == 0xc0caf5 and hl("CursorLineNr").bg == nil)
  assert(hl("LineNr").fg == 0x40486a)
  assert(hl("@punctuation.bracket").fg == 0xbb9af7)
  assert(hl("@function.method.call").fg == 0xf7768e)
  assert(hl("OrbitStModeInsert").bg == 0x9d7cd8)
  assert(hl("OrbitTbActiveModified").fg == 0x9ece6a)
  assert(hl("OrbitTbInactiveModified").fg == 0xf7768e)
  assert(hl("BlinkCmpLabelMatch").fg == 0x7aa2f7 and hl("BlinkCmpLabelMatch").bold)
  assert(hl("NvimTreeNormal").bg == 0x16161e)
  assert(hl("MasonHeader").bg == 0xf7768e)
  assert(hl("WhichKeyGroup").fg == 0x9ece6a)
  assert(hl("TodoBgFix").bg == 0xf7768e)
  vim.opt.rtp:remove(directory)
end)

vim.fn.delete(directory, "rf")
print(string.format("%d theme tests passed.", passed))
