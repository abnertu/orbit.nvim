# orbit.nvim

A modular Neovim configuration with independently configurable features and generated settings documentation.

[![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io/)

> Development preview: this package now contains modular editor, navigation, language tooling, and plugin integrations. It is not yet a drop-in replacement for the legacy configuration.

## Install with Neovim's native package loader

Neovim can load orbit.nvim directly from its built-in `pack/start` directory. A separate plugin manager is not required.

1. In Neovim, run `:echo stdpath('data')` to find the platform-specific data directory.
2. Clone this repository into `<data-dir>/site/pack/orbit/start/orbit.nvim`. Replace `<data-dir>` with the reported path.
3. Add the following lines to your Neovim `init.lua` under `stdpath('config')`:

```lua
-- Load the package before calling its Lua API during init.lua.
vim.cmd.packadd("orbit.nvim")
require("orbit").setup()
```

4. Restart Neovim and verify `:OrbitSettings info` is available.

The explicit `:packadd` is necessary when requiring the package during `init.lua`. The automatic `pack/start` scan occurs later in Neovim's startup sequence.

`plugins.enabled` defaults to `false`. The installation above loads Orbit's native features without downloading Lazy or any managed plugins. Enable Lazy only after choosing a pre-existing Lazy checkout or an explicit `bootstrap = true` configuration.

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

The `plugins` Lazy import delegates to `orbit.plugins`, which reads the same module manifest as the configuration system. Each feature can expose `spec()` and is independently configurable using LuaDoc. The ported plugin specs include `mini.icons`, `gitsigns.nvim`, `vim-matchup`, `indent-blankline.nvim`, `trouble.nvim` and `todo-comments.nvim`. The Trouble LSP-reference callback retains its close/reopen workaround. The Mason module now exposes the original `Mason`, `MasonInstall` and `MasonUpdate` commands, PATH skip policy, registry and package icons through LuaDoc. Standard LSP servers now have an independently configurable native LSP owner. They activate at `VeryLazy`, with common diagnostics, Blink-capability fallback and Lua/Python/JSON/YAML defaults. Roslyn and TypeScript tools now have a dedicated LuaDoc-configured provider owner, with Roslyn solution selection and TypeScript-specific diagnostics. Real TypeScript LSP diagnostics and Hangar persisted-state/NUI sessions have pinned Linux/Windows integration coverage; real Roslyn and backend debug sessions remain pending. Hangar has an independent opt-in-state-preserving Lazy owner with the canonical legacy tool registry, JSON state path and `:Hangar` command. Hangar saved enablement now gates standard LSP registrations, and its per-filetype formatter/linter selections reach Conform and nvim-lint. Python debugpy launch/attach adapters and DAP UI now have LuaDoc-owned configuration. Hangar controls whether Python and CoreCLR adapters activate. The `dotnet` module declares dotnet-cli.nvim with Comet. It provides `DotnetManager`, `DotnetBuild`, `DotnetPublish`, `DotnetGlobalJson`, `DotnetDebug`, `DotnetAttach` and `<leader>ud`, and it owns CoreCLR registration. Real debug sessions remain unverified. The Tree-sitter owner now includes the parser manager, context and autotag specs, plus a guarded FileType start hook. `:TSInstallAll` installs every parser in the Hangar registry and never replaces a user command. C# SQL query predicates and T-SQL fallback have hermetic tests, and pinned real C#/SQL grammar injections run on Linux and Windows; broader grammar parity remains pending. Conform now owns the manual format mapping, filetype formatter defaults and one-operation-per-buffer async lifecycle. SQLFluff formatter and linter entries share project configuration discovery and a bundled T-SQL fallback. Other project-specific formatter command resolution and full progress UI parity remain pending; pinned Hangar tool ordering has integration coverage. Oil and nvim-tree now own explorer shortcuts, Windows watcher settings and the CreateFile event; Harpoon now owns its buffer list and navigation callbacks. The nvim-lint module now owns debounced event scheduling, language defaults and skipping SQLFluff on TextChanged, while project-aware tool resolution remains outstanding. The Snacks module now owns the original picker, Git, search and buffer key bindings and redraw workaround. Custom dashboard artwork and full picker layout parity are separate tasks. Gitsigns preserves legacy unstaged and staged glyphs, and loads on the one-shot `User FilePost` event. Both expose settings through LuaDoc.

```lua
require("orbit").setup({
  modules = {
    plugins = { enabled = true, bootstrap = true,
      path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim" },
    icons = { enabled = true, mock_devicons = true },
  },
})
```

Completion uses independent Blink, LuaSnip, autopairs, and Lazydev specs. LuaDoc settings control documentation, command-line completion, and snippet history. JSX and SQL snippet filetype extensions are preserved. The 105-template T-SQL collection loads through `luasnippets/tsql.lua`; upstream CI verifies real parser expansion. Pinned input tests verify Blink windows, candidate acceptance, snippet navigation, and Escape and InsertLeave cleanup. Commandline tests cover native colon demand, candidate navigation, acceptance, execution, cancellation, and forward/backward search. Separate children verify Noice integration and independent owner disabling. These tests use Blink's Lua matcher. Rust distribution, native regex builds, terminal paste transports, other custom snippets, and dynamic popup sizing remain separate acceptance tasks.

Commandline completion handles a colon and command prefix sent in one input batch, including first activation. Tests cover rapid execution, cancellation, replacement commandlines, search-first startup, and disabled commandline completion. Delayed initialization cannot recover input from a departed or changed commandline. This coverage uses Neovim's input API; terminal paste transports require separate verification.

The `messages` module contributes a VeryLazy Noice spec for commandline, notification, popupmenu, and LSP message presentation. Its LuaDoc options control those features and popup size limits. Noice is not imported during normal setup; its runtime configuration runs only when Lazy activates the spec. Pinned Linux/Windows tests verify formatter notifications render in a real NUI floating popup. Actual input also verifies commandline rendering, Blink coordination, cancellation, reopening, and disabled-owner controls. Native popupmenu rendering, LSP presentation, and theme parity remain unverified.

Plugin specifications are not evaluated during normal startup when the Lazy owner is disabled. More legacy features still require migration.

Pinned upstream startup tests cover native package loading, dashboard rendering, file and directory arguments, and mapped Oil/nvim-tree windows. Directory arguments set cwd without automatically opening an explorer. Dashboard artwork, themes, and broader explorer workflows remain unverified.

The Markdown module contributes command- and filetype-lazy markdown-preview.nvim. Its build adapter checks the installed executable version before running the upstream platform installer. The preview toggle and installer timeout are restart-only LuaDoc settings. CI uses local process fixtures; upstream browser rendering is not yet verified.

The Markdown module also supports an optional Obsidian vault. Set `modules.markdown.vault` to a directory to expose the filetype-lazy Obsidian spec. The vault path and enablement are restart-only. Frontmatter preserves legacy metadata and updates the modified timestamp. Pinned real Obsidian vault setup, Markdown buffer attachment and frontmatter save are now tested on Linux and Windows. Other vault workflows and custom Markdown highlight queries remain unverified.

The `keyguide` module restores the legacy which-key group labels, the `<leader>wK` listing and `<leader>wk` query. It loads `folke/which-key.nvim` through Lazy only when demanded, without Base46 cache dependencies. Its `preset` and `border` settings come from LuaDoc and require restart.

The `menu` module loads mouse context menus through Lazy on right-click in Normal or Visual mode. Set `modules.menu.enabled = false` before activation to disable it. This setting requires restart. File and tree menus keep the existing action owners and configured save and format shortcuts.

Closing a menu restores its temporary LeftMouse and Escape mappings. User replacements made while a menu is open survive cleanup. One Escape also closes a menu opened inside a Visual selection. Activated right-click mappings remain Lazy-owned until restart.

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

The corekeys module owns `<C-s>` for save, `<C-h/j/k/l>` for window navigation, tab-local `<Tab>` / `<S-Tab>` buffer cycling through the `orbit.buffers` order owner, and the legacy visual `J/K` line-move callbacks. Its fixed editing mappings restore previous user bindings when disabled.

The keymaps module owns `<leader>bn` for a new buffer, `<leader>fd` for project-root navigation, `<leader>tf` for diagnostics, `<leader>uc` for the current settings command, and `<leader>/` for native Normal/Visual comments. `<leader>fu` converts DOS line endings to Unix, and `<leader>fi` reloads Big5 content and writes UTF-8. Conversion shortcuts modify files only when invoked. Leader changes and disabled modules restore user-owned physical mappings.

The events module owns diagnostic redraw, startup buffers, directory arguments and an optional one-shot `User FilePost` event. FilePost fires only when a named normal file is ready after UI entry, then replays FileType to attach delayed plugin observers. Each behavior can be disabled independently.

The filetypes module registers Compose YAML and JSX detection with optional custom type names. Disabling it restores the prior matching rules.

Each module receives validated defaults for omitted options. Set `enabled = false` to skip a module during setup. Saved JSON overrides can be loaded with `setup_from_file(path)` and reapplied with `reload_from_file(path)`. Unchanged options preserve local editor overrides. File watching is opt-in through `watch_settings(path)` and can be stopped with `unwatch_settings()`.

On Windows, the `system` module also provides the explicit `:ClearShada` recovery command. It removes only regular `*.tmp` files in the current and legacy ShaDa directories; it never deletes `main.shada`, other files, or directories. Settings are defined in the module's LuaDoc. No files are deleted during setup.

The `python_tools` module restores the explicit `:PyrightReCreateStub` command. Select an existing directory under project `typings/` to regenerate it. The previous directory remains in a temporary backup until Pyright succeeds; failed processes restore the original contents. The command never runs during editor startup and requires the `pyright` executable only when used.

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
