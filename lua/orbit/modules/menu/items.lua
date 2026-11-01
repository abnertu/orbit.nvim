-- Legacy item groups dispatch through their existing action owners.
local M = {}

---@class Orbit.MenuSource
---@field win integer
---@field buf integer

---@class Orbit.MenuTreeNode
---@field absolute_path string
---@field name string
---@field type string

---@class Orbit.MenuItem
---@field name string
---@field cmd? fun()
---@field rtxt? string
---@field hl? string
---@field keybind? string
---@field items? Orbit.MenuItem[]

---@param source Orbit.MenuSource
---@param action fun()
---@return fun()
local function deferred(source, action)
  return function()
    require("orbit.modules.menu.runtime").close()
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(source.win)
        or not vim.api.nvim_buf_is_valid(source.buf)
        or vim.api.nvim_win_get_buf(source.win) ~= source.buf then return end
      local ok, err = pcall(vim.api.nvim_win_call, source.win, action)
      if not ok then vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Context Menu" }) end
    end)
  end
end

---@param source Orbit.MenuSource
---@return fun(name: string, lhs: string, hl?: string): Orbit.MenuItem
local function key_items(source)
  return function(name, lhs, hl)
    return { name = name, rtxt = lhs, hl = hl, cmd = deferred(source, function()
      local keys = lhs:gsub("<leader>", function() return vim.g.mapleader or "\\" end)
        :gsub("<localleader>", function() return vim.g.maplocalleader or "\\" end)
      vim.api.nvim_feedkeys(vim.keycode(keys), "m", false)
    end) }
  end
end

---@param source Orbit.MenuSource
---@return Orbit.MenuItem[]
function M.general(source)
  local config = assert(require("orbit").get_config())
  local item = key_items(source)
  return {
    item("󰆓  Save File", config.modules.corekeys.save, "ExGreen"),
    item("󰆏  Copy Whole File", "<C-c>", "ExBlue"),
    item("󰉼  Format File", config.modules.formatter.key, "ExYellow"),

    { name = "separator" },

    {
      name = "  Code",
      keybind = "c",
      hl = "ExBlue",
      items = {
        item("󰅩  Code Action", "<leader>ca", "ExYellow"),
        item("󰑕  Rename Symbol", "<leader>cr", "ExBlue"),
        item("󰈔  Go to Definition", "gd"),
        item("󰈔  Go to Declaration", "gD"),
        item("󰈔  Go to Implementation", "gI"),
        item("󰊄  Go to Type Definition", "gy"),
        item("  Find References", "gR"),
        item("  Show Diagnostic", "<leader>tf", "ExYellow"),
        item("󰆏  Toggle Comment", "<leader>/"),
      },
    },
    {
      name = "󰍉  Find",
      keybind = "f",
      hl = "ExBlue",
      items = {
        item("󰈞  Files", "<leader>ff"),
        item("󰊢  Git Files", "<leader>fg"),
        item("󰋚  Recent Files", "<leader>fr"),
        item("󰓩  Buffers", "<leader>bb"),
        item("󰱼  Buffer Lines", "<leader>sb"),
        item("󰊄  Grep Files", "<leader>sg"),
        item("  Diagnostics", "<leader>sd", "ExYellow"),
        item("  Buffer Diagnostics", "<leader>sD", "ExYellow"),
        item("  Config Files", "<leader>fc"),
      },
    },
    {
      name = "󰓩  Buffer",
      keybind = "b",
      hl = "ExYellow",
      items = {
        item("  New Buffer", "<leader>bn", "ExGreen"),
        item("󰒭  Next Buffer", "<Tab>"),
        item("󰒮  Previous Buffer", "<S-Tab>"),
        item("󰅖  Close Buffer", "<leader>x", "ExRed"),
        item("󰱝  Close Other Buffers", "<leader>bD", "ExRed"),
        item("󰉋  Set Cwd to File Root", "<leader>fd"),
      },
    },
    {
      name = "  Terminal",
      keybind = "t",
      hl = "ExGreen",
      items = {
        item("  New Horizontal Terminal", "<leader>h"),
        item("  New Vertical Terminal", "<leader>v"),
        item("  Toggle Horizontal Terminal", "<M-h>"),
        item("  Toggle Vertical Terminal", "<M-v>"),
        item("󰉈  Toggle Floating Terminal", "<M-i>"),
      },
    },
    {
      name = "󰒓  Tools",
      keybind = "u",
      hl = "ExYellow",
      items = {
        item("󰕮  Dashboard", "<leader>uD"),
        item("󰂚  Notification History", "<leader>un"),
        item("󰒋  Hangar", "<leader>us"),
        item("󰒓  Settings", "<leader>uc"),
        item("󰏘  Theme Picker", "<leader>ut", "ExBlue"),
        item("󰑓  Reload Theme", "<leader>ur"),
        item("󰊢  LazyGit", "<leader>gg", "ExGreen"),
      },
    },
  }
