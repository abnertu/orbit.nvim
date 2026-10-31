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

The Markdown owner contributes the legacy preview Lazy command and filetype entry points. Its build adapter verifies the platform executable version after installation. CI checks its process boundary without downloading upstream plugins. Browser rendering and Obsidian vault integration remain separate acceptance tasks.

The completion owner configures Blink, LuaSnip, autopairs and Lazydev only at Lazy callback boundaries. It keeps snippet filetype extensions and its own InsertLeave cleanup. Full custom snippets and live resizing remain separate parity checks.

The `orbit.plugins` spec import scans the module manifest. Modules that implement `spec()` contribute Lazy declarations without a second feature inventory. `lua/plugins/init.lua` is only a compatibility import shim. The navigation module owns Oil and nvim-tree specs, Windows watcher settings and one FileCreated-to-CreateFile observer. Harpoon integration is a separate owner.

The nvim-lint module debounces triggers per buffer, skips SQLFluff while editing, and cancels pending timers on buffer wipe. Windows command quoting, custom project tool resolution and Hangar ordering remain separate integration tasks.

The shared SQLFluff adapter resolves project configuration, process roots and stdin arguments for Conform and nvim-lint. It uses a bundled T-SQL fallback only when no project SQLFluff section exists.

The Conform formatter module keeps async requests owned by one buffer and cleans up pending operations when a buffer is wiped. It retains language formatter defaults, but needs Hangar ordering and project-specific command adapters before full parity.

The Tree-sitter module contributes parser, context and autotag specs. Parser activation is guarded by buffer/filetype validity and excludes bigfile buffers. SQL-specific injection predicates and legacy syntax fallback remain planned.

The native LSP module uses LuaDoc-owned server flags and a single registration boundary. It preserves shared diagnostics and language defaults. Roslyn and TypeScript tools are independent provider-owned Lazy specs, not registered by generic LSP; Hangar activation gating now filters standard LSP servers, Conform and nvim-lint through one optional bridge. The bridge does not import Hangar until its Lazy owner has initialized; DAP now registers debugpy launch/attach and provides Hangar-compatible adapter controls. CoreCLR delegates to dotnet-cli, and DAP UI listeners are installed once. Real Python/.NET debug sessions remain pending. The Hangar registry is the canonical source for Mason packages, parsers and tool metadata. Its owner sets state paths and adapters before event-loaded consumers read tool settings.

The Mason module owns only the command-lazy package manager declaration and its settings. It does not register or enable LSP servers, which require a separate runtime lifecycle.

The Snacks module owns the legacy picker shortcuts and the narrow invalid-window redraw guard. Theme, dashboard art and extended picker layout migration remain separate.

The diagnostics_plugins owner contributes Trouble and todo-comments. Its LSP-reference handler and TODO-picker entry points are covered by Lua fixtures; Snacks integration is pending its own module.

The independent editor_plugins owner contributes vim-matchup and indent-blankline. Its init callback owns the matchup globals, and its indent hook is registered only at Lazy config time. Existing theme highlights remain a separate migration requirement.

The icons and git owners produce Lazy declarations without loading external code. The git owner preserves the original staged and unstaged glyph defaults and uses the one-shot FilePost event.

The first-demand integration test combines a local locked Git checkout, the module manifest spec import and file observer replay in a single Neovim process. It does not require external plugins or network access.

The opt-in plugin module owns one package searcher and one demand-event group. It initializes an existing Lazy installation on first use. Newly registered file observers receive only the missed event. Setup does not clone plugins or require the network. First demand may clone the stable Lazy source when explicitly authorized by `bootstrap = true`. The optional lockfile pins the checkout. Existing installations are never replaced by bootstrap. All plugin options are restart-only because loaded plugins cannot be rolled back.

Keep plugin loading with Lazy until a separate benchmark and compatibility plan approves another owner. Keep tool state and operations with hangar.nvim. Keep the configuration registry and runtime adapters within orbit.nvim.

The editor module owns core statusline, clipboard, mouse, indentation and signcolumn defaults. Its schema declares every migrated scalar option.

The corekeys module owns the original bindings for its five key slots and restores them during reconfiguration, disable and rollback. It does not depend on plugins or the leader key.

The events module owns core Neovim events and the legacy one-shot `User FilePost` signal. It emits FilePost once after UI entry and a named normal buffer are ready. It resends FileType only to that buffer to attach newly available filetype observers.

The events module owns only standalone core events. It registers callbacks once and disables them through state instead of destroying an event group needed for rollback.

The commands module owns the settings command and restores its registration after failed activation. It does not replace other commands.

The filetypes module owns only Compose YAML and JSX detection. It captures the existing Neovim registry entries before registration and restores them on rollback or disable.

Port each feature behind the public module contract. Preserve previous behavior until the feature's targeted checks pass. Avoid persistent compatibility aliases that hide old names in new code.

Keep startup side effects outside module imports. Complete asynchronous work only while its buffer or owner remains valid. Every module must implement `capture(opts)` and `restore(snapshot)` beside `setup(opts)`. The root captures all modules before activation and restores activated modules in reverse order on failure. Repeated setup must replace owned mappings and subscriptions instead of duplicating them.

## Tooling language

Write executable tooling and tests in Lua. Use Neovim as the Lua host to reuse `vim.json`, filesystem APIs and process execution. Keep only the generated `settings.schema.json`, the manifest and GitHub Actions YAML as data formats. Add non-Lua code only when a specific requirement cannot be met reasonably with Lua, and document the exception.

C# SQL injection queries use the `after/queries/c_sharp/injections.scm` extension. The Lua predicates exclude undecodable escape sequences and allow independently configured comment and SQL-name detection. Actual parser compatibility remains an upstream integration gate.

SQL Server highlighting also uses `after/queries/sql/highlights.scm` and the focused `syntax/tsql.vim` fallback. Explicit buffer and global dialect preferences take precedence. Markdown SQL fences retain user mappings.
