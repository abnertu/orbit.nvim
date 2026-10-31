# Architecture

The public entry point is `require("orbit").setup(opts)`. It validates all declared options before activating modules.

## Module contract

A module lives in `lua/orbit/modules/<name>/`. Its `init.lua` exports `setup(opts)`. Its `schema.json` declares each option, type, bound, default and description.

The explicit `manifest.json` orders module activation. Both the runtime and the schema generator read this manifest. No second module inventory is maintained.

An omitted option takes its declared default. An unknown option or invalid type fails before any module activates. An explicit `false` is retained. Arrays will replace previous arrays when the persistent settings layer is introduced.

## Ownership

| Component | Responsibility |
| --- | --- |
| `lua/orbit/init.lua` | Public setup and activation order |
| `lua/orbit/config.lua` | Option validation and defaults |
| `lua/orbit/modules/manifest.json` | Module inventory and activation order |
| `lua/orbit/modules/*/schema.json` | Per-module option contract |
| `lua/orbit/modules/*/init.lua` | Module activation and runtime owner |
| `scripts/generate_schema.py` | Deterministic bundle generation |
| `settings.schema.json` | Generated editor-facing schema, not an editable source |

## Future integration

Keep plugin loading with Lazy until a separate benchmark and compatibility plan approves another owner. Keep tool state and operations with hangar.nvim. Keep the configuration registry and runtime adapters within orbit.nvim.

Port each feature behind the public module contract. Preserve previous behavior until the feature's targeted checks pass. Avoid persistent compatibility aliases that hide old names in new code.

Keep startup side effects outside module imports. Complete asynchronous work only while its buffer or owner remains valid. Repeated setup must replace owned mappings and subscriptions instead of duplicating them.
