-- Exercise the actual Hangar + NUI floating interface on Linux and Windows.
-- A real upstream UI is rendered; the Neovim buffer/window APIs remain native.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local dependencies = {
  {
    name = "hangar.nvim",
    url = "https://github.com/Orbit-Lua/hangar.nvim.git",
    sha = "fb79cc024aba1a20661064245541a821d0516ead",
  },
  {
    name = "nui.nvim",
    url = "https://github.com/MunifTanjim/nui.nvim.git",
    sha = "10fc361835c856ba4233ef5ea135b919bf3dce97",
  },
}
local base = vim.fn.tempname() .. " orbit live Hangar UI with spaces"
local original_columns, original_lines = vim.o.columns, vim.o.lines
local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) .. ": "
    .. tostring(result.stderr or result.stdout or result.code))
  return result.stdout or ""
end

local function hangar_body()
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer)
      and vim.api.nvim_get_option_value("filetype", { buf = buffer }) == "Hangar"
      and vim.fn.bufwinid(buffer) ~= -1
    then
      return buffer, vim.fn.bufwinid(buffer)
    end
  end
end

local function lines(buffer)
  return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
end

local function key(buffer, value)
  local mapping = vim.api.nvim_buf_call(buffer, function()
    return vim.fn.maparg(value, "n", false, true)
  end)
  assert(type(mapping.callback) == "function",
    "real NUI Hangar key is unbound: " .. value)
  mapping.callback()
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1)
  assert(vim.fn.mkdir(base, "p") == 1)
  for _, dependency in ipairs(dependencies) do
    local dir = vim.fs.joinpath(base, dependency.name)
    assert(vim.fn.mkdir(dir, "p") == 1)
    run({ "git", "init", dir })
    run({ "git", "-C", dir, "fetch", "--depth", "1",
      dependency.url, dependency.sha })
    run({ "git", "-C", dir, "checkout", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", dir, "rev-parse", "HEAD" }))
      == dependency.sha, "upstream UI dependency revision mismatch")
    vim.opt.rtp:prepend(dir)
  end

  vim.o.columns = 165
  vim.o.lines = 52
  local source = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(source)
  vim.api.nvim_buf_set_name(source, vim.fn.tempname() .. ".lua")
  vim.api.nvim_set_option_value("filetype", "lua", { buf = source })
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { "local answer = 42" })

  local state_path = vim.fs.joinpath(base, "state", "tools.json")
  local orbit = require("orbit")
  orbit.setup({ modules = { hangar = { state_file = state_path } } })
  assert(package.loaded.hangar == nil and package.loaded["nui.popup"] == nil,
    "root setup must not eagerly import upstream UI")
  require("orbit.modules.hangar").spec()[2].config()
  assert(package.loaded.hangar ~= nil)
  assert(package.loaded["nui.popup"] == nil,
    "Hangar state setup must not open or import its NUI view")
  print("PASS real Hangar and NUI stay lazy until opening their UI")

  vim.cmd("Hangar")
  local buffer, win = hangar_body()
  assert(buffer and win and vim.api.nvim_win_is_valid(win),
    "real :Hangar did not mount its NUI floating window")
  assert(vim.api.nvim_get_current_win() == win,
    "real Hangar did not focus its body window")
  assert(lines(buffer):find("lua_ls", 1, true),
    "Hangar did not render Lua language server state: "
    .. lines(buffer):sub(1, 1300))
  local view_group = "HangarView" .. buffer
  assert(#vim.api.nvim_get_autocmds({ group = view_group }) > 0)
  assert(vim.fn.filereadable(state_path) == 0,
    "opening Hangar's read-only view unexpectedly wrote persistent state")
  print("PASS real :Hangar renders language tools and installs UI observers")

  vim.cmd("Hangar")
  local again_buf, again_win = hangar_body()
  assert(again_buf == buffer and again_win == win,
    "reopening Hangar must focus, not duplicate its floating view")
  key(buffer, "<Tab>")
  assert(lines(buffer):find("python", 1, true),
    "NUI category switch did not render Python debug adapter")
  key(buffer, "<S-Tab>")
  assert(lines(buffer):find("lua_ls", 1, true),
    "reverse NUI category switch did not return to Lua LSP")
  print("PASS real Hangar view reuse and bidirectional category mappings")

  key(buffer, "q")
  assert(not vim.api.nvim_win_is_valid(win),
    "real Hangar close mapping left a floating body window")
  local group_left = pcall(vim.api.nvim_get_autocmds, { group = view_group })
  assert(not group_left, "real Hangar close leaked its view autocmd group")
  require("hangar").close()
  assert(vim.fn.filereadable(state_path) == 0,
    "opening and closing the UI must not persist implicit tool choices")
  print("PASS real Hangar close removes windows and owned observers")

  vim.cmd("Hangar")
  local reopened, second = hangar_body()
  assert(reopened and second and vim.api.nvim_win_is_valid(second))
  require("hangar").close()
  assert(not vim.api.nvim_win_is_valid(second))
  print("PASS real Hangar view can be reopened safely after cleanup")
end, debug.traceback)

vim.o.columns, vim.o.lines = original_columns, original_lines
vim.fn.delete(base, "rf")
assert(ok, tostring(err))
print("Pinned real Hangar/NUI lifecycle integration passed.")
