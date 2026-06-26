## Handoff — Pommora React

Lean current-state snapshot. Read first at session start. Deep docs: editor → `Features/MarkdownPM.md` (+ build spec `Planning/MarkdownPM.md`); the footer → `Features/Subfield.md`; data/IPC → `Features/Architecture.md`; design system → `Features/Design.md` + `Features/Typography.md`; drag-and-drop → `Features/DragAndDrop.md`; parked ideas → `Prospects.md`; locked decisions → `History.md`; **tables → `Features/MarkdownPM.md` § Tables**.

### Session summary — Subfield (footer) + window chrome (2026-06-25)

A polish-heavy session on the detail surface and chrome.

- **Subfield** (Swift's footer) — shipped. A breadcrumb with the dimmed forward **ghost crumb** (last-visited page), per-view items (pages → `lines·words·chars`; Collections/Sets → a New-Page/Container add-menu; Homepage + Contexts none yet), and an **app-level** hover chevron that slides the bar. New **8/10 "Subline" type scale**; persisted per-nexus in `.nexus/settings.json` under a `subfield` foreign key via a `subfield:get/set` IPC that mirrors `folds`. Spec → `Features/Subfield.md`.
- **Inspector pane** — a full-height right-side twin of the sidebar (`Detail/InspectorPanel`, `GlassWindow`): pushes/reflows content when open (`--content-inset-right` mirrors the sidebar's left inset), edge-resizable, toggled from the trio. Empty scaffold — content (frontmatter/properties/page-info) is future.
- **Locked-header content-views** — Collections/Sets/Contexts pin their banner + title while the body (table) scrolls (`DetailScaffold` `lockedHeader`). This also fixed **banner-less views showing no title** (Areas); the title now always renders, the divider is full-width always, and the title size is one DRY value (banner vs no-banner, Collection vs Set identical).
- **Add-Banner unified** — one shared `AddBannerButton` across pages + content-views, centred in the toolbar→title gap.
- **Liquid-glass controls** — `glass-controls` swapped from frost to Apple "Liquid Glass" (`@samasante/liquid-glass`, real `feDisplacementMap` refraction); optics tuned then baked static; the homepage tuning lab removed. Window/Surface stay frost. Detail → `Features/Design.md` § Glass.
- **Scrollbars hidden app-wide**; **sidebar toggle** sized to the toolbar buttons + centred between the traffic lights and Back/Forward; app-level horizontal-scroll clip on `.shell`.

Typecheck + **542 tests** green throughout; each task a path-limited commit on `main` (not pushed). A parallel session held uncommitted edits in `MarkdownPM/Styles.css` + the root `.claude/*` all session — left untouched.

### Where the project is

Foundations, container views, the page editor (MarkdownPM + Tables), the page/container banners, the **inspector**, and the **Subfield footer** are built. The data + read/write paths match Swift; what remains is the editor tail + polish + **performance**.

- **Data layer — done** (CRUD, properties, connections, Agenda; files canonical, SQLite a regeneratable accelerator). → `Features/Architecture.md`.
- **Design system — done, tokenized, live** (colour + accent + tint + typography incl. the new Subline + chips; Lucide icons; glass now two materials — frost Window/Surface, liquid-glass Controls). → `Features/Design.md` + `Features/Typography.md`.
- **Sidebar — fully built** (Contexts + Vaults/Collections/Sets/Pages; create/rename/delete/reorder; PommoraDND drag-and-drop; disclosure persisted). → `Features/DragAndDrop.md`.
- **Page editor — MarkdownPM, richly built + Tables done** (CM6, dynamic syntax, folding, lists, connections + `[[` autocomplete, native menu + shortcuts, full GFM table editing). → `Features/MarkdownPM.md`.
- **Detail surface** — `DetailPane` routes selection → `HomepageView`/`ContextView`/`ContainerView`/`PageView`, each through `DetailScaffold` (+ `lockedHeader` for content-views); the Subfield mounts below; the inspector floats right.

### Next session

1. **MarkdownPM performance** (Nathan's priority) — long-scrolling pages **with tables** are slow to render their contents; **caret placement jitters on longer docs**. Profile CM6 measurement/decoration + the table widget's `updateDOM`/`ResizeObserver` cost on long docs; that's also where the caret-jitter likely originates.
2. **Subfield reorder** — drag the items via PommoraDND (horizontal). The persisted `order` is already wired; only the drag UI remains.
3. **Editor tail** — the real **Icon Picker** (Edit-Icon routes to a stub), then `::` **callouts** (→ `> [!type]`) + the **image / latex** render seams (detected/styled today, rendered later).
4. **Inspector content** — frontmatter → properties → page-info in the empty pane.
5. **Beyond** — Homepage dynamic widgets, the Gallery view, Agenda surfacing. Roadmap → `Framework.md`.

### Pending focuses

- **Tables — lazy cell editors (deferred perf).** Every table cell mounts a full CM6 `EditorView` (`MarkdownPM/Tables/CellEditor.tsx`), so a large table builds dozens of nested editors synchronously the moment it scrolls into view (`Tables/widget.tsx` `toDOM`) — the visible hitch on long pages with big tables. Fix: render cells as plain styled divs and instantiate a real `CellEditor` only on focus/edit (most cells are never edited). Biggest remaining table-perf win, but the largest change — left for after the parse/region scoping fixes that landed this session.
- **Subfield reorder + live-stats + custom items** — the registry/order/persistence are the seams; see `Features/Subfield.md` § Roadmap.
- **Icon picker** — build the real `Components/IconPicker` + wire the icon's frontmatter save (Swift `IconPicker` is the spec; wants a shared dropdown-animation primitive).
- **Real design-system Components** (Button / Menu / Label / Separator) from the token layer — prerequisite for replacing one-offs (notably the inline-rename `<input>`).
- **Radius + spacing tokens** — still ad-hoc literals; lift from Figma.
- **Settings editing UI** deferred — `.nexus/settings.json` is the control surface (labels + accent + now `subfield`).
- **One-time Biome normalization** — the format-on-write hook keeps touched files clean, but a whole-tree `npm run check` pass hasn't run (defer to a tree with no parallel uncommitted edits, so it doesn't clobber them).
- **Doc mirror** — a launchd watcher mirrors these docs into the Obsidian vault; keep them current.

### Working notes

- UI iteration runs in **dev mode (HMR)** — keep `npm run dev` up; renderer edits hot-reload, **but CM6 widget/extension code needs a full ⌘R** (only CSS hot-swaps), and a freshly-added module sometimes needs one reload past HMR. Don't ⌘Q it.
- **Main-process edits need a dev-server restart**; a stale main can silently drop a mutation.
- Runs against a **test nexus** (`~/test`) — a *managed* nexus (carries `.nexus/`) so reorder/settings persist.
- The agent **can** screenshot the React UI headlessly via Electron + CDP (`--remote-debugging-port` → `Page.captureScreenshot`), but Nathan is the primary visual verifier.
- **Parallel sessions happen** — never bundle or revert unattributed changes; **stage explicit paths** (`git add <paths>`), never `-A`.

### Lessons learned (durable)

- vanilla-extract vars are hashed; the `theme-vars.css.ts` bridge re-exports them as stable `var(--…)` — one source across `.ts` and `.css` (incl. `--weight-*`).
- **`@samasante/liquid-glass` `<Glass>` forces `display:inline-block` inline** — a flex consumer (the segmented control) must re-assert `display:flex` in its own inline style or the row flattens. It renders `children` + the filter layers as direct children of the styled root, so `className`/`style` pass through cleanly.
- **Styling `::-webkit-scrollbar` at all opts Chromium out of its native auto-hiding overlay** onto the always-visible classic bar. A custom CSS bar can't truly auto-hide (only fake it via hover); real scroll-then-fade needs an overlay-scrollbar lib. We hid them entirely instead.
- **Per-machine UI state vs portable settings** — `subfield` config + accent + labels live in the Swift-shared `.nexus/settings.json` (foreign keys round-trip); ephemeral chrome (folds, sidebar disclosure) lives in separate local files / localStorage.
- **The editor caret is already native** (no `drawSelection`) — its tall look is the editor's 1.6 line-height (native carets span the line box); a shorter caret needs a non-native custom cursor or lower line-height. Not a bug.
- **The editor bakes CM6 extensions at mount** — extension-code changes need ⌘R, not HMR; a stale dev server can leave a GHOST Electron running old code (`pkill -f "…/node_modules/electron"`). Verify extension behaviour headlessly (jsdom) over a possibly-stale window.
- **CM6 injects `.ͼN .cm-line{display:block}` at (0,2,0)** — override line display/padding with a `.mdpm-editor .cm-line.X` (0,3,0) selector, not `!important`; after chained edits to one rule, re-read the whole file.
- **(Tables)** Drags bind move/up on `window` + `setPointerCapture` (a mid-drag re-render drops element listeners → frozen drag); `updateDOM` re-renders the React root in place (else CM rebuilds every nested editor — "jank on drop"); the live element is the only drag feedback. `@tanstack/react-table` was rejected (its resize grows the table, opposite our conserve-total dash model). React port of **ckant/codemirror-markdown-tables** (MIT).

#### Fix Log

- **Caret look/jitter** — the caret is native (above); its tall height is line-height-inherent, and it **jitters on longer docs** — folded into the *MarkdownPM performance* focus next session.
- **Aliased `[[A|B]]` vs cell-pipe** — a `|` in an aliased connection collides with cell-pipe escaping inside a table cell; autocomplete only inserts alias-free `[[Title]]`. Open paradigm call.
- **Table links non-clickable** (no input handling for the rendered link inside a cell); proposed single-click navigate + right-click edit.

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-unfixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home (`History.md` / `Features/*` / `Framework.md`).