end

---@param source Orbit.MenuSource
---@return Orbit.MenuItem[]
function M.tree(source)
  local winid = source.win
  ---@param name string
  ---@param lhs string
  ---@param action fun()
  ---@param hl? string
  ---@return Orbit.MenuItem
  local function action_item(name, lhs, action, hl)
    return { name = name, rtxt = lhs, hl = hl, cmd = deferred(source, action) }
  end
  local api = require("nvim-tree.api")
  local node = vim.api.nvim_win_call(winid, api.tree.get_node_under_cursor)

  ---@param action fun(node: Orbit.MenuTreeNode)
  ---@return fun()
  local function node_action(action)
    return function()
      assert(node, "No tree node under the clicked cursor")
      action(node)
    end
  end

  return {
    action_item("  Open", "o", node_action(api.node.open.edit), "ExGreen"),
    action_item(
      "󰈙  Open Preview",
      "<Tab>",
      node_action(api.node.open.preview),
      "ExBlue"
    ),
    action_item(
      "  Open in Vertical Split",
      "<C-v>",
      node_action(api.node.open.vertical)
    ),
    action_item(
      "  Open in Horizontal Split",
      "<C-x>",
      node_action(api.node.open.horizontal)
    ),
    action_item(
      "󰓩  Open in New Tab",
      "<C-t>",
      node_action(api.node.open.tab)
    ),

    { name = "separator" },

    action_item(
      "  Create File or Directory",
      "a",
      node_action(api.fs.create),
      "ExGreen"
    ),
    action_item("󰑕  Rename", "r", node_action(api.fs.rename), "ExYellow"),
    action_item(
      "󰑕  Rename without Extension",
      "e",
      node_action(api.fs.rename_basename),
      "ExYellow"
    ),
    action_item("󰆴  Trash", "D", node_action(api.fs.trash), "ExRed"),
    action_item("  Delete", "d", node_action(api.fs.remove), "ExRed"),

    { name = "separator" },

    {
      name = "  Clipboard",
      keybind = "c",
      hl = "ExBlue",
      items = {
        action_item("  Cut", "x", node_action(api.fs.cut), "ExYellow"),
        action_item("󰆏  Copy", "c", node_action(api.fs.copy.node), "ExBlue"),
        action_item("󰆒  Paste", "p", node_action(api.fs.paste), "ExGreen"),
        action_item("󰆾  Move", "gp", node_action(api.fs.move), "ExYellow"),
      },
    },
    {
      name = "󰅍  Copy Path",
      keybind = "y",
      hl = "ExBlue",
      items = {
        action_item("󰈔  Filename", "y", node_action(api.fs.copy.filename)),
        action_item("󰈔  Basename", "ge", node_action(api.fs.copy.basename)),
        action_item(
          "󰝰  Relative Path",
          "Y",
          node_action(api.fs.copy.relative_path)
        ),
        action_item(
          "󰝰  Absolute Path",
          "gy",
          node_action(api.fs.copy.absolute_path)
        ),
      },
    },
    {
      name = "  Tree",
      keybind = "t",
      hl = "ExYellow",
      items = {
        action_item("󰑓  Refresh", "R", api.tree.reload, "ExGreen"),
        action_item("󰘕  Collapse All", "W", api.tree.collapse_all),
        action_item("󰘖  Expand All", "E", node_action(api.tree.expand_all)),
        action_item(
          "󰘓  Toggle Dotfiles",
          "H",
          api.filter.dotfiles.toggle,
          "ExYellow"
        ),
        action_item("󰋖  Help", "g?", api.tree.toggle_help, "ExBlue"),
        action_item("󰅖  Close", "q", api.tree.close, "ExRed"),
      },
    },
  }
end

return M

