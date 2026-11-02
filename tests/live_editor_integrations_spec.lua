-- Set up real todo-comments, vim-matchup and indent-blankline through Orbit.
-- Requires Git and network; Orbit highlight groups must reach the plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local pins = {
  { "https://github.com/folke/todo-comments.nvim.git", "31e3c38ce9b29781e4422fc0322eb0a21f4e8668" },
  { "https://github.com/nvim-lua/plenary.nvim.git", "74b06c6c75e4eeb3108ec01852001636d85a932b" },
  { "https://github.com/andymass/vim-matchup.git", "0106b1afd4a2f7e1098037b5ceb161bab7471088" },
  { "https://github.com/lukas-reineke/indent-blankline.nvim.git", "f1e186e44d3b7f9ae918008e2c28ce37c6023d2d" },
}
local workspace = vim.fn.tempname() .. " live editor integrations with spaces"

local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 300000 }):wait()
  assert(result.code == 0, vim.inspect(argv) ..
    " failed: " .. tostring(result.stderr or "") .. tostring(result.stdout or ""))
  return result.stdout or ""
end

local function find(specs, name)
  for _, spec in ipairs(specs) do
    if spec[1] == name then return spec end
  end
  error("Orbit did not declare " .. name)
end

local function marks(buffer, namespace)
  local id = vim.api.nvim_get_namespaces()[namespace]
  assert(id, "namespace " .. namespace .. " is missing")
  return vim.api.nvim_buf_get_extmarks(buffer, id, 0, -1, { details = true })
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required")
  for index, pin in ipairs(pins) do
    local directory = vim.fs.joinpath(workspace, "plugin" .. index)
    assert(vim.fn.mkdir(directory, "p") == 1)
    run({ "git", "init", directory })
    run({ "git", "-C", directory, "fetch", "--depth", "1", pin[1], pin[2] })
    run({ "git", "-C", directory, "checkout", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", directory, "rev-parse", "HEAD" })) == pin[2])
    vim.opt.rtp:prepend(directory)
  end

  require("orbit").setup()
  require("orbit.modules.theme.runtime").apply_highlights()
  local source = vim.fs.joinpath(workspace, "sample.lua")
  assert(vim.fn.writefile({
    "local function sample(value)",
    "  -- TODO: keep the default keyword",
    "  -- WORKAROUND: Orbit adds this keyword",
    "  if value then",
    "    for _ = 1, 2 do",
    "      value = value + 1",
    "    end",
    "    return value",
    "  end",
    "end",
  }, source) == 0)
  -- Orbit loads matchup eagerly, so it is active before the first buffer.
  local matchup = find(require("orbit.modules.editor_plugins").spec(), "andymass/vim-matchup")
  assert(matchup.lazy == false, "Orbit made vim-matchup lazy")
  matchup.init()
  vim.cmd.runtime("plugin/matchup.vim")
  vim.cmd("filetype plugin on")
  vim.cmd.edit(vim.fn.fnameescape(source))
  local buffer = vim.api.nvim_get_current_buf()
  vim.treesitter.start(buffer, "lua")
  vim.treesitter.get_parser(buffer):parse(true)
  assert(vim.g.loaded_matchup == 1, "vim-matchup did not load")
  assert(vim.g.matchup_treesitter_stopline == 500, "Orbit did not set the matchup stopline")
  assert(vim.g.matchup_matchparen_offscreen.method == "popup", "Orbit did not set the offscreen popup")
  assert(vim.b[buffer].matchup_delim_enabled == 1, "vim-matchup did not enable the Lua buffer")
  assert(vim.fn.maparg("%", "n") == "<Plug>(matchup-%)", "vim-matchup does not own %")
  print("PASS real vim-matchup loads with Orbit options")

  local todo = find(require("orbit.modules.diagnostics_plugins").spec(), "folke/todo-comments.nvim")
  todo.config(todo, todo.opts)
  vim.cmd.runtime("plugin/todo.vim")
  local highlight = require("todo-comments.highlight")
  highlight.attach(vim.api.nvim_get_current_win(), true)
  highlight.highlight(buffer, 0, vim.api.nvim_buf_line_count(buffer))
  local lines = {}
  assert(vim.wait(5000, function()
    lines = {}
    for _, mark in ipairs(marks(buffer, "todo-comments")) do
      lines[mark[2]] = mark[4].hl_group
    end
    return lines[1] ~= nil and lines[2] ~= nil
  end, 50), "todo-comments did not highlight both keywords: " .. vim.inspect(lines))
  assert(tostring(lines[2]):find("WORKAROUND", 1, true),
    "Orbit's WORKAROUND keyword has no highlight: " .. vim.inspect(lines))
  print("PASS real todo-comments highlights TODO and Orbit's WORKAROUND")

  local ibl = find(require("orbit.modules.editor_plugins").spec(), "lukas-reineke/indent-blankline.nvim")
  ibl.config(ibl, ibl.opts)
  vim.api.nvim_win_set_cursor(0, { 6, 6 })
  require("ibl").refresh(buffer)
  local groups = {}
  for _, mark in ipairs(marks(buffer, "indent_blankline")) do
    for _, chunk in ipairs(mark[4].virt_text or {}) do
      local names = type(chunk[2]) == "table" and chunk[2] or { chunk[2] }
      for _, name in ipairs(names) do
        if chunk[1] == "│" then groups[name:match("^@ibl%.(%a+)%.char") or name] = name end
      end
    end
  end
  assert(groups.indent and groups.scope, "indent-blankline drew no indent and scope guides: "
    .. vim.inspect(groups))
  -- ibl copies the configured groups into its own @ibl.* groups.
  local function fg(name) return vim.api.nvim_get_hl(0, { name = name, link = false }).fg end
  assert(fg(groups.indent) == fg("IblChar") and fg("IblChar") == fg("Comment"),
    "indent guides do not use Orbit's IblChar")
  assert(fg(groups.scope) == fg("IblScopeChar") and fg("IblScopeChar") == fg("Statement"),
    "scope guides do not use Orbit's IblScopeChar")
  print("PASS real indent-blankline draws guides with Orbit highlights")
end, debug.traceback)

vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("Real editor integrations passed.")
