local M = {}
local accepted
local subscribed = false

---@class Orbit.NavigationOptions # Oil and nvim-tree file explorers.
---@field enabled boolean @default(true) @restart(true) # Enable explorer integrations.
---@field oil boolean @default(true) @restart(true) # Enable Oil floating explorer.
---@field tree boolean @default(true) @restart(true) # Enable nvim-tree.
---@field delete_to_trash boolean @default(true) @restart(true) # Move Oil deletions to trash.
---@field tree_width integer @default(40) @minimum(10) @maximum(200) @restart(true) # Tree window width.
---@field sync_root boolean @default(true) @restart(true) # Synchronize tree root with cwd.
---@field harpoon boolean @default(true) @restart(true) # Enable Harpoon buffer navigation.
---@field harpoon_short_path_length integer @default(8) @minimum(1) @maximum(128) @restart(true) # Harpoon display path segment limit.

function M.capture()
  return accepted and vim.deepcopy(accepted) or nil
end

function M.restore(snapshot)
  accepted = snapshot and vim.deepcopy(snapshot) or nil
end

---@param opts? Orbit.NavigationOptions
function M.setup(opts)
  accepted = require("orbit.config").resolve_module("navigation", opts)
end

local function oil_options(c)
  return {
    default_file_explorer = false,
    delete_to_trash = c.delete_to_trash,
    keymaps = {
      ["<C-h>"] = false, ["<C-l>"] = false,
      ["<C-p>"] = false, ["-"] = false,
      ["s"] = { "<cmd>write<CR>", mode = "n", desc = "sync/apply changes" },
      ["R"] = "actions.refresh",
      ["H"] = "actions.toggle_hidden",
      ["."] = "actions.cd",
      ["<BS>"] = "actions.parent",
      [";"] = { ":", mode = "n", desc = "command mode" },
    },
    float = {
      max_width = 0.9, max_height = 0.9,
      border = "rounded", preview_split = "right",
    },
  }
end

local function tree_options(c)
  local windows = vim.fn.has("win32") == 1
  return {
    filesystem_watchers = { enable = not windows },
    auto_reload_on_write = true,
    reload_on_bufenter = windows,
    filters = { dotfiles = false },
    disable_netrw = true,
    hijack_cursor = true,
    sync_root_with_cwd = c.sync_root,
    update_focused_file = { enable = true, update_root = { enable = false } },
    view = { width = c.tree_width, preserve_window_proportions = true, signcolumn = "no" },
    renderer = {
      root_folder_label = false, highlight_git = "all",
      highlight_diagnostics = "all", indent_markers = { enable = true },
      icons = {
        glyphs = {
          default = "󰈚",
          folder = { default = "", empty = "", empty_open = "", open = "", symlink = "" },
          git = { unstaged = "󰄱", staged = "󰱒", unmerged = "" },
        },
        diagnostics_placement = "right_align",
      },
    },
    diagnostics = {
      enable = true,
      icons = { error = " ", warning = " ", hint = " ", info = " " },
    },
    git = { enable = false, timeout = 200 },
  }
end

local function setup_tree(opts)
  require("nvim-tree").setup(opts)
  if subscribed then return end
  local api = require("nvim-tree.api")
  api.events.subscribe(api.events.Event.FileCreated, function()
    vim.api.nvim_exec_autocmds("User", { pattern = "CreateFile", modeline = false })
  end)
  subscribed = true
end

---@return table[]
function M.spec()
  if not accepted or not accepted.enabled then return {} end
  local c = vim.deepcopy(accepted)
  local specs = {}
  if c.oil then
    specs[#specs + 1] = {
      "stevearc/oil.nvim",
      cmd = "Oil", event = "VeryLazy",
      keys = { { "-", function()
        require("oil").toggle_float(nil, { preview = {} })
      end, desc = "oil toggle floating" } },
      opts = oil_options(c),
    }
  end
  if c.tree then
    specs[#specs + 1] = {
      "nvim-tree/nvim-tree.lua",
      keys = {
        { "<C-n>", "<cmd>NvimTreeToggle<CR>", desc = "nvimtree toggle window" },
        { "<leader>fe", "<cmd>NvimTreeFocus<CR>", desc = "nvimtree focus window" },
        { "<C-Right>", "<cmd>NvimTreeResize +5<CR>", desc = "nvimtree resize +5" },
        { "<C-Left>", "<cmd>NvimTreeResize -5<CR>", desc = "nvimtree resize -5" },
        { "<leader>fC", function() require("nvim-tree.api").fs.create() end, desc = "create file" },
      },
      opts = tree_options(c),
      config = function(_, opts) setup_tree(opts) end,
    }
  end
  if c.harpoon then
    specs[#specs + 1] = {
      "Orbit-Lua/harpoon",
      branch = "harpoon2",
      dependencies = { "nvim-lua/plenary.nvim" },
      keys = {
        { "<C-e>", function()
          local h = require("harpoon")
          h.ui:toggle_quick_menu(h:list())
        end, desc = "harpoon quick menu" },
        { "<M-S-p>", function()
          require("harpoon"):list():prev()
        end, desc = "harpoon previous item" },
        { "<M-S-n>", function()
          require("harpoon"):list():next()
        end, desc = "harpoon next item" },
        { "<leader>ba", function()
          require("harpoon"):list():add()
        end, desc = "add buffer to harpoon" },
      },
      config = function()
        require("orbit.modules.navigation.harpoon")
          .setup(c.harpoon_short_path_length)
      end,
    }
  end
  return specs
end

return M
