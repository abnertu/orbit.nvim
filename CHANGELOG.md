# Changelog

All notable changes to orbit.nvim are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A `dev` module that installs telemetry.nvim through Lazy for the test runner.

### Changed

- **Breaking:** Hangar settings moved from `modules.hangar` to `modules.mason.hangar`.
- The `mason` module owns hangar.nvim `^0.4` and its tool registry. Hangar loads even when Mason is disabled.
- The Hangar registry lists the `typescript-tools` language server.
- Lazy skips unused built-in runtime plugins: gzip, rplugin, spellfile, tar, tutor and zip.
- The tab line and `<Tab>` cycling keep listed buffers that are not loaded yet, such as argument, session, `:badd` and `:bunload` buffers. Entering one loads it.

### Fixed

- A multi-select picker confirm shows every selected file in the tab line, in selection order.
- The startup dashboard shows the real startup time on its first render instead of `0ms`.
- The startup dashboard no longer moves down one row when Noice loads.
- Hangar 0.4.2 opens the parser tab without an error and never runs a disabled linter.
- Hangar 0.4.2 installs Mason packages before Mason has a registry and repairs a broken package. An installed server attaches to open buffers.

## [1.1.0] - 2026-11-02

### Added

- An independent terminal module with validated dimensions, input mode and enablement settings.
- LuaLS acceptance checks for upstream types, aliases, class members and every module's settings on Linux and Windows.

### Changed

- Terminal actions delegate from keymaps to the terminal owner. Settings changes and rollback preserve saved sessions.
- Plugin options and callbacks use upstream LuaDoc types. Orbit settings keep their separate JSON validation contracts.

### Fixed

- Horizontal terminals open below, and vertical terminals open right, regardless of editor split preferences.
- Default Windows terminals select pwsh or Windows PowerShell, load profiles and suppress startup banners.
- Shell startup preserves quoted executable paths, paths containing spaces and explicit arguments.
- `<leader>x` shares Snacks buffer deletion with `<leader>bd`. Native buffer deletion also preserves split windows.
- LazyDev resolves `LazySpec` and annotation-only plugin types. Project configuration no longer overrides its library discovery.
- Lua settings completion includes all modules. Callback aliases and generic annotations use valid LuaDoc syntax.
- Roslyn defers executable resolution until Mason exposes its installed server.

## [1.0.0] - 2026-11-02

The first stable release. It completes the modular Lua rewrite tracked in [#1](https://github.com/abnertu/orbit.nvim/issues/1).

### Added

- Modules with LuaDoc settings, transactional setup, rollback and a generated `settings.schema.json`.
- Saved JSON settings with validation, reload, an opt-in watcher and the `:OrbitSettings` command.
- Native editor defaults, core keys, leader actions, terminals, statusline, tabline and color previews.
- Opt-in Lazy loading with a locked first-demand bootstrap and a spec import built from the module manifest.
- Plugin owners for Snacks, Blink, LuaSnip, Noice, Oil, nvim-tree, Harpoon, Trouble, Edgy, which-key, menus, tokyonight, gitsigns, todo-comments, vim-matchup and indent-blankline.
- Language owners for native LSP, Roslyn, TypeScript tools, Conform, nvim-lint, SQLFluff, Tree-sitter, Markdown preview, Obsidian, Mason and Hangar.
- Debugging with nvim-dap, debugpy launch and attach, DAP UI and CoreCLR through dotnet-cli.
- Live suites against real plugins and tools on Linux and Windows, including Roslyn, tsserver, debugpy, netcoredbg, SQLFluff, Mason and a headless browser.
- The bundled `init.lua` enables plugins and bootstraps Lazy, so a clone into the configuration directory works without extra setup.
- A `justfile` and `scripts/test.lua` that run every suite with private XDG directories.
- A release workflow for version tags.

### Changed

- **Breaking:** the default `plugins.import` is now `orbit.plugins`. `require("plugins")` no longer returns Orbit specs. Set `modules.plugins.import` to keep a custom module.
- `:ClearShada` scans only the current ShaDa directory under `stdpath("state")`.

### Removed

- The `lua/plugins/init.lua` import shim.
- The legacy name scanner, the migration notes and the review records.

### Fixed

- Mason-managed servers resolve before the Mason UI loads.
- LSP hover and navigation keys use native handlers and restore complete prior buffer mappings.
- The first semicolon opens the commandline UI, and first-demand startup completes dashboard timing.
- Opening a file releases an unused startup buffer while preserving user scratch buffers.
- Theme, statusline, tabline and debugger visuals preserve their configured colors and symbols.
- Dotnet Manager colors remain independent of context menus.
- Color previews stay cleared when the owner or hex previews disable before a queued refresh.
- Split windows share one color swatch for each visible hex code.
- DAP UI closes when an attach session ends.
- The Markdown preview build records the installed release, so a successful install no longer reports a failure.
- The Orbit-Lua nvim-dap fork converts breakpoint paths to backslashes only on Windows.

[Unreleased]: https://github.com/abnertu/orbit.nvim/compare/1.1.0...HEAD
[1.1.0]: https://github.com/abnertu/orbit.nvim/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/abnertu/orbit.nvim/releases/tag/1.0.0
