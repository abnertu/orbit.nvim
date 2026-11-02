-- Exercise DotnetManager's actual Comet windows without running a .NET command.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local workspace = vim.fn.tempname() .. " dotnet manager colors"
local pins = {
  { "dotnet-cli.nvim", "Orbit-Lua/dotnet-cli.nvim", "a74464a59be996b5db3e7f9480b937c9ff992471" },
  { "comet.nvim", "Orbit-Lua/comet.nvim", "b30afe9e5fcd5445804e584eb1cadf68c64873fe" },
}
local cwd = vim.fn.getcwd()
local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 60000 }):wait()
  assert(result.code == 0, tostring(result.stderr))
end
local ok, err = xpcall(function()
  for _, pin in ipairs(pins) do
    local path = vim.fs.joinpath(workspace, pin[1])
    vim.fn.mkdir(path, "p")
    run({ "git", "init", "--quiet", path })
    run({ "git", "-C", path, "fetch", "--depth", "1", "https://github.com/" .. pin[2] .. ".git", pin[3] })
    run({ "git", "-C", path, "checkout", "--quiet", "--detach", "FETCH_HEAD" })
    vim.opt.rtp:prepend(path)
  end
  vim.api.nvim_set_current_dir(workspace)
  require("orbit").setup({ modules = { theme = { colorscheme = "habamax" } } })
  require("orbit.modules.theme.runtime").start()
  local spec = require("orbit.modules.dotnet").spec()[1]
  if spec.config then spec.config(spec, spec.opts) else require("dotnet-cli").setup(spec.opts) end
  vim.cmd("DotnetManager")
  local state = require("comet.state")
  local manager = assert(state.get())
  for _, window in ipairs({ manager.input_win, manager.list_win, manager.output_win }) do
    local highlights = vim.wo[window].winhighlight
    assert(highlights:find("Normal:NormalFloat", 1, true)
      and highlights:find("FloatBorder:FloatBorder", 1, true),
      "DotnetManager inherited menu background/border groups: " .. highlights)
  end
  vim.cmd.colorscheme("desert")
  assert(vim.api.nvim_get_hl(0, { name = "FloatBorder" }).fg == require("orbit.modules.theme.runtime").palette().blue)
  require("comet.ui.window").close()
  require("comet").open({ { name = "Other consumer", action = function() end } }, {
    session_id = "other_consumer", insert_mode = false,
  })
  assert(vim.wo[state.get().input_win].winhighlight:find("Normal:ExBlack2Bg", 1, true),
    "Dotnet styling changed an unrelated Comet consumer")
  require("comet.ui.window").close()
end, debug.traceback)
pcall(function() require("comet.ui.window").close() end)
vim.api.nvim_set_current_dir(cwd)
vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
print("PASS real DotnetManager uses floating-window colors and preserves other Comet consumers")
