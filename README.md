# orbit.nvim

A modular Neovim configuration with independently configurable features and generated settings documentation.

[![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io/)

> Development preview: this package now contains modular editor, navigation, language tooling, and plugin integrations. It is not yet a drop-in replacement for the legacy configuration.

## Requirements

- Neovim 0.12 or newer.
- Git for the tracked-source identifier check.

No plugin is downloaded during default startup or CI. Lazy integration is opt-in; an existing checkout or explicit first-demand bootstrap is required.

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

When enabled at first setup, Lazy initializes on the first demand event or missing-module lookup. Plugin options are restart-only.

Set `bootstrap = true` to clone Lazy only when first demanded and not already installed. The default Git source is `https://github.com/folke/lazy.nvim.git`. When a `lazy-lock.json` exists, the bootstrap checks out its `lazy.nvim` commit, rather than the current stable head. The optional `lockfile` and `source` fields support custom locations and hermetic local Git tests. No network is needed for CI.

## Declarative plugin features

The `plugins` Lazy import delegates to `orbit.plugins`, which reads the same module manifest as the configuration system. Each feature can expose `spec()` and is independently configurable using LuaDoc. The ported plugin specs include `mini.icons`, `gitsigns.nvim`, `vim-matchup`, `indent-blankline.nvim`, `trouble.nvim` and `todo-comments.nvim`. The Trouble LSP-reference callback retains its close/reopen workaround. The Mason module now exposes the original `Mason`, `MasonInstall` and `MasonUpdate` commands, PATH skip policy, registry and package icons through LuaDoc. Standard LSP servers now have an independently configurable native LSP owner. They activate at `VeryLazy`, with common diagnostics, Blink-capability fallback and Lua/Python/JSON/YAML defaults. Roslyn and TypeScript tools now have a dedicated LuaDoc-configured provider owner, with Roslyn solution selection and TypeScript-specific diagnostics. Real server and Hangar provider-state verification remain pending; Hangar now has an independent opt-in-state-preserving Lazy owner with the canonical legacy tool registry, JSON state path and `:Hangar` command. Hangar saved enablement now gates standard LSP registrations, and its per-filetype formatter/linter selections reach Conform and nvim-lint. Python debugpy launch/attach adapters and DAP UI now have LuaDoc-owned configuration. Hangar controls whether Python and CoreCLR adapters activate. The CoreCLR adapter is registered by the separate dotnet-cli provider; real debug sessions remain unverified. The Tree-sitter owner now includes the parser manager, context and autotag specs, plus a guarded FileType start hook. C# SQL query predicates and T-SQL fallback now have hermetic tests; real grammar integration remains pending. Conform now owns the manual format mapping, filetype formatter defaults and one-operation-per-buffer async lifecycle. SQLFluff formatter and linter entries share project configuration discovery and a bundled T-SQL fallback. Other project-specific formatter command resolution, Hangar ordering and progress UI remain pending. Oil and nvim-tree now own explorer shortcuts, Windows watcher settings and the CreateFile event; Harpoon now owns its buffer list and navigation callbacks. The nvim-lint module now owns debounced event scheduling, language defaults and skipping SQLFluff on TextChanged, while project-aware tool resolution remains outstanding. The Snacks module now owns the original picker, Git, search and buffer key bindings and redraw workaround. Custom dashboard artwork and full picker layout parity are separate tasks. Gitsigns preserves legacy unstaged and staged glyphs, and loads on the one-shot `User FilePost` event. Both expose settings through LuaDoc.

```lua
require("orbit").setup({
  modules = {
    plugins = { enabled = true, bootstrap = true,
      path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim" },
    icons = { enabled = true, mock_devicons = true },
  },
})
```

Completion has an independent Blink/LuaSnip/autopairs/Lazydev owner, with LuaDoc-configured documentation, command-line and snippet history. JSX and SQL snippet filetype extensions are preserved. The legacy 105-template T-SQL LuaSnip collection is now namespaced under `orbit` and loads through `luasnippets/tsql.lua`; real parser expansion runs in dedicated upstream CI. Other custom snippets, dynamic popup sizing and full real upstream completion tests remain pending.

The `messages` module contributes a VeryLazy Noice spec for commandline, notification, popupmenu, and LSP message presentation. Its LuaDoc options control those features and popup size limits. Noice is not imported during normal setup; its runtime configuration runs only when Lazy activates the spec. Real upstream Noice rendering remains unverified.

Plugin specifications are not evaluated during normal startup when the Lazy owner is disabled. More legacy features still require migration.

The Markdown module contributes command- and filetype-lazy markdown-preview.nvim. Its build adapter checks the installed executable version before running the upstream platform installer. The preview toggle and installer timeout are restart-only LuaDoc settings. CI uses local process fixtures; upstream browser rendering is not yet verified.

The Markdown module also supports an optional Obsidian vault. Set `modules.markdown.vault` to a directory to expose the filetype-lazy Obsidian spec. The vault path and enablement are restart-only. Frontmatter preserves legacy metadata and updates the modified timestamp. Custom Markdown highlight queries and real vault workflows still require upstream verification.

The `keyguide` module restores the legacy which-key group labels, the `<leader>wK` listing and `<leader>wk` query. It loads `folke/which-key.nvim` through Lazy only when demanded, without Base46 cache dependencies. Its `preset` and `border` settings come from LuaDoc and require restart.

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

The corekeys module owns `<C-s>` for save, `<C-h/j/k/l>` for window navigation, tab-local `<Tab>` / `<S-Tab>` buffer cycling, and the legacy visual `J/K` line-move callbacks. Its fixed editing mappings restore previous user bindings when disabled.

The keymaps module owns `<leader>bn` for a new buffer, `<leader>fd` for project-root navigation, `<leader>tf` for diagnostics, `<leader>uc` for the current settings command, and `<leader>/` for native Normal/Visual comments. `<leader>fu` converts DOS line endings to Unix, and `<leader>fi` reloads Big5 content and writes UTF-8. Conversion shortcuts modify files only when invoked. Leader changes and disabled modules restore user-owned physical mappings.

The events module owns diagnostic redraw, startup buffers, directory arguments and an optional one-shot `User FilePost` event. FilePost fires only when a named normal file is ready after UI entry, then replays FileType to attach delayed plugin observers. Each behavior can be disabled independently.

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

Startup-only fields use `@restart(true)` in their owning module's `init.lua` LuaDoc. On later setup or reload, changes to those fields are deferred while safe fields apply immediately. `require("orbit").get_pending_restart()` returns the requested values by field path. Restart Neovim to activate them. Startup-only fields include event, plugin, Markdown and other integration options; inspect the generated schema for the active list.

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

`.github/workflows/validate.yml` runs schema checks, Lua tests, identifier checks and a headless Neovim smoke test. It also measures a bounded process-level startup baseline and repeated setup latency; see [performance](doc/performance.md). It runs on Linux and Windows for pushes and pull requests. It also runs daily on the default branch and supports manual dispatch.

A scheduled GitHub Actions run is not real-time monitoring. GitHub may delay scheduled jobs. GitHub Actions records the required Linux and Windows checks for each pushed development branch and pull request.

Source repository: [abnertu/orbit.nvim](https://github.com/abnertu/orbit.nvim).
