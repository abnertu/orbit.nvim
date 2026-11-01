# Product acceptance contract

This document defines the completion target for orbit.nvim.
The README describes currently available behavior.

## Supported boundary

- Support Linux and Windows with Neovim 0.12 or newer.
- Configure public features under the `orbit` namespace.
- Keep native setup usable without plugin downloads.
- Activate optional plugins through explicit Lazy configuration.
- Preserve user commands, mappings, files, and accepted settings during failures.
- Keep tool state with Hangar and its canonical registry.

## Functional contract

The following gates define the complete product scope.
Each gate requires an implementation owner and matching Linux and Windows evidence.
The module manifest remains the runtime feature inventory.

| Gate | Area | Required behavior |
| --- | --- | --- |
| G01 | Configuration | Validate LuaDoc-derived settings before activation. Support transactional setup, explicit saved settings, reload, watch, and collision-safe settings commands. |
| G02 | Editor | Preserve global, buffer, and window option scopes. Detect Compose and JSX files. Restore prior filetype rules when disabled. |
| G03 | Startup | Handle empty, file, and directory arguments. Preserve backing buffers, one-shot FilePost, EditorConfig application, and observer counts. |
| G04 | Editing | Provide save, copy, comments, conversions, project roots, buffer cycling, and safe buffer cleanup. Use one explicit buffer-order owner. |
| G05 | Terminals | Provide split and floating sessions. Preserve live jobs while hidden. Replace exited sessions. Restore windows and honor platform shell arguments. |
| G06 | Plugin loading | Bootstrap only with explicit opt-in. Respect locked revisions. Collect specs from module entries. Use `orbit.plugins` as the bundled import. |
| G07 | Theme and UI | Provide theme selection, reload, explicit persistence, diagnostic/plugin highlights, statusline, tabline, and color preview through independently configurable owners. |
| G08 | Dashboard and pickers | Render configured dashboard sections and picker layouts. Preserve picker navigation, notifications, statuscolumn, and auxiliary Snacks behavior. |
| G09 | File navigation | Provide Oil, nvim-tree, and Harpoon entry points. Preserve chosen files, project roots, and saved Harpoon lists across restarts. |
| G10 | Menu and discoverability | Provide file/tree context menus and keyguide groups. Preserve native selection, captured actions, temporary mappings, and complete disposal. |
| G11 | Side layouts | Provide layout toggling and window selection. Position Trouble views by their requested side without capturing unrelated windows. |
| G12 | Generic LSP | Register configured servers once. Preserve capabilities, diagnostics, keymaps, language defaults, failure isolation, and managed-tool enablement. |
| G13 | C# provider | Run Roslyn through its owner. Honor solution selection and enablement. Publish real diagnostics from a disposable C# project. |
| G14 | TypeScript provider | Run TypeScript-tools with real tsserver. Preserve provider diagnostics, inlays, semantic-token policy, and independent registration. |
| G15 | Python debugging | Launch and attach through debugpy. Reach a breakpoint, continue, disconnect, and clean UI listeners without duplicate sessions. |
| G16 | .NET tools | Provide manager, build, publish, global.json, debug, and attach commands. Delegate CoreCLR registration to the dotnet-cli owner. |
| G17 | Formatting and linting | Preserve per-buffer ownership, debounce, cancellation, and managed-tool filtering. Use real SQLFluff project configuration and stdin arguments. |
| G18 | Parsing | Provide configured parser installation, context, autotag, C#/SQL injections, and T-SQL syntax/fences. Derive bulk installation from the canonical registry. |
| G19 | Markdown preview | Build, start, update, toggle, and stop preview. Observe the resulting document through a real browser connection. |
| G20 | Notes | Attach an explicit Obsidian vault. Preserve frontmatter and agent-note exclusions. Own Markdown conceal/highlight changes and restore prior state. |
| G21 | Completion and snippets | Provide Insert and commandline completion, acceptance, search controls, snippet navigation/cleanup, T-SQL assets, JSX extensions, and supported native build paths. |
| G22 | Editor integrations | Provide icons, Git signs, diagnostics/TODO, matchup, and indentation through their real plugin entry points and highlight owners. |
| G23 | Managed tools | Use the Hangar registry for tools and parsers. Preserve state, UI ownership, selections, install operations, and activation filtering. |
| G24 | Recovery | Provide current-platform ShaDa temporary-file recovery and transactional Pyright stub regeneration. Preserve persistent files and failed-operation backups. |
| G25 | Product readiness | Verify standalone installation, combined plugin activation, current documentation, bounded startup performance, required CI, and release readiness. |

## Verification rules

1. Exercise the public entry point or actual user input for each protected contract.
2. Record the exact revision, platform, prerequisite versions, command, and result.
3. Reuse existing evidence when its scope and supported behavior match.
4. Add a stored test only for a distinct behavior contract.
5. Prove new regression tests reject the protected failure.
6. Fail required integrations when prerequisites are unavailable.
7. Obtain a clean independent review and passing platform checks before merging.

Hermetic suites use local fixtures and do not download plugins.
Separate integration workflows fetch pinned dependencies and provision their explicit tools.
Fixtures isolate configuration, caches, state, projects, vaults, and processes.

The external session targets are Roslyn, TypeScript-tools, debugpy, CoreCLR, SQLFluff, and Markdown preview.
Other registry entries retain their configuration, argument, registration, and enablement contracts.
Arbitrary external versions do not expand this fixed session matrix.

Terminal acceptance covers native Neovim input, Linux `sh`, and Windows `pwsh`.
Additional frontend transports require their own evidence.
Native completion acceptance includes matcher distribution and the LuaSnip regex build.

## Interface and data ownership

- Preserve independently configurable `setup`, `capture`, and `restore` contracts.
- Declare module options only in each owning `init.lua` LuaDoc.
- Generate the bundled settings schema from those declarations.
- Keep explicit `false`, array replacement, and restart-only behavior.
- Keep commands collision-safe and restore displaced user mappings.
- Keep plugin-manager and callback activation restart-only where rollback cannot restore external state.
- Preserve existing Orbit settings and plugin-owned persisted data.
- Create settings files only through explicit settings open.
- Persist theme selection through an explicit settings action.
- Preserve accepted settings and disk contents when a save fails.
- Keep explicit custom Lazy imports supported.
- Keep current upstream provider APIs and behavior guards where integrations require them.

## Completion gates

1. Freeze G01-G25 and their observable acceptance criteria.
2. Complete retained capabilities and their fixed platform evidence.
3. Retire project transition facilities after the final source audit.
4. Pass standalone product verification and close the completion issue.

The final package uses current Orbit interfaces and paths.
It does not require another configuration checkout, framework cache, or source comparison during normal development.
Functional regression tests, schema checks, and platform integration remain product requirements.
Release publication follows the repository's versioning and approval rules.
