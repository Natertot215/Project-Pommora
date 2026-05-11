### Pommora — React+Electron Reference

Reference document for the React + Electron implementation path. Captures research findings, library choices, and architectural patterns so a future build (or a stack pivot) can move directly to implementation without re-researching the landscape.

**Status:** React + Electron is one of two viable stack paths (SwiftUI is the other). Stack decision is open. Nothing here is committed; this document captures *findings*, *patterns*, and *library options* — not Pommora's final React architecture.

---

#### What's been verified

- **BlockNote (open-source MPL-2.0 core)** is the editor primitive direction. ProseMirror-based block editor with custom block specs, slash menu, formatting toolbar, drag handles (which Pommora disables for the prose-first feel). Pivot doors held open: Tiptap (commercial-trajectory risk), Milkdown (markdown-first by design), Yoopta (Slate-based), CodeMirror 6 (markdown-canonical Plan B).
- **`@dnd-kit/core` v6.x** is the drag-and-drop library for Spaces. Stable, recipe-rich. **NOT `@dnd-kit/react`** (v0.x, pre-1.0 ground-up rewrite by the same author).
- **`@parcel/watcher` v2.5+** for vault folder watching — native FSEvents on macOS; ms vs seconds vs chokidar at large tree scale. Used by VSCode, Nx, Tailwind.
- **`better-sqlite3` (WAL mode) + SQLite FTS5** for the local index. External-content table + `unicode61` tokenizer (`remove_diacritics=2`) is the recommended pattern for vault scale (1k–10k pages).
- **`remark-directive` + `mdast-util-directive`** for `:::columns` / `:::callout` / toggles. Container directives have a clean AST and `directiveToMarkdown()` round-trips them back to `:::` syntax. Nesting requires the outer fence to use more colons (`::::columns` containing `:::callout`) to avoid ambiguous closes.
- **`@flowershow/remark-wiki-link` v3.3.1+** for Obsidian-flavored wikilinks: `[[name]]`, `[[name|alias]]`, `[[name#heading]]`, combined `[[name#heading|alias]]`, and `![[asset]]` embeds with dimensions. Healthiest of the maintained options.

---

#### Where React+Electron breaks for Pommora

##### Editor: BlockNote markdown is lossy by design

Confirmed in BlockNote's official docs: `blocksToMarkdownLossy` and `tryParseMarkdownToBlocks` are lossy by design; the team explicitly recommends `JSON.stringify(editor.document)` as the canonical store. Behaviors that drop on round-trip include nested non-list blocks getting flattened, custom blocks without serializers being skipped, and inline marks beyond the built-ins (bold/italic/strike/code/link) silently dropping.

**Implication for Pommora's "files canonical" principle:** the markdown round-trip layer is something Pommora must own end-to-end. Custom serialization is achievable without forking ([Issue #221](https://github.com/TypeCellOS/BlockNote/issues/221) → [PR #426](https://github.com/TypeCellOS/BlockNote/pull/426); register `toExternalHTML`/markdown handlers per custom block spec), but covering every block type *is* the canonical-format guarantee — it's a real layer, not a small add-on.

**Plan B if BlockNote disappoints:** CodeMirror 6 is buffer-based (markdown literally *is* the document; round-trip is perfect by definition). Architecturally it's how Obsidian Live Preview works (`StateField` parses the document; `Decoration.replace` swaps source ranges with `WidgetType` block widgets). Trade-off: getting a prose-first feel requires building widget enter/exit, caret behavior across widget boundaries, and placeholder rendering yourself — meaningfully more work than a block editor like BlockNote.

##### Mac OS integration ceiling

The areas where pure Electron has a hard ceiling and "Mac-first cohesion" doesn't fully land:

