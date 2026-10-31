-- Obsidian's optional vault is configured only at the Lazy callback boundary.
local M = {}

---@param note table
---@return table
function M.frontmatter(note)
  if note.id == "AGENTS" or note.id == "CLAUDE" or note.id == "SKILL" then
    return {}
  end

  -- Keep the legacy portable local-time format (no POSIX-only strftime tokens).
  local now = os.date("%Y-%m-%d %H:%M:%S")
  local result = {
    id = note.id,
    aliases = note.aliases,
    tags = note.tags,
    created = now,
    modified = now,
  }
  if type(note.metadata) == "table" then
    for key, value in pairs(note.metadata) do
      result[key] = value
    end
    if note.metadata.modified ~= nil then
      result.modified = now
    end
  end
  return result
end

---@param vault string
---@return table
function M.options(vault)
  return {
    legacy_commands = false,
    workspaces = { { name = "knowledge base", path = vim.fn.expand(vault) } },
    frontmatter = { func = M.frontmatter },
  }
end

---@param opts table
function M.setup(opts)
  require("obsidian").setup(opts)
  vim.opt_local.conceallevel = 2
end

return M
