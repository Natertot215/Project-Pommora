### Pommora — React+Electron Reference

Reference document for the React + Electron implementation path. Captures research findings, library choices, and architectural patterns so a future build (or a stack pivot) can move directly to implementation without re-researching the landscape.

**Status:** React + Electron is one of two viable stack paths (SwiftUI is the other). Stack decision is open. Nothing here is committed; this document captures *findings*, *patterns*, and *library options* — not Pommora's final React architecture.

---

#### Design system status (Figma → React)

The Figma design system is built at the variable + visual-mock level: ~118 tokens with full binding, primitives and composed components rendered as gallery FRAMEs, three-pane shell mockup. Conversion of gallery FRAMEs into reusable COMPONENT_SETs is planned at `.claude// Planning// Figma Components 5-13.md` and runs next.

**What the Figma build revealed about the React path:** Figma produces really good UIX for React — the Figma → React translation is a real, well-supported workflow that gives Nathan the design system he wants. It's also gimmicky in places, requires tweaking, and has things that look obvious to a designer but are hard for Claude to implement directly. The design system is a real option, not a free one — it requires work and frustration like anything else. This matters for the stack decision because it sizes the rest-of-app build effort: React's path means every component is a Figma → translation chain, and Nathan owns that surface.

**Live React demo is the gate.** Until components are translated to React + Tailwind in `UI-UX// Components//` and the localhost dev server is running, "what React feels like" is hypothetical. The Figma file alone reveals static design intent; the live demo reveals UIX behavior under interaction. Stack decision is deferred until the live demo exists — the Figma file is necessary but not sufficient evidence.

**Build sequence to live demo (after Figma component conversion):**
1. Figma Variables → CSS custom properties → `UI-UX// Design// tokens.css`
2. Figma COMPONENT_SETs → React components in `UI-UX// Components//` consuming those tokens
3. Vite + Electron renderer scaffolded with `UI-UX// Components//` as root
4. Localhost dev server running the component gallery — this is the demo

---

#### What's been verified

- **BlockNote (MPL-2.0) and Tiptap (MIT)** are the two co-primary editor candidates — both ProseMirror-based, both fully open-source and free for Pommora's scope, either able to deliver the **wanted Notion-style block editor surface**: per-paragraph `+` (insert) and drag-handle (reorder) markers on the left, slash menu, formatting toolbar, custom blocks for `:::columns` / `:::callout`, markdown round-trip. The block UI is a wanted feature on React — the affordance for inserting directives, reordering paragraphs, and anchoring focus visually — sitting on top of an on-disk continuous Markdown stream. BlockNote is the higher-level / batteries-included option (it's literally built on top of Tiptap); Tiptap is the lower-level / fully-configurable option. Pick at React commit time. Pivot doors (only if the block UX disappoints): Milkdown (markdown-first by design), Yoopta (Slate-based), CodeMirror 6 (markdown-canonical Plan B).
- **`@dnd-kit/core` v6.x** is the drag-and-drop library for Spaces. Stable, recipe-rich. **NOT `@dnd-kit/react`** (v0.x, pre-1.0 ground-up rewrite by the same author).
- **`@parcel/watcher` v2.5+** for vault folder watching — native FSEvents on macOS; ms vs seconds vs chokidar at large tree scale. Used by VSCode, Nx, Tailwind.
- **`better-sqlite3` (WAL mode) + SQLite FTS5** for the local index. External-content table + `unicode61` tokenizer (`remove_diacritics=2`) is the recommended pattern for vault scale (1k–10k pages).
- **`remark-directive` + `mdast-util-directive`** for `:::columns` and `:::callout` directives. Container directives have a clean AST and `directiveToMarkdown()` round-trips them back to `:::` syntax. Nesting requires the outer fence to use more colons (`::::columns` containing `:::callout`) to avoid ambiguous closes. (Blockquotes use standard `>` syntax — not a directive. Callouts are now a distinct construct with their own directive, not a styled blockquote.)
- **`@flowershow/remark-wiki-link` v3.3.1+** for Obsidian-flavored wikilinks: `[[name]]`, `[[name|alias]]`, `[[name#heading]]`, combined `[[name#heading|alias]]`, and `![[asset]]` embeds with dimensions. Healthiest of the maintained options.

---

#### Where React+Electron breaks for Pommora

##### Editor serialization architecture — Markdown on disk, JSON in-editor

The React editor uses **two serialization formats deliberately**, each chosen for what it does best. This is the editor's architecture, not a risk mitigation — both formats are first-class and Pommora needs both to function.

**Markdown (`.md` on disk) — canonical content format.**

- **Used for:** every Page's storage in the vault. The file is what an external agent reads, what Obsidian / GitHub / `cat` render, what `grep` searches. The third load-bearing constraint (persistent immediate legibility for agents) requires this.
- **API:** `blocksToMarkdownLossy(blocks?: Block[]): string` (write) and `tryParseMarkdownToBlocks(markdown: string): Promise<Block[]>` (read).
- **Carries:** standard Markdown (paragraphs, headings, lists, code blocks, images, GFM tables, blockquotes, horizontal rules) plus the two Pommora directives (`:::columns`, `:::callout`).
- **`Lossy` is a generic-API label, not a Pommora concern.** Pommora's content model is the standard Markdown set plus two well-defined directives (`:::columns`, `:::callout`); the per-block / per-node serializers below close that gap. Small, bounded code — quick fix at the boundary, not an ongoing risk.

