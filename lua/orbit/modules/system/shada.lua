-- Clear only regular *.tmp files in ShaDa directories on explicit demand.
local M = {}

local function inspect(directory)
  local stat, err, code = vim.uv.fs_lstat(directory)
  if not stat then
    if code == "ENOENT" then return 0 end
    return nil, tostring(err)
  end
  if stat.type ~= "directory" then
    return nil, "ShaDa path is not a directory: " .. directory
  end
  local scan, scan_error = vim.uv.fs_scandir(directory)
  if not scan then return nil, tostring(scan_error) end

  local deleted = 0
  while true do
    local name = vim.uv.fs_scandir_next(scan)
    if not name then break end
    -- Never delete the persistent ShaDa file or unrelated user data.
    if name ~= "main.shada" and name:lower():match("%.tmp$") then
      local path = vim.fs.joinpath(directory, name)
      local entry = vim.uv.fs_lstat(path)
      -- Ignore links and directories, including links named *.tmp.
      if entry and entry.type == "file" then
        local removed, remove_error = vim.uv.fs_unlink(path)
        if not removed then return nil, tostring(remove_error) end
        deleted = deleted + 1
      end
    end
  end
  return deleted
end

---Remove regular temporary files from current and legacy ShaDa directories.
---The optional directory list is for explicit recovery and test fixtures.
---@param directories? string[]
---@return integer? count
---@return string? err
function M.clear(directories)
  directories = directories or {
    vim.fs.joinpath(vim.fn.stdpath("state"), "shada"),
    vim.fs.joinpath(vim.fn.stdpath("data"), "shada"),
  }
  local seen, count = {}, 0
  for _, directory in ipairs(directories) do
    local normalized = vim.fs.normalize(directory)
    local key = vim.fn.has("win32") == 1 and normalized:lower() or normalized
    if not seen[key] then
      seen[key] = true
      local removed, err = inspect(normalized)
      if not removed then return nil, err end
      count = count + removed
    end
  end
  return count
end

return M
