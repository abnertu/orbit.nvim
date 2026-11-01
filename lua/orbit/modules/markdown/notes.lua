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

local group

-- The upstream query conceals code fences. Replace it so fences and their
-- language labels stay visible at conceallevel=2. A query that fails to
-- parse, such as without an installed parser, leaves the upstream query.
---@return boolean
function M.apply_highlights()
  local path = vim.api.nvim_get_runtime_file("lua/orbit/modules/markdown/highlights.scm", false)[1]
  if not path then return false end
  local text = table.concat(vim.fn.readfile(path), "\n")
  local ok, err = pcall(vim.treesitter.query.parse, "markdown", text)
  if not ok then
    vim.notify("Markdown highlights unchanged: " .. tostring(err),
      vim.log.levels.WARN, { title = "orbit.nvim notes" })
    return false
  end
  vim.treesitter.query.set("markdown", "highlights", text)
  -- Existing highlighters keep their parsed query until restarted.
  for buffer, _ in pairs(vim.treesitter.highlighter.active) do
    if vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].filetype == "markdown" then
      vim.treesitter.stop(buffer)
      pcall(vim.treesitter.start, buffer, "markdown")
    end
  end
  return true
end

-- Conceal is window-local per buffer, so other buffers shown later in the
-- same window keep their own value.
local function conceal_markdown(buffer)
  if vim.bo[buffer].filetype == "markdown" and vim.api.nvim_get_current_buf() == buffer then
    vim.opt_local.conceallevel = 2
  end
end

---@param opts Orbit.ObsidianOptions
---@param highlights? boolean
function M.setup(opts, highlights)
  require("obsidian").setup(opts)
  -- Lazy activation is restart-only; the group is created once.
  if not group then
    group = vim.api.nvim_create_augroup("OrbitMarkdownNotes", { clear = true })
    vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
      group = group,
      callback = function(args) conceal_markdown(args.buf) end,
      desc = "Conceal Markdown markup in note windows",
    })
  end
  conceal_markdown(vim.api.nvim_get_current_buf())
  if highlights ~= false then M.apply_highlights() end
end

return M
