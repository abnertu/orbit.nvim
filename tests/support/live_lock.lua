-- Resolve live-suite plugin revisions from the tracked lazy-lock.json.
-- Load with dofile(root .. "/tests/support/live_lock.lua").
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local lockfile = vim.fs.joinpath(root, "lazy-lock.json")

---@class Orbit.LiveLockEntry
---@field branch? string
---@field commit string

---@type table<string, Orbit.LiveLockEntry>?
local entries

---@return table<string, Orbit.LiveLockEntry>
local function read()
  if entries then
    return entries
  end
  local file = assert(io.open(lockfile, "rb"), "cannot read " .. lockfile)
  local text = file:read("*a")
  file:close()
  local ok, decoded = pcall(vim.json.decode, text)
  assert(ok and type(decoded) == "table", "invalid JSON in " .. lockfile)
  entries = decoded
  return entries
end

---@param name string
---@param argv string[]
---@return string
local function git(name, argv)
  local result = vim.system(argv, { text = true, timeout = 120000 }):wait()
  if result.code ~= 0 then
    error(
      string.format(
        "%s: %s failed: %s",
        name,
        table.concat(argv, " "),
        vim.trim(result.stderr or result.stdout or "")
      ),
      0
    )
  end
  return result.stdout or ""
end

---@class Orbit.LiveLock
local M = {}

M.lockfile = lockfile

---Return the locked commit of one plugin.
---@param name string Plugin name as Lazy writes it, such as "nvim-dap".
---@return string commit
function M.commit(name)
  local entry = read()[name]
  if type(entry) ~= "table" or type(entry.commit) ~= "string" then
    error(string.format("%s has no entry in %s", name, lockfile), 0)
  end
  if not entry.commit:match("^%x+$") or #entry.commit ~= 40 then
    error(string.format("%s has an invalid commit in %s", name, lockfile), 0)
  end
  return entry.commit
end

---Fetch the locked commit of one plugin into a new Git checkout.
---@param name string Plugin name as Lazy writes it.
---@param repository string "owner/repo" on GitHub, or a full clone URL.
---@param directory string Checkout path; it is created when missing.
---@return string directory
function M.checkout(name, repository, directory)
  local commit = M.commit(name)
  if vim.fn.executable("git") ~= 1 then
    error(name .. ": Git is required for live plugin checkouts", 0)
  end
  local url = repository:find("://", 1, true) and repository
    or ("https://github.com/" .. repository .. ".git")
  if vim.fn.isdirectory(directory) == 0 and vim.fn.mkdir(directory, "p") ~= 1 then
    error(name .. ": cannot create " .. directory, 0)
  end
  git(name, { "git", "init", "--quiet", directory })
  git(name, { "git", "-C", directory, "fetch", "--quiet", "--depth", "1", url, commit })
  git(name, { "git", "-C", directory, "checkout", "--quiet", "--detach", "FETCH_HEAD" })
  local head = vim.trim(git(name, { "git", "-C", directory, "rev-parse", "HEAD" }))
  if head ~= commit then
    error(string.format("%s: checked out %s, lock has %s", name, head, commit), 0)
  end
  return directory
end

return M
