-- Install lazy.nvim only when an enabled plugin manager is demanded.
-- Git runs with argument arrays. No shell command interpolation is used.
local M = {}

local function git(args, context)
  assert(vim.fn.executable("git") == 1, "Git is required for Lazy bootstrap")
  local command = { "git" }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait(60000)
  if result.code ~= 0 then
    error(context .. " (exit " .. tostring(result.code) .. "): " ..
      vim.trim(result.stderr or result.stdout or ""), 0)
  end
  return vim.trim(result.stdout or "")
end

local function locked_revision(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode,
    table.concat(vim.fn.readfile(path), "\n"))
  assert(ok and type(decoded) == "table",
    "invalid Lazy lockfile JSON: " .. path)
  local entry = decoded["lazy.nvim"]
  if not entry then
    return nil
  end
  local revision = entry.commit
  assert(type(revision) == "string"
      and #revision == 40
      and revision:match("^[0-9a-fA-F]+$"),
    "invalid lazy.nvim commit in lockfile: " .. path)
  return revision
end

---Resolve or create a Lazy checkout. Existing directories are never modified.
---@param opts {path:string, bootstrap:boolean, source:string, lockfile:string}
---@return string
function M.ensure(opts)
  assert(type(opts.path) == "string" and opts.path ~= "",
    "Lazy bootstrap requires an installation path")

  local path = vim.fs.normalize(vim.fn.fnamemodify(opts.path, ":p"))
  local stat = vim.uv.fs_stat(path)
  if stat then
    assert(stat.type == "directory",
      "Lazy installation path is not a directory: " .. path)
    return path
  end

  assert(opts.bootstrap == true,
    "lazy.nvim is not installed at " .. path .. "; enable bootstrap or install it")
  assert(type(opts.source) == "string" and opts.source ~= "",
    "Lazy bootstrap requires a Git source")

  local lockfile = opts.lockfile ~= "" and opts.lockfile or
    vim.fs.joinpath(vim.fn.stdpath("config"), "lazy-lock.json")
  local revision = locked_revision(lockfile)
  local parent = vim.fs.dirname(path)
  vim.fn.mkdir(parent, "p")
  assert(vim.fn.isdirectory(parent) == 1,
    "cannot create Lazy installation parent: " .. parent)

  local ok, err = xpcall(function()
    git({ "clone", "--filter=blob:none", "--branch=stable", opts.source, path },
      "unable to clone lazy.nvim")
    if revision then
      git({ "-C", path, "checkout", "--detach", revision },
        "unable to check out locked Lazy revision")
    end
  end, debug.traceback)
  if not ok then
    -- The destination was absent before our clone, so it is safe to remove.
    vim.fn.delete(path, "rf")
    error(tostring(err), 0)
  end
  assert(vim.uv.fs_stat(path), "Lazy clone did not create " .. path)
  return path
end

return M
