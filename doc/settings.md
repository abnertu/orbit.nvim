# Saved settings

Use `require("orbit").setup_from_file(path)` to read JSON settings. The path is optional.
The default path is `stdpath("data") .. "/settings.json"`.

Missing input uses module defaults. Reading does not create or rewrite any file.

## Validation

`settings.schema.json` is generated from each module's `schema.json`.
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

File watching is opt-in. Restart-only options and schema-linked editor commands remain separate work.
