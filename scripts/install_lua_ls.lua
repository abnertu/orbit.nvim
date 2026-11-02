-- Install the pinned LuaLS acceptance-test prerequisite on GitHub runners.
local windows = vim.fn.has("win32") == 1
local version = "3.19.2"
local platform = windows and "win32-x64.zip" or "linux-x64.tar.gz"
local expected = windows and "4a3dc851b3b31e7b75a23f645d1ba4a2137579a55f5fa4edbb17a3e2a6254044"
  or "93ad326b10f6c00911dd8c450fa098332dbd8f9f45d1052f5636a2d54479b947"
local home = assert(vim.env.RUNNER_TEMP, "RUNNER_TEMP is required") .. "/orbit-lua-ls"
vim.fn.mkdir(home, "p")
local archive = home .. "/" .. platform
---@param argv string[]
---@return string
local function run(argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  assert(result.code == 0, vim.inspect(argv) .. ": " .. tostring(result.stderr))
  return result.stdout or ""
end
run({
  "curl",
  "--fail",
  "--location",
  "--silent",
  "--show-error",
  "--retry",
  "3",
  "--output",
  archive,
  "https://github.com/LuaLS/lua-language-server/releases/download/"
    .. version
    .. "/lua-language-server-"
    .. version
    .. "-"
    .. platform,
})
local checksum =
  run(windows and { "certutil", "-hashfile", archive, "SHA256" } or { "sha256sum", archive })
assert(checksum:lower():gsub("%s", ""):find(expected, 1, true), "LuaLS archive checksum mismatch")
run({ "tar", "-xf", archive, "-C", home })
local bin = home .. "/bin"
local executable = bin .. (windows and "/lua-language-server.exe" or "/lua-language-server")
assert(run({ executable, "--version" }):find(version, 1, true), "LuaLS version mismatch")
assert(vim.fn.writefile({ bin }, assert(vim.env.GITHUB_PATH, "GITHUB_PATH is required"), "a") == 0)
