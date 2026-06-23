## Handoff — Pommora React

Lean current-state snapshot. Read first at session start. Deep docs: editor → `Features/MarkdownPM.md` (+ exhaustive build spec `Planning/MarkdownPM.md`); data/IPC → `Features/Architecture.md`; design system → `Features/Design.md` + `Features/Typography.md`; drag-and-drop → `Features/DragAndDrop.md`; banner → `Features/Architecture.md`; parked ideas → `Prospects.md`; locked decisions → `History.md`; **tables → `Features/MarkdownPM.md` § Tables**.

### ⚠ Tables — critical decision point (read first)

The Tables feature (`MarkdownPM/Tables/`) is at a fork. **Nathan: "I'm at the critical point where you either prove this table system is sustainable, or we completely start from scratch."**

His read on *why* it's been hard: we've been hand-rolling dragging + hover-menu functionality in the immediate scope, designing the renderer on **mountains of assumptions about unbuilt features** (resize, grip menus, structural ops). **The candidate path is simple-first: build a basic GFM render FIRST, then layer dragging + hover-menus ON TOP — start basic, add incrementally, rather than design the "simple" renderer around features that don't exist yet.** Next session opens on this choice: continue layering on the current (working, tested) foundation, or restart simple-first — salvaging the headless core + the one-guard insight either way.

### Where the project is

Foundations, the container views, the page editor (MarkdownPM), and the page banner are all built and richly featured. The data and read/write paths have caught up to Swift; what remains is a short tail of editor constructs + polish and live UIX passes. The current focus is the editor's final constructs and cleanups (see Next session).

