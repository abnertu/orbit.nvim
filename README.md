# orbit.nvim

A modular Neovim configuration with independently configurable features and generated settings documentation.

[![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io/)

> Development preview: this package currently implements only the editor and keymaps modules. It does not replace the existing configuration yet.

## Requirements

- Neovim 0.12 or newer.
- Git for the tracked-source identifier check.

No external plugin is needed for the current preview modules.

## Try the preview

Run these commands from the extracted `orbit.nvim` directory:

```sh
nvim --clean --cmd "set rtp^=." -c "lua require('orbit').setup()"
```

The command loads the public API without replacing your personal configuration.

Automation scripts and tests run through Neovim Lua with no Python dependency.

## Configure modules

Call the root API with module-specific options:

```lua
require("orbit").setup({
  modules = {
    editor = {
      number = true,
      relativenumber = false,
      shiftwidth = 4,
    },
    keymaps = {
      leader = " ",
      save = "<leader>w",
    },
  },
})
```

Each module receives validated defaults for omitted options. Set `enabled = false` to skip a module during setup. The current preview does not support live reload or persisted JSON settings.

## Generate the JSON Schema

Each module owns a `schema.json` beside its Lua entry point. `lua/orbit/modules/manifest.json` defines the activation order. The generator combines these files into `settings.schema.json`.

```sh
nvim --headless -u NONE -l scripts/generate_schema.lua
nvim --headless -u NONE -l scripts/generate_schema.lua --check
nvim --headless -u NONE -l tests/schema_spec.lua
nvim --headless -u NONE -l scripts/check_legacy_names.lua
```

Do not edit `settings.schema.json` manually.

## Development status

The migration is staged to protect existing startup behavior, commands, mappings, tool state and Windows support. Read [architecture](doc/architecture.md) and [migration](doc/migration.md) for planned boundaries and acceptance checks.

The current prototype is not production-ready. The complete plugin, language tooling and settings workflows remain in the existing configuration until ported and verified.

## Continuous validation

`.github/workflows/validate.yml` runs schema checks, Lua tests, identifier checks and a headless Neovim smoke test. It runs on Linux and Windows for pushes and pull requests. It also runs daily on the default branch and supports manual dispatch.

A scheduled GitHub Actions run is not real-time monitoring. GitHub may delay scheduled jobs. The workflow becomes active after you publish this repository.

Source repository: [abnertu/orbit.nvim](https://github.com/abnertu/orbit.nvim).
