# Saved settings

Use `require("orbit").setup_from_file(path)` to read JSON settings. The path is optional.
The default path is `stdpath("data") .. "/settings.json"`.

Missing input uses module defaults. Reading does not create or rewrite any file.

## Validation

`settings.schema.json` is generated from LuaDoc in each module's `init.lua`.
No per-module `schema.json` files are authored.
Objects merge by field, and explicit `false` values are preserved.
Unknown keys, invalid types, out-of-range values, and JSON null are rejected before activation.

The public call returns `true` on success, or `false, err` on failure.
Failed reads and validation keep the previously accepted configuration.
Users can inspect effective options through `require("orbit").get_config()`.

## Scope

This is an explicit startup input, not automatic file watching.
Module activation is transactional for the current editor and keymaps owners. A failed activation restores captured editor options and affected key bindings, without replacing the accepted configuration. A failed rollback reports its errors and requires a restart.
An explicit `require("orbit").reload_from_file(path)` reads and validates the file again. Only changed module options are applied. When an editor module option changes, unrelated local option overrides remain untouched. Invalid input and failed activation preserve accepted options and their captured runtime values.

## Optional save observation

Call `require("orbit").watch_settings(path)` to watch a specific settings JSON file after loading it. Saving that file inside Neovim triggers the same validated, transactional reload. An unrelated file save has no effect.

Repeated calls replace the observer rather than stacking callbacks. Call `require("orbit").unwatch_settings()` to remove it. Invalid saves produce a warning and leave accepted values active; the input file is never rewritten.

File watching is opt-in. Schema-linked editor commands remain separate work.

## Restart-only settings

Fields marked `@restart(true)` in module LuaDoc apply on first setup. Later setup and saved-settings reload defer changed restart-only values. Other validated fields apply immediately.

`require("orbit").get_config()` reports active values. `require("orbit").get_pending_restart()` returns deferred requested values keyed by their `orbit.modules.*` paths. Restart Neovim to apply them. If a reload fails, both active and pending values remain unchanged.

Nested restart-only fields defer independently. Arrays with restart-only members defer as a whole. The current preview marks the startup buffer and directory argument event options as restart-only.

When loading from an explicit path, the settings command retains that path across reloads. An explicit `modules.commands.path` value in the JSON file takes precedence.