- **Data layer — done.** The full write/mutation side matches Swift (CRUD, properties, connections, Agenda). Files are canonical; the SQLite index is a regeneratable accelerator off the read path. Detail → `Features/Architecture.md`.
- **Design system — done, tokenized, live.** The Figma "Pommora - React" library is the source; the token layer is complete (colour primitives + swappable accent + tint scale + typography + chips), Lucide icons, and a shared CSS-frost glass Material. Showcase live (`npm run showcase`; deploy notes → `Deployment.md`). Spec → `Features/Design.md` + `Features/Typography.md`.
- **Desktop app — runs** (packaged `Pommora.app` + dev-mode HMR) with a working write path + live auto-refresh. One `mutate` IPC (create / rename / delete / move / reorder / setBanner), native right-click menus + ⌘N + inline rename, and a chokidar watcher that swaps the tree in place on external change.
- **Sidebar — fully built.** Renders Contexts + Vaults/Collections/Sets/Pages; create / rename / delete / reorder all from the UI. **Drag-and-drop** is shipped (Apple-style insertion line + grab ghost, no displacement; valid moves only). **Disclosure open/collapse now persists** across sessions (`Sidebar/disclosureState.ts` → localStorage, keyed by entity id; tiers by `tier:*`). **Storage-row click is split:** on vault/collection rows, clicking the icon/title opens the view, while the chevron / empty space / edges only toggle expand-collapse — gated on `onSelect`, so tiers/sets/leaves are unchanged. Spec → `Features/DragAndDrop.md`.
- **Drag engine — PommoraDND, in-house** (replaced `@dnd-kit`). Generic sort engines (list/grid/table/board) behind the `interactions/drag.tsx` seam, exercised in the Interaction Lab; only the sidebar consumes a behaviour so far.
- **Page editor — MarkdownPM, richly built (committed).** Dynamic-syntax Markdown editor on CodeMirror 6 with a framework-free, unit-tested behavior layer behind seams. Inline marks, caret-aware headings + folding, bullet/ordered/task lists, HR, blockquote cards, fenced code, clickable 3-state connections + the `[[` autocomplete panel, a native right-click context menu + ⌘B/I/E/K/⌘⇧X/⌘⇧K shortcuts, input transforms, unfocused-clean render. Full feature map → `Features/MarkdownPM.md`.
- **Tables — built, at a decision point (see ⚠ callout).** Live GFM tables: proportional dash-width columns rendered as a CSS grid with hidden pipes/delimiter, self-healing (committed `f3d321a`; headless core `90f00b3`→`7ce09c5`,`64eb780`). A single `transactionFilter` "structureGuard" makes the structure uncorruptable from the keyboard while cell content edits freely — including emptying a cell; Tab/Enter navigation; `|`→`\|` escape (uncommitted, **26 tests + type-clean**). A 4-agent review hardened it (memoize the doc scan, escaped-`\\|`, wide-row overflow, edge-exit newline, dropped both `!important` for a `.mdpm-editor`-scoped selector). **Not yet built:** resize-drag, grip menus, structural ops, in-cell line breaks. **Known limits (current):** whole-table delete is blocked from the keyboard (the guard cancels it) — it routes through the future "Delete table" grip-menu item via the `StructuralEdit` annotation; a bare `--` delimiter isn't shape-protected (hidden + atomic protects it in practice). Spec → `Features/MarkdownPM.md` § Tables.
- **Page banner + title header — built + live-verified.** A cover band (Swift-compatible `cover` frontmatter, asset under `.nexus/assets/<page-id>/`), full-bleed behind the sidebar + toolbar glass via a local `z-index:0` stacking context. Title overlaid via the shared `DetailTitleHeader` (`[icon][name]`; right-click the icon **or** the name → Rename / Edit Icon; banner's own right-click → Change / Remove); one title size across banner / no-banner; icon sizes to the title and renders nothing when unassigned; the header parks on scroll via a CSS scroll-driven animation (compositor, no shake). Edit Icon routes to a `Components/IconPicker` **stub**.
- **Container + banner views — built.** Vault / Collection render their pages in a table; Context + the nexus-header **Homepage** render their own views. Vault + Collection share one `ContainerView`; every banner-bearing view sits in a shared `DetailScaffold`. A shared image cover renders behind the glass on Vault/Collection/Context/Homepage via the registered `nexus-asset://` protocol; the homepage's banner lives in `.nexus/homepage.json`.
- **Renderer structure mirrors Swift** — `Detail/` (router · `DetailScaffold` · `ContainerView`/`HomepageView`/`ContextView`/`PageView`) · `Sidebar/` · `Components/` · `design-system/`; co-located stylesheets per area. Detail → `Features/Architecture.md`.
- **Repo + branch.** One monorepo, one `main`; the React build lives under `React/`. Work happens in the `pommora-main-preview` worktree on `main`; **nothing is pushed to GitHub** until Nathan says so. **Working tree (uncommitted):** the banner / icon-title + scroll-park work, the sidebar disclosure-persistence + storage-row click-split, and these docs — typecheck + tests green, awaiting a commit. (A dropdown/icon-picker primitive was explored this session, then reverted.)

### Next session

**▶ The Tables decision (see the ⚠ callout up top) gates everything else.**

1. **Decide + act on Tables — sustainable-continue vs simple-first-restart.** If continuing: commit T6 + the 6 agent-fixes (uncommitted, green) with **path-limited staging** (parallel/Swift `M` files in the tree are not yours — `git commit -- React/src/renderer/src/MarkdownPM/Tables/* …`), then build **T8 resize** (the dash-drag that rewrites delimiter dashes; `operations.resizeColumn` is built + tested). If restarting simple-first: salvage the headless core (`model`/`codec`/`regions`/`operations`) + the structureGuard, rebuild the render minimally, then layer dragging/menus on top.
2. **Then the deferred editor tail** (behind the Tables decision): the carried stats-footer + icon-picker (see Pending), then `::` callouts (→ portable `> [!type]`) + the image/latex render seams.

Beyond that: page properties + frontmatter inspector, then Agenda surfacing + the Homepage's dynamic widgets — roadmap in `Framework.md`.

Discipline: a green commit per task; a live UIX pass with Nathan before any milestone closeout. **The editor bakes CM6 extensions at mount — see Working notes for the reload/ghost-window gotcha that cost ~6 rounds this session.**

### Working notes

- UI iteration runs in **dev mode (HMR)** — keep `npm run dev` up; renderer edits hot-reload. Don't ⌘Q it. A component's mount-once `useEffect` won't re-run under Fast Refresh — re-mount (re-select) to see those changes.
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
- **Scroll-linked headers belong on the compositor, not a JS `scroll` handler** — bind the translate to a CSS scroll-driven animation (`scroll-timeline` + `timeline-scope`); a JS handler lags a frame (shake) and forces a layout read each frame.
- **A full-bleed layer behind the floating sidebar must not out-rank it in z-order.** Give an inner element that needs its own z-index a local stacking context (`position:relative; z-index:0`) so it can't escape above the `z-index:1` sidebar glass.
- **Transient UI chrome persists app-side, not in `.nexus/`.** Sidebar disclosure open/collapse saves to localStorage (`Sidebar/disclosureState.ts`) — regeneratable chrome, kept out of the portable nexus model (mirrors Swift `IconFavorites` → UserDefaults), unlike per-page `.nexus/folds.json`.
- **The editor bakes CM6 extensions at mount.** Extension-code changes need a full ⌘R reload, NOT HMR, and a dev-server restart can leave a GHOST Electron window running stale code — kill the app process (`pkill -f "Project Pommora/React/node_modules/electron"`), not just the server. Verify extension behavior **headlessly** (jsdom render of `tableExtension()`) rather than trusting a possibly-stale live window. Cost ~6 debug rounds this session. **→ candidate CLAUDE.md quirk**
- **CM6 injects `.ͼN .cm-line{display:block}` at (0,2,0).** Override line display/padding with a `.mdpm-editor .cm-line.X` (0,3,0) selector, not `!important`. And after several edits to one CSS rule, **read the whole file** — a malformed selector from chained edits (a stray `.cm-line` + an orphaned comment) cost hours while jsdom's `getComputedStyle` correctly reported the failure the whole time; I wrongly doubted the tool.
- **GFM does NOT size columns by dash count** (proven: `|-|` ≡ `|----------|` through micromark). Dash-as-width is a Pommora convention that *requires* the custom grid — it is not free from GFM, and any "just render GFM" path gives content-sized columns that kill the dash-drag resize.
- **Structure protection wants ONE rule, not per-key handlers.** Piecemeal Backspace/Enter/selection guards were endless whack-a-mole; a single shape-preserving `transactionFilter` (cancel any edit that changes `columns:rows:pipes`) covers every edit path — typing, ranged delete, paste, IME — at once. **→ candidate CLAUDE.md quirk**

### Pending focuses

- **Stats footer on pages** — the hover bar: `Vault › Collection › Page` breadcrumb + line / word / char counts. The `editor/textStats.ts` stub exists, unwired. (Carried — behind the Tables decision.)
- **Icon picker** — build the real `Components/IconPicker` (the Edit-Icon menu routes to a stub) + wire the icon's frontmatter save. The Swift `IconPicker` is the spec (SF-Symbols 6-wide glass grid, pill search, saved-on-top, Remove row). (Carried — behind the Tables decision.)
- **Real design-system Components** (Button / Menu / Label / Separator) from the finished token layer — the prerequisite for replacing ad-hoc one-offs (notably the inline-rename `<input>`) during the live UIX pass.
- **Radius + spacing tokens** — corners + spacing are ad-hoc literals; formalize as scales from Figma.
- **Settings editing UI** is deferred — `.nexus/settings.json` (labels + accent) is the control surface for now.
- **Doc mirror** — a launchd watcher mirrors these docs into the Obsidian vault; keep them current so the mirror stays useful.
