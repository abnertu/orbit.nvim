# Migration from orbitvim

This is a migration inventory and an implementation plan, not a claim of feature parity.

## Identifier families

| Old form | Target | Required checks |
| --- | --- | --- |
| `OrbitVim` in messages and docs | `orbit.nvim` | README, CI, diagnostics, tests |
| `orbitvim` in internal symbols | `orbit` | Lua requires, function names, type annotations |
| `vim.g.orbitvim_*` | Encapsulated settings or `vim.g.orbit_*` only where needed | Code, tests, fixtures, public overrides |
| `ORBITVIM_*` | `ORBIT_*` if needed | CI, test subprocesses, Windows shell |
| `OrbitVim*` autocmd groups | `Orbit*` names with clear owners | Repeated setup and teardown |
| `orbitvim-*` Tree-sitter predicates | `orbit-*` | Queries, predicate registration, parser tests |
| NvChad and Base46 cache paths | Explicit theme adapter | `chadrc.lua`, theme runtime, caches |
| `OrbitSettings` command | Keep `:OrbitSettings`, allow a configured name | Command registration, leader shortcut, saved paths |

A case-insensitive code search identified old identifiers across runtime files, fixtures, docs and CI. The source scanner also checks type annotations and files under test directories.

## Existing behavior to preserve

- Startup-on-demand must not load plugins twice or replay existing observers.
- Invalid JSON must not replace an accepted settings snapshot.
- Live updates must roll back changed editor options on failure.
- Hangar retains its own persisted state and view defaults.
- Core tests remain hermetic and external integrations run against real fixtures.
- Windows shell, native builds, JSON URI handling and file paths stay covered.
- SQL queries, snippets, Roslyn selection and buffer-lifetime behavior remain covered.

## Current migration state

The module manifest orders runtime setup and Lazy specs. LuaDoc in each owning `init.lua` generates the settings schema. No feature module supplies a handwritten schema.

- Core editor options, filetypes, independent events, settings commands, Windows ShaDa recovery, Pyright stub recovery, and transactional rollback now have Lua tests.
- Core mappings cover saving, windows, buffers, native comments, project navigation, terminal reuse, theme selection, and explicit encoding conversions.
- Smart Escape, keyguide groups, and explicit buffer cleanup now have native Neovim tests.
- Plugin owners cover Snacks, navigation, Harpoon, Markdown, Tree-sitter, LSP, completion, DAP, Mason, Conform, nvim-lint, and Hangar.
- Pinned real upstream Linux/Windows tests exercise icons, Git signs, LuaSnip T-SQL, WhichKey, Noice, Trouble, Harpoon, Conform, and nvim-lint.
- A real nvim-dap client performs an attach and breakpoint handshake against a pure-Lua TCP adapter. Backend debuggee sessions remain unverified.
- Native `packadd` installation and root initialization have an isolated local-checkout acceptance test.

## Outstanding legacy contracts

- Verify Escape/menu/snippet cleanup against real completion UI and plugin sessions.
- Verify long-running terminal processes and window restoration with real Windows shell sessions.
- Verify theme reload integration, dashboard artwork, and remaining highlight ownership.
- Verify editorconfig replay, custom snippet collections, SQLFluff commands, and language-specific integrations.
- Run actual Tree-sitter grammar injections and live Roslyn, TypeScript, DAP, and plugin sessions on both platforms.
- Audit renamed commands, persisted state, public keys, README installation steps, performance, and release rules.

## Completion order

1. Finish core keymap, terminal and plugin-coupled event contracts with real Neovim tests.
2. Verify remaining theme, navigation and UI behaviors against the legacy repository.
3. Run upstream plugin, parser, formatter, LSP and debugger integrations without substituting source-only assertions.
4. Complete naming and persisted-state audits, documentation and startup performance checks.
5. Record Linux and Windows integration evidence, clean reviews and release readiness in [Roadmap #1](https://github.com/abnertu/orbit.nvim/issues/1).

Do not rename the GitHub repository until installation instructions and external references have a migration plan. Keep the legacy configuration's default branch unchanged.
