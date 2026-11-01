-- Explicit network integration; hermetic callback tests remain offline.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local workspace = vim.fn.tempname() .. " live completion with spaces"
local dependencies = {
  { "lazy.nvim", "folke/lazy.nvim", "306a05526ada86a7b30af95c5cc81ffba93fef97" },
  { "blink.cmp", "saghen/blink.cmp", "78336bc89ee5365633bcf754d93df01678b5c08f" },
  { "LuaSnip", "L3MON4D3/LuaSnip", "0abc8f390b278c3b4aabc4c004ac8a088b65cf24" },
  { "friendly-snippets", "rafamadriz/friendly-snippets", "b2ea5c41a150ba72fb656eedb4ed0a86d138d945" },
  { "nvim-autopairs", "windwp/nvim-autopairs", "3172f40c16563db871a58f20d205c710ad782311" },
  { "lazydev.nvim", "folke/lazydev.nvim", "ff2cbcba459b637ec3fd165a2be59b7bbaeedf0d" },
  { "wezterm-types", "justinsgithub/wezterm-types", "39511289aa040a7746a9e2d551b35ef330f15c77" },
}
---@type table<string, string>
local paths = {}

---@param state Orbit.LiveCompletionSnapshot
---@return boolean
local function menu_closed(state)
  if state.visible then return false end
  for _, window in ipairs(state.windows) do
    if window.ft == "blink-cmp-menu" then return false end
  end
  return true
end

---@param argv string[]
---@return string
local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 60000 }):wait()
  assert(result.code == 0, vim.inspect(argv) .. ": " .. tostring(result.stderr))
  return result.stdout or ""
end

