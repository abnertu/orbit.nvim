# Architecture

The public entry point is `require("orbit").setup(opts)`. It validates all options before any module activates.

## Module contract

- A module lives in `lua/orbit/modules/<name>/`.
- Its `init.lua` exports `setup(opts)`, `capture()`, `restore(snapshot)` and, for plugin owners, `spec()`.
- LuaDoc in `init.lua` declares the option types, defaults, bounds and descriptions.
- Defaulted fields use `---@field name? type`. The generator removes `?` from JSON property names.
- `spec()` returns a `LazySpec` list and imports no external plugin.
- Runtime side effects stay in `runtime.lua` files or in Lazy callbacks.

Orbit settings use local LuaDoc contracts for JSON validation. Plugin options and callbacks use upstream types where available.
LazyDev adds installed libraries for annotation-only references, including `LazySpec` and Snacks option classes.
The project LuaLS configuration leaves library discovery to Neovim and LazyDev.

`lua/orbit/modules/manifest.json` orders module activation. The runtime, the Lazy import and the schema generator read this manifest. No second feature inventory exists.

## Option rules

- An omitted option takes its declared default.
- An unknown option, an invalid type or JSON null fails before any module activates.
- An explicit `false` stays `false`.
- Arrays replace earlier arrays.
- Nested LuaDoc classes produce closed objects with derived defaults.
- Use `vim.tbl_extend("force", ...)` for flat overlays and `vim.tbl_deep_extend("force", ...)` for nested maps.
- Fields with `@restart(true)` apply only after a restart. Later setup calls defer them and report them through `get_pending_restart()`.

## Ownership

| Component | Responsibility |
| --- | --- |
| `lua/orbit/init.lua` | Public setup, transactional activation and rollback |
| `lua/orbit/config.lua` | Option validation and defaults |
| `lua/orbit/settings.lua` | JSON settings input, reload, watch and atomic updates |
| `lua/orbit/modules/manifest.json` | Module inventory and activation order |
| `lua/orbit/modules/*/init.lua` | Settings contract and module owner |
| `lua/orbit/plugins/init.lua` | Lazy spec import built from the manifest |
| `lua/orbit/buffers.lua` | Tab-local order of loaded, listed buffers |
| `lua/orbit/sqlfluff.lua` | Shared SQLFluff configuration for Conform and nvim-lint |
| `lua/orbit/tooling/schema.lua`, `scripts/generate_schema.lua` | Deterministic schema generation |
| `settings.schema.json` | Generated schema; do not edit |

## Lifecycle

- Setup is transactional. When a module fails, Orbit restores every module from its `capture()` snapshot.
- Owners restore replaced options, mappings, commands and filetype rules when they disable or roll back.
- Owners create their autocommand groups once and reuse them on repeated setup.
- Orbit never replaces a user-defined command.
- Activated plugin managers and loaded plugins are restart-only. Orbit does not claim rollback of external plugin state.

## Plugin loading

The `plugins` module owns Lazy. It is disabled by default.

- It registers one package searcher and one demand-event group.
- Lazy starts on the first demand event or on a lookup of a missing module.
- An attached UI starts an installed Lazy during setup, so Lazy times `UIEnter` after start plugins.
- New file observer groups receive missed demand events. Existing observers are not replayed.
- Late one-shot UI callbacks receive the first `UIEnter`, including Lazy's startup timer.
- `bootstrap = true` clones Lazy on first demand. A lockfile pins the commit. An existing checkout is never replaced.
- The owner keeps Orbit's runtime and `after` directories through Lazy's runtimepath reset.
- `import` defaults to `orbit.plugins`. Each module adds its specs from `spec()`.

Keep plugin loading with Lazy and tool state with hangar.nvim.

## Startup events

