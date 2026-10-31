local M = {}

local roots = { "lua/", "tests/", "after/", "syntax/", ".github/", "scripts/" }
local files = { ["init.lua"] = true, ["settings.schema.json"] = true }
local extensions = {
  lua = true,
  json = true,
  scm = true,
  vim = true,
  yml = true,
  yaml = true,
  toml = true,
}

local function should_scan(path)
  local selected = files[path] == true
  for _, prefix in ipairs(roots) do
    if vim.startswith(path, prefix) then
      selected = true
      break
    end
  end
  return selected and extensions[path:match("%.([^%.]+)$") or ""] == true
end

---Recognize legacy project identifiers without matching migration documentation.
---@param value string
---@return boolean
function M.is_legacy(value)
  local lower = value:lower()
  local base = "orbit"
  local suffix = "vim"
  for _, token in ipairs({
    base .. suffix,
    base .. "_" .. suffix,
    base .. "-" .. suffix,
    "nv" .. "chad",
    "base" .. "46",
  }) do
    if lower:find(token, 1, true) then
      return true
    end
  end
  return false
end

---Scan only tracked sources; ignore working-tree artifacts and personal data.
---@param root string
---@return string[]
function M.scan(root)
  local result = vim.system({ "git", "ls-files", "-z" }, { cwd = root, text = false }):wait()
  assert(result.code == 0, "git ls-files failed: " .. tostring(result.stderr))

  local findings = {}
  for path in (result.stdout or ""):gmatch("[^%z]+") do
    if should_scan(path) then
      if M.is_legacy(path) then
        findings[#findings + 1] = "legacy path: " .. path
      end
      local absolute = vim.fs.joinpath(root, path)
      local ok, lines = pcall(vim.fn.readfile, absolute)
      assert(ok, "cannot read tracked source: " .. absolute)
      for index, line in ipairs(lines) do
        if M.is_legacy(line) then
          findings[#findings + 1] = string.format("%s:%d: %s", path, index, vim.trim(line))
        end
      end
    end
  end
  table.sort(findings)
  return findings
end

return M
