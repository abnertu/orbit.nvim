return {
  {
    "<leader>uD",
    function()
      require("snacks").dashboard()
    end,
    desc = "open dashboard",
  },
  {
    "<leader>un",
    function()
      require("snacks").picker.notifications()
    end,
    desc = "notification history",
  },

  -- find
  {
    "<leader>bd",
    function()
      require("snacks").bufdelete()
    end,
    desc = "close current buffer",
  },
  {
    "<leader>bb",
    function()
      require("snacks").picker.buffers()
    end,
    desc = "find buffers",
  },
  {
    "<leader>fc",
    function()
      require("snacks").picker.files({ cwd = vim.fn.stdpath("config") })
    end,
    desc = "find config file",
  },
  {
    "<leader>ff",
    function()
      require("snacks").picker.files()
    end,
    desc = "find files",
  },
  {
    "<leader>fg",
    function()
      require("snacks").picker.git_files()
    end,
    desc = "find git files",
  },
  {
    "<leader>fp",
    function()
      require("snacks").picker.projects()
    end,
    desc = "find projects",
  },
  {
    "<leader>fr",
    function()
      require("snacks").picker.recent()
    end,
    desc = "find recent files",
  },

  -- git
  {
    "<leader>gb",
    function()
      require("snacks").picker.git_branches()
    end,
    desc = "git branches",
  },
  {
    "<leader>gl",
    function()
      require("snacks").picker.git_log()
    end,
    desc = "git log",
  },
  {
    "<leader>gL",
    function()
      require("snacks").picker.git_log_line()
    end,
    desc = "git log line",
  },
  {
    "<leader>gs",
    function()
      require("snacks").picker.git_status()
    end,
    desc = "git status",
  },
  {
    "<leader>gS",
    function()
      require("snacks").picker.git_stash()
    end,
    desc = "git stash",
  },
  {
    "<leader>gd",
    function()
      require("snacks").picker.git_diff()
    end,
    desc = "git diff (hunks)",
  },
  {
    "<leader>gf",
    function()
      require("snacks").picker.git_log_file()
    end,
    desc = "git log file",
  },

  -- grep
  {
    "<leader>sb",
    function()
      require("snacks").picker.lines()
    end,
    desc = "buffer lines",
  },
  {
    "<leader>sB",
    function()
      require("snacks").picker.grep_buffers()
    end,
    desc = "grep open buffers",
  },
  {
    "<leader>sg",
    function()
      require("snacks").picker.grep()
    end,
    desc = "grep files",
  },
  {
    "<leader>sw",
    function()
      require("snacks").picker.grep_word()
    end,
    desc = "grep selection or word",
    mode = { "n", "x" },
  },

  -- search
  {
    '<leader>s"',
    function()
      require("snacks").picker.registers()
    end,
    desc = "registers",
  },
  {
    "<leader>s/",
    function()
      require("snacks").picker.search_history()
    end,
    desc = "search history",
  },
  {
    "<leader>sa",
    function()
      require("snacks").picker.autocmds()
    end,
    desc = "autocmds",
  },
  {
    "<leader>sc",
    function()
      require("snacks").picker.command_history()
    end,
    desc = "command history",
  },
  {
    "<leader>sC",
    function()
      require("snacks").picker.commands()
    end,
    desc = "commands",
  },
  {
    "<leader>sd",
    function()
      require("snacks").picker.diagnostics()
    end,
    desc = "diagnostics",
  },
  {
    "<leader>sD",
    function()
      require("snacks").picker.diagnostics_buffer()
    end,
    desc = "buffer diagnostics",
  },
  {
    "<leader>sh",
    function()
      require("snacks").picker.highlights()
    end,
    desc = "highlights",
  },
  {
    "<leader>sH",
    function()
      require("snacks").picker.highlights({ pattern = "hl_group:^Snacks" })
    end,
    desc = "snack highlights",
  },
  {
    "<leader>si",
    function()
      require("snacks").picker.icons()
    end,
    desc = "icons",
  },
  {
    "<leader>sj",
    function()
      require("snacks").picker.jumps()
    end,
    desc = "jumps",
  },
  {
    "<leader>sk",
    function()
      require("snacks").picker.keymaps()
    end,
    desc = "keymaps",
  },
  {
    "<leader>sl",
    function()
      require("snacks").picker.loclist()
    end,
    desc = "location list",
  },
  {
    "<leader>s'",
    function()
      require("snacks").picker.marks()
    end,
    desc = "marks",
  },
  {
    "<leader>sM",
    function()
      require("snacks").picker.man()
    end,
    desc = "man pages",
  },
  {
    "<leader>sp",
    function()
      require("snacks").picker.lazy()
    end,
    desc = "search for plugin spec",
  },
  {
    "<leader>sq",
    function()
      require("snacks").picker.qflist()
    end,
    desc = "quickfix list",
  },
  {
    "<leader>sR",
    function()
      require("snacks").picker.resume()
    end,
    desc = "resume picker",
  },
  {
    "<leader>su",
    function()
      require("snacks").picker.undo()
    end,
    desc = "undo history",
  },

  -- other
  {
    "<leader>gg",
    function()
      require("snacks").lazygit()
    end,
    desc = "lazygit",
  },
}
