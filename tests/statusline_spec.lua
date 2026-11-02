-- Verify status line ownership, rendered sections and rollback.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local commands = require("orbit.modules.commands")
local passed = 0
local function check(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

local function rendered()
  return vim.api.nvim_eval_statusline(vim.go.statusline, { highlights = false, maxwidth = 400 }).str
end

vim.go.statusline = "user statusline"
vim.o.columns = 160

check("setup owns the status line and renders mode, file, cursor and cwd", function()
  orbit.setup()
  assert(vim.go.statusline:find("orbit.modules.statusline.render", 1, true))
  vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. "-orbit 100% name.lua"))
  local text = rendered()
  assert(text:find("NORMAL", 1, true), text)
  assert(text:find("orbit 100% name.lua", 1, true), "file names must be escaped: " .. text)
  assert(text:find(" %d+/%d+ "), text)
  assert(text:find(vim.fn.fnamemodify(vim.fn.getcwd(), ":t"), 1, true), text)
end)

check("diagnostics and Git status appear when present", function()
  local buffer = vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace("orbit.statusline.test")
  vim.diagnostic.set(ns, buffer, {
    { lnum = 0, col = 0, message = "e", severity = vim.diagnostic.severity.ERROR },
    { lnum = 0, col = 0, message = "w", severity = vim.diagnostic.severity.WARN },
    { lnum = 0, col = 0, message = "w2", severity = vim.diagnostic.severity.WARN },
  })
  vim.b[buffer].gitsigns_head = "main"
  vim.b[buffer].gitsigns_status_dict = { added = 2, changed = 0, removed = 1 }
  local text = rendered()
  assert(text:find(" 1", 1, true) and text:find(" 2", 1, true), text)
  assert(text:find(" main  2  1", 1, true), text)
  vim.diagnostic.reset(ns, buffer)
  vim.b[buffer].gitsigns_head = nil
end)

check("symbols use Trouble lazily and preserve escaped names and truncation", function()
  local previous = package.loaded.trouble
  local calls = 0
  package.loaded.trouble = {
    statusline = function(opts)
      calls = calls + 1
      assert(opts.mode == "symbols" and opts.filter.range and opts.hl_group == "OrbitStSymbols")
      local boundary = opts.format:sub(-1)
      return { get = function()
        local parts = {}
        for _, name in ipairs({ "Root%%", "Hidden", "Class", "Method" }) do
          parts[#parts + 1] = "%#Function#ƒ%*%#OrbitStSymbols#" .. name .. "%*" .. boundary
        end
        return table.concat(parts) .. "%#OrbitStSymbols# %*"
      end }
    end,
  }
  local text = rendered()
  assert(text:find("Root%  …  ƒClass  ƒMethod", 1, true), text)
  rendered()
  assert(calls == 1, "redraw must reuse the symbol provider")
  package.loaded.trouble = previous
end)

check("narrow status lines hide the cwd block", function()
  local columns = vim.o.columns
  vim.o.columns = 70
  local text = rendered()
  assert(not text:find("󰉋", 1, true), text)
  vim.o.columns = columns
end)

check("highlight links survive a colorscheme change", function()
  vim.cmd.colorscheme("habamax")
  local link = vim.api.nvim_get_hl(0, { name = "OrbitStModeNormal" }).link
  assert(link == "PmenuSel", tostring(link))
  assert(#vim.api.nvim_get_autocmds({ group = "OrbitStatusline", event = "ColorScheme" }) == 1)
end)

check("later module failure keeps the owned status line", function()
  local expression = vim.go.statusline
  local prior = commands.setup
  commands.setup = function() error("injected statusline rollback") end
  local ok = pcall(orbit.setup, { modules = { statusline = { enabled = false },
    commands = { name = "OrbitStatuslineFail" } } })
  commands.setup = prior
  assert(not ok and vim.go.statusline == expression)
  assert(#vim.api.nvim_get_autocmds({ group = "OrbitStatusline" }) > 0)
end)

check("disabling restores the prior status line and removes observers", function()
  orbit.setup({ modules = { statusline = { enabled = false } } })
  assert(vim.go.statusline == "user statusline", vim.go.statusline)
  assert(not pcall(vim.api.nvim_get_autocmds, { group = "OrbitStatusline" }))
end)

check("disabling keeps a status line the user set after ownership", function()
  orbit.setup()
  vim.go.statusline = "replaced by user"
  orbit.setup({ modules = { statusline = { enabled = false } } })
  assert(vim.go.statusline == "replaced by user")
end)

print(string.format("%d statusline tests passed.", passed))
