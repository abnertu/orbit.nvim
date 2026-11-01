# Architecture

The public entry point is `require("orbit").setup(opts)`. It validates all declared options before activating modules.

## Module contract

A module lives in `lua/orbit/modules/<name>/`. Its `init.lua` exports `setup(opts)` and documents the options with LuaDoc. The LuaDoc includes types, defaults, bounds and descriptions. The schema generator reads source comments without evaluating the module.

The explicit `manifest.json` orders module activation. Both the runtime and the schema generator read this manifest. No second module inventory is maintained.

Module `spec()` functions return `LazySpec`, the upstream Lazy specification type. They do not return an untyped `table[]`.

Use `vim.tbl_extend("force", ...)` for validated object overlays. Use `vim.tbl_deep_extend("force", ...)` only for nested maps that support recursive overlays. Keep arrays as replacements.

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

The Markdown owner contributes the legacy preview Lazy command and filetype entry points. Its build adapter verifies the platform executable version after installation. CI checks its process boundary without downloading upstream plugins. Browser rendering and real Obsidian vault workflows remain separate acceptance tasks. The opt-in Obsidian spec resolves a configured vault at Lazy activation and defers plugin imports until its config callback.

The completion owner configures Blink, LuaSnip, autopairs and Lazydev only at Lazy callback boundaries. It keeps snippet filetype extensions and its own InsertLeave cleanup. Full custom snippets and live resizing remain separate parity checks.

The `orbit.plugins` spec import scans the module manifest. Modules that implement `spec()` contribute Lazy declarations without a second feature inventory. `lua/plugins/init.lua` is only a compatibility import shim. The navigation module owns Oil and nvim-tree specs, Windows watcher settings and one FileCreated-to-CreateFile observer. Harpoon integration is a separate owner.

The nvim-lint module debounces triggers per buffer, skips SQLFluff while editing, and cancels pending timers on buffer wipe. Pinned upstream Linux/Windows tests verify actual process output, diagnostic publication, edit-event suppression and buffer cancellation. Production SQLFluff binaries, Windows tool arguments and Hangar ordering remain separate integration tasks.

The shared SQLFluff adapter resolves project configuration, process roots and stdin arguments for Conform and nvim-lint. It uses a bundled T-SQL fallback only when no project SQLFluff section exists.

The Conform formatter module keeps async requests owned by one buffer and cleans up pending operations when a buffer is wiped. A pinned upstream Linux/Windows test exercises native Lua formatting, delayed completion and duplicate request rejection. Real external formatter binaries, Hangar ordering and project-specific adapters remain separate parity checks.

The Tree-sitter module contributes parser, context and autotag specs. Parser activation is guarded by buffer/filetype validity and excludes bigfile buffers. The C# injection query captures raw-string node owners before evaluating SQL predicates. Pinned upstream C#/SQL parser integration validates injection captures and an actual SQL child LanguageTree. Legacy syntax fallback still protects unsupported T-SQL syntax.

The native LSP module uses LuaDoc-owned server flags and a single registration boundary. It preserves shared diagnostics and language defaults. Roslyn and TypeScript tools are independent provider-owned Lazy specs, not registered by generic LSP; Hangar activation gating now filters standard LSP servers, Conform and nvim-lint through one optional bridge. The bridge does not import Hangar until its Lazy owner has initialized; DAP now registers debugpy launch/attach and provides Hangar-compatible adapter controls. CoreCLR delegates to dotnet-cli, and DAP UI listeners are installed once. A pinned real nvim-dap TCP integration test verifies Python attach, breakpoint synchronization and disconnect on Linux/Windows without external debuggers. A hermetic Linux/Windows TCP language-server test exercises the real native Neovim LSP client and TypeScript provider diagnostic deduplication. Real Python/.NET debuggee sessions remain pending. The Hangar registry is the canonical source for Mason packages, parsers and tool metadata. Its owner sets state paths and adapters before event-loaded consumers read tool settings. A pinned real Hangar v0.3.1 test validates persisted LSP/linter/formatter flags, Python formatter order, runtime filtering, reload, explicit state path precedence, and concurrent-writer protection on Linux and Windows. An additional pinned real NUI integration validates Hangar window rendering, navigation, focus reuse, and close/reopen ownership in headless Neovim on both platforms. Actual Mason installs and a complete interactive UX audit remain separate acceptance gates.

The Mason module owns only the command-lazy package manager declaration and its settings. It does not register or enable LSP servers, which require a separate runtime lifecycle.

The messages module owns Noice's commandline, notification, and LSP presentation settings. It constructs routes and popup layouts only at the Lazy callback boundary. It does not import Noice during root setup. Real upstream UI integration and theme parity remain separate verification work.

The Snacks module owns the legacy picker shortcuts and the narrow invalid-window redraw guard. Theme, dashboard art and extended picker layout migration remain separate.

The diagnostics_plugins owner contributes Trouble and todo-comments. Its LSP-reference handler and TODO-picker entry points are covered by Lua fixtures; Snacks integration is pending its own module.

The independent editor_plugins owner contributes vim-matchup and indent-blankline. Its init callback owns the matchup globals, and its indent hook is registered only at Lazy config time. Existing theme highlights remain a separate migration requirement.

The icons and git owners produce Lazy declarations without loading external code. The git owner preserves the original staged and unstaged glyph defaults and uses the one-shot FilePost event.