---@param plugins boolean
local function check(plugins)
  local kind = plugins and "completion" or "native"
  local base = vim.fs.joinpath(workspace, kind)
  local site = vim.fs.joinpath(base, "site")
  local installed = vim.fs.joinpath(site, "pack/orbit/start/orbit.nvim")
  local config = vim.fs.joinpath(base, "config")
  local init = vim.fs.joinpath(config, "init.lua")
  local job, request = 0, 0
  ---@type string[]
  local stderr = {}

  ---@param code string
  ---@return Orbit.LiveCompletionSnapshot|boolean
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
    end, 10), "completion RPC timed out")
    assert(vim.fn.filereadable(response) == 1, "child exited before responding")
    local result = vim.json.decode(table.concat(vim.fn.readfile(response), "\n"))
    assert(result.ok, result.value)
    return result.value
  end

  ---@return Orbit.LiveCompletionSnapshot
  local function snapshot()
    return exec("return require('orbit.tests.live_completion_escape').snapshot()") --[[@as Orbit.LiveCompletionSnapshot]]
  end

  ---@param predicate fun(state: Orbit.LiveCompletionSnapshot): boolean
  ---@param label string
  ---@return Orbit.LiveCompletionSnapshot
  local function await(predicate, label)
    local state
    assert(vim.wait(10000, function()
      state = snapshot()
      -- Pinned LuaSnip uses :silent! foldopen!, which sets v:errmsg without
      -- reporting an error when the placeholder is outside a fold.
      assert(#state.errors == 0 and (state.errmsg == "" or state.errmsg == "E490: No fold found"),
        vim.inspect(state.errors) .. state.errmsg)
      return predicate(state)
    end, 20), label .. ": " .. vim.inspect(state))
    return state
  end

  ---@param keys string
  local function input(keys) vim.rpcnotify(job, "nvim_input", keys) end

  local ok, err = xpcall(function()
    vim.fn.mkdir(vim.fs.joinpath(config, "lua"), "p")
    for _, name in ipairs(vim.split(run({ "git", "-C", root, "ls-files", "-z" }), "\0", { trimempty = true })) do
      local target = vim.fs.joinpath(installed, name)
      vim.fn.mkdir(vim.fs.dirname(target), "p")
      assert(vim.uv.fs_copyfile(vim.fs.joinpath(root, name), target))
    end
    local options = { site = site, installed = installed, dependencies = paths, plugins = plugins }
    vim.fn.writefile(vim.split(string.format("dofile(%q)(%s)",
      vim.fs.joinpath(root, "tests/support/live_completion_escape.lua"), vim.inspect(options)), "\n"), init)
    vim.fn.writefile({ "return require('orbit.tests.live_completion_escape').import()" },
      vim.fs.joinpath(config, "lua/live_completion_paths.lua"))
    job = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-i", "NONE", "-u", init }, {
      rpc = true, cwd = base, clear_env = true,
      env = {
        PATH = vim.env.PATH, SystemRoot = vim.env.SystemRoot, PATHEXT = vim.env.PATHEXT,
        COMSPEC = vim.env.COMSPEC, HOME = base, USERPROFILE = base,
        XDG_CONFIG_HOME = base, XDG_DATA_HOME = vim.fs.joinpath(base, "data"),
        XDG_STATE_HOME = vim.fs.joinpath(base, "state"), XDG_CACHE_HOME = vim.fs.joinpath(base, "cache"),
        LOCALAPPDATA = base, APPDATA = vim.fs.joinpath(base, "roaming"), NVIM_APPNAME = "config",
        NVIM_LOG_FILE = vim.fs.joinpath(base, "nvim.log"), TMPDIR = base, TEMP = base, TMP = base,
      },
      on_stderr = function(_, lines) vim.list_extend(stderr, lines) end,
    })
    assert(job > 0, "failed to spawn Neovim")
    vim.rpcnotify(job, "nvim_ui_attach", 100, 35, { rgb = true })
    exec("assert(vim.v.vim_did_enter == 1); return true")
    local initial = snapshot()
    assert(not initial.blink and not initial.luasnip, "completion loaded before InsertEnter")
    input("<Esc>")
    local ordinary = await(function(s) return s.mode == "n" end, "ordinary Escape")
    assert(not ordinary.blink and not ordinary.luasnip, "ordinary Escape imported completion")

    if plugins then
      input("i")
      local active = await(function(s) return s.mode == "i" and s.blink and s.luasnip end, "InsertEnter demand")
      assert(active.loaded["blink.cmp"] == 1 and active.loaded.LuaSnip == 1 and active.cleanup == 1)
      input("<Esc>")
      await(function(s) return s.mode == "n" end, "initial InsertLeave")

      local function completion_cycle()
        exec("vim.api.nvim_buf_set_lines(0,0,-1,false,{'orbitCandidateUnique',''}); vim.api.nvim_win_set_cursor(0,{2,0}); return true")
        local before = #snapshot().accepts
        input("iorbitCan")
        local menu = await(function(s)
          if not s.visible or s.selected ~= "orbitCandidateUnique" then return false end
          for _, window in ipairs(s.windows) do
            if window.ft == "blink-cmp-menu" and table.concat(window.lines, "\n"):find("orbitCandidateUnique", 1, true) then return true end
          end
          return false
        end, "real Blink candidate window")
        assert(menu.mode == "i")
        input("<C-e>")
        await(function(s) return menu_closed(s) and s.mode == "i" end, "mapped completion hide")
        input("<C-e>")
        await(function(s) return s.visible and s.selected == "orbitCandidateUnique" end, "mapped completion reopen")
        input("<C-y>")
        local accepted = await(function(s) return #s.accepts == before + 1 and menu_closed(s) end, "mapped acceptance event")
        assert(accepted.accepts[#accepted.accepts] == "orbitCandidateUnique" and accepted.lines[2] == "orbitCandidateUnique")
        input("<Esc>")
        await(function(s) return s.mode == "n" end, "accepted completion Escape")
      end
      completion_cycle()

      -- Keep the popup visible while checking Escape, independently of acceptance.
      exec("vim.api.nvim_buf_set_lines(0,0,-1,false,{'orbitCandidateUnique',''}); vim.api.nvim_win_set_cursor(0,{2,0}); return true")
      input("iorbitCan")
      await(function(s) return s.visible end, "popup before Escape")
      exec("vim.o.hlsearch=true; vim.fn.setreg('/', 'orbitCandidateUnique'); vim.v.hlsearch=1; return true")
      assert(snapshot().hlsearch == 1)
      input("<Esc>")
      await(function(s) return s.mode == "n" and menu_closed(s) and s.hlsearch == 0 end, "Escape closes completion and search")

      ---@param exit string
      ---@param early boolean
      ---@param select_mode boolean
      local function snippet_cycle(exit, early, select_mode)
        exec("vim.api.nvim_buf_set_lines(0,0,-1,false,{''}); vim.api.nvim_win_set_cursor(0,{1,0}); return true")
        input("i")
        await(function(s) return s.mode == "i" end, "insert before snippet")
        exec("local ls=require('luasnip'); ls.snip_expand(ls.parser.parse_snippet('orbit_test','${1:first} ${2:second}$0')); return true")
        await(function(s) return s.mode:sub(1,1) == "s" and s.snippet and s.node == 1 end, "real first placeholder")
        input("<Tab>")
        await(function(s) return s.mode:sub(1,1) == "s" and s.snippet and s.node == 2 end, "mapped snippet Tab")
        if not select_mode then
          input("changed")
          await(function(s) return s.mode == "i" and s.snippet end, "edit real placeholder")
        end
        local before = snapshot()
        input(exit)
        local stopped = await(function(s) return s.mode == "n" and not s.snippet and menu_closed(s) end, "snippet session cleanup")
        assert(vim.deep_equal(stopped.lines, before.lines), "cleanup changed snippet text")
        if not select_mode then
          assert(#stopped.leaves == #before.leaves + 1, "missing independent InsertLeave observation")
          assert(stopped.leaves[#stopped.leaves] == not early, "Escape and InsertLeave cleanup masked one another")
        end
      end
      snippet_cycle("<Esc>", true, true)
      snippet_cycle("<Esc>", true, false)
      snippet_cycle("<C-\\><C-n>", false, false)

      local before = snapshot()
      exec("require('orbit.tests.live_completion_escape').repeat_setup(); return true")
      local repeated = snapshot()
      assert(repeated.cleanup == 1 and vim.deep_equal(before.loaded, repeated.loaded), "repeated completion setup")
      snippet_cycle("<Esc>", true, false)
      completion_cycle()
      for _, count in pairs(snapshot().loaded) do assert(count == 1, "plugin activation repeated") end
      print("PASS real Blink input, LuaSnip navigation, independent cleanup, and repeated setup")
    else
      input("i")
      await(function(s) return s.mode == "i" end, "native insert")
      exec("vim.snippet.expand('${1:native} ${2:placeholder}$0'); return true")
      await(function(s) return s.native and s.mode:sub(1,1) == "s" end, "native snippet expansion")
      local before = snapshot()
      input("<Esc>")
      local stopped = await(function(s) return s.mode == "n" and not s.native end, "native snippet Escape")
      assert(not stopped.blink and not stopped.luasnip and vim.deep_equal(stopped.lines, before.lines))
      print("PASS native snippet Escape without external completion imports")
    end
  end, debug.traceback)
  if job > 0 then
    pcall(vim.rpcnotify, job, "nvim_command", "qa!")
    local exit = vim.fn.jobwait({ job }, 2000)[1]
    if exit == -1 then vim.fn.jobstop(job); vim.fn.jobwait({ job }, 2000) end
    if ok then assert(exit == 0, "child shutdown failed") end
  end
  assert(ok, "FAIL " .. kind .. "\n" .. tostring(err) .. "\n" .. table.concat(stderr, "\n"))
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required for pinned upstream integration")
  vim.fn.mkdir(workspace, "p")
  for _, dependency in ipairs(dependencies) do
    local path = vim.fs.joinpath(workspace, dependency[1])
    run({ "git", "init", "--quiet", path })
    run({ "git", "-C", path, "fetch", "--depth", "1", "https://github.com/" .. dependency[2] .. ".git", dependency[3] })
    run({ "git", "-C", path, "checkout", "--quiet", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", path, "rev-parse", "HEAD" })) == dependency[3])
    paths[dependency[1]] = path
  end
  check(true)
  check(false)
end, debug.traceback)
local removed = vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
assert(removed == 0, "live completion fixture cleanup failed")
print("2 pinned upstream completion/Escape cases passed.")
