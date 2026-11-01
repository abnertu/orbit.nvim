-- Explicit pinned upstream acceptance. Hermetic validation never fetches plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local workspace = vim.fn.tempname() .. " live menu with spaces"
local dependencies = {
  { name = "lazy.nvim", source = "folke/lazy.nvim", revision = "306a05526ada86a7b30af95c5cc81ffba93fef97" },
  { name = "menu", source = "Orbit-Lua/menu", revision = "7a0a4a2896b715c066cfbe320bdc048091874cc6" },
  { name = "volt", source = "Orbit-Lua/volt", revision = "620de1321f275ec9d80028c68d1b88b409c0c8b1" },
  { name = "nvim-tree.lua", source = "nvim-tree/nvim-tree.lua", revision = "3be8cad084e79e84833ef98cef88116c26a224ff" },
}
---@type table<string, string>
local paths = {}
---@param argv string[]
---@return string
local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 60000 }):wait()
  assert(result.code == 0, vim.inspect(argv) .. ": " .. tostring(result.stderr))
  return result.stdout or ""
end

---@param kind 'normal'|'visual'|'no-corekeys'|'disabled'
local function check(kind)
  local base = vim.fs.joinpath(workspace, kind)
  local project = vim.fs.joinpath(base, "project with spaces")
  local first = vim.fs.joinpath(project, "first file.txt")
  local second = vim.fs.joinpath(project, "second file.txt")
  local site = vim.fs.joinpath(base, "site")
  local installed = vim.fs.joinpath(site, "pack/orbit/start/orbit.nvim")
  local config = vim.fs.joinpath(base, "config")
  local init = vim.fs.joinpath(config, "init.lua")
  local job, request = 0, 0
  local stderr = {}
  local observed_buffers, observed_windows = {}, {}
  ---@type Orbit.LiveMenuSnapshot?
  local initial
  -- Async RPC with atomic files keeps stalled input from hanging the test host.
  ---@param code string
  ---@return any
  local function exec(code)
    request = request + 1
    local response = vim.fs.joinpath(base, "response-" .. request .. ".json")
    vim.rpcnotify(job, "nvim_exec_lua", string.format([[
vim.schedule(function()
  local ok, value = xpcall(function() %s end, debug.traceback)
  local path = %q
  vim.fn.writefile({vim.json.encode({ok=ok,value=value})}, path .. '.tmp')
  assert(vim.uv.fs_rename(path .. '.tmp', path))
end)
]], code, response), {})
    assert(vim.wait(10000, function()
      return vim.fn.filereadable(response) == 1 or vim.fn.jobwait({ job }, 0)[1] ~= -1
    end, 10), "menu RPC timed out")
    assert(vim.fn.filereadable(response) == 1, "menu child exited before response")
    local result = vim.json.decode(table.concat(vim.fn.readfile(response), "\n"))
    assert(result.ok, result.value)
    return result.value
  end
  ---@return Orbit.LiveMenuSnapshot
  local function snapshot()
    local state = exec("return require('orbit.tests.live_menu').snapshot()")
    for _, menu in ipairs(state.menus) do
      observed_buffers[menu.buf], observed_windows[menu.win] = true, true
    end
    return state
  end
  ---@param s Orbit.LiveMenuSnapshot
  local function healthy(s) assert(#s.errors == 0 and s.errmsg == "", vim.inspect(s.errors) .. s.errmsg) end
  ---@param predicate fun(state: Orbit.LiveMenuSnapshot): boolean
  ---@param label string
  ---@return Orbit.LiveMenuSnapshot
  local function await(predicate, label)
    local s
    assert(vim.wait(5000, function()
      s = snapshot(); healthy(s)
      return predicate(s)
    end, 20), label .. ": " .. vim.inspect(s))
    return s
  end
  ---@param keys string
  local function input(keys)
    vim.rpcnotify(job, "nvim_input", vim.keycode(keys))
    exec("return true")
  end
  ---@param button 'left'|'right'
  ---@param row integer
  ---@param col integer
  ---@param modifier? string
  local function mouse(button, row, col, modifier)
    if not modifier then
      -- Keep separate actions outside native multi-click aggregation.
      local interval = exec("return vim.o.mousetime")
      vim.wait(interval + 50, function() return false end, 20)
    end
    vim.rpcnotify(job, "nvim_input_mouse", "move", "", "", 0, row, col)
    exec("return true")
    vim.rpcnotify(job, "nvim_input_mouse", button, "press", modifier or "", 0, row, col)
    exec("require('orbit.tests.live_menu').mark('after-press'); return true")
    vim.rpcnotify(job, "nvim_input_mouse", button, "release", modifier or "", 0, row, col)
    exec("require('orbit.tests.live_menu').mark('after-release'); return true")
  end
  ---@param row? integer
  ---@param col? integer
  ---@param modifier? string
  ---@return Orbit.LiveMenuSnapshot
  local function open(row, col, modifier)
    mouse("right", row or 1, col or 5, modifier)
    return await(function(s) return #s.menus == 1 end, "real right-click did not open menu")
  end
  ---@return Orbit.LiveMenuSnapshot
  local function closed()
    local s = await(function(value) return #value.menus == 0 and value.preserved end,
      "menu or temporary mappings survived close")
    exec("require('orbit.tests.live_menu').exercise_maps(); return true")
    for id in pairs(observed_buffers) do
      assert(exec(string.format("return not vim.api.nvim_buf_is_valid(%d)", id)), "orphan menu buffer")
    end
    for id in pairs(observed_windows) do
      assert(exec(string.format("return not vim.api.nvim_win_is_valid(%d)", id)), "orphan menu window")
    end
    if initial then
      for _, id in ipairs(initial.windows) do
        assert(exec(string.format("return vim.api.nvim_win_is_valid(%d)", id)), "unrelated window was closed")
      end
    end
    healthy(snapshot())
    return s
  end
  ---@param s Orbit.LiveMenuSnapshot
  ---@param text string
  ---@param index? integer
  local function click(s, text, index)
    local menu = assert(s.menus[index or #s.menus])
    for row, label in ipairs(menu.rows) do
      if label:find(text, 1, true) then
        local position = menu.positions[row]
        mouse("left", position.row - 1, position.col + 2)
        return
      end
    end
    error("missing rendered menu label " .. text .. ": " .. vim.inspect(menu.rows))
  end

  local ok, err = xpcall(function()
    vim.fn.mkdir(project, "p")
    vim.fn.mkdir(vim.fs.joinpath(config, "lua"), "p")
    for _, name in ipairs(vim.split(run({ "git", "-C", root, "ls-files", "-z" }), "\0", { trimempty = true })) do
      local target = vim.fs.joinpath(installed, name)
      vim.fn.mkdir(vim.fs.dirname(target), "p")
      assert(vim.uv.fs_copyfile(vim.fs.joinpath(root, name), target))
    end
    vim.fn.writefile({ "alpha source line", "second source line", "third source line", "fourth source line" }, first)
    vim.fn.writefile({ "tree target" }, second)
    local opts = { site = site, installed = installed, dependencies = paths,
      enabled = kind ~= "disabled", corekeys = kind ~= "no-corekeys" }
    vim.fn.writefile(vim.split(string.format("dofile(%q)(%s)",
      vim.fs.joinpath(root, "tests/support/live_menu.lua"), vim.inspect(opts)), "\n"), init)
    vim.fn.writefile({ "return require('orbit.tests.live_menu').import()" },
      vim.fs.joinpath(config, "lua/live_paths.lua"))
    job = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-i", "NONE", "-u", init, first }, {
      rpc = true, cwd = project, clear_env = true,
      env = {
        PATH = vim.env.PATH, SystemRoot = vim.env.SystemRoot, PATHEXT = vim.env.PATHEXT,
        COMSPEC = vim.env.COMSPEC, HOME = base, USERPROFILE = base,
        XDG_CONFIG_HOME = base, XDG_DATA_HOME = vim.fs.joinpath(base, "data"),
        XDG_STATE_HOME = vim.fs.joinpath(base, "state"), XDG_CACHE_HOME = vim.fs.joinpath(base, "cache"),
        LOCALAPPDATA = base, APPDATA = vim.fs.joinpath(base, "roaming"), NVIM_APPNAME = "config",
        NVIM_LOG_FILE = vim.fs.joinpath(base, "nvim.log"), TMPDIR = base, TEMP = base, TMP = base,
      }, on_stderr = function(_, lines) vim.list_extend(stderr, lines) end,
    })
    assert(job > 0)
    vim.rpcnotify(job, "nvim_ui_attach", 140, 45, { rgb = true })
    exec("assert(vim.v.vim_did_enter == 1); require('orbit.tests.live_menu').prepare(); return true")
    initial = snapshot()
    healthy(initial)
    assert(not initial.menu_loaded and not initial.runtime_loaded and not initial.tree_loaded,
      "optional owner imported before right-click demand")
    if kind == "disabled" then
      -- A disabled feature must leave the user right-click binding intact.
      exec("vim.keymap.set('n','<RightMouse>',function() end,{desc='disabled user'}); return true")
      mouse("right", 1, 5)
      local s = snapshot()
      assert(not s.menu_loaded and not s.runtime_loaded and #s.menus == 0 and s.preserved)
      return
    end

    if kind == "visual" then
      input("ggvjj")
      await(function(s) return s.mode == "v" end, "selection did not start")
      local s = open(1, 5)
      assert(s.mode == "v", "inside-selection right-click lost native Visual mode")
      input("<Esc>") -- Exactly one physical Escape, no test cleanup.
      s = closed()
      assert(s.mode == "n" and vim.deep_equal(s.lines, initial.lines))
      input("ggv")
      input("<Esc>") -- Outside a menu, the original user Visual map still runs.
      await(function(value) return value.mode == "n" end, "outside-menu Visual Escape changed")
      -- Outside-selection popup_setpos exits Visual mode; extend changes endpoints.
      input("ggv")
      s = open(3, 5)
      assert(s.mode == "n", "outside-selection popup_setpos retained Visual mode")
      input("<Esc>"); closed()
      exec("vim.o.mousemodel='extend'; return true")
      input("ggv")
      s = open(2, 5)
      assert(s.mode == "v" and s.cursor[1] == 3, "extend model did not adjust selection endpoint")
      input("<Esc>"); closed()
      assert(vim.deep_equal(snapshot().lines, initial.lines))
      return
    end

    local s = open()
    assert(s.loaded.menu == 1 and s.loaded.volt == 1 and not s.tree_loaded)
    assert(s.win == initial.win, "mouse menu stole source focus")
    exec("require('orbit.tests.live_menu').repeat_setup(); return true")
    local repeated = snapshot()
    assert(vim.deep_equal(repeated.menus, s.menus) and vim.deep_equal(repeated.windows, s.windows),
      "repeated setup disturbed the active menu")
    assert(repeated.loaded.menu == 1 and repeated.loaded.volt == 1)
    input("<Esc>")
    assert(closed().mode == "n")
    if kind == "no-corekeys" then return end

    -- Each additional click-count mapping must reach the real Lazy callback.
    for _, modifier in ipairs({ "2", "3", "4" }) do
      open(1, 5, modifier)
      input("<Esc>"); closed()
    end
    s = open()
    local old = s.menus[1].buf
    s = open(2, 6)
    assert(s.menus[1].buf ~= old, "replacement reused stale menu")
    assert(exec(string.format("return not vim.api.nvim_buf_is_valid(%d)", old)))
    mouse("left", 3, 4)
    closed()
    open()
    exec("require('orbit.tests.live_menu').replace_visual_escape(); return true")
    input("<Esc>")
    closed()

    -- The real configured save mapping must write the file exactly once, after UI disposal.
    exec([[
      local group = vim.api.nvim_create_augroup('OrbitLiveMenuSave',{})
      package.loaded['orbit.tests.live_menu'].writes=0
      vim.api.nvim_create_autocmd('BufWritePost',{group=group,callback=function()
        assert(#require('menu.state').bufids==0, 'save ran before menu disposal')
        local fixture=require('orbit.tests.live_menu'); fixture.writes=fixture.writes+1
      end})
      return true
    ]])
    input("ggA changed<Esc>")
    s = open()
    click(s, "Save File")
    closed()
    await(function() return exec("return require('orbit.tests.live_menu').writes") == 1 end, "menu save did not write")
    assert(vim.fn.readfile(first)[1] == "alpha source line changed")
    -- A nested general action runs once through the existing mapping owner.
    s = open()
    click(s, "Buffer")
    s = await(function(value) return #value.menus == 2 end, "nested menu did not render")
    click(s, "New Buffer")
    s = closed()
    assert(s.current ~= initial.current and s.lines[1] == "", "nested new-buffer action failed")
    exec(string.format("vim.api.nvim_set_current_buf(%d); return true", initial.current))

    -- Right-click a non-current split; native positioning and Save target that source.
    exec(string.format("vim.cmd.vsplit(%q); vim.api.nvim_set_current_win(%d); return true", second, initial.win))
    local target = exec(string.format([[
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if require('orbit.tests.live_menu').same_path(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), %q) then
          local pos=vim.fn.screenpos(win,1,1); return {win=win,row=pos.row-1,col=pos.col+3}
        end
      end
    ]], second))
    s = open(target.row, target.col)
    assert(s.win == target.win and s.current ~= initial.current, "menu ignored clicked source window")
    input("<Esc>"); closed()
    exec("require('orbit.tests.live_menu').repeat_setup(); return true")
    s = snapshot()
    assert(s.loaded.menu == 1 and s.loaded.volt == 1)

    -- Real mapped tree demand, real tree-specific menu, real node-open action.
    input("<C-n>")
    await(function(value) return value.tree_loaded end, "mapped tree demand failed")
    assert(exec([[
      local api=require('nvim-tree.api')
      for row,line in ipairs(vim.api.nvim_buf_get_lines(0,0,-1,false)) do
        if line:find('second file.txt',1,true) then vim.api.nvim_win_set_cursor(0,{row,0}); return true end
      end
      return false
    ]]), "tree target did not render")
    local treepos = exec("local p=vim.fn.screenpos(0,vim.api.nvim_win_get_cursor(0)[1],1); return {row=p.row-1,col=p.col+5}")
    s = open(treepos.row, treepos.col)
    click(s, "Open")
    closed()
    await(function() return exec(string.format(
      "return require('orbit.tests.live_menu').same_path(vim.api.nvim_buf_get_name(0), %q)", second)) end,
      "tree menu did not open clicked node")
    assert(vim.deep_equal(vim.fn.readfile(second), { "tree target" }))
  end, debug.traceback)

  if job > 0 then
    pcall(vim.rpcnotify, job, "nvim_command", "qa!")
    local exit = vim.fn.jobwait({ job }, 2000)[1]
    if exit == -1 then vim.fn.jobstop(job); vim.fn.jobwait({ job }, 2000) end
    if ok then assert(exit == 0, "menu child shutdown failed") end
  end
  assert(ok, "FAIL " .. kind .. "\n" .. tostring(err) .. "\n" .. table.concat(stderr, "\n"))
  print("PASS pinned real menu " .. kind)
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required for pinned menu acceptance")
  vim.fn.mkdir(workspace, "p")
  for _, dependency in ipairs(dependencies) do
    local path = vim.fs.joinpath(workspace, dependency.name)
    run({ "git", "init", "--quiet", path })
    run({ "git", "-C", path, "fetch", "--depth", "1", "https://github.com/" .. dependency.source .. ".git", dependency.revision })
    run({ "git", "-C", path, "checkout", "--quiet", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", path, "rev-parse", "HEAD" })) == dependency.revision)
    paths[dependency.name] = path
  end
  local cases = arg[1] and { arg[1] } or { "normal", "visual", "no-corekeys", "disabled" }
  for _, kind in ipairs(cases) do
    assert(vim.tbl_contains({ "normal", "visual", "no-corekeys", "disabled" }, kind), "unknown menu case")
    check(kind)
  end
end, debug.traceback)
local removed = vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
assert(removed == 0, "menu fixture cleanup failed")
print("Pinned real menu input cases passed.")