The first-demand integration test combines a local locked Git checkout, the module manifest spec import and file observer replay in a single Neovim process. It does not require external plugins or network access.

The independent `live-upstream.yml` workflow exercises a pinned real mini.icons checkout on Linux and Windows through its actual Lazy config callback and devicons compatibility API. This intentionally uses GitHub network access, unlike hermetic unit suites. It also verifies a pinned real gitsigns checkout, plugin setup, tracked-file attachment and asynchronous hunk updates. Those checks do not establish parity for other plugins, parser installations, LSP servers or terminal sessions.

The opt-in plugin module owns one package searcher and one demand-event group. It initializes an existing Lazy installation on first use. Newly registered file observers receive only the missed event. Setup does not clone plugins or require the network. First demand may clone the stable Lazy source when explicitly authorized by `bootstrap = true`. The optional lockfile pins the checkout. Existing installations are never replaced by bootstrap. All plugin options are restart-only because loaded plugins cannot be rolled back.

Keep plugin loading with Lazy until a separate benchmark and compatibility plan approves another owner. Keep tool state and operations with hangar.nvim. Keep the configuration registry and runtime adapters within orbit.nvim.

The editor module owns core statusline, clipboard, mouse, indentation and signcolumn defaults. Its schema declares every migrated scalar option.

The corekeys module owns configurable save/window keys and fixed plugin-independent editing shortcuts. It restores overwritten user mappings during reconfiguration, disable and rollback. Buffer-local LSP mappings can override its global `K` reservation. The Normal/Insert/Select Escape maps are expression callbacks: when a loaded menu is active they schedule cleanup, otherwise they clear search highlights and stop an active LuaSnip or native snippet. Escape does not load completion/UI plugins solely to handle a keypress.

The keymaps module owns leader-based save, new-buffer, project-root, diagnostic, settings and native comment actions. It stores mode-qualified physical mappings across leader changes and restores user bindings during rollback. Project roots prefer the current buffer's LSP before the legacy repository and language markers. Settings shortcuts resolve the configured command at invocation. DOS-to-Unix and Big5-to-UTF-8 conversion keys reload and write only when invoked; their Lua helper refuses unnamed buffers. The `<leader>bD` and `<leader>x` buffer actions replace the legacy `%bd|e#` / tabufline dependency. Bulk cleanup preflights every listed, normal candidate and refuses modified buffers before deleting any; the current buffer is preserved. Single-buffer close rejects unsaved or special buffers. This is intentionally safer than the legacy force-prone bulk command and does not require NvChad.

The keymaps terminal helper restores `<leader>h/v` split terminals plus Normal/Terminal `<M-h/v/i>` toggles. It owns reusable buffer IDs in Lua, starts processes using argv vectors (including PowerShell `-NoLogo` on Windows), avoids operating on unrelated floating windows and leaves running user terminals intact when keymaps are disabled. The current window proportions remain fixed to the original 30%/20% splits and approximately 80% floating region; tunable terminal settings and real long-running Windows shell sessions remain separate integration work.

The keymaps theme helper restores `<leader>ut/ur` using Neovim's installed colorscheme list and `vim.ui.select`, with reload via the active `:colorscheme`. It does not import the old external theme picker, reload external highlight caches, or attempt to recreate the legacy dashboard; those UI and persisted-theme contracts remain separate parity work.

The events module owns core Neovim events and the legacy one-shot `User FilePost` signal. It emits FilePost once after UI entry and a named normal buffer are ready. It resends FileType only to that buffer to attach newly available filetype observers. When `vim.g.editorconfig` is enabled, it then applies the configured EditorConfig module to that same still-loaded buffer; optional imports are deferred and external configuration errors are reported without breaking the callback.

The events module owns only standalone core events. It registers callbacks once and disables them through state instead of destroying an event group needed for rollback.

The commands module owns the settings command and restores its registration after failed activation. It does not replace other commands.

The filetypes module owns only Compose YAML and JSX detection. It captures the existing Neovim registry entries before registration and restores them on rollback or disable.

Port each feature behind the public module contract. Preserve previous behavior until the feature's targeted checks pass. Avoid persistent compatibility aliases that hide old names in new code.

Keep startup side effects outside module imports. Complete asynchronous work only while its buffer or owner remains valid. Every module must implement `capture(opts)` and `restore(snapshot)` beside `setup(opts)`. The root captures all modules before activation and restores activated modules in reverse order on failure. Repeated setup must replace owned mappings and subscriptions instead of duplicating them.

## Tooling language

Write executable tooling and tests in Lua. Use Neovim as the Lua host to reuse `vim.json`, filesystem APIs and process execution. Keep only the generated `settings.schema.json`, the manifest and GitHub Actions YAML as data formats. Add non-Lua code only when a specific requirement cannot be met reasonably with Lua, and document the exception.

C# SQL injection queries use the `after/queries/c_sharp/injections.scm` extension. The Lua predicates exclude undecodable escape sequences and allow independently configured comment and SQL-name detection. Actual parser compatibility remains an upstream integration gate.

SQL Server highlighting also uses `after/queries/sql/highlights.scm` and the focused `syntax/tsql.vim` fallback. Explicit buffer and global dialect preferences take precedence. Markdown SQL fences retain user mappings.
