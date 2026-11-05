-- Verify status line ownership, rendered sections and rollback.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local orbit = require("orbit")
local commands = require("orbit.modules.commands")
-- Drawing both bars in this headless fixture can crash Windows Neovim 0.12.5.
-- The tabline has its own suite; isolate the statusline checks from its redraw.
local function setup(opts)
  orbit.setup(
    vim.tbl_deep_extend("force", { modules = { tabline = { enabled = false } } }, opts or {})
  )
end
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

check("setup owns the status line and renders mode, file and cursor", function()
  setup()
  assert(vim.go.statusline:find("orbit.modules.statusline.render", 1, true))
  vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. "-orbit 100% name.lua"))
  local text = rendered()
  assert(text:find("NORMAL", 1, true), text)
  assert(text:find("orbit 100% name.lua", 1, true), "file names must be escaped: " .. text)
  assert(text:find("^▌ NORMAL"), "the mode bar starts the line: " .. text)
  assert(text:find("%d+:%d+ %a+$"), "line, column and %P end the line: " .. text)
end)

check("diagnostics and Git status appear when present", function()
  local buffer = vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace("orbit.statusline.test")
  vim.diagnostic.set(ns, buffer, {
    { lnum = 0, col = 0, message = "e", severity = vim.diagnostic.severity.ERROR },
    { lnum = 0, col = 0, message = "w", severity = vim.diagnostic.severity.WARN },
    { lnum = 0, col = 0, message = "w2", severity = vim.diagnostic.severity.WARN },
    { lnum = 0, col = 0, message = "i", severity = vim.diagnostic.severity.INFO },
    { lnum = 0, col = 0, message = "h", severity = vim.diagnostic.severity.HINT },
    { lnum = 0, col = 0, message = "h2", severity = vim.diagnostic.severity.HINT },
  })
  vim.b[buffer].gitsigns_head = "main"
  vim.b[buffer].gitsigns_status_dict = { added = 2, changed = 0, removed = 1 }
  local text = rendered()
  assert(
    text:find("\u{F057} 1 \u{F071} 2 \u{F02FC} 3", 1, true),
    "info and hint share one count: " .. text
  )
  assert(text:find("main +2 -1", 1, true), "Git counts are text: " .. text)
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
      return {
        get = function()
          local parts = {}
          for _, name in ipairs({ "Root%%", "Hidden", "Class", "Method" }) do
            parts[#parts + 1] = "%#Function#ƒ%*%#OrbitStSymbols#" .. name .. "%*" .. boundary
          end
          return table.concat(parts) .. "%#OrbitStSymbols# %*"
        end,
      }
    end,
  }
  local text = rendered()
  assert(text:find("Root%  …  ƒClass  ƒMethod", 1, true), text)
  rendered()
  assert(calls == 1, "redraw must reuse the symbol provider")
  package.loaded.trouble = previous
end)

check("one gap separates visible sections and empty sections leave none", function()
  local buffer = vim.api.nvim_get_current_buf()
  vim.b[buffer].gitsigns_head = "main"
  vim.b[buffer].gitsigns_status_dict = nil
  local text = rendered()
  assert(text:find("NORMAL · main · ", 1, true), "one divider between sections: " .. text)
  vim.b[buffer].gitsigns_head = nil
  text = rendered()
  assert(text:find("NORMAL · %S"), "an empty Git section leaves one divider: " .. text)
  assert(not text:find("·%s+·"), "dividers never double: " .. text)
  assert(not text:find("^%s"), "no gap before the mode bar: " .. text)
  assert(not text:find("%s$"), "no gap after the position: " .. text)
end)

check("a long line truncates the path and keeps the mode and branch", function()
  local buffer = vim.api.nvim_get_current_buf()
  vim.b[buffer].gitsigns_head = "main"
  vim.b[buffer].gitsigns_status_dict = nil
  local text =
    vim.api.nvim_eval_statusline(vim.go.statusline, { highlights = false, maxwidth = 40 }).str
  vim.b[buffer].gitsigns_head = nil
  assert(text:find("^▌ NORMAL · main · <"), "the cut starts after the branch: " .. text)
end)

check("the gap option widens every gap and rolls back with its module", function()
  setup({ modules = { statusline = { gap = 3 } } })
  local buffer = vim.api.nvim_get_current_buf()
  vim.b[buffer].gitsigns_head = "main"
  vim.b[buffer].gitsigns_status_dict = nil
  local text = rendered()
  assert(text:find("NORMAL   ·   main   ·   ", 1, true), text)
  vim.b[buffer].gitsigns_head = nil
  local prior = commands.setup
  commands.setup = function()
    error("injected gap rollback")
  end
  local ok = pcall(
    setup,
    { modules = { statusline = { gap = 1 }, commands = { name = "OrbitStatuslineGapFail" } } }
  )
  commands.setup = prior
  assert(not ok and require("orbit.modules.statusline").gap() == 3)
  setup()
  assert(require("orbit.modules.statusline").gap() == 1)
end)

