local M = {}

---Resolve the saved settings path without global variables or hidden writes.
---@param path? string
---@return string
function M.path(path)
  assert(path == nil or (type(path) == "string" and path ~= ""), "settings path must be a nonempty string")
  local selected = path or (vim.fn.stdpath("data") .. "/settings.json")
  return vim.fs.normalize(vim.fn.fnamemodify(selected, ":p"))
end

---Read and validate a complete configuration before any activation occurs.
---Missing input uses declared defaults. A malformed file is never rewritten.
---@param path? string
---@return Orbit.Config?, string?, table<string, any>?
function M.read(path)
  local ok, filename = pcall(M.path, path)
  if not ok then
    return nil, tostring(filename)
  end

  local stat, stat_error, code = vim.uv.fs_stat(filename)
  if not stat then
    if code == "ENOENT" then
      return require("orbit.config").resolve({}), nil, {}
    end
    return nil, "cannot stat settings " .. filename .. ": " .. tostring(stat_error)
  end
  if stat.type ~= "file" then
    return nil, "settings path must refer to a file: " .. filename
  end

  local file, open_error = io.open(filename, "rb")
  if not file then
    return nil, "cannot open settings " .. filename .. ": " .. tostring(open_error)
  end

  local source = file:read("*a")
  file:close()
  local decoded, raw = pcall(vim.json.decode, source)
  if not decoded then
    return nil, "invalid JSON in " .. filename .. ": " .. tostring(raw)
  end

  local valid, values = pcall(require("orbit.config").resolve, raw)
  if not valid then
    return nil, tostring(values)
  end
  return values, nil, raw
end

---Set one value in an existing settings file after validating the result.
---The file is replaced atomically. A missing file is not created, and any
---failure leaves the file and the accepted configuration unchanged.
---@param path string
---@param keys string[]
---@param value any
---@return boolean, string?
function M.update(path, keys, value)
  local filename = M.path(path)
  local stat = vim.uv.fs_stat(filename)
  if not stat or stat.type ~= "file" then
    return false, "settings file does not exist; open settings to create it: " .. filename
  end
  local file, open_error = io.open(filename, "rb")
  if not file then
    return false, "cannot open settings " .. filename .. ": " .. tostring(open_error)
  end
  local source = file:read("*a")
  file:close()
  local decoded, raw = pcall(vim.json.decode, source)
  if not decoded or type(raw) ~= "table" then
    return false, "invalid JSON in " .. filename .. ": " .. tostring(raw)
  end

  local node = raw
  for index = 1, #keys - 1 do
    local key = keys[index]
    if node[key] == nil then node[key] = vim.empty_dict() end
    if type(node[key]) ~= "table" then
      return false, "settings key is not an object: " .. table.concat(keys, ".", 1, index)
    end
    node = node[key]
  end
  node[keys[#keys]] = value
  local valid, err = pcall(require("orbit.config").resolve, raw)
  if not valid then
    return false, tostring(err)
  end

  local content = vim.json.encode(raw, { indent = "  ", sort_keys = true }) .. "\n"
  local temporary = filename .. ".orbit-" .. vim.uv.os_getpid() .. ".tmp"
  local handle, create_error = vim.uv.fs_open(temporary, "wx", stat.mode)
  if not handle then
    return false, "cannot write settings: " .. tostring(create_error)
  end
  local written, write_error = vim.uv.fs_write(handle, content, 0)
  local synced = written == #content and vim.uv.fs_fsync(handle)
  vim.uv.fs_close(handle)
  if written ~= #content or not synced then
    vim.uv.fs_unlink(temporary)
    return false, "cannot write settings: " .. tostring(write_error or "short write")
  end
  local renamed, rename_error = vim.uv.fs_rename(temporary, filename)
  if not renamed then
    vim.uv.fs_unlink(temporary)
    return false, "cannot replace settings: " .. tostring(rename_error)
  end
  return true
end

local watch_group = "OrbitSettingsWatch"

---Watch the selected file only. Repeated calls replace the old observer.
---@param path? string
---@return string
function M.watch(path)
  local expected = M.path(path)
  local group = vim.api.nvim_create_augroup(watch_group, { clear = true })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    desc = "Reload the selected orbit.nvim settings file",
    callback = function(event)
      local actual = M.path(event.file)
      local target = expected
      if vim.fn.has("win32") == 1 then
        actual = actual:lower()
        target = target:lower()
      end
      if actual ~= target then
        return
      end

      local ok, err = require("orbit").reload_from_file(expected)
      if not ok then
        vim.notify(tostring(err), vim.log.levels.WARN, { title = "orbit.nvim settings" })
      end
    end,
  })

  return expected
end

---Stop watching. A later call to watch() can register the observer again.
function M.unwatch()
  pcall(vim.api.nvim_del_augroup_by_name, watch_group)
end

return M