- **QuickLook (.md preview via Finder spacebar):** no path in Electron without shipping a separate Swift bundle outside the app.
- **Share Extension** (receive shares from Safari / Mail / etc.): impossible in pure Electron ([Issue #31984](https://github.com/electron/electron/issues/31984) still open). Would require a sidecar Swift extension target.
- **CoreSpotlight (vault-wide system search):** possible only via `electron-spotlight` (Objective-C native module), which is maintained by one person and requires a signed build to talk to `corespotlightd`. Fragile.
- **NSServices** ("New Pommora Page from Selection"): `Info.plist` registration works, but receiving selection requires native bridging the framework doesn't expose ([Issue #8394](https://github.com/electron/electron/issues/8394) still open).
- **Finder file-promise drag-out** (drag a Page from the sidebar to Finder writes the file at the drop location): broken for years; community workarounds write a temp file then call `startDrag`.
- **Sidebar vibrancy:** Electron exposes `vibrancy: 'sidebar'` on `BrowserWindow`, but it can flicker on resize and bleeds through DOM. Looks ~80% right; the remaining 20% is exactly what cohesion-sensitive users notice.
- **Accessibility (VoiceOver, Dynamic Type):** Chromium ARIA → AX bridge has documented gaps that surface for power users; Dynamic Type doesn't apply.

These are not feature blockers — Pommora can either ship companion Swift bundles for QuickLook / Share Extension (which partially defeats the cross-platform appeal of Electron) or accept the integration ceiling. The choice is structural to the React path.

##### More moving parts

The runtime is a stack: Vite + Electron main + Electron renderer + Tailwind + better-sqlite3 (with native rebuild for the Electron ABI). Each component is well-trodden, but the surface area is larger than a single-process Swift app. For an agentic-implementation workflow, this trades a larger training corpus for more components to keep aligned across version bumps and platform updates.

---

#### Editor strategy

**Locked direction (if React + Electron is picked):** BlockNote (open-source MPL-2.0 core) configured prose-first.

- Disable BlockNote's per-paragraph drag handles; the prose feel comes from the absence of block UI on every line
- Custom block specs for `:::columns`, `:::callout`, toggles via `createReactBlockSpec`
- Build the multi-column block in BlockNote core (avoid `@blocknote/xl-multi-column`; that's GPL-3.0 OR $195/mo commercial — depending on Pommora's project license, may be inheriting GPL or unaffordable)
- Custom markdown serializer per block type to enforce files-canonical round-trip
- Wikilinks render as styled colored inline text via custom inline marks; pair with `@flowershow/remark-wiki-link` for the parse direction
- Slash menu via BlockNote's built-in slash menu; bubble toolbar via the formatting toolbar API
- All built-in: undo/redo, copy/paste, keyboard shortcuts, content schema enforcement

**Pivot doors held open** (in order of decreasing similarity to BlockNote's developer experience):

- **Milkdown** — markdown-first by design (round-trip integrity built into the framework); MIT; ProseMirror foundation. Plugin ecosystem includes slash, history, clipboard, listener, prism, math, emoji, upload, tooltip.
- **Yoopta** — Slate-based; MIT; 20+ built-in plugins including a callout.
- **Tiptap** — MIT core editor + MIT `@tiptap/markdown` extension. Note: Tiptap eliminated their free Cloud/Pro plan in 2026; AI / Conversion / Collaboration / Comments are paid. Free for Pommora's specific needs but commercial trajectory worth tracking.
- **CodeMirror 6** — buffer-based; perfect markdown round-trip by construction; meaningfully more work for prose-first feel.

---

#### Spaces strategy

**Locked direction:** `@dnd-kit/core` v6 + flat-array `[id, depth, parentId]` tree representation.

- Cross-level drag (a block dragged into a `columns` child or out into the top-level vertical flow) requires the flat-array shape; nested arrays don't compose well with dnd-kit's sortable strategies
- One shared `<CollectionViewRenderer>` dispatcher renders embedded Collection views inside Spaces and standalone Collection pages — same component, two contexts (mirrors Notion's `child_database` block pattern)
- View-override (filter / sort / group at embed time) is data merged onto the saved-view spec at render time; the Collection's saved view isn't modified

**Block JSON serialization discipline:**

- Validate with Zod on load and save (catches schema drift early)
- Atomic write via `.tmp` + rename
- ULID per block (sortable, generation-friendly)

---

#### State, data, file watching

**State.** Zustand v5+ vanilla. `zustand/vanilla`'s `createStore` produces a framework-agnostic store that React binds to via `useSyncExternalStore`. The framework-agnostic shape keeps the state pattern translatable to a future Swift rebuild (the conceptual equivalent on Swift is `@Observable` + GRDB `ValueObservation`). Avoid: Jotai (atom-first; viral across the codebase), Valtio (Proxy magic fights TypeScript), Redux Toolkit (overkill for solo work), Preact / TC39 Signals (not stable for production).

**Reactive SQLite layer.** `better-sqlite3` is synchronous and emits no change events, so reactivity is fully manual. Recommended pattern: hand-rolled table-keyed pub/sub — mutations publish touched tables; the Adapter holds a `Map<table, Set<queryFn>>` and re-runs subscribers. ~80 LOC, perfectly portable to Swift if a future migration ever happens. TanStack Query v5 with explicit `invalidateQueries` is the heavier-weight alternative if hand-rolled discipline isn't preferred.

**File watching.** `@parcel/watcher` v2.5+ in the Electron main process; IPC events across to the renderer. Gotchas:

- Editor atomic-save (write to `.tmp` + rename) emits `create` then `delete` for the temp; debounce 50–100ms by path
- APFS clones don't fire events
- Track outbound mtimes to ignore Pommora's own writes

**Search.** SQLite FTS5 with `unicode61` tokenizer (`remove_diacritics=2`) + external-content mode pointing at the `pages` table. Trigram tokenizer is 2× insert cost — only enable if substring search becomes a requirement. MiniSearch (in-memory) is fine up to ~2k notes but balloons memory at 10k. For Pommora's 1k–10k vault scale, FTS5 wins decisively.

---

#### Mac integration

Areas where pure Electron is **first-party** (no companion bundles needed):

- **App menu bar + keyboard shortcuts** — `Menu.setApplicationMenu` with role-based items (`appMenu`, `editMenu`, `windowMenu`); covers standard Mac shortcuts adequately.
- **Deep links** (`pommora://page/<id>`): `app.setAsDefaultProtocolClient` + `open-url` event + `Info.plist` `CFBundleURLTypes`. Single-instance lock required.
- **Basic notifications** — HTML5 `Notification` API maps to `UNUserNotification`; categories/actions need native module work.
- **Dark mode toggling** — `nativeTheme` + `prefers-color-scheme`.
- **Tray icon** — works; popup uses an HTML window (heavier than a native MenuBarExtra popover).

Areas requiring **companion Swift bundles** (out-of-process extensions Pommora ships separately):

- **QuickLook Preview Extension** — for `.md` preview via Finder spacebar
- **Share Extension** — for receiving shares from other apps
- **Spotlight at depth** — beyond what `electron-spotlight` exposes

Areas with a **hard ceiling** (no clean path):

- **Finder file-promise drag-out** — temp-file workarounds only
- **Sidebar vibrancy polish** — Chromium DOM bleed + resize flicker
- **Accessibility for power users** — Chromium ARIA gaps for `aria-activedescendant`, AX tree shape, focus rings; no Dynamic Type
- **Window state restoration with macOS Spaces** — `electron-window-state` persists size/position only; not Mission Control Spaces

---

#### Distribution

- **Build tooling:** `electron-vite` for the dev loop (Vite-first, HMR for the main process) + `electron-builder` for packaging. Alternative: Electron Forge 7+ (official, all-in-one, first-party feature parity). Both production-grade.
- **Native module rebuild:** `@electron/rebuild` (renamed successor to electron-rebuild) handles ABI compatibility for `better-sqlite3`. Forge auto-runs it via `install-app-deps`. Mark `better-sqlite3` as external in Vite config so the `.node` binary isn't bundled.
- **Auto-update:** `electron-updater` with GitHub Releases is the path of least resistance (free, reliable, no infra). MAS apps use Apple's mechanism — Pommora doesn't ship its own updates in that case.
- **Code signing + notarization:** `@electron/notarize` wraps Apple's `notarytool` (post-altool deprecation). Required entitlements: `com.apple.security.cs.allow-jit`. Hardened runtime mandatory.
- **MAS sandbox:** disables certain Electron modules and forces `contextIsolation: true`, `sandbox: true`, `nodeIntegration: false`. All renderer↔main IPC goes through `contextBridge.exposeInMainWorld` + `ipcRenderer.invoke`/`ipcMain.handle`. Filesystem requires `com.apple.security.files.user-selected.read-write` — same constraint as a SwiftUI MAS build; gives scoped access to user-picked vault folders only.
- **Crash reporting:** `@sentry/electron` is the de-facto standard; hooks into Crashpad for native crashes including renderer/main/utility processes.

---

#### Maintenance notes

- This file captures research findings, not committed architecture. The "locked direction" notes are best-known approaches as of the audit, not Pommora's locked design.
- Update as new React-ecosystem research lands (BlockNote releases, Electron version updates, dnd-kit v6 → vNext transitions, library deprecations).
- If the SwiftUI path is locked permanently, this file can be archived. If React+Electron is picked, the contents promote to the active Architecture and Domain-Model docs.
