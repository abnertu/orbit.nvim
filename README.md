# orbit.nvim

orbit.nvim is a modular Neovim configuration. Each feature is a module with its own validated settings, and a generated JSON Schema documents every option.

[![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io/)

## Features

- Native editor defaults, key mappings, terminals, statusline, tabline and color previews.
- Optional plugin integrations through Lazy: Snacks, Blink, LuaSnip, Noice, Oil, nvim-tree, Harpoon, Trouble, Edgy and more.
- Language tools: native LSP, Roslyn, TypeScript tools, Conform, nvim-lint, SQLFluff, Tree-sitter, nvim-dap with debugpy and CoreCLR.
- Managed tool state through Hangar and Mason.
- Saved JSON settings with validation, reload and an optional file watcher.
- Equal support for Linux and Windows.

The statusline shows file and symbol paths, diagnostic icons and Git state. Trouble supplies symbols after LSP attachment.
The tabline retains file icon colors. The editor highlights the current line number by default.

## Requirements

- Neovim 0.12 or newer.
- Git, to install orbit.nvim and optional plugins.
- External tools only for the features that use them, for example `dotnet` for Roslyn or `node` for TypeScript tools.

## Install

### As your configuration directory

Clone the repository as your Neovim configuration:

```sh
git clone https://github.com/abnertu/orbit.nvim ~/.config/nvim
```

On Windows, clone it into `~/AppData/Local/nvim`. The bundled `init.lua` enables all features. On the first start, Orbit clones Lazy and Lazy installs the plugins.

### As a package

1. In Neovim, run `:echo stdpath('data')` to find the data directory.
2. Clone this repository into `<data-dir>/site/pack/orbit/start/orbit.nvim`.
3. Add these lines to `init.lua` in `stdpath('config')`:

```lua
-- Load the package before you call its Lua API in init.lua.
vim.cmd.packadd("orbit.nvim")
require("orbit").setup({
  modules = {
    plugins = {
      enabled = true,
      bootstrap = true,
      path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim",
    },
  },
})
```

4. Restart Neovim. Then run `:checkhealth lazy` and `:OrbitSettings info`.

`:packadd` loads Orbit's plugin and `after` files before `setup()` runs, not only its Lua modules.

To try orbit.nvim without changing your configuration, run this command in the repository:

```sh
nvim --clean --cmd "set rtp^=." -c "lua require('orbit').setup()"
```

## Plugins

Most features load through Lazy. Both install methods above enable it.

- `require("orbit").setup()` without `modules.plugins.enabled = true` loads only native features and downloads nothing.
- Lazy starts on the first demand event, for example the first file read.
- `bootstrap = true` clones Lazy on first demand when the checkout is missing. It uses the `lazy.nvim` commit from `lazy-lock.json` when that file exists.
- `import` selects the Lazy spec module. The default is `orbit.plugins`, which collects the specs of all enabled modules.
- Plugin options apply only after a restart.

## Configure modules

Pass options for each module under `modules`:

```lua
require("orbit").setup({
  modules = {
    editor = { number = true, relativenumber = false, shiftwidth = 4 },
    keymaps = { leader = " ", save = "<leader>w" },
    terminal = { horizontal_size = 30, vertical_size = 20, startinsert = true },
    theme = { colorscheme = "tokyonight-night" },
    markdown = { vault = "~/notes" },
  },
})
```

- Omitted options use validated defaults.
- Set `enabled = false` to skip a module.
- Invalid options stop setup and keep the previous configuration.
- `settings.schema.json` lists every module, option, default and bound.

Use `---@type Orbit.Config` for Lua settings. Plugin options use upstream types, such as `snacks.Config` and `blink.cmp.Config`.
LazyDev resolves installed plugin types from annotations without activating the plugins.

## Saved settings

Orbit can read options from a JSON file. The default path is `stdpath("data") .. "/settings.json"`.

```lua
local ok, err = require("orbit").setup_from_file()
if not ok then
  vim.notify(err, vim.log.levels.ERROR)
end
```

- Reading never creates or changes the file.
- A missing file uses the defaults.
- Invalid input keeps the accepted configuration.
- `reload_from_file(path)` applies only the changed fields, so buffer and window overrides stay.
- `watch_settings(path)` reloads on change. `unwatch_settings()` stops it.
- Fields marked restart-only apply after a restart. `get_pending_restart()` lists them.

Add `"$schema": "<orbit.nvim>/settings.schema.json"` to the file for editor completion. See [saved settings](doc/settings.md) for the merge rules.

## Commands and keys

| Command | Owner | Action |
| --- | --- | --- |
| `:OrbitSettings` | commands | Open the settings file. It creates the file only when missing. |
| `:OrbitSettings reload` | commands | Validate and apply the saved settings. |
| `:OrbitSettings info` | commands | Show the accepted settings. |
| `:TSInstallAll` | treesitter_plugins | Install every parser in the Hangar registry. |
| `:ClearShada` | system | On Windows, remove stale ShaDa `*.tmp` files. |
| `:PyrightReCreateStub` | python_tools | Regenerate a stub directory under `typings/`. |
| `:Hangar` | hangar | Enable, disable and order managed tools. |

Orbit never replaces a user-defined command. Each module defines its keys in its LuaDoc settings. Disabling a module restores the mappings that it replaced. `<leader>wK` lists all keys when the keyguide module is enabled.

With an attached LSP, `gd`, `gD`, `gI`, `gy`, and `gR` navigate definitions, declarations, implementations, types, and references.
Orbit restores prior buffer mappings after the last client detaches.

`<leader>x` and `<leader>bd` share Snacks buffer deletion when active. Native buffer deletion also preserves split windows.
Set `modules.terminal.enabled = false` to disable terminal actions without stopping saved sessions.

Without an explicit `shell`, Windows terminals prefer available pwsh, then Windows PowerShell.
PowerShell loads profiles and suppresses its startup banner. Explicit shell choices and flags take priority.

## Development

Run the checks with [just](https://github.com/casey/just) on Linux or Windows:

| Recipe | Checks |
| --- | --- |
| `just test` | Offline Lua suites and the startup smoke test. |
| `just live` | Real plugins and tools. These suites need network and the tools that CI installs. |
| `just schema` | Generated schema, schema contracts and saved settings. |

`just test terminal` runs only the suites whose path contains `terminal`. Each suite runs in its own Neovim process with private XDG directories. A missing tool fails its suite.

`just live luadoc` checks Lua type resolution and completion with pinned plugins.
Install `lua-language-server` on `PATH` before running it locally.

Module settings are LuaDoc annotations in each module's `init.lua`. After you change them, regenerate the schema:

```sh
nvim --headless -u NONE -l scripts/generate_schema.lua
```

Do not edit `settings.schema.json` by hand. Read [architecture](doc/architecture.md) before you change module boundaries.

## Continuous integration

- `validate.yml` runs `just schema`, `just test` and `just live luadoc` on Linux and Windows.
- Validation runs on pushes, pull requests and a daily schedule on `main`.
- `live-upstream.yml` installs pinned tools and runs `just live` on Linux and Windows only when started manually.
- `release.yml` validates version tags before publishing. Releases do not run live suites.

## Releases

orbit.nvim follows [Semantic Versioning](https://semver.org/). Tags are bare versions, such as `1.1.0`. [CHANGELOG](CHANGELOG.md) lists the changes for each release.

To install a release, check out its tag in the package directory:

```sh
git -C <data-dir>/site/pack/orbit/start/orbit.nvim checkout 1.1.0
```
