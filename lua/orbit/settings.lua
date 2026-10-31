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
---@return Orbit.Config?, string?, table?
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
