-- Protect child command lookup without changing Neovim's inherited environment.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
require("orbit").setup({ modules = { terminal = { startinsert = false } } })
local runtime = require("orbit.modules.terminal.runtime")
local windows = vim.fn.has("win32") == 1
local original_path, original_shell = vim.env.PATH, vim.o.shell
local has, jobstart = vim.fn.has, vim.fn.jobstart
local passed = 0

---@param label string
---@param callback fun()
local function check(label, callback)
  local ok, err = xpcall(callback, debug.traceback)
  vim.env.PATH, vim.o.shell = original_path, original_shell
  vim.fn.has, vim.fn.jobstart = has, jobstart
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

if windows then
  check("a real nested cmd resolves a command through a duplicate-heavy terminal PATH", function()
    local workspace = vim.fn.tempname() .. " terminal environment"
    assert(vim.fn.mkdir(workspace, "p") == 1)
    -- cmd fixtures require batch syntax; all fixture generation and assertions stay in Lua.
    vim.fn.writefile(
      { "@echo orbit-child-%ORBIT_TERMINAL_SENTINEL%" },
      workspace .. "/orbit-path-probe.cmd"
    )
    local shell = vim.fn.exepath("pwsh.exe")
    assert(shell ~= "", "pwsh is required for Windows terminal acceptance")
    local command = '"'
      .. shell
      .. '" -NoLogo -NoProfile -Command '
      .. '"& $env:ORBIT_TERMINAL_CMD /d /c orbit-path-probe; '
      .. 'if ($LASTEXITCODE -eq 0) { exit 3 } else { exit 5 }"'
    local system32 = vim.env.SystemRoot .. "\\System32"
    local path = workspace .. ";" .. system32
    while #path <= 10000 do
      path = path .. ";" .. workspace .. ";" .. system32
    end
    local cmd, sentinel = vim.env.ORBIT_TERMINAL_CMD, vim.env.ORBIT_TERMINAL_SENTINEL
    vim.env.ORBIT_TERMINAL_CMD = system32 .. "\\cmd.exe"
    vim.env.ORBIT_TERMINAL_SENTINEL = "preserved-42"
    vim.env.PATH = path
    local child
    local ok, err = xpcall(function()
      child = jobstart(
        { vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" },
        { rpc = true }
      )
      assert(child > 0)
      vim.rpcrequest(child, "nvim_ui_attach", 120, 30, { rgb = true })
      vim.rpcrequest(
        child,
        "nvim_exec_lua",
        [[
        local root, command = ...
        vim.opt.rtp:prepend(root)
        vim.o.shell = command
        require('orbit').setup({modules={terminal={startinsert=false}}})
        vim.api.nvim_create_autocmd('TermClose', {once=true, callback=function(event)
          vim.b[event.buf].orbit_probe_exit = vim.v.event.status
        end})
        require('orbit.modules.terminal').open('sp')
      ]],
        { root, command }
      )
      local output, finished
      assert(
        vim.wait(15000, function()
          local result = vim.rpcrequest(
            child,
            "nvim_exec_lua",
            [[
          local buffer = vim.api.nvim_get_current_buf()
          return {
            table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n'),
            vim.b[buffer].orbit_probe_exit or -1,
          }
        ]],
            {}
          )
          output, finished = result[1], result[2]
          return finished ~= -1
        end, 20),
        "nested cmd did not exit"
      )
      assert(finished == 3 and output:find("orbit-child-preserved-42", 1, true), output)
      assert(vim.env.PATH == path, "opening a terminal changed parent PATH")
      assert(vim.env.ORBIT_TERMINAL_SENTINEL == "preserved-42")
    end, debug.traceback)
    if child then
      pcall(vim.fn.jobstop, child)
    end
    vim.env.ORBIT_TERMINAL_CMD, vim.env.ORBIT_TERMINAL_SENTINEL = cmd, sentinel
    vim.fn.delete(workspace, "rf")
    assert(ok, err)
  end)
end

check("Windows spawn compacts only repeated nonempty entries in its child environment", function()
  vim.fn.has = function(name)
    return name == "win32" and 1 or has(name)
  end
  local path = [[C:\First;;C:\Tools;c:\first;C:\Unique\;C:\Tools;;]]
  local expected = [[C:\First;;C:\Tools;C:\Unique\;;]]
  vim.env.PATH = path
  local spawned = false
  vim.fn.jobstart = function(_, opts)
    spawned = true
    assert(opts.term == true and opts.detach == false)
    assert(vim.deep_equal(opts.env, { PATH = expected }), "incorrect child PATH override")
    assert(vim.env.PATH == path, "spawn changed parent PATH")
    return 42
  end
  assert(runtime.spawn() == 42 and spawned)
  assert(vim.env.PATH == path)
end)

check("Linux spawn leaves duplicate PATH entries untouched", function()
  vim.fn.has = function(name)
    return name == "win32" and 0 or has(name)
  end
  local path = "/first::/tools:/first:/unique::"
  vim.env.PATH = path
  vim.fn.jobstart = function(_, opts)
    assert(not opts.env or opts.env.PATH == nil, "Linux PATH must not be compacted")
    return 42
  end
  assert(runtime.spawn() == 42 and vim.env.PATH == path)
end)

check("absent PATH remains absent", function()
  vim.fn.has = function(name)
    return name == "win32" and 1 or has(name)
  end
  vim.env.PATH = nil
  vim.fn.jobstart = function(_, opts)
    assert(not opts.env or opts.env.PATH == nil, "spawn invented a PATH value")
    return 42
  end
  assert(runtime.spawn() == 42 and vim.env.PATH == nil)
end)

print(string.format("%d terminal environment checks passed.", passed))
