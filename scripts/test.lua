-- Run Orbit test groups. Each suite runs in its own Neovim process with
-- private XDG state, data and cache directories, so no test touches the
-- user's real Neovim directories.
-- Usage: nvim --headless -u NONE -l scripts/test.lua test|live|schema [pattern]
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local group, pattern = arg[1], arg[2]
local ci = vim.env.GITHUB_ACTIONS == "true"

---@class Orbit.TestSuite
---@field name string
---@field argv string[]

---@param file string
---@param before? string[] Neovim arguments before -l.
---@param after? string[] Script arguments.
---@return Orbit.TestSuite
local function suite(file, before, after)
  local argv = { vim.v.progpath, "--headless", "-u", "NONE" }
  vim.list_extend(argv, before or {})
  vim.list_extend(argv, { "-l", file })
  vim.list_extend(argv, after or {})
  return { name = file, argv = argv }
end

---@param prefix "live"|"other"
---@return Orbit.TestSuite[]
local function specs(prefix)
  local found = {}
  for name, kind in vim.fs.dir(vim.fs.joinpath(root, "tests")) do
    local live = name:match("^live_.+_spec%.lua$") ~= nil
    if kind == "file" and name:match("_spec%.lua$") and live == (prefix == "live") then
      found[#found + 1] = name
    end
  end
  table.sort(found)
  return vim.tbl_map(function(name)
    return suite("tests/" .. name)
  end, found)
end

---@type table<string, fun(): Orbit.TestSuite[]>
local groups = {
  schema = function()
    return {
      suite("scripts/generate_schema.lua", nil, { "--check" }),
      suite("tests/schema_spec.lua"),
      suite("tests/settings_spec.lua"),
    }
  end,
  test = function()
    local list = specs("other")
    list[#list + 1] = suite("tests/smoke.lua", { "--cmd", "set rtp^=." })
    return list
  end,
  live = function()
    return specs("live")
  end,
}

assert(groups[group], "usage: scripts/test.lua test|live|schema [pattern]")
local list = groups[group]()
if pattern then
  list = vim.tbl_filter(function(item)
    return item.name:find(pattern, 1, true) ~= nil
  end, list)
end
assert(#list > 0, "no suites match " .. tostring(pattern))

local sandbox = vim.fn.tempname() .. "-orbit-tests"
local failed = {}
for index, item in ipairs(list) do
  local home = vim.fs.joinpath(sandbox, tostring(index))
  local env = {}
  for _, name in ipairs({ "state", "data", "cache", "config" }) do
    local directory = vim.fs.joinpath(home, name)
    assert(vim.fn.mkdir(directory, "p") == 1, "cannot create " .. directory)
    env["XDG_" .. name:upper() .. "_HOME"] = directory
  end
  io.stdout:write((ci and "::group::" or "== ") .. item.name .. "\n")
  io.stdout:flush()
  local started = vim.uv.hrtime()
  local result = vim
    .system(item.argv, {
      cwd = root,
      env = env,
      stdout = function(_, data)
        if data then
          io.stdout:write(data)
        end
      end,
      stderr = function(_, data)
        if data then
          io.stderr:write(data)
        end
      end,
    })
    :wait()
  io.stdout:write(
    string.format(
      "%s %s (%.1fs)%s\n",
      result.code == 0 and "ok" or "FAILED",
      item.name,
      (vim.uv.hrtime() - started) / 1e9,
      result.code == 0 and "" or string.format(" exit=%d signal=%d", result.code, result.signal)
    )
  )
  if ci then
    io.stdout:write("::endgroup::\n")
  end
  if result.code ~= 0 then
    failed[#failed + 1] = item.name
    if ci then
      io.stdout:write("::error::" .. item.name .. " failed\n")
    end
  end
end
vim.fn.delete(sandbox, "rf")

io.stdout:write(string.format("%d of %d %s suites passed.\n", #list - #failed, #list, group))
if #failed > 0 then
  io.stderr:write("Failed: " .. table.concat(failed, ", ") .. "\n")
  os.exit(1)
end
