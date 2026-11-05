# Appearance

Orbit preserves orbitvim's default Tokyo Night palette and its active highlight integrations.
Other colorschemes supply their own foreground, background and accent colors.

## Reference

The comparison used these local revisions:

| Source | Revision |
| --- | --- |
| `orbitvim` | `da6e3b3713e3b6247a05c1b1f4ad5f81a6ad18c1` |
| `Orbit-Lua/nv-base46` | `29fb906a950ba20288c436fe6ec3d7e934f988df` |
| `Orbit-Lua/nv-ui` | `1f96dd253fe7c4d1f4c106209e58c8c12771106e` |

The theme tables contain adapted nv-base46 highlight definitions.
Their license is stored in `lua/orbit/modules/theme/BASE46-LICENSE`.
Runtime rendering does not import nv-base46 or nv-ui.

## Ownership

| Area | Preserved appearance | Owner |
| --- | --- | --- |
| Editor | Current line number, gutters, selection, search, folds, floats and separators | `theme/editor.lua` |
| Syntax | Vim syntax, Tree-sitter captures and Tokyo Night polish | `theme/editor.lua`, `theme/runtime.lua` |
| Diagnostics | Severity colors, virtual backgrounds, inlay hints and terminal-aware underlines | `theme/runtime.lua` |
| Plugin UI | Blink, Git, nvim-tree, Mason, which-key, TODO and icon compatibility groups | `theme/plugins.lua` |
| Custom UI | Hangar, Noice, Snacks, Harpoon and Volt menu colors | `theme/runtime.lua` |
| Statusline | Rounded mode, workspace and position blocks; file and symbol paths; diagnostic and Git icons | `statusline/` |
| Tabline | Explorer offset, 21-cell buffer entries, colored icons and separate modified and close colors | `tabline/` |
| Debugger | Breakpoint, condition, rejected, logpoint and stopped signs | `dap/runtime.lua` |

The editor enables `cursorline` with `cursorlineopt=number`.
Option reloads preserve unchanged window overrides.
The tabline shows the explorer offset and buffers, matching orbitvim's module order.
Trouble loads on `LspAttach` and owns symbol requests and refreshes.
The statusline reuses one symbol provider and never loads plugins from its render loop.
The statusline renderer owns the spacing between sections. `modules.statusline.gap` sets its width.
File icons retain their source foreground and use the surrounding bar's background.
Menu opening reapplies owned colors after Volt installs fallback highlights.
Dotnet Manager uses `NormalFloat` and `FloatBorder` for its panels, independent of Volt highlight availability.

## Verification

The migration compared original attributes across 375 active highlight groups.
It corrected two nvim-tree information links from nonexistent `DiagnosticNormal` to `DiagnosticInfo`.
Unused CMP, Telescope, dashboard and cheatsheet integrations remain absent.

Offline tests cover rendered icons, symbol formatting, palette stability, current-line settings, rollback and menu colors.
Manual live tests exercise pinned Trouble symbol requests and real Tokyo Night colorscheme changes.
