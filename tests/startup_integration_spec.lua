-- Real embedded UI startup with isolated storage and no external plugins.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local windows = vim.fn.has("win32") == 1
local passed = 0

---@param directory string
local function lazy_fixture(directory)
  assert(vim.fn.executable("git") == 1, "Git is required for the local Lazy fixture")
  vim.fn.mkdir(vim.fs.joinpath(directory, "lua", "lazy"), "p")
  vim.fn.writefile({ "return { setup = function()",
    "  require('orbit.tests.startup').lazy_setup()", "end }" },
    vim.fs.joinpath(directory, "lua", "lazy", "init.lua"))
  for _, args in ipairs({
    {"init", "--quiet", directory},
    {"-C", directory, "add", "."},
    {"-C", directory, "-c", "user.name=orbit.nvim", "-c", "user.email=tests@example.invalid",
      "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "local startup fixture"},
  }) do
    local result = vim.system(vim.list_extend({"git"}, args), {
      text = true, timeout = 10000,
      env = {GIT_CONFIG_NOSYSTEM = "1", GIT_CONFIG_GLOBAL = vim.fs.joinpath(directory, "no-global-config")},
    }):wait()
    assert(result.code == 0, "local Git fixture failed: " .. tostring(result.stderr))
  end
end

---@param path string
---@return string
local function canonical(path)
  local value = vim.fs.normalize(vim.uv.fs_realpath(path) or path)
  return windows and value:lower() or value
end

---@param snapshot Orbit.StartupTestSnapshot
---@param event string
---@param path? string
---@return Orbit.StartupTestEvent[]
local function events(snapshot, event, path)
  return vim.tbl_filter(function(item)
    return item.event == event and (not path or canonical(item.name) == canonical(path))
  end, snapshot.journal)
end

---@param kind 'empty'|'interface'|'existing'|'new'|'directory'
---@param plugins boolean
local function check(kind, plugins)
  local base = vim.fn.tempname() .. " orbit startup with spaces"
  local project = vim.fs.joinpath(base, "project with spaces")
  local first = vim.fs.joinpath(project, kind == "new" and "new file.lua" or "first file.lua")
  local second = vim.fs.joinpath(project, "second file.lua")
  local lazy = vim.fs.joinpath(base, "local lazy")
  local init = vim.fs.joinpath(base, "init.lua")
  ---@type string[]
  local stderr = {}
  local job, request = 0, 0

  ---@param code string
  ---@return Orbit.StartupTestSnapshot|boolean
  local function exec(code)
    request = request + 1
    local response = vim.fs.joinpath(base, "response-" .. request .. ".json")
    local wrapped = string.format([[
vim.schedule(function()
local ok, value = xpcall(function()
%s
end, debug.traceback)
local path = %q
vim.fn.writefile({vim.json.encode({ok=ok, value=value})}, path .. '.tmp')
assert(vim.uv.fs_rename(path .. '.tmp', path))
end)
]], code, response)
    vim.rpcnotify(job, "nvim_exec_lua", wrapped, {})
    assert(vim.wait(10000, function()
      return vim.fn.filereadable(response) == 1 or vim.fn.jobwait({job}, 0)[1] ~= -1
    end, 10), "startup RPC timed out")
    assert(vim.fn.filereadable(response) == 1, "child exited before responding")
    local result = vim.json.decode(table.concat(vim.fn.readfile(response), "\n"))
    assert(result.ok, result.value)
    return result.value
  end

  ---@return Orbit.StartupTestSnapshot
  local function snapshot()
    return exec("return require('orbit.tests.startup').snapshot()")
  end

  local ok, err = xpcall(function()
    assert(vim.fn.mkdir(project, "p") == 1)
    vim.fn.writefile({ "root = true", "", "[*.lua]", "indent_style = space",
      "indent_size = 6", "tab_width = 6" }, vim.fs.joinpath(project, ".editorconfig"))
    if kind ~= "new" then vim.fn.writefile({ "return 'first'" }, first) end
    vim.fn.writefile({ "return 'second'" }, second)
    if plugins then lazy_fixture(lazy) end
    local options = {
      root = root, lazy = lazy, plugins = plugins,
      interface = kind == "interface",
    }
    vim.fn.writefile(vim.split(string.format("dofile(%q)(%s)",
      vim.fs.joinpath(root, "tests", "support", "startup.lua"), vim.inspect(options)), "\n"), init)
    local argv = { vim.v.progpath, "--embed", "--headless", "-i", "NONE", "-u", init }
    if kind == "existing" or kind == "new" then argv[#argv + 1] = first end
    if kind == "directory" then argv[#argv + 1] = project end
    job = vim.fn.jobstart(argv, {
      rpc = true, cwd = base, clear_env = true,
      env = {
        PATH = vim.env.PATH, SystemRoot = vim.env.SystemRoot, PATHEXT = vim.env.PATHEXT,
        COMSPEC = vim.env.COMSPEC,
        XDG_CONFIG_HOME = vim.fs.joinpath(base, "config"),
        XDG_DATA_HOME = vim.fs.joinpath(base, "data"),
        XDG_STATE_HOME = vim.fs.joinpath(base, "state"),
        XDG_CACHE_HOME = vim.fs.joinpath(base, "cache"),
        LOCALAPPDATA = vim.fs.joinpath(base, "local"),
        APPDATA = vim.fs.joinpath(base, "roaming"),
        NVIM_APPNAME = "orbit-startup-test", NVIM_LOG_FILE = vim.fs.joinpath(base, "nvim.log"),
        TMPDIR = base, TEMP = base, TMP = base,
      },
      on_stderr = function(_, lines) vim.list_extend(stderr, lines) end,
    })
    assert(job > 0, "failed to start Neovim")
    vim.rpcnotify(job, "nvim_ui_attach", 80, 24, {rgb = true})
    assert(vim.wait(10000, function()
      return exec("return package.loaded['orbit.tests.startup'] ~= nil and vim.v.vim_did_enter == 1")
    end, 10), "Neovim did not reach VimEnter")
    -- A scheduled RPC runs after the owner's startup callbacks have settled.
    local initial = snapshot()
    assert(#events(initial, "VimEnter") == 1, "VimEnter was missed or repeated")
    assert(#events(initial, "UIEnter") == 1, "real attached UI did not enter once")
    assert(#initial.errors == 0 and initial.errmsg == "", vim.inspect(initial.errors) .. initial.errmsg)
    assert(initial.setups == (plugins and 1 or 0), "Lazy initialization count changed")
    assert(initial.status == (plugins and "loaded" or "disabled"), "unexpected plugin state")
    assert(initial.lazy_loaded == plugins, "plugin opt-in was ignored")

    if kind == "empty" or kind == "interface" then
      local unnamed = vim.tbl_filter(function(buffer)
        return buffer.listed and buffer.buftype == "" and buffer.name == ""
      end, initial.buffers)
      assert(#unnamed == 1, "startup must retain one unnamed listed normal buffer")
      assert(initial.fileposts == 0, "unnamed/interface startup consumed FilePost")
    elseif kind == "directory" then
      assert(canonical(initial.cwd) == canonical(project), "directory startup did not change cwd")
      for _, buffer in ipairs(initial.buffers) do
        assert(canonical(buffer.name) ~= canonical(project), "directory argument buffer survived")
      end
      -- Record, rather than redefine, when directory startup consumes FilePost.
      print("INFO directory startup FilePost count: " .. initial.fileposts)
    else
      assert(canonical(initial.name) == canonical(first), "startup replaced the requested file")
      assert(vim.deep_equal(initial.lines, kind == "new" and {""} or {"return 'first'"}),
        "startup changed file contents")
      assert(initial.fileposts == 1, "file startup did not emit one FilePost")
      local post = events(initial, "FilePost")[1]
      assert(post.ui and canonical(post.name) == canonical(first), "FilePost preceded file/UI readiness")
      local replayed = false
      for index, event in ipairs(initial.journal) do
        if event.event == "FilePost" then
          local filetype, editorconfig = initial.journal[index + 1], initial.journal[index + 2]
          replayed = filetype and filetype.event == "FileType"
            and editorconfig and editorconfig.event == "EditorConfig"
            and filetype.buffer == post.buffer and editorconfig.buffer == post.buffer
            and editorconfig.shiftwidth == 6
        end
      end
      assert(replayed, "FilePost did not replay FileType then real EditorConfig on its buffer")
      assert(initial.shiftwidth == 6 and initial.tabstop == 6, "project indentation was not restored")
      if kind == "existing" then
        assert(#events(initial, "BufReadPre", first) == 1, "earlier read observer was replayed")
        if plugins then assert(#events(initial, "LazyRead", first) == 1, "new Lazy read observer missed demand") end
      end
    end

    exec("require('orbit.tests.startup').repeat_setup(); return true")
    local repeated = snapshot()
    assert(repeated.fileposts == initial.fileposts and repeated.setups == initial.setups,
      "repeated setup repeated startup work")
    exec(string.format("require('orbit.tests.startup').edit(%q); return true", second))
    local final = snapshot()
    local expected = initial.fileposts == 0 and 1 or initial.fileposts
    assert(final.fileposts == expected and final.setups == initial.setups, "later file repeated startup work")
    assert(#events(final, "BufReadPre", second) == 1, "later read observer count changed")
    if plugins then assert(#events(final, "LazyRead", second) == 1, "later Lazy read observer count changed") end
    assert(#final.errors == 0 and final.errmsg == "", vim.inspect(final.errors) .. final.errmsg)
    assert(vim.deep_equal(vim.fn.readfile(second), {"return 'second'"}), "fixture file was changed")
    if kind == "new" then assert(vim.fn.filereadable(first) == 0, "startup created the new file on disk") end
  end, debug.traceback)

  if job > 0 then
    pcall(vim.rpcnotify, job, "nvim_command", "qa!")
    local exit = vim.fn.jobwait({job}, 2000)[1]
    if exit == -1 then
      pcall(vim.fn.jobstop, job)
      vim.fn.jobwait({job}, 2000)
    end
    if ok and exit ~= 0 then
      ok, err = false, "child shutdown failed: " .. exit
    end
  end
  local removed = vim.fn.delete(base, "rf")
  if ok and removed ~= 0 then ok, err = false, "fixture cleanup failed" end
  assert(ok, string.format("FAIL %s plugins=%s\n%s\n%s", kind, plugins, err, table.concat(stderr, "\n")))
  passed = passed + 1
  print(string.format("PASS actual startup %s plugins=%s", kind, plugins))
end

for _, plugins in ipairs({false, true}) do
  for _, kind in ipairs({"empty", "interface", "existing", "new", "directory"}) do
    check(kind, plugins)
  end
end
print(string.format("%d actual Neovim startup cases passed.", passed))