- The `events` module owns core events, the DiagnosticChanged redraw and the one-shot `User FilePost` event.
- FilePost fires once after UI entry, when a named normal buffer is ready.
- After FilePost, the owner sends FileType to that buffer again, so late filetype observers attach.
- When `vim.g.editorconfig` is on, it then applies EditorConfig to the same buffer.
- Directory arguments set the working directory. They do not open an explorer.
- Opening a file removes an unused Orbit startup buffer. User-created, visible or edited scratch buffers remain.

## Editor and keys

- `editor` owns global, buffer-local and window-local option defaults and keeps each option in its scope.
- `corekeys` owns save, window navigation, buffer cycling and fixed editing keys. Escape is an expression mapping that does not load plugins.
- Buffer-local LSP navigation follows client attachment and restores prior mappings after the last client detaches.
- `keymaps` owns leader actions, conversions, comments and the theme picker. Terminal keys call the terminal owner.
- `terminal` owns shell selection, window geometry and saved sessions. Setup and rollback preserve running sessions.
- Buffer cleanup checks every candidate first and refuses modified buffers. It never runs `%bd|e#`.
- Terminals open horizontal splits below and vertical splits right. They reuse live jobs and replace exited jobs.
- Terminal argv preserves quoted shell paths and explicit flags. Windows PowerShell defaults to `-NoLogo` when no flags exist.
- With no explicit Windows shell, terminals prefer pwsh, then Windows PowerShell, with profiles enabled and `-NoLogo`.
- `statusline` and `tabline` set only the global options through `%!` expressions and restore the previous values.
- Trouble loads on `LspAttach` and supplies the statusline symbol path. The render loop never imports external plugins.
- The theme owns bar and plugin highlights. [Appearance](appearance.md) records their sources and rendering contracts.
- `colors` draws swatches for hex codes in visible rows and uses the built-in LSP document color provider.

## Language tools

- `mason` owns Mason, hangar.nvim and the Hangar registry. The registry is the canonical inventory of Mason packages, parsers and tool metadata.
- hangar.nvim gates LSP, DAP, Conform, nvim-lint and Tree-sitter from saved state. No consumer calls Hangar.
- `lsp` registers generic servers once at `VeryLazy`. It does not register Roslyn or TypeScript tools.
- `lsp_providers` owns Roslyn and TypeScript tools. Roslyn selects a unique root solution. TypeScript tools removes semantic tokens and filters duplicate tsserver diagnostics.
- `formatter` (Conform) and `linter` (nvim-lint) declare their tools; Hangar filters them. Each async operation belongs to one buffer and stops when the buffer is wiped.
- `treesitter_plugins` owns parsers, context and autotag. `:TSInstallAll` installs the registry parsers.
- `dap` registers debugpy launch and attach, closes DAP UI when a session ends, and delegates CoreCLR to the `dotnet` owner.
- `mason` declares the command-lazy package manager. It does not enable servers.

## UI plugins

- `theme` declares tokyonight and applies Orbit highlight overrides after each colorscheme. A theme selection saves only to an existing settings file.
- `snacks` owns pickers, layouts, the dashboard and the notifier filter.
- The dashboard refreshes startup statistics after `LazyVimStarted`, including when Lazy starts during `UIEnter`.
- `messages` owns Noice routes and popups at the Lazy callback boundary.
- `completion` owns Blink, LuaSnip, autopairs and Lazydev. Its callbacks are restart-only.
- `menu` owns right-click menus. A menu temporarily owns Escape and LeftMouse and restores them on close.
- `navigation` owns Oil, nvim-tree and Harpoon. `layout` owns Edgy side windows.
- `markdown` owns markdown-preview.nvim and an optional Obsidian vault. Its build records the installed release in `app/bin/.orbit-version`.
- Vault activation sets `conceallevel=2` in Markdown windows and can replace the Markdown highlight query. Both changes are restart-only.

## Tests

- Offline suites use hermetic Lua fixtures and local Git checkouts. They do not download plugins.
- Live suites use the `lazy-lock.json` plugin commits and pinned tools. They run on Linux and Windows.
- `scripts/test.lua` runs each suite in its own process with private XDG directories.