local render = require("orbit.modules.statusline.render")
---@param layout Orbit.StatuslineItem[]
---@return string
local function composed(layout)
  return vim.api.nvim_eval_statusline(
    render.compose(layout, vim.api.nvim_get_current_win()),
    { highlights = false, maxwidth = 400 }
  ).str
end
local function component(value)
  return function()
    return value
  end
end
local empty = component("")

check("containers join only visible children with their gap", function()
  setup({ modules = { statusline = { gap = 2 } } })
  assert(composed({ render.container({ component("a"), empty, component("b") }) }) == "a  b")
  assert(composed({ render.container({ component("a"), component("b") }, { gap = 0 }) }) == "ab")
  local nested =
    render.container({ component("a"), render.container({ empty, empty }), component("b") })
  assert(composed({ nested }) == "a  b", "an empty inner container leaves no gap")
  setup()
end)

check("spacers collapse at edges and next to empty items", function()
  assert(composed({ render.spacer(3), component("a"), render.spacer(3) }) == "a")
  assert(
    composed({ component("a"), render.spacer(1), empty, render.spacer(3), component("b") })
      == "a   b"
  )
  local marked =
    composed({ component("a"), render.truncate(), render.spacer(2), empty, render.spacer() })
  assert(marked == "a", "a trailing spacer stays empty: " .. marked)
  local raw = render.compose({
    component("a"),
    render.spacer(2),
    render.container({ empty }),
    render.spacer(1),
    render.fill(),
    component("b"),
  }, vim.api.nvim_get_current_win())
  assert(
    raw:find("a%%#OrbitStFill#  %%#OrbitStFill#%%=b"),
    "the merged spacer keeps the first position: " .. raw
  )
end)

check("separators follow the spacer rules and win a merged run", function()
  local a, b = component("a"), component("b")
  assert(composed({ render.separator(), a, render.separator() }) == "a")
  assert(composed({ a, render.separator(), empty, render.separator(), b }) == "a · b")
  assert(composed({ a, render.spacer(3), empty, render.separator(), b }) == "a   ·   b")
  assert(composed({ a, render.separator(), render.container({ empty }) }) == "a")
  local sides = composed({ a, render.separator(), render.fill(), empty, render.separator(), b })
  assert(
    sides:find("^a%s+b$") and not sides:find("·", 1, true),
    "no divider crosses the fill: " .. sides
  )
end)

check("components receive the window and status line width", function()
  local seen
  composed({
    function(ctx)
      seen = ctx
      return ""
    end,
  })
  assert(
    seen.win == vim.api.nvim_get_current_win() and seen.buffer == vim.api.nvim_get_current_buf()
  )
  assert(seen.width == vim.o.columns, "a global status line spans the columns")
end)

check("invalid gap or spacer widths fail at declaration", function()
  assert(not pcall(render.spacer, -1))
  assert(not pcall(render.spacer, 1.5))
  assert(not pcall(render.container, {}, { gap = 1.5 }))
  assert(not pcall(render.container, { render.spacer(1) }))
end)

check("narrow status lines drop detail in priority order", function()
  local buffer = vim.api.nvim_get_current_buf()
  local columns, clients, trouble = vim.o.columns, vim.lsp.get_clients, package.loaded.trouble
  vim.b[buffer].gitsigns_head = "main"
  vim.b[buffer].gitsigns_status_dict = { added = 2 }
  vim.lsp.get_clients = function()
    return { { name = "lua_ls" } }
  end
  package.loaded.trouble = {
    statusline = function()
      return {
        get = function()
          return "Sym\31"
        end,
      }
    end,
  }
  local function at(width)
    vim.o.columns = width
    return rendered()
  end
  local ok, err = pcall(function()
    local text = at(160)
    for _, part in ipairs({ "Sym", "lua_ls", "+2", "/", "main" }) do
      assert(text:find(part, 1, true), part .. ": " .. text)
    end
    assert(not at(119):find("Sym", 1, true) and at(120):find("Sym", 1, true))
    assert(not at(99):find("lua_ls", 1, true) and at(100):find("lua_ls", 1, true))
    assert(not at(89):find("+2", 1, true) and at(90):find("+2", 1, true))
    text = at(79)
    assert(not text:find("/", 1, true) and not text:find("%a+$"), text)
    assert(at(80):find("/", 1, true))
    text = at(59)
    assert(
      not text:find("main", 1, true) and text:find("NORMAL", 1, true) and text:find("%d+:%d+$")
    )
  end)
  vim.o.columns, vim.lsp.get_clients, package.loaded.trouble = columns, clients, trouble
  vim.b[buffer].gitsigns_head, vim.b[buffer].gitsigns_status_dict = nil, nil
  assert(ok, err)
end)

