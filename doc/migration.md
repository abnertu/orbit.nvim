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
| `OrbitSettings` command | Migration decision required | User mappings, documentation, commands |

A case-insensitive code search identified old identifiers across runtime files, fixtures, docs and CI. The source scanner also checks type annotations and files under test directories.

## Existing behavior to preserve

- Startup-on-demand must not load plugins twice or replay existing observers.
- Invalid JSON must not replace an accepted settings snapshot.
- Live updates must roll back changed editor options on failure.
- Hangar retains its own persisted state and view defaults.
- Core tests remain hermetic and external integrations run against real fixtures.
- Windows shell, native builds, JSON URI handling and file paths stay covered.
- SQL queries, snippets, Roslyn selection and buffer-lifetime behavior remain covered.

## Migration order

1. Freeze current behavior and identify external contracts.
2. Introduce the `orbit` namespace and independent setup APIs.
3. Define per-module schemas and generate the combined JSON Schema.
4. Move editor, keymaps, settings commands and startup with contract tests. Independent core events now have a separate module. Core scalar editor options and Compose/JSX detection now use module schemas.
5. Move theme, UI and navigation without redundant providers.
6. Move LSP, completion and language tooling with their existing tests.
7. Move Hangar, DAP, SQL, Markdown and platform integrations.
8. Rename public commands, persisted references and repository metadata.
9. Run Linux CI, Windows validation and a final old-name audit.

Do not rename the GitHub repository until install instructions and external references have a migration plan. Do not replace the stable default branch before the new startup tests pass.
