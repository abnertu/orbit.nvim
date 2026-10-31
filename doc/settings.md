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
Live reload, restart-only options and schema-linked editor commands require separate verified changes.
