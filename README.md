# orbit.nvim

A modular Neovim configuration with independently configurable features and generated settings documentation.

[![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io/)

> Development preview: this package implements editor, filetype, keymaps and settings-command modules. It does not replace the existing configuration yet.

## Requirements

- Neovim 0.12 or newer.
- Git for the tracked-source identifier check.

No plugin is downloaded by startup or CI. Lazy integration is opt-in, requiring an existing installation.

```lua
require("orbit").setup({
  modules = {
    plugins = {
      enabled = true,
      path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim",
      import = "plugins",
    },
  },
})
```

When enabled at first setup, Lazy initializes on the first demand event or missing-module lookup. Plugin options are restart-only. This module does not clone or update Lazy.

## Try the preview

Run these commands from the extracted `orbit.nvim` directory:

```sh
nvim --clean --cmd "set rtp^=." -c "lua require('orbit').setup()"
```

The command loads the public API without replacing your personal configuration.

Automation scripts and tests run through Neovim Lua with no Python dependency.

## Configure modules

Call the root API with module-specific options:

```lua
require("orbit").setup({
  modules = {
    editor = {
      number = true,
      relativenumber = false,
      shiftwidth = 4,
    },
    keymaps = {
      leader = " ",
      save = "<leader>w",
    },
  },
})
```

The editor module exposes configurable statusline, clipboard, mouse, signcolumn, undo and file-format defaults.

The corekeys module owns `<C-s>` for save and `<C-h/j/k/l>` for window navigation. Each key is independently configurable and restores the previous mapping when disabled.

The events module owns diagnostic statusline redraw, unnamed startup buffers and directory startup arguments. Each behavior can be disabled independently.

The filetypes module registers Compose YAML and JSX detection with optional custom type names. Disabling it restores the prior matching rules.

Each module receives validated defaults for omitted options. Set `enabled = false` to skip a module during setup. Saved JSON overrides can be loaded with `setup_from_file(path)` and reapplied with `reload_from_file(path)`. Unchanged options preserve local editor overrides. File watching is opt-in through `watch_settings(path)` and can be stopped with `unwatch_settings()`.

## Saved settings

`require("orbit").setup_from_file(path)` loads JSON overrides and validates them before activation. If `path` is omitted, it reads `stdpath("data") .. "/settings.json"`. Missing files use defaults. Invalid input leaves the accepted configuration unchanged.

```lua
local ok, err = require("orbit").setup_from_file()
if not ok then
  vim.notify(err, vim.log.levels.ERROR)
end
```

Reading never creates or rewrites the file. See [saved settings](doc/settings.md) for precedence and current limitations.

Startup-only fields use `@restart(true)` in their owning module's `init.lua` LuaDoc. On later setup or reload, changes to those fields are deferred while safe fields apply immediately. `require("orbit").get_pending_restart()` returns the requested values by field path. Restart Neovim to activate them. The current preview marks the two startup event options as restart-only.

## Settings command

`:OrbitSettings` opens the settings file and creates it only when missing, with a reference to the generated schema. `:OrbitSettings reload` validates and applies saved options. `:OrbitSettings info` shows accepted values. Configure its name or path through `modules.commands`.

## Generate the JSON Schema

Each module declares its settings entirely in LuaDoc annotations inside `init.lua`. The manifest defines activation order. The generator parses those annotations into `settings.schema.json`, so no module-specific schema file is authored.

```lua
---@class Orbit.ExampleOptions # Example module settings.
---@field enabled boolean @default(true) # Enable this module.
---@field size integer @default(2) @minimum(0) @maximum(16) # Indentation width.
---@field label string @default(" ") @minLength(1) # Display label.
---@field style 'compact'|'wide' @default("compact") # Display style.
```

Nested LuaDoc classes and arrays are also supported:

```lua
---@class Orbit.PanelOptions # Panel display settings.
---@field width integer @default(2) @minimum(1) @maximum(12) # Panel width.

---@class Orbit.ExampleOptions # Example module settings.
---@field enabled boolean @default(true) # Enable this module.
---@field panel Orbit.PanelOptions @default({}) # Individual panel.
---@field panels Orbit.PanelOptions[] @default([]) # Active panels.
---@field labels string[] @default([]) # Panel labels.
```

Nested objects inherit their member defaults. Arrays are validated by element type and replace previous arrays. The generator rejects recursive class references and unknown types. For composite types, use empty `@default({})` and `@default([])`.

Use `@restart(true)` to mark a field that cannot safely change in a running session. The generated schema exposes `x-orbit-restart: true`. A nested restart-only field defers independently; arrays containing restart-only fields defer as a whole.

Primitive field types and LuaLS literal unions are supported. The metadata provides defaults and bounds. The text following `#` is the schema description. Unsupported types or missing defaults fail schema generation.

```sh
nvim --headless -u NONE -l scripts/generate_schema.lua
nvim --headless -u NONE -l scripts/generate_schema.lua --check
nvim --headless -u NONE -l tests/schema_spec.lua
nvim --headless -u NONE -l tests/settings_spec.lua
nvim --headless -u NONE -l scripts/check_legacy_names.lua
```

Do not edit `settings.schema.json` manually.

## Development status

The migration is staged to protect existing startup behavior, commands, mappings, tool state and Windows support. Read [architecture](doc/architecture.md) and [migration](doc/migration.md) for planned boundaries and acceptance checks.

The current prototype is not production-ready. The complete plugin, language tooling and settings workflows remain in the existing configuration until ported and verified.

## Continuous validation

`.github/workflows/validate.yml` runs schema checks, Lua tests, identifier checks and a headless Neovim smoke test. It runs on Linux and Windows for pushes and pull requests. It also runs daily on the default branch and supports manual dispatch.

A scheduled GitHub Actions run is not real-time monitoring. GitHub may delay scheduled jobs. The workflow becomes active after you publish this repository.

Source repository: [abnertu/orbit.nvim](https://github.com/abnertu/orbit.nvim).
