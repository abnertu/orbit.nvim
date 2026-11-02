# Saved settings

Use `require("orbit").setup_from_file(path)` to read JSON settings. The path is optional.
The default path is `stdpath("data") .. "/settings.json"`.

Missing input uses module defaults. Reading does not create or rewrite any file.

## Validation

`settings.schema.json` is generated from LuaDoc in each module's `init.lua`.
No per-module `schema.json` files are authored.

Run `nvim --headless -u NONE -l scripts/generate_schema.lua` after you change module LuaDoc.
The read-only `schema-preview.yml` workflow prints numbered JSON fragments, a byte count and a SHA256 checksum on schema pull requests.
It never writes the tracked schema. Regenerate and commit the schema before validation can pass.

- Objects merge by field, and explicit `false` values stay.
- Unknown keys, invalid types, out-of-range values and JSON null fail before activation.
- The call returns `true` on success, or `false, err` on failure.
- Failed reads and failed validation keep the accepted configuration.
- `require("orbit").get_config()` returns the active options.

## Activation and reload

Every module captures its state before setup and restores it when activation fails.
A failed activation keeps the accepted configuration.
A failed rollback reports its errors and requires a restart.

`require("orbit").reload_from_file(path)` reads and validates the file again.
It applies only the changed module options, so unrelated buffer and window overrides stay.

## Optional save observation

Call `require("orbit").watch_settings(path)` to watch one settings file after you load it.
Saving that file in Neovim starts the same validated reload.
A save of another file has no effect.

Repeated calls replace the observer. Call `require("orbit").unwatch_settings()` to remove it.
An invalid save shows a warning and keeps the accepted values.

## Writes

Orbit writes the settings file only in two cases:

- `:OrbitSettings` creates the file when it is missing, with a `$schema` reference.
- A theme selected with `<leader>ut` is saved to an existing file. The write is validated and atomic, and the JSON keys are sorted.

A failed write keeps the file contents and the accepted settings.

## Restart-only settings

Fields marked `@restart(true)` in module LuaDoc apply on first setup.
Later setup and reload calls defer changed restart-only values. Other validated fields apply immediately.

- `require("orbit").get_pending_restart()` returns the deferred values keyed by their `orbit.modules.*` paths.
- Restart Neovim to apply them.
- If a reload fails, the active and pending values stay unchanged.
- Nested restart-only fields defer independently. Arrays with restart-only members defer as a whole.

When Orbit loads an explicit path, the settings command keeps that path across reloads. An explicit `modules.commands.path` value in the JSON file takes precedence.
