# Initial rewrite review

Baseline: `Orbit-Lua/orbitvim` at `da6e3b3713e3b6247a05c1b1f4ad5f81a6ad18c1`.
Reference: `nvim-mini/mini.nvim` at `6d5a29e86a7352739506c28e0bc50fe214b5216f`.
Skill source: `abnertu/skills` at `a27ed07af44c4ca8539a00d09824170108b6f877`.

## Findings

| Priority | Finding | Evidence | Required response |
| --- | --- | --- | --- |
| High | The old name is present in runtime state, queries, CI and tests. | `lua/features/settings/config.lua`, `lua/features/treesitter/runtime.lua`, `after/queries/c_sharp/injections.scm`, `tests/support/minimal.vim` | Audit both definitions and consumers before renaming. |
| High | Settings currently derive defaults and validation from a hand-maintained bundled schema. | `lua/features/settings/config.lua`, `settings.schema.json` | Keep one source of truth. Replace handwritten aggregate schema with per-module definitions and a generator. |
| High | The schema change changes configuration layout. | `doc/settings.md`, `tests/integration/settings_schema_spec.lua` | Preserve old settings and explicit precedence through a separate migration plan. |
| High | Startup has deliberate event replay and failure behavior. | `lua/core/startup.lua`, `tests/integration/startup_demand_spec.lua` | Keep existing lifecycle contracts and run integration tests during migration. |
| High | Hangar owns persistent state and its view defaults. | `doc/architecture.md`, `lua/features/hangar/runtime.lua` | Keep saved tool state out of the new public module defaults. |
| Medium | NvChad/Base46 coupling spans theme and startup. | `init.lua`, `lua/core/startup.lua`, `lua/features/theme/spec.lua` | Make theme ownership explicit before removing the dependency. |
| Medium | Different modules use plugin `opts` and runtime setups in different ways. | `lua/features/completion/spec.lua`, `lua/features/lsp/spec.lua` | Normalize the public module setup contract without flattening all plugin-specific APIs. |
| Medium | Platform and native-build behavior is significant. | `lua/core/shell.lua`, `doc/testing.md`, `justfile` | Keep Windows as a first-class target. |

## Reference principles adopted from mini.nvim

- Treat modules as independently configurable units.
- Expose a predictable `setup(opts)` entry point per module.
- Keep defaults explicit and avoid unnecessary shared dependencies.
- Document a module's public options and runtime behavior.

The reference is architectural, not a proposal to replace the existing Lazy or Hangar owners. No migration to mini.deps is planned without an independent performance and compatibility review.

## Preview verification

- Python schema generator and contract tests: 5 passed.
- Bundled schema drift check: passed.
- Legacy source name scan: passed for the new preview only.
- Lua parser check: 6 Lua files parsed with LuaTeX, not Neovim's LuaJIT.
- English document sentence review: no sentences flagged.
- Neovim startup test: unavailable because Neovim is not installed in the validation environment.
- Windows behavioral tests: not executed.
- Runtime badge URL: not verified offline.
- The old repository has not been modified or renamed.

## Next scoped migration

Port the existing settings loader in the next plan. Preserve object merge, array replacement, invalid-input rejection, live-update rollback and saved Hangar precedence. Its tests must run under Neovim before the public interface is replaced.

## First published CI regression

The first CI run (41152935074) failed on both platforms in `tests/smoke.lua:8`. The editor module set global option defaults but did not update buffer-local `shiftwidth` in the existing buffer. The Lua-tooling migration also updates this behavior and adds a new-buffer assertion. The new CI run must confirm the fix.
