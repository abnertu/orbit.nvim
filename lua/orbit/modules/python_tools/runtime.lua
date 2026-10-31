-- Guard existing Pyright stubs until the replacement has completed.
local M = {}
local active = {}

local function valid_name(name)
  return type(name) == "string"
    and name ~= "" and name ~= "." and name ~= ".."
    and not name:find("[/\\:]")
    and not name:match("^%.orbit%-stub%-")
end

---Regenerate a direct child of project typings with failure recovery.
---@param root string
---@param name string
---@param on_done fun(ok:boolean, err?:string)
---@return boolean started
function M.recreate(root, name, on_done)
  assert(type(on_done) == "function", "completion callback is required")
  if not valid_name(name) then
    on_done(false, "Invalid stub selection")
    return false
  end
  root = vim.fs.normalize(vim.fn.resolve(vim.fn.fnamemodify(root, ":p")))
  local parent = vim.fs.joinpath(root, "typings")
  local target = vim.fs.joinpath(parent, name)
  local root_stat = vim.uv.fs_lstat(parent)
  local target_stat = vim.uv.fs_lstat(target)
  if not root_stat or root_stat.type ~= "directory"
    or not target_stat or target_stat.type ~= "directory"
  then
    on_done(false, "Selected stub is no longer a directory")
    return false
  end
  if active[target] then
    on_done(false, "This stub is already being regenerated")
    return false
  end

  local backup = vim.fs.joinpath(parent, ".orbit-stub-" .. tostring(vim.uv.hrtime()))
  if vim.uv.fs_lstat(backup) then
    on_done(false, "Stub backup path already exists")
    return false
  end
  local moved, move_err = vim.uv.fs_rename(target, backup)
  if not moved then
    on_done(false, tostring(move_err))
    return false
  end
  active[target] = true

  local finished = false
  local function finish(ok, err)
    if finished then return end
    finished = true
    local new_stat = vim.uv.fs_lstat(target)
    if ok and (not new_stat or new_stat.type ~= "directory") then
      ok, err = false, "Pyright produced no stub directory"
    end
    if ok then
      if vim.fn.delete(backup, "rf") ~= 0 then
        err = "Generated stub saved; old copy retained at " .. backup
      end
    else
      if new_stat then
        local flag = new_stat.type == "directory" and "rf" or ""
        if vim.fn.delete(target, flag) ~= 0 then
          err = tostring(err) .. "; incomplete stub remains; old copy at " .. backup
          active[target] = nil
          on_done(false, err)
          return
        end
      end
      local restored, restore_err = vim.uv.fs_rename(backup, target)
      if not restored then
        err = tostring(err) .. "; restore failed: " .. tostring(restore_err)
          .. "; old copy at " .. backup
      end
    end
    active[target] = nil
    on_done(ok, err)
  end

  local started, job = pcall(vim.fn.jobstart,
    { "pyright", "--createstub", name }, {
      cwd = root,
      on_exit = vim.schedule_wrap(function(_, status)
        finish(status == 0,
          status ~= 0 and "Pyright exited with code " .. status or nil)
      end),
    })
  if not started or type(job) ~= "number" or job <= 0 then
    finish(false, started and "Could not start Pyright" or tostring(job))
    return false
  end
  return true
end

return M