check("terminal, help, list and plugin buffers show a label", function()
  local start = vim.api.nvim_get_current_win()
  local function line()
    return vim.api.nvim_eval_statusline(
      vim.go.statusline,
      { highlights = false, maxwidth = 400, winid = vim.api.nvim_get_current_win() }
    ).str
  end
  vim.cmd("vsplit")
  vim.cmd.terminal({ args = { vim.fn.shellescape(vim.v.progpath) .. " --version" } })
  local text = line()
  assert(text:find("nvim", 1, true), "terminal shows its program: " .. text)
  assert(not text:find("%d+:%d+"), "terminal hides the position: " .. text)
  vim.cmd("bwipeout!")
  vim.cmd.help("options")
  text = line()
  assert(text:find("help options", 1, true) and text:find("%d+:%d+"), text)
  vim.cmd.close()
  vim.fn.setqflist({}, " ", { title = "Orbit list", items = { { filename = "a", lnum = 1 } } })
  vim.cmd.copen()
  text = line()
  assert(text:find("quickfix Orbit list", 1, true), text)
  vim.cmd.cclose()
  vim.cmd("vnew")
  vim.bo.buftype, vim.bo.filetype = "nofile", "OrbitPanel"
  text = line()
  assert(text:find("OrbitPanel", 1, true), "plugin buffers show their filetype: " .. text)
  vim.cmd("bwipeout!")
  vim.api.nvim_set_current_win(start)
end)

check("search count and selection size appear only in their states", function()
  vim.cmd("enew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo bar", "foo baz", "foo" })
  local text = rendered()
  assert(not text:find("%d+/%d+") and not text:find("%d+L"), text)
  vim.o.hlsearch = true
  vim.fn.setreg("/", "foo")
  vim.v.hlsearch = 1
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  text = rendered()
  assert(text:find(" 2/3", 1, true), "search shows current/total: " .. text)
  vim.v.hlsearch = 0
  assert(not rendered():find(" 2/3", 1, true), "no count without hlsearch")
  vim.api.nvim_feedkeys(vim.keycode("Vj"), "nx", false)
  text = rendered()
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  assert(text:find(" 2L", 1, true), "line-wise selection counts lines: " .. text)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys("vll", "nx", false)
  text = rendered()
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  assert(text:find(" 3 ", 1, true), "character selection counts characters: " .. text)
  vim.o.hlsearch = false
  vim.cmd("bwipeout!")
end)

check("unusual file formats and read-only files are flagged", function()
  vim.cmd("enew")
  local fileformats = vim.o.fileformats
  vim.o.fileformats = "unix,dos"
  local text = rendered()
  assert(not text:find("CRLF", 1, true) and not text:find("\u{F023}", 1, true), text)
  vim.bo.fileformat, vim.bo.fileencoding, vim.bo.bomb = "dos", "latin1", true
  text = rendered()
  assert(text:find("CRLF latin1 BOM", 1, true), "unusual values are flagged: " .. text)
  vim.o.fileformats = "dos,unix"
  assert(not rendered():find("CRLF", 1, true), "the first fileformats entry is usual")
  vim.bo.readonly = true
  assert(rendered():find("\u{F023}", 1, true), "read-only files show the lock")
  vim.bo.readonly, vim.bo.modifiable = false, false
  assert(rendered():find("\u{F023}", 1, true), "nomodifiable files show the lock")
  vim.o.fileformats = fileformats
  vim.cmd("bwipeout!")
end)

check("highlight links survive a colorscheme change", function()
  vim.cmd.colorscheme("habamax")
  local link = vim.api.nvim_get_hl(0, { name = "OrbitStModeNormal" }).link
  assert(link == "Function", tostring(link))
  assert(#vim.api.nvim_get_autocmds({ group = "OrbitStatusline", event = "ColorScheme" }) == 1)
end)

check("later module failure keeps the owned status line", function()
  local expression = vim.go.statusline
  local prior = commands.setup
  commands.setup = function()
    error("injected statusline rollback")
  end
  local ok = pcall(
    setup,
    { modules = { statusline = { enabled = false }, commands = { name = "OrbitStatuslineFail" } } }
  )
  commands.setup = prior
  assert(not ok and vim.go.statusline == expression)
  assert(#vim.api.nvim_get_autocmds({ group = "OrbitStatusline" }) > 0)
end)

check("disabling restores the prior status line and removes observers", function()
  setup({ modules = { statusline = { enabled = false } } })
  assert(vim.go.statusline == "user statusline", vim.go.statusline)
  assert(not pcall(vim.api.nvim_get_autocmds, { group = "OrbitStatusline" }))
end)

check("disabling keeps a status line the user set after ownership", function()
  setup()
  vim.go.statusline = "replaced by user"
  setup({ modules = { statusline = { enabled = false } } })
  assert(vim.go.statusline == "replaced by user")
end)

print(string.format("%d statusline tests passed.", passed))
