return {
  std = "luajit",
  globals = { "vim" },
  max_line_length = 100,
  max_comment_line_length = false,
  max_string_line_length = false,
  exclude_files = { ".plans/**" },
  files = {
    ["tests/live_snacks_spec.lua"] = {
      read_globals = { "Snacks" },
    },
  },
}
