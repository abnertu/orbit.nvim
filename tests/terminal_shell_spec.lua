-- Exercise shell policy through setup and real Neovim command entry points.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local windows = vim.fn.has("win32") == 1
local passed = 0

---@param label string
---@param callback fun(run: fun(code: string, ...: string))
local function check(label, callback)
  local child = vim.fn.jobstart(
    { vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" },
    { rpc = true }
  )
  assert(child > 0)
  ---@param code string
  ---@param ... string
  local function run(code, ...)
    vim.rpcrequest(child, "nvim_exec_lua", code, { ... })
  end
  local ok, err = xpcall(function()
    run("vim.opt.rtp:prepend(...)", root)
    callback(run)
  end, debug.traceback)
  pcall(vim.fn.jobstop, child)
  assert(ok, "FAIL " .. label .. "\n" .. tostring(err))
  passed = passed + 1
  print("PASS " .. label)
end

-- Fake availability, not shell behavior. Actual commands below use real shells.
local emulate_windows = [[
  local has = vim.fn.has
  vim.fn.has = function(name) return name == 'win32' and 1 or has(name) end
  local executable = vim.fn.executable
  vim.fn.executable = function(name)
    return (name == 'pwsh.exe' or name == 'powershell.exe') and 1 or executable(name)
  end
]]

for _, available in ipairs({ "pwsh.exe", "powershell.exe", "none" }) do
  check("setup selects the available Windows shell: " .. available, function(run)
    run(emulate_windows)
    run(
      [[
      local available = ...
      local executable = vim.fn.executable
      vim.fn.executable = function(name)
        if name == 'pwsh.exe' or name == 'powershell.exe' then
          return name == available and 1 or 0
        end
        return executable(name)
      end
      local original = vim.o.shell
      require('orbit').setup()
      local expected = available == 'none' and original or available
      assert(vim.o.shell == expected, 'shell was not selected during setup')
      if available ~= 'none' then
        local shell = require('orbit.modules.terminal.runtime')
        local args = shell.shell_argv()
        assert(vim.deep_equal(args, {available, '-NoLogo'}))
        args[2] = 'mutated'
        assert(shell.shell_argv()[2] == '-NoLogo', 'shared interactive flags were mutated')
        assert(vim.o.shellcmdflag:find('-NoProfile', 1, true))
        assert(vim.o.shellcmdflag:find('UTF8Encoding', 1, true))
        assert(not vim.o.shelltemp)
      end
    ]],
      available
    )
  end)
end

check("explicit custom shell and command options retain priority", function(run)
  run(emulate_windows)
  run([[
    vim.o.shell = 'cmd.exe /d'
    local before = {vim.o.shellcmdflag, vim.o.shellredir, vim.o.shellpipe,
      vim.o.shellquote, vim.o.shellxquote, vim.o.shelltemp}
    require('orbit').setup()
    assert(vim.o.shell == 'cmd.exe /d')
    assert(vim.deep_equal(before, {vim.o.shellcmdflag, vim.o.shellredir, vim.o.shellpipe,
      vim.o.shellquote, vim.o.shellxquote, vim.o.shelltemp}))
  ]])
end)

check("explicit PowerShell command options survive setup and disable", function(run)
  run(emulate_windows)
  run([[
    vim.o.shell = 'pwsh.exe'
    vim.o.shellcmdflag = '-Command custom'
    vim.o.shellredir = '> custom-output'
    vim.o.shellpipe = '> custom-errors'
    vim.o.shellquote = 'custom-quote'
    vim.o.shellxquote = 'custom-xquote'
    vim.o.shelltemp = true
    local function values()
      return {vim.o.shell, vim.o.shellcmdflag, vim.o.shellredir, vim.o.shellpipe,
        vim.o.shellquote, vim.o.shellxquote, vim.o.shelltemp}
    end
    local before = values()
    require('orbit').setup()
    assert(vim.deep_equal(before, values()))
    require('orbit').setup({modules={terminal={enabled=false}}})
    assert(vim.deep_equal(before, values()))
  ]])
end)

check("disable and retry retain original provenance despite sticky option metadata", function(run)
  run(emulate_windows)
  run([[
    local orbit = require('orbit')
    local original = vim.o.shell
    orbit.setup()
    assert(vim.o.shell == 'pwsh.exe')
    local flags = vim.o.shellcmdflag
    orbit.setup({modules={terminal={horizontal_size=35}}})
    assert(vim.o.shell == 'pwsh.exe' and vim.o.shellcmdflag == flags)
    orbit.setup({modules={terminal={enabled=false}}})
    assert(vim.o.shell == original)
    orbit.setup()
    assert(vim.o.shell == 'pwsh.exe', 'restored shell was misclassified as a user override')
    orbit.setup({modules={terminal={enabled=false}}})
    vim.o.shell = original
    orbit.setup()
    assert(vim.o.shell == original, 'same-value explicit user assignment was ignored')
  ]])
end)

check("first activation rollback restores options and permits retry", function(run)
  run(emulate_windows)
  run([[
    local function values()
      return {vim.o.shell, vim.o.shellcmdflag, vim.o.shellredir, vim.o.shellpipe,
        vim.o.shellquote, vim.o.shellxquote, vim.o.shelltemp}
    end
    local before = values()
    local commands = require('orbit.modules.commands')
    local setup = commands.setup
    commands.setup = function() error('shell rollback fixture') end
    local orbit = require('orbit')
    local ok, err = pcall(orbit.setup)
    commands.setup = setup
    assert(not ok and tostring(err):find('shell rollback fixture', 1, true))
    assert(vim.deep_equal(before, values()), 'partial shell setup was not restored')
    orbit.setup()
    assert(vim.o.shell == 'pwsh.exe', 'rollback lost original shell provenance')
  ]])
end)

check("later option assignments survive disable and changed-option setup", function(run)
  run(emulate_windows)
  run([[
    local orbit = require('orbit')
    orbit.setup()
    vim.o.shellcmdflag = '-Command user-choice'
    orbit.setup({modules={terminal={horizontal_size=36}}})
    assert(vim.o.shellcmdflag == '-Command user-choice')
    orbit.setup({modules={terminal={enabled=false}}})
    assert(vim.o.shellcmdflag == '-Command user-choice')
  ]])
end)

check("partial shell activation restores options before retry", function(run)
  run(emulate_windows)
  run([[
    local function values()
      return {vim.o.shell, vim.o.shellcmdflag, vim.o.shellredir, vim.o.shellpipe,
        vim.o.shellquote, vim.o.shellxquote, vim.o.shelltemp}
    end
    local before = values()
    local setter = vim.api.nvim_set_option_value
    local injected = false
    vim.api.nvim_set_option_value = function(name, value, opts)
      if name == 'shellredir' and not injected then
        injected = true
        error('partial shell failure')
      end
      return setter(name, value, opts)
    end
    local orbit = require('orbit')
    local ok, err = pcall(orbit.setup)
    vim.api.nvim_set_option_value = setter
    assert(injected and not ok and tostring(err):find('partial shell failure', 1, true))
    assert(vim.deep_equal(before, values()))
    orbit.setup()
    assert(vim.o.shell == 'pwsh.exe')
  ]])
end)

check("switching to a custom shell releases owned PowerShell command options", function(run)
  run(emulate_windows)
  run([[
    local before = vim.o.shellcmdflag
    local orbit = require('orbit')
    orbit.setup()
    vim.o.shell = 'cmd.exe /d'
    orbit.setup({modules={terminal={horizontal_size=37}}})
    assert(vim.o.shell == 'cmd.exe /d' and vim.o.shellcmdflag == before)
  ]])
end)

if windows then
  for _, executable in ipairs({ "pwsh.exe", "powershell.exe" }) do
    assert(vim.fn.executable(executable) == 1, executable .. " is required")
    check("real UTF-8, status, filters, and quickfix with " .. executable, function(run)
      run(
        [[
        local executable = ...
        vim.o.shell = '"' .. vim.fn.exepath(executable) .. '"'
        require('orbit').setup()
        local function read(command)
          vim.cmd.enew({bang=true})
          vim.cmd('silent read! ' .. command)
          return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'), vim.v.shell_error
        end
        local text, status = read("Write-Output 'orbit-中文'")
        assert(status == 0 and text:find('orbit-中文', 1, true), text)
        text, status = read("Write-Error 'orbit-cmdlet-failed'")
        assert(status ~= 0 and text:find('orbit-cmdlet-failed', 1, true), text)
        local fixture = vim.fn.tempname() .. ' native fixture.lua'
        vim.fn.writefile({
          "io.stdout:write('orbit-native-中文\\n')",
          "io.stderr:write('orbit-native-stderr\\n')",
          "os.exit(tonumber(arg[1]))",
        }, fixture)
        -- PowerShell syntax is required to exercise Neovim's Windows shell boundary.
        local native = "& '" .. vim.v.progpath:gsub("'", "''")
          .. "' --headless -u NONE -i NONE -l '" .. fixture:gsub("'", "''") .. "' "
        text, status = read(native .. '0')
        assert(status == 0 and text:find('orbit-native-中文', 1, true), 'status=' .. status .. ': ' .. text)
        assert(text:find('orbit-native-stderr', 1, true), text)
        text, status = read(native .. '7')
        assert(status ~= 0, 'pipe-based read lost native failure status')
        -- shellredir applies to file-based reads; PowerShell -Command normalizes
        -- native failures to 1 when Neovim uses pipes instead.
        vim.o.shelltemp = true
        text, status = read(native .. '0')
        assert(status == 0 and text:find('orbit-native-stderr', 1, true), text)
        text, status = read(native .. '7')
        assert(status == 7 and text:find('orbit-native-stderr', 1, true), 'status=' .. status .. ': ' .. text)
        text, status = read("Write-Error 'orbit-captured-failed'")
        assert(status ~= 0 and text:find('orbit-captured-failed', 1, true), text)
        vim.o.shelltemp = false
        vim.cmd('silent !' .. native .. '7')
        assert(vim.v.shell_error ~= 0)
        vim.cmd("silent !Write-Error 'orbit-direct-failed'")
        assert(vim.v.shell_error ~= 0)
        vim.cmd("silent !Write-Output 'orbit-direct-ok'")
        assert(vim.v.shell_error == 0)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {'orbit-filter'})
        -- Neovim supplies the input pipeline itself for legacy powershell.exe.
        local input = executable == 'pwsh.exe' and '$input | ' or ''
        vim.cmd('silent %!' .. input .. 'ForEach-Object { $_.ToUpper() }')
        assert(vim.v.shell_error == 0, vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
        assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'ORBIT-FILTER')
        vim.o.errorformat = '%f:%l:%m'
        vim.o.makeprg = "& { Write-Output 'orbit-fixture.lua:3:orbit diagnostic'; Write-Error 'orbit-make-failed' }"
        vim.cmd('silent make!')
        assert(vim.v.shell_error ~= 0)
        local found = false
        for _, item in ipairs(vim.fn.getqflist()) do
          found = found or (item.valid == 1 and item.lnum == 3 and item.text == 'orbit diagnostic')
        end
        assert(found, 'PowerShell make output did not populate quickfix: ' .. vim.inspect(vim.fn.getqflist()))
        vim.fn.delete(fixture)
      ]],
        executable
      )
    end)
  end
else
  check("Linux options and real command execution remain unchanged", function(run)
    run([[
      local before = {vim.o.shell, vim.o.shellcmdflag, vim.o.shellredir, vim.o.shellpipe,
        vim.o.shellquote, vim.o.shellxquote, vim.o.shelltemp}
      require('orbit').setup()
      assert(vim.deep_equal(before, {vim.o.shell, vim.o.shellcmdflag, vim.o.shellredir,
        vim.o.shellpipe, vim.o.shellquote, vim.o.shellxquote, vim.o.shelltemp}))
      vim.cmd('silent read! printf orbit-linux')
      assert(vim.v.shell_error == 0)
      assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false)):find('orbit-linux', 1, true))
    ]])
  end)
end

print(string.format("%d terminal shell checks passed.", passed))
