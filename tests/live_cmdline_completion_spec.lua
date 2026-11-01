-- Explicit network integration; hermetic owner tests remain offline.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local workspace = vim.fn.tempname() .. " live cmdline with spaces"
local dependencies = {
  { "lazy.nvim", "folke/lazy.nvim", "306a05526ada86a7b30af95c5cc81ffba93fef97" },
  { "blink.cmp", "saghen/blink.cmp", "78336bc89ee5365633bcf754d93df01678b5c08f" },
  { "LuaSnip", "L3MON4D3/LuaSnip", "0abc8f390b278c3b4aabc4c004ac8a088b65cf24" },
  { "friendly-snippets", "rafamadriz/friendly-snippets", "b2ea5c41a150ba72fb656eedb4ed0a86d138d945" },
  { "nvim-autopairs", "windwp/nvim-autopairs", "3172f40c16563db871a58f20d205c710ad782311" },
  { "lazydev.nvim", "folke/lazydev.nvim", "ff2cbcba459b637ec3fd165a2be59b7bbaeedf0d" },
  { "wezterm-types", "justinsgithub/wezterm-types", "39511289aa040a7746a9e2d551b35ef330f15c77" },
  { "noice.nvim", "folke/noice.nvim", "7bfd942445fb63089b59f97ca487d605e715f155" },
  { "nui.nvim", "MunifTanjim/nui.nvim", "10fc361835c856ba4233ef5ea135b919bf3dce97" },
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

---@param state Orbit.LiveCmdlineSnapshot
---@param ft string
---@param text? string
---@return integer?
local function window_with(state, ft, text)
  for _, window in ipairs(state.windows) do
    if window.ft == ft and window.floating
      and (not text or table.concat(window.lines, "\n"):find(text, 1, true))
    then return window.id end
  end
end

---@param state Orbit.LiveCmdlineSnapshot
---@return boolean
local function closed(state)
  return state.mode == "n" and not state.visible
    and not window_with(state, "blink-cmp-menu") and not window_with(state, "noice")
end

---@param completion boolean
---@param messages boolean
local function check(completion, messages)
  local kind = completion and (messages and "combined" or "blink-only") or "noice-only"
  local base = vim.fs.joinpath(workspace, kind)
  local site = vim.fs.joinpath(base, "site")
  local installed = vim.fs.joinpath(site, "pack/orbit/start/orbit.nvim")
  local config = vim.fs.joinpath(base, "config")
  local init = vim.fs.joinpath(config, "init.lua")
  local job, request = 0, 0
  ---@type string[]
  local stderr = {}

  ---@param code string
  ---@return Orbit.LiveCmdlineSnapshot|boolean
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
    end, 10), "commandline RPC timed out")
    assert(vim.fn.filereadable(response) == 1, "child exited before responding")
    local result = vim.json.decode(table.concat(vim.fn.readfile(response), "\n"))
    assert(result.ok, result.value)
    return result.value
  end

  ---@return Orbit.LiveCmdlineSnapshot
  local function snapshot()
    return exec("return require('orbit.tests.live_cmdline_completion').snapshot()") --[[@as Orbit.LiveCmdlineSnapshot]]
  end

  ---@param predicate fun(state: Orbit.LiveCmdlineSnapshot): boolean
  ---@param label string
  ---@return Orbit.LiveCmdlineSnapshot
  local function await(predicate, label)
    local state
    assert(vim.wait(10000, function()
      state = snapshot()
      assert(#state.errors == 0 and state.errmsg == "", vim.inspect(state.errors) .. state.errmsg)
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
    local options = { site = site, installed = installed, dependencies = paths,
      completion = completion, messages = messages }
    vim.fn.writefile(vim.split(string.format("dofile(%q)(%s)",
      vim.fs.joinpath(root, "tests/support/live_cmdline_completion.lua"), vim.inspect(options)), "\n"), init)
    vim.fn.writefile({ "return require('orbit.tests.live_cmdline_completion').import()" },
      vim.fs.joinpath(config, "lua/live_cmdline_paths.lua"))
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
    local initial = await(function(s) return not messages or s.noice_running end, "native VeryLazy Noice activation")
    assert(not initial.blink, "Blink loaded before CmdlineEnter")
    assert(initial.noice == messages, "disabled messages owner imported Noice")
    assert(vim.tbl_contains(initial.events, "UIEnter"))
    if messages then
      assert(vim.tbl_contains(initial.events, "VeryLazy") and initial.loaded["noice.nvim"] == 1)
      local very_lazy, noice_load
      for index, event in ipairs(initial.events) do
        if event == "VeryLazy" then very_lazy = index end
        if event == "LazyLoad:noice.nvim" then noice_load = index end
      end
      assert(very_lazy and noice_load and very_lazy < noice_load, "Noice did not load on VeryLazy")
    end

    ---@param s Orbit.LiveCmdlineSnapshot
    local function owner_state(s)
      assert(s.blink == completion, "disabled completion owner imported Blink")
      assert(s.noice == messages, "disabled messages owner imported Noice")
      for _, event in ipairs(s.events) do assert(event ~= "InsertEnter", "commandline was not first demand") end
    end

    ---@param text string
    ---@return Orbit.LiveCmdlineSnapshot
    local function enter(text)
      input(":")
      await(function(s) return s.mode == "c" and s.command_type == ":" and (not completion or s.blink) end,
        "CmdlineEnter demand before typing command")
      input(text)
      local state = await(function(s)
        return s.mode == "c" and s.command_type == ":" and s.command == text
          and (not messages or window_with(s, "noice", text) ~= nil)
          and (not completion or s.blink)
      end, "native colon input and commandline popup")
      owner_state(state)
      return state
    end

    ---@param before Orbit.LiveCmdlineSnapshot
    local function cancel(before)
      input("<Esc>")
      local state = await(closed, "commandline cancellation closes popups")
      assert(vim.deep_equal(state.executed, before.executed), "cancel executed a command")
      assert(state.current_window == initial.editor and state.editor_buffer == initial.editor_buffer)
      assert(vim.deep_equal(state.lines, initial.lines) and vim.deep_equal(state.cursor, initial.cursor))
      for _, window in ipairs(before.windows) do
        if window.ft == "noice" or window.ft == "blink-cmp-menu" then
          exec(string.format("assert(not vim.api.nvim_win_is_valid(%d)); return true", window.id))
        end
      end
      owner_state(state)
    end

    local function completion_cycle()
      local before = snapshot()
      enter("OrbitCmdline")
      local menu = await(function(s)
        return s.visible and #s.items >= 3 and s.selected == ""
          and window_with(s, "blink-cmp-menu", "OrbitCmdlineAlpha") ~= nil
      end, "real command candidates with no preselection")
      assert(menu.command == "OrbitCmdline" and #menu.executed == #before.executed)
      input("<C-j>")
      await(function(s) return s.selected_index == 1 and s.selected == menu.items[1] end, "mapped command select next")
      input("<C-j>")
      await(function(s) return s.selected_index == 2 and s.selected == menu.items[2] end, "mapped command select second")
      input("<C-k>")
      await(function(s) return s.selected_index == 1 and s.selected == menu.items[1] end, "mapped command select previous")
      input("<C-y>")
      local accepted = await(function(s)
        return #s.accepts == #before.accepts + 1 and not s.visible and not window_with(s, "blink-cmp-menu")
      end, "mapped command acceptance event")
      assert(accepted.accepts[#accepted.accepts] == menu.items[1] and accepted.command == menu.items[1])
      assert(#accepted.executed == #before.executed and accepted.mode == "c", "accept executed prematurely")
      input("<CR>")
      local executed = await(function(s) return closed(s) and #s.executed == #before.executed + 1 end,
        "accepted command executes once")
      assert(executed.executed[#executed.executed] == menu.items[1])
      owner_state(executed)
    end

    if completion then
      completion_cycle()
      local active = snapshot()
      assert(active.loaded["blink.cmp"] == 1 and active.loaded.LuaSnip == 1
        and active.loaded["nvim-autopairs"] == 1 and active.loaded["lazydev.nvim"] == 1)
      local first_enter, blink_load
      for index, event in ipairs(active.events) do
        if event == "CmdlineEnter" and not first_enter then first_enter = index end
        if event == "LazyLoad:blink.cmp" then blink_load = index end
      end
      assert(first_enter and blink_load and first_enter < blink_load, "Blink did not load on CmdlineEnter")
      enter("OrbitCmdline")
      cancel(await(function(s) return s.visible end, "visible candidates before cancellation"))

      for _, direction in ipairs({ "/", "?" }) do
        local query = direction == "/" and "orbitSearchUniqueFor" or "orbitSearchUniqueBack"
        local candidate = direction == "/" and "orbitSearchUniqueForward" or "orbitSearchUniqueBackward"
        -- Prove candidates exist independently; an empty provider cannot pass suppression.
        input(direction .. query)
        await(function(s) return s.command_type == direction and s.command == query end, "search positive-control input")
        input("<C-space>")
        cancel(await(function(s) return s.visible and window_with(s, "blink-cmp-menu", candidate) ~= nil end,
          "manual search completion positive control"))
        input(direction .. query)
        await(function(s) return s.command_type == direction and s.command == query end, "search suppression input")
        local start = vim.uv.hrtime()
        repeat
          local state = snapshot()
          assert(not state.visible and not window_with(state, "blink-cmp-menu"), "search menu opened automatically")
          assert(#state.errors == 0 and state.errmsg == "", vim.inspect(state.errors) .. state.errmsg)
          vim.wait(20)
        until (vim.uv.hrtime() - start) / 1e6 >= 500
        cancel(snapshot())
        input(direction .. query)
        await(function(s) return s.command_type == direction and s.command == query end, "native search input")
        input("<CR>")
        local found = await(closed, "native search executes without completion acceptance")
        assert(found.cursor[1] == (direction == "/" and 3 or 1) and found.cursor[2] == 0,
          "native search did not reach its matching word")
        assert(vim.deep_equal(found.lines, initial.lines))
        exec("vim.api.nvim_win_set_cursor(0,{2,0}); return true")
      end
      local before = snapshot()
      exec("require('orbit.tests.live_cmdline_completion').repeat_setup(); return true")
      assert(vim.deep_equal(snapshot().loaded, before.loaded), "setup reactivated commandline plugins")
      completion_cycle()
    else
      enter("OrbitCmdlineAlpha")
      input("<CR>")
      local executed = await(function(s) return closed(s) and #s.executed == 1 end, "native command executes without Blink")
      assert(executed.executed[1] == "OrbitCmdlineAlpha")
      cancel(enter("OrbitCmdlineBeta"))
      local before = snapshot()
      exec("require('orbit.tests.live_cmdline_completion').repeat_setup(); return true")
      assert(vim.deep_equal(snapshot().loaded, before.loaded))
      cancel(enter("OrbitCmdlineGamma"))
    end
    local final = snapshot()
    owner_state(final)
    assert(closed(final) and #final.errors == 0 and final.errmsg == "")
    assert(#final.accepts == (completion and 2 or 0) and #final.executed == (completion and 2 or 1),
      "command acceptance or execution counts changed")
    for _, count in pairs(final.loaded) do assert(count == 1, "plugin activation repeated") end
    print("PASS " .. kind .. " commandline input, acceptance, cancellation, search, and ownership")
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
  check(true, true)
  check(true, false)
  check(false, true)
end, debug.traceback)
local removed = vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
assert(removed == 0, "live commandline fixture cleanup failed")
print("3 pinned upstream commandline cases passed.")
