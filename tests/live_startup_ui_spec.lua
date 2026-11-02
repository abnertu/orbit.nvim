-- Explicit network integration; hermetic startup coverage stays separate.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local workspace = vim.fn.tempname() .. " live startup with spaces"
local windows = vim.fn.has("win32") == 1
local dependencies = {
  { name = "lazy.nvim", source = "folke/lazy.nvim", revision = "306a05526ada86a7b30af95c5cc81ffba93fef97" },
  { name = "snacks.nvim", source = "folke/snacks.nvim", revision = "882c996cf28183f4d63640de0b4c02ec886d01f2" },
  { name = "nvim-tree.lua", source = "nvim-tree/nvim-tree.lua", revision = "3be8cad084e79e84833ef98cef88116c26a224ff" },
  { name = "oil.nvim", source = "stevearc/oil.nvim", revision = "d3733d933833a0e59b813ecec99341527adf0c28" },
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

---@param path string
---@return string
local function canonical(path)
  local value = vim.fs.normalize(vim.uv.fs_realpath(path) or path):gsub("/+$", "")
  return windows and value:lower() or value
end

---@param state Orbit.LiveStartupSnapshot
---@param name string
---@param path? string
---@return Orbit.LiveStartupEvent[]
local function events(state, name, path)
  return vim.tbl_filter(function(event)
    return event.event == name and (not path or canonical(event.name) == canonical(path))
  end, state.journal)
end

---@param state Orbit.LiveStartupSnapshot
---@param ft string
---@return Orbit.LiveStartupBuffer[]
local function buffers(state, ft)
  return vim.tbl_filter(function(buffer) return buffer.ft == ft end, state.buffers)
end

---@param state Orbit.LiveStartupSnapshot
---@param id integer
---@return Orbit.LiveStartupBuffer
local function buffer(state, id)
  for _, item in ipairs(state.buffers) do if item.id == id then return item end end
  error("missing buffer " .. id)
end

---@param state Orbit.LiveStartupSnapshot
local function healthy(state)
  assert(#state.errors == 0 and state.errmsg == "", vim.inspect(state.errors) .. state.errmsg)
end

---@param kind 'empty'|'existing'|'new'|'directory'|'no-dashboard'|'no-plugins'
local function check(kind)
  local base = vim.fs.joinpath(workspace, kind)
  local project = vim.fs.joinpath(base, "project with spaces")
  local first = vim.fs.joinpath(project, kind == "new" and "new file.lua" or "first file.lua")
  local second = vim.fs.joinpath(project, "second file.lua")
  local site = vim.fs.joinpath(base, "site")
  local installed = vim.fs.joinpath(site, "pack/orbit/start/orbit.nvim")
  local config = vim.fs.joinpath(base, "config")
  local init = vim.fs.joinpath(config, "init.lua")
  local plugins = kind ~= "no-plugins"
  local dashboard = kind ~= "no-dashboard"
  local job, request = 0, 0
  ---@type string[]
  local stderr = {}

  ---@param code string
  ---@return Orbit.LiveStartupSnapshot|boolean|string
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
    end, 10), "startup RPC timed out")
    assert(vim.fn.filereadable(response) == 1, "child exited before responding")
    local result = vim.json.decode(table.concat(vim.fn.readfile(response), "\n"))
    assert(result.ok, result.value)
    return result.value
  end

  ---@return Orbit.LiveStartupSnapshot
  local function snapshot()
    return exec("return require('orbit.tests.live_startup_ui').snapshot()") --[[@as Orbit.LiveStartupSnapshot]]
  end

  ---@param predicate fun(state: Orbit.LiveStartupSnapshot): boolean
  ---@param label string
  ---@return Orbit.LiveStartupSnapshot
  local function await(predicate, label)
    local state
    assert(vim.wait(10000, function()
      state = snapshot()
      healthy(state)
      return predicate(state)
    end, 20), label .. ": " .. vim.inspect(state))
    return state
  end

  local ok, err = xpcall(function()
    vim.fn.mkdir(project, "p")
    vim.fn.mkdir(vim.fs.joinpath(config, "lua"), "p")
    -- Copy working source, including uncommitted corrections. No Git hardlinks.
    for _, name in ipairs(vim.split(run({ "git", "-C", root, "ls-files", "-z" }), "\0", { trimempty = true })) do
      local target = vim.fs.joinpath(installed, name)
      vim.fn.mkdir(vim.fs.dirname(target), "p")
      assert(vim.uv.fs_copyfile(vim.fs.joinpath(root, name), target))
    end
    if kind ~= "new" then vim.fn.writefile({ "return 'first'" }, first) end
    vim.fn.writefile({ "return 'second'" }, second)
    local options = { site = site, installed = installed, dependencies = paths,
      plugins = plugins, dashboard = dashboard }
    vim.fn.writefile(vim.split(string.format("dofile(%q)(%s)",
      vim.fs.joinpath(root, "tests/support/live_startup_ui.lua"), vim.inspect(options)), "\n"), init)
    vim.fn.writefile({ "return require('orbit.tests.live_startup_ui').import()" },
      vim.fs.joinpath(config, "lua/live_paths.lua"))

    local argv = { vim.v.progpath, "--embed", "--headless", "-i", "NONE", "-V1" .. vim.fs.joinpath(base, "startup.log"), "-u", init }
    if kind == "existing" or kind == "new" then argv[#argv + 1] = first end
    if kind == "directory" then argv[#argv + 1] = project end
    job = vim.fn.jobstart(argv, {
      rpc = true, cwd = kind == "directory" and base or project, clear_env = true,
      env = {
        PATH = vim.env.PATH, SystemRoot = vim.env.SystemRoot, PATHEXT = vim.env.PATHEXT,
        COMSPEC = vim.env.COMSPEC, HOME = base, USERPROFILE = base,
        XDG_CONFIG_HOME = base,
        XDG_DATA_HOME = vim.fs.joinpath(base, "data"),
        XDG_STATE_HOME = vim.fs.joinpath(base, "state"),
        XDG_CACHE_HOME = vim.fs.joinpath(base, "cache"),
        LOCALAPPDATA = base, APPDATA = vim.fs.joinpath(base, "roaming"),
        NVIM_APPNAME = "config", NVIM_LOG_FILE = vim.fs.joinpath(base, "nvim.log"),
        TMPDIR = base, TEMP = base, TMP = base,
      },
      on_stderr = function(_, lines) vim.list_extend(stderr, lines) end,
    })
    assert(job > 0, "failed to spawn Neovim")
    vim.rpcnotify(job, "nvim_ui_attach", 100, 35, { rgb = true })
    exec("assert(vim.v.vim_did_enter == 1); return true")
    local initial = await(function(s)
      return #events(s, "VimEnter") == 1 and #events(s, "UIEnter") == 1
        and (not plugins or #events(s, "VeryLazy") == 1)
    end, "native startup did not settle")
    assert(initial.status == (plugins and "loaded" or "disabled"))
    assert(initial.lazy == plugins and initial.snacks == plugins and initial.imported == plugins)
    if plugins then
      for _, list in ipairs({ initial.manifest, initial.specs, initial.helper }) do
        assert(#list == 1 and canonical(list[1]):find(canonical(installed), 1, true),
          "Lazy dropped the installed Orbit runtime")
      end
      assert(initial.helper_loaded, "real Snacks callback could not load deferred Orbit helper")
      assert(not initial.tree, "tree loaded before mapped demand")
      assert(#buffers(initial, "oil") == 0 and #buffers(initial, "NvimTree") == 0,
        "startup opened an explorer before mapped demand")
    else
      assert(not initial.tree and not initial.oil, "disabled plugins imported explorers")
    end
    local posts = #events(initial, "FilePost")
    if kind == "empty" and plugins and dashboard then
      local dashboards = buffers(initial, "snacks_dashboard")
      assert(#dashboards == 1 and initial.current == dashboards[1].id,
        "empty startup did not display one real dashboard")
      assert(table.concat(dashboards[1].lines, ""):match("%S"), "dashboard did not render content")
    else
      assert(#buffers(initial, "snacks_dashboard") == 0, "unexpected startup dashboard")
    end
    if kind == "existing" or kind == "new" then
      local current = buffer(initial, initial.current)
      assert(canonical(current.name) == canonical(first), "startup replaced file argument")
      assert(vim.deep_equal(current.lines, kind == "new" and { "" } or { "return 'first'" }))
      assert(posts == 1 and events(initial, "FilePost")[1].ui, "file FilePost was missed or early")
      assert(canonical(events(initial, "FilePost")[1].name) == canonical(first))
      if kind == "existing" then
        assert(#events(initial, "BufReadPre", first) == 1, "earlier read observer was replayed")
        assert(#events(initial, "NewRead", first) == 1, "new read observer missed first demand")
      end
    elseif kind == "directory" then
      assert(canonical(initial.cwd) == canonical(project), "directory cwd was lost")
      for _, b in ipairs(initial.buffers) do
        assert(canonical(b.name) ~= canonical(project), "directory argument buffer survived")
      end
    else
      local unnamed = vim.tbl_filter(function(b) return b.listed and b.bt == "" and b.name == "" end, initial.buffers)
      assert(#unnamed == 1, "startup did not retain one normal unnamed buffer")
      assert(posts == 0, "empty startup consumed FilePost")
    end

    exec("require('orbit.tests.live_startup_ui').repeat_setup(); return true")
    local repeated = snapshot()
    assert(repeated.current == initial.current and repeated.window == initial.window)
    assert(vim.deep_equal(repeated.windows, initial.windows), "repeated setup replaced active windows")
    assert(vim.deep_equal(repeated.loaded, initial.loaded) and #events(repeated, "FilePost") == posts)
    if plugins then
      -- Drive the installed mapping through Neovim's real input path.
      vim.rpcnotify(job, "nvim_input", "-")
      local oil = await(function(s)
        return buffer(s, s.current).ft == "oil" and table.concat(buffer(s, s.current).lines, "\n"):find("second file.lua", 1, true) ~= nil
      end, "mapped Oil did not render the project")
      local floating = false
      for _, w in ipairs(oil.windows) do if w.id == oil.window then floating = w.floating end end
      assert(floating, "Oil did not open in a float")
      assert(canonical(exec("return require('oil').get_current_dir()")) == canonical(project))
      exec("require('oil').close(); return true")
      await(function(s) return s.window == initial.window and s.current == initial.current end,
        "Oil did not restore the prior window and buffer")
      if kind == "directory" then
        vim.rpcnotify(job, "nvim_input", "<C-n>")
        local tree = await(function(s)
          return #buffers(s, "NvimTree") == 1
            and table.concat(buffers(s, "NvimTree")[1].lines, "\n"):find("second file.lua", 1, true) ~= nil
        end, "mapped nvim-tree did not render project contents")
        assert(tree.tree and tree.loaded["nvim-tree.lua"] == 1)
        assert(canonical(exec("return require('nvim-tree.api').tree.get_nodes().absolute_path")) == canonical(project))
        vim.rpcnotify(job, "nvim_input", "<C-n>")
        await(function(s) return s.window == initial.window end, "tree did not close")
      end
    end
    exec(string.format("vim.cmd.edit(vim.fn.fnameescape(%q)); return true", second))
    local final = snapshot()
    healthy(final)
    assert(#events(final, "FilePost") == (posts == 0 and 1 or posts), "later file repeated FilePost")
    assert(#events(final, "BufReadPre", second) == 1)
    if plugins then
      assert(#events(final, "NewRead", second) == 1)
      for _, count in pairs(final.loaded) do assert(count == 1, "plugin activation repeated") end
    end
    assert(vim.deep_equal(vim.fn.readfile(second), { "return 'second'" }))
    if kind == "new" then
      assert(vim.fn.filereadable(first) == 0, "startup wrote new file")
    else
      assert(vim.deep_equal(vim.fn.readfile(first), { "return 'first'" }), "startup changed fixture contents")
    end
  end, debug.traceback)

  if job > 0 then
    pcall(vim.rpcnotify, job, "nvim_command", "qa!")
    local exit = vim.fn.jobwait({ job }, 2000)[1]
    if exit == -1 then vim.fn.jobstop(job); vim.fn.jobwait({ job }, 2000) end
    if ok then assert(exit == 0, "child shutdown failed") end
  end
  local log = vim.fs.joinpath(base, "startup.log")
  local details = not ok and vim.fn.filereadable(log) == 1 and table.concat(vim.fn.readfile(log), "\n") or ""
  assert(ok, "FAIL " .. kind .. "\n" .. tostring(err) .. "\n" .. table.concat(stderr, "\n") .. "\n" .. details)
  print("PASS real native startup " .. kind)
end

local ok, err = xpcall(function()
  assert(vim.fn.executable("git") == 1, "Git is required for pinned upstream integration")
  vim.fn.mkdir(workspace, "p")
  for _, dependency in ipairs(dependencies) do
    local path = vim.fs.joinpath(workspace, dependency.name)
    run({ "git", "init", "--quiet", path })
    run({ "git", "-C", path, "fetch", "--depth", "1", "https://github.com/" .. dependency.source .. ".git", dependency.revision })
    run({ "git", "-C", path, "checkout", "--quiet", "--detach", "FETCH_HEAD" })
    assert(vim.trim(run({ "git", "-C", path, "rev-parse", "HEAD" })) == dependency.revision)
    paths[dependency.name] = path
  end
  for _, kind in ipairs({ "empty", "existing", "new", "directory", "no-dashboard", "no-plugins" }) do check(kind) end
end, debug.traceback)
local removed = vim.fn.delete(workspace, "rf")
assert(ok, tostring(err))
assert(removed == 0, "live startup fixture cleanup failed")
print("6 pinned upstream native startup cases passed.")
