## Handoff — Pommora React

Lean current-state snapshot. Read first at session start. Deep docs: editor → `Features/MarkdownPM.md` (+ exhaustive build spec `Planning/MarkdownPM.md`); data/IPC → `Features/Architecture.md`; design system → `Features/Design.md` + `Features/Typography.md`; drag-and-drop → `Features/DragAndDrop.md`; parked ideas → `Prospects.md`; locked decisions → `History.md`; **tables → `Features/MarkdownPM.md` § Tables**.

### Session summary — Tables shipped (2026-06-22 → 06-23)

**Tables are done — basic functionality complete, in a good position.** After a long, ugly fight (last session opened on Nathan's fork: *"prove this table system is sustainable, or start from scratch"*), we continued on the layered foundation and it held — no restart needed. GFM tables now edit as a real interactive table: a block-replace CM6 widget over the canonical source, live nested cell editors, drag-reorder of rows/columns, an OS-native grip menu, and — the last structural piece — **column width-resize** (drag a boundary; whole dashes redistribute between the two adjacent columns, 1-dash floor, pixel-exact preview, commit on release). Structure is keyboard-uncorruptable (one shape-preserving `transactionFilter` + a second guard that refuses the blank-line delete which would fuse two tables); in-cell Cmd-Z scopes to the page. Closed out with a simplify + code-review + comment-audit pass, a doc rewrite, and `typecheck + 51 Tables tests` green. Tweaks (snap feel, affordances) will come later — but the feature is functionally complete.

Provenance matters here: the whole thing is a **React port of `ckant/codemirror-markdown-tables` (MIT)** — the widget-over-GFM + nested-cell architecture is theirs; **dash-width columns and width-resize are ours** (ckant has content-sized columns and a *dimension* resize, not width). `@tanstack/react-table` was evaluated and rejected for tables (its resize grows the table — the opposite of our conserve-total dash model). Full breakdown → `Features/MarkdownPM.md` § Tables.

### Where the project is

Foundations, the container views, the page editor (MarkdownPM) **+ Tables**, and the page banner are all built and richly featured. The data and read/write paths have caught up to Swift; what remains is a short tail of editor constructs + polish and live UIX passes.

- **Data layer — done.** The full write/mutation side matches Swift (CRUD, properties, connections, Agenda). Files are canonical; the SQLite index is a regeneratable accelerator off the read path. Detail → `Features/Architecture.md`.
- **Design system — done, tokenized, live.** The Figma "Pommora - React" library is the source; the token layer is complete (colour primitives + swappable accent + tint scale + typography + chips), Lucide icons, and a shared CSS-frost glass Material. Showcase live (`npm run showcase`; deploy notes → `Deployment.md`). Spec → `Features/Design.md` + `Features/Typography.md`.
- **Desktop app — runs** (packaged `Pommora.app` + dev-mode HMR) with a working write path + live auto-refresh. One `mutate` IPC (create / rename / delete / move / reorder / setBanner), native right-click menus + ⌘N + inline rename, and a chokidar watcher that swaps the tree in place on external change.
- **Sidebar — fully built.** Renders Contexts + Vaults/Collections/Sets/Pages; create / rename / delete / reorder all from the UI. **Drag-and-drop** is shipped (Apple-style insertion line + grab ghost, no displacement; valid moves only). **Disclosure open/collapse persists** across sessions (`Sidebar/disclosureState.ts` → localStorage, keyed by entity id). **Storage-row click is split:** on vault/collection rows, clicking the icon/title opens the view, while the chevron / empty space toggles expand-collapse. Spec → `Features/DragAndDrop.md`.
- **Drag engine — PommoraDND, in-house** (replaced `@dnd-kit`). Generic sort engines (list/grid/table/board) behind the `interactions/drag.tsx` seam, exercised in the Interaction Lab; only the sidebar consumes a behaviour so far.
- **Page editor — MarkdownPM, richly built (committed).** Dynamic-syntax Markdown editor on CodeMirror 6 with a framework-free, unit-tested behavior layer behind seams. Inline marks, caret-aware headings + folding, bullet/ordered/task lists, HR, blockquote cards, fenced code, clickable 3-state connections + the `[[` autocomplete panel, external-link validity styling, a native right-click context menu + ⌘B/I/E/K/⌘⇧X/⌘⇧K shortcuts, input transforms, unfocused-clean render. Full feature map → `Features/MarkdownPM.md`.
- **Tables — done.** Full GFM table editing: a block-replace CM6 widget over canonical source (the source never leaves `EditorState.doc`), every cell a live nested CodeMirror editor, **drag-reorder + an OS-native grip menu + column width-resize**, structure keyboard-uncorruptable via one shape `transactionFilter` + a two-table merge guard, page-scoped in-cell undo. Dash-count-as-width columns (`<colgroup>` + `table-layout:fixed`) are a Pommora convention; resize redistributes whole dashes. A React port of **ckant/codemirror-markdown-tables**. Spec → `Features/MarkdownPM.md` § Tables.
- **Page banner + title header — built + live-verified.** A cover band (Swift-compatible `cover` frontmatter, asset under `.nexus/assets/<page-id>/`), full-bleed behind the sidebar + toolbar glass via a local `z-index:0` stacking context. Title overlaid via the shared `DetailTitleHeader` (`[icon][name]`; right-click the icon **or** the name → Rename / Edit Icon; banner's own right-click → Change / Remove); the header parks on scroll via a CSS scroll-driven animation (compositor, no shake). Edit Icon routes to a `Components/IconPicker` **stub**.
- **Container + banner views — built.** Vault / Collection render their pages in a table; Context + the nexus-header **Homepage** render their own views. Vault + Collection share one `ContainerView`; every banner-bearing view sits in a shared `DetailScaffold`. A shared image cover renders behind the glass via the registered `nexus-asset://` protocol; the homepage's banner lives in `.nexus/homepage.json`.
- **Renderer structure mirrors Swift** — `Detail/` (router · `DetailScaffold` · `ContainerView`/`HomepageView`/`ContextView`/`PageView`) · `Sidebar/` · `Components/` · `design-system/`; co-located stylesheets per area. Detail → `Features/Architecture.md`.
- **Repo + branch.** One monorepo, one `main`; the React build lives under `React/`. Work happens in the React worktree on `main`; **nothing is pushed to GitHub** until Nathan says so. **Working tree (uncommitted):** the full **Tables batch** (widget editing, reorder, grip menu, merge guard, page-scoped undo, column resize) + these docs — typecheck + 51 Tables tests green, awaiting a commit. A parallel session has renamed structure in the tree, so commit **path-limited** (`git commit -- React/src/renderer/src/MarkdownPM/Tables/* React/.claude/* …`) — the rename session's files are not ours.

### Next session

1. **Commit the Tables batch** (path-limited — the `Tables/*` files + the docs explicitly) if not already landed.
2. **The deferred editor tail:** the **stats footer** (hover breadcrumb + line/word/char counts; `editor/textStats.ts` stub unwired), the real **icon picker** (Edit-Icon routes to a stub), then `::` **callouts** (→ portable `> [!type]`, behind a swappable codec) + the **image / latex** render seams (detected + styled today, rendered later).
3. **Beyond:** page properties + frontmatter inspector, then Agenda surfacing, the Homepage's dynamic widgets, and the Gallery view — roadmap in `Framework.md`.
4. **Normalize formatting once** — Biome was just added (`biome.json`, 2-space; format-on-write hook in Studio settings). Run `npm run check` to reformat the whole tree to the config in a single formatting-only commit; after that the hook keeps files clean as they're touched.

Discipline: a green commit per task; a live UIX pass with Nathan before any milestone closeout. **The editor bakes CM6 extensions at mount — ⌘R the renderer (not HMR) to see widget/extension changes; CSS hot-swaps live.**

### Working notes

- UI iteration runs in **dev mode (HMR)** — keep `npm run dev` up; renderer edits hot-reload. Don't ⌘Q it. A component's mount-once `useEffect` won't re-run under Fast Refresh — re-mount (re-select) to see those changes; **widget/CM6-extension code needs a full ⌘R**, only CSS hot-swaps.
- **Main-process edits need a dev-server restart.** The main-watcher can go stale in a long session — if a mutation silently doesn't persist, suspect a stale main and restart `npm run dev`. Repackage the Dock app only at milestones.
- Runs against a **test nexus** (`~/test`) so nothing real is touched. It must be a *managed* nexus (carry `.nexus/nexus.json` + sidecars) for reorder to persist on read.
- A GUI app can't be launched from the agent shell (no Aqua session) — Nathan is the visual verifier. Launch gotcha (`ELECTRON_RUN_AS_NODE`) → `Guidelines/Build-Gotchas.md`.
- **Parallel sessions happen** — the working tree isn't guaranteed yours alone. Never bundle or revert unattributed changes; commit with **path-limited commits** (`git commit -- <paths>`).

### Lessons learned (durable)

- vanilla-extract vars are hashed, so plain CSS can't read them; the `theme-vars.css.ts` bridge re-exports them as stable `var(--…)` — one source across `.ts` and `.css`.
- The packaged renderer must serve over the registered **`app://` scheme**, never `file://` (Vite ES-module scripts hit module CORS over `file://` → blank window). Dev over http is unaffected.
- **better-sqlite3 is dual-ABI** (Node ≠ Electron). `node_modules` stays Node-ABI so the vitest gate is reliable; electron-builder rebuilds for Electron at package time; `db.ts` lazy-requires it so an ABI mismatch degrades to a cold index instead of crashing.
- The live watcher must watch `.nexus/` **and** carry an `.on('error')` guard, or fd/inotify exhaustion crashes the main process.
- **A stable asset filename behind glass is a stale-image trap.** Banners write a fresh filename per save so the `<img>` URL changes; image bytes ride the `nexus-asset://` protocol, never base64-in-tree.
- **Scroll-linked headers belong on the compositor, not a JS `scroll` handler** — bind the translate to a CSS scroll-driven animation; a JS handler lags a frame (shake) and forces a layout read each frame.
- **A full-bleed layer behind the floating sidebar must not out-rank it in z-order.** Give an inner element that needs its own z-index a local stacking context (`position:relative; z-index:0`).
- **Transient UI chrome persists app-side, not in `.nexus/`.** Sidebar disclosure saves to localStorage (`Sidebar/disclosureState.ts`) — regeneratable chrome kept out of the portable nexus model — unlike per-page `.nexus/folds.json`.
- **The editor bakes CM6 extensions at mount.** Extension-code changes need a full ⌘R reload, NOT HMR, and a dev-server restart can leave a GHOST Electron window running stale code — kill the app process (`pkill -f "Project Pommora/React/node_modules/electron"`), not just the server. Verify extension behavior **headlessly** (jsdom render) rather than trusting a possibly-stale live window. **→ candidate CLAUDE.md quirk**
- **CM6 injects `.ͼN .cm-line{display:block}` at (0,2,0).** Override line display/padding with a `.mdpm-editor .cm-line.X` (0,3,0) selector, not `!important`. After several edits to one CSS rule, **read the whole file** — a malformed selector from chained edits cost hours while jsdom's `getComputedStyle` reported the failure correctly the whole time.
- **GFM does NOT size columns by dash count** (proven: `|-|` ≡ `|----------|` through micromark). Dash-as-width is a Pommora convention that *requires* the custom `<colgroup>` grid — not free from GFM.
- **Structure protection wants ONE rule, not per-key handlers.** A single shape-preserving `transactionFilter` (cancel any edit that changes `columns:rows:pipes`) covers every edit path — typing, ranged delete, paste, IME — at once. **→ candidate CLAUDE.md quirk**
- **(Tables) Every in-widget drag binds move/up on `window`, not the grabbed element** — it re-renders mid-drag (state + `ResizeObserver`), dropping element listeners and releasing pointer-capture without a `pointerup` (frozen drag). `setPointerCapture` + window listeners survive; commit once on release (one undo step); a no-op move clears the preview locally.
- **(Tables) `updateDOM` re-renders the same React root in place** — otherwise CM destroy+recreates the widget and re-mounts every nested cell editor (the "jank on drop"). A cell edit tagged self-edit *remaps*; a structural edit *rebuilds*.
- **(Tables) The live element is the only drag feedback** — a separate indicator (e.g. a resize bar) positioned off a measured boundary lags it via the async `ResizeObserver` and stutters; the moving columns + the `ew-resize` cursor suffice.
- **(Tables) `@tanstack/react-table` is the wrong tool for table resize** (capability ≠ fit) — its resize grows the column + table total (datagrid), opposite our fixed-width conserve-total dash redistribution. Tables are instead a React port of **ckant/codemirror-markdown-tables**.

### Pending focuses

- **Stats footer on pages** — the hover bar: `Vault › Collection › Page` breadcrumb + line / word / char counts. The `editor/textStats.ts` stub exists, unwired.
- **Icon picker** — build the real `Components/IconPicker` (the Edit-Icon menu routes to a stub) + wire the icon's frontmatter save. The Swift `IconPicker` is the spec (SF-Symbols 6-wide glass grid, pill search, saved-on-top, Remove row).
- **Real design-system Components** (Button / Menu / Label / Separator) from the finished token layer — the prerequisite for replacing ad-hoc one-offs (notably the inline-rename `<input>`) during the live UIX pass.
- **Radius + spacing tokens** — corners + spacing are ad-hoc literals; formalize as scales from Figma.
- **Settings editing UI** is deferred — `.nexus/settings.json` (labels + accent) is the control surface for now.
- **Doc mirror** — a launchd watcher mirrors these docs into the Obsidian vault; keep them current so the mirror stays useful.

#### Fix Log

- **Non-native caret** used in the MarkdownPM editor; investigate and fix.
- **Aliased `[[A|B]]` vs cell-pipe** — a `|` in an aliased connection collides with cell-pipe escaping inside a table cell, so the alias degrades; autocomplete only ever inserts alias-free `[[Title]]`. Open paradigm call.
- **Table links non-clickable** (no input handling for the rendered link inside a cell); proposed single-click navigate + right-click edit.

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-not-yet-fixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home.
