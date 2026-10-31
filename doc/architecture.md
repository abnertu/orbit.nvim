# Architecture

The public entry point is `require("orbit").setup(opts)`. It validates all declared options before activating modules.

## Module contract

A module lives in `lua/orbit/modules/<name>/`. Its `init.lua` exports `setup(opts)` and documents the options with LuaDoc. The LuaDoc includes types, defaults, bounds and descriptions. The schema generator reads source comments without evaluating the module.

The explicit `manifest.json` orders module activation. Both the runtime and the schema generator read this manifest. No second module inventory is maintained.

An omitted option takes its declared default. An unknown option or invalid type fails before any module activates. An explicit `false` is retained. Arrays replace earlier arrays when overrides are applied. Nested LuaDoc classes produce closed objects with derived defaults.

## Ownership

| Component | Responsibility |
| --- | --- |
| `lua/orbit/init.lua` | Public setup and activation order |
| `lua/orbit/config.lua` | Option validation and defaults |
| `lua/orbit/settings.lua` | JSON settings input and validation before explicit activation |
| `lua/orbit/modules/manifest.json` | Module inventory and activation order |
| `lua/orbit/modules/*/init.lua` LuaDoc | Per-module settings contract and type hints |
| `lua/orbit/modules/*/init.lua` | Module activation and runtime owner |
| `lua/orbit/tooling/schema.lua` and `scripts/generate_schema.lua` | Deterministic bundle generation |
| `settings.schema.json` | Generated editor-facing schema, not an editable source |

## Future integration

The opt-in plugin module owns one package searcher and one demand-event group. It initializes an existing Lazy installation on first use. Newly registered file observers receive only the missed event. Setup does not clone plugins or require the network. First demand may clone the stable Lazy source when explicitly authorized by `bootstrap = true`. The optional lockfile pins the checkout. Existing installations are never replaced by bootstrap. All plugin options are restart-only because loaded plugins cannot be rolled back.

Keep plugin loading with Lazy until a separate benchmark and compatibility plan approves another owner. Keep tool state and operations with hangar.nvim. Keep the configuration registry and runtime adapters within orbit.nvim.

The editor module owns core statusline, clipboard, mouse, indentation and signcolumn defaults. Its schema declares every migrated scalar option.

The corekeys module owns the original bindings for its five key slots and restores them during reconfiguration, disable and rollback. It does not depend on plugins or the leader key.

The events module owns only standalone core events. It registers callbacks once and disables them through state instead of destroying an event group needed for rollback.

The commands module owns the settings command and restores its registration after failed activation. It does not replace other commands.

The filetypes module owns only Compose YAML and JSX detection. It captures the existing Neovim registry entries before registration and restores them on rollback or disable.

Port each feature behind the public module contract. Preserve previous behavior until the feature's targeted checks pass. Avoid persistent compatibility aliases that hide old names in new code.

Keep startup side effects outside module imports. Complete asynchronous work only while its buffer or owner remains valid. Every module must implement `capture(opts)` and `restore(snapshot)` beside `setup(opts)`. The root captures all modules before activation and restores activated modules in reverse order on failure. Repeated setup must replace owned mappings and subscriptions instead of duplicating them.

## Tooling language

Write executable tooling and tests in Lua. Use Neovim as the Lua host to reuse `vim.json`, filesystem APIs and process execution. Keep only the generated `settings.schema.json`, the manifest and GitHub Actions YAML as data formats. Add non-Lua code only when a specific requirement cannot be met reasonably with Lua, and document the exception.
