# Changelog

All notable changes to orbit.nvim are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

- Color previews stay cleared when the owner or hex previews disable before a queued refresh.
- Split windows share one color swatch for each visible hex code.
- DAP UI closes when an attach session ends.
- The Markdown preview build records the installed release, so a successful install no longer reports a failure.
- The Orbit-Lua nvim-dap fork converts breakpoint paths to backslashes only on Windows.

[Unreleased]: https://github.com/abnertu/orbit.nvim/compare/1.0.0...HEAD
[1.0.0]: https://github.com/abnertu/orbit.nvim/releases/tag/1.0.0