**Working JSON state (in-memory) — editor state and perfect-fidelity export.**

- **Used for:** the editor's internal working state (always JSON in memory while editing), undo/redo history, debug snapshots, any case where perfect round-trip fidelity matters and Markdown can't carry it (selection ranges, in-flight transforms, Pommora-to-Pommora interchange).
- **API (BlockNote):** `editor.document` reads the block tree; `JSON.stringify` serializes it. **API (Tiptap):** `editor.getJSON()` reads the ProseMirror document as JSON; `editor.getHTML()` for the HTML form. Both are canonical stores; round-trip is exact by construction.

**Custom serializers for the two directives.**

- `:::columns` and `:::callout` get per-block / per-node markdown handlers. **BlockNote pattern:** `toExternalHTML` / markdown handlers per block spec ([Issue #221](https://github.com/TypeCellOS/BlockNote/issues/221) → [PR #426](https://github.com/TypeCellOS/BlockNote/pull/426)). **Tiptap pattern:** `renderHTML` per node + the first-party `@tiptap/markdown` extension's `MarkdownManager` (`editor.markdown.parse(md)` / `editor.markdown.serialize(json)` / `editor.getMarkdown()` / `editor.commands.setContent(md, { contentType: 'markdown' })`). Markdown round-trip is first-class — no extensibility hooks or parallel `prosemirror-markdown` wiring required.
- These bridge the in-memory JSON representation of Pommora's directives to their Markdown form on disk. Without them, the directives fall back to the editor's default serialization on save.
- Two block / node types, two pairs of handlers — small, well-bounded code surface, not an open-ended serializer burden.

**Why both formats are necessary:**

- Markdown alone can't carry editor state (cursor positions, selection ranges, in-flight operations, undo stack). The editor needs a richer working format.
- JSON alone breaks agent-legibility, external-tool compatibility, and vault portability. Pages must be Markdown on disk.
- Custom serializers alone don't help if the editor can't represent the directives internally; they're the boundary code, not the working format.

The Markdown ↔ JSON split is deliberate, not a workaround. Treat it as a load-bearing architectural detail of the React path.

**If the BlockNote / Tiptap block UX fails to land as wanted** (unlikely — both are mature implementations of the Notion-style pattern), Milkdown (markdown-first; ProseMirror foundation) or CodeMirror 6 (buffer-based; markdown literally *is* the document) remain in the catalog. Both trade the Notion-style block UI for a different editor model — the opposite tradeoff from what React wants. The Markdown ↔ internal-state architecture survives the pivot; only the API names and the boundary code change.

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

**Co-primary candidates (if React + Electron is picked) — pick at commit time:**

- **BlockNote (MPL-2.0)** — batteries-included block editor built on Tiptap; slash menu, formatting toolbar, drag handles, schema enforcement all wired by default. Faster to a working editor; less ceremony for custom blocks. License caveat on the XL packages (`@blocknote/xl-multi-column` is GPL-3.0 OR a paid commercial Business subscription — pricing not pinned in docs, verify on blocknotejs.org/pricing; build the multi-column block in core to avoid the question entirely).
- **Tiptap (MIT)** — headless editor framework; the underlying primitive BlockNote is built on. Every package Pommora would use (`@tiptap/core`, `@tiptap/react`, `@tiptap/extension-drag-handle-react`, `@tiptap/markdown`, etc.) ships under MIT from the regular `@tiptap/*` npm scope. Trades batteries for full configurability — slash menu, formatting toolbar, drag handles are wired explicitly.

Either editor delivers the same wanted UX:

- Keep per-paragraph `+` insertion markers and drag-handle (grip) markers on the left of every block — they're the wanted Notion-style affordance, how you insert directives and reorder paragraphs without diving to a menu. The on-disk format stays continuous Markdown; the block UI is purely the editing surface.
- Custom block / node specs for `:::columns` and `:::callout` (BlockNote: `createReactBlockSpec`; Tiptap: `Node.create` with a React node view). Blockquotes use standard `>` syntax via the built-in blockquote node, with Pommora's distinct visual styling (filled background + left-side emphasis bar via `blockquote//` tokens). Callouts are a distinct construct with their own custom spec / node (outlined box; `callout//` tokens).
- Build the multi-column block in-tree on BlockNote (don't pull `@blocknote/xl-multi-column`, which is the one copyleft-or-commercial BlockNote package); on Tiptap, build it as a custom node directly — no comparable package to avoid
- Custom markdown serializer per block / node type to enforce files-canonical round-trip
- Wikilinks render as styled colored inline text via custom inline marks; pair with `@flowershow/remark-wiki-link` for the parse direction
- Slash menu, bubble toolbar, undo / redo, copy / paste, keyboard shortcuts, content schema enforcement — built-in on BlockNote, wired explicitly on Tiptap

**Pivot doors held open** (in order of decreasing similarity to BlockNote / Tiptap):

- **Milkdown** — markdown-first by design (round-trip integrity built into the framework); MIT; ProseMirror foundation. Plugin ecosystem includes slash, history, clipboard, listener, prism, math, emoji, upload, tooltip.
- **Yoopta** — Slate-based; MIT; 20+ built-in plugins including a callout.
- **CodeMirror 6** — buffer-based; perfect markdown round-trip by construction; meaningfully more work to layer Notion-style block UI on top (its strength is the markdown-as-document model, the opposite tradeoff from what React wants).

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
