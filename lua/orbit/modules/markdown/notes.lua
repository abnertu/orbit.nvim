-- Obsidian's optional vault is configured only at the Lazy callback boundary.
local M = {}

---@class Orbit.ObsidianNote
---@field id string
---@field aliases? string[]
---@field tags? string[]
---@field metadata? table<string, any>

---@class Orbit.ObsidianFrontmatter
---@field id? string
---@field aliases? string[]
---@field tags? string[]
---@field created? string
---@field modified? string

---@alias Orbit.ObsidianOptions {legacy_commands: boolean, workspaces: {name: string, path: string}[], frontmatter: {func: fun(note: Orbit.ObsidianNote): Orbit.ObsidianFrontmatter}}

---@param note Orbit.ObsidianNote
---@return Orbit.ObsidianFrontmatter
function M.frontmatter(note)
  if note.id == "AGENTS" or note.id == "CLAUDE" or note.id == "SKILL" then
    return {}
  end

  -- Keep the legacy portable local-time format (no POSIX-only strftime tokens).
  local now = os.date("%Y-%m-%d %H:%M:%S")
  -- Preserve arbitrary frontmatter metadata. The refreshed timestamp must
  -- win even when the note supplied an earlier modified value.
  return vim.tbl_extend("force", {
    id = note.id,
    aliases = note.aliases,
    tags = note.tags,
    created = now,
  }, type(note.metadata) == "table" and note.metadata or {}, {
    modified = now,
  })
end

---@param vault string
---@return Orbit.ObsidianOptions
function M.options(vault)
  return {
    legacy_commands = false,
    workspaces = { { name = "knowledge base", path = vim.fn.expand(vault) } },
    frontmatter = { func = M.frontmatter },
  }
end

---@param opts Orbit.ObsidianOptions
function M.setup(opts)
  require("obsidian").setup(opts)
  vim.opt_local.conceallevel = 2
end

return M
