## Handoff — Pommora React

Lean current-state snapshot. Read first at session start. Deep docs: data layer → `Planning/Data-Layer-Design.md`; desktop/filesystem → `Planning/Desktop-Filesystem-Integration.md`; design system → `Features/Design.md` + `Features/Typography.md`; drag-and-drop → `Features/DragAndDrop.md`; locked decisions → `History.md`.

### Where the project is

Foundations, the **container views**, AND the **page editor (MarkdownPM)** are down — selecting a page now renders an editable Markdown surface. The editor is an in-house, faithful port of the Swift `MarkdownPM` package on CodeMirror 6. What remains: a handful of constructs (callouts, wikilink resolution, image/latex, folding) and one **persistent list/line-editing issue** (below) that needs real tracing, not another patch.

- **Data layer — done.** The full write/mutation side caught up to Swift (CRUD, properties, connections, Agenda). Files are canonical; the SQLite index is a regeneratable accelerator off the read path. Tests-only at this level. Detail → `Planning/Data-Layer-Design.md`.
- **Design system — done, tokenized, live.** The Figma "Pommora - React" library is the source; the token layer is complete (colour primitives + a swappable accent + tint scale + typography + chips), Lucide icons, and a shared CSS-frost glass Material. Showcase live at https://pommora-design-system.vercel.app (`npm run showcase`). Spec → `Features/Design.md` + `Features/Typography.md`.
- **Desktop app — runs (packaged `Pommora.app` + dev-mode HMR), with a working write path + live auto-refresh.** One `mutate` IPC (create / rename / delete / move / reorder; relative paths resolved under the root), native right-click menus + ⌘N + inline rename on every sidebar row, and a chokidar watcher that re-reads and swaps the tree in place on external changes. Detail → `Planning/Desktop-Filesystem-Integration.md`.
- **Sidebar — fully built, drag-and-drop included.** Renders Contexts + Vaults/Collections/Sets/Pages; create / rename / delete / reorder all from the UI. **Drag-and-drop is shipped + committed** — the bespoke "sidebar" behaviour (Apple-style insertion line + grab ghost, no displacement): every entity reorders within its parent, pages move freely across the tree, sets move between collections, collections and sets stay within their vault, and invalid moves no-op. Followed by a DRY refactor of the sidebar + its data routing (one store write-path, a shared row wrapper, a single slot helper, single-sourced order-key types). typecheck + tests green; live-verified. Spec → `Features/DragAndDrop.md`.
- **Drag engine — PommoraDND, in-house (replaced `@dnd-kit`).** The generic sort engines (list/grid/table/board) sit behind the `interactions/drag.tsx` seam and are exercised in the Interaction Lab; so far only the sidebar consumes a drag behaviour (its own, above). View-row adoption + board keyboard are deferred.
- **Page editor — MarkdownPM, substantially built (committed).** A dynamic-syntax Markdown editor: CodeMirror 6 substrate + micromark/mdast parser, both behind seams; the behavior layer (`parser`/`detect`/`tokens`/`input`/`decorations`) is framework-free + unit-tested (415 tests). Shipped: inline marks (bold/italic/strike/inline-code/link/connection), caret-aware headings (`#` reveal + per-level sizing), bullet/ordered/task lists, HR, blockquote cards, fenced code blocks (fences hide caret-out); an inline title + divider in a scroll-tracking top zone with rename-on-Enter (reuses `submitRename`); input transforms (list continuation, smart-backspace, auto-pair, dash/arrow, checkbox-canonicalize, Tab-indent, Shift+Enter exit, blockquote continuation); unified zoom (slider built, not yet placed); the body gutter aligned to the title. Spec → `Planning/MarkdownPM.md`; phased plan → `Planning/MarkdownPM-Build-Plan.md`.
- **Container views — built.** Selecting a Vault or Collection renders its pages in a table; Context + the nexus-header **Homepage** render their own (currently blank-but-real) views. Vault + Collection share one `ContainerView` (same view principles, `source.kind` the divergence seam); every banner-bearing view sits in a shared `DetailScaffold` (banner + body + divider). Homepage + Collections are now **selectable sidebar entities** (the nexus header *is* the homepage).
- **Banner — built.** A shared image cover *behind the glass* on Vault/Collection/Context/Homepage: native picker → `.nexus/assets/<id>/banner-<token>.<ext>` → served over a registered `nexus-asset://` protocol; native Change/Remove menu; one `setBanner` mutate op (the homepage's banner lives in the `.nexus/homepage.json` singleton). Spec → `Planning/Banner-Design.md`.
- **Renderer structure — mirrors Swift.** `Detail/` (router · `DetailScaffold`≈ViewSurface · `Scope`≈DetailScope · `ContainerView`/`HomepageView`/`ContextView`/`PageView`) · `Detail/Table/` · `Detail/Banner/` · `Sidebar/` · `Components/`; the `styles.css` monolith split into co-located stylesheets per area. Detail → `Features/Architecture.md`.
- **Repo + branch.** One monorepo, one `main`; the React build is a sub-project under `React/`. The live React session works in the **`pommora-main-preview` worktree on `main`**; all work (banner, container views, the Swift-aligned renderer reorg, and the MarkdownPM editor) is **committed locally on `main`** there — **nothing is pushed to GitHub** until Nathan says so.

### Next session

**▶ The persistent list / line-editing issue — trace it before patching (top editor priority).** See "Known issue" below. Several surface fixes were tried and reverted; the next pass must trace from the initial CodeMirror decoration + line-geometry build, not guess.

**Remaining editor constructs** (Build-Plan phases): `::` callouts (→ portable `> [!type]`, via the codec) · wikilink 3-state resolution (resolved / phantom / ambiguous, wired to `@shared/connections`) · image + latex service seams · heading folding (chevron + `.nexus/folds.json`) · the `[[` connection autocomplete panel · native OS context menu + stats footer · placing the zoom slider in the UI.

After the editor: page **properties** + frontmatter inspector · Agenda · the Homepage's dynamic widgets.

Discipline: a green commit per task with an adversarial review (standard agents), and a live UIX pass with Nathan before any milestone closeout.

### Known issue — list markers + line editing (pending deep exploration)

Bullet / ordered / task markers render as atomic CM6 **replace-widgets**, so they are **not editable inline** like normal text, and the marker↔text spacing + the "add a space after the marker" editing behaviour is **bugged** — e.g. typing a space after a numbered marker misbehaves (the space is swallowed and the adjacent bold reveals its raw `**`).

Multiple fixes were attempted and **all reverted**: caret-aware marker reveal, editable clear-color marks + a `•` overlay (the Swift model), and a natural-width hanging indent. Each broke the indentation or alignment. **The root cause has not been found** — this is *pending deep exploration*. It needs real tracing back to the **initial CodeMirror build** (how line decorations, replace-widgets, the `padding-left` / negative `text-indent` hanging indent, and CM6's caret/coordinate mapping actually interact), not another surface patch.

Current committed state is the **widget approach** — markers aligned but non-editable. Kept on top (uncommitted, working): the body-gutter↔title alignment and the independent `--bullet-indent` / `--gap` list knobs. Target model (Swift reference): markers are `NSColor.clear` *editable text* with an overlaid glyph drawn always-on (not caret-aware) — `External/MarkdownPM/Sources/MarkdownPM/Input/MarkdownListHandler.swift` + `Renderer/MarkdownTextLayoutFragment.swift`.

### Working notes

- UI iteration runs in **dev mode (HMR)** — keep `npm run dev` up; renderer edits hot-reload into the window. Don't ⌘Q it.
- **Main-process edits need a dev-server restart.** The main-watcher can go stale in a long-running session — a real recurring trap: if a mutation silently doesn't persist, suspect a stale main and restart `npm run dev`. Repackage the Dock app only at milestones.
- Runs against a **test nexus** (`~/test`) so nothing real is touched. It must be a *managed* nexus (carry `.nexus/nexus.json` + per-folder sidecars) for reorder to persist on read — an "adopted" folder with no identity ignores the on-disk order.
- A GUI app can't be launched from the agent shell (no Aqua session) — Nathan is the visual verifier, or the agent drives it via screen control when he's away.
- **Parallel sessions happen** — the working tree isn't guaranteed yours alone. Never bundle or revert unattributed changes; commit with **path-limited commits** (`git commit -- <paths>`) so concurrent staging can't leak in.

### Lessons learned (durable)

- vanilla-extract vars are hashed, so plain CSS can't read them; the `theme-vars.css.ts` bridge re-exports them as stable `var(--…)` — one source across `.ts` and `.css`.
- The packaged renderer must serve over the registered **`app://` scheme**, never `file://` (Vite's ES-module scripts hit module CORS over `file://` → blank window). Dev over http is unaffected.
- **better-sqlite3 is dual-ABI** (Node ≠ Electron). `node_modules` stays Node-ABI so the vitest gate is reliable; electron-builder rebuilds for Electron at package time; `db.ts` lazy-requires it so an ABI mismatch degrades to a cold index instead of crashing (the index is off the read path).
- The live watcher must watch `.nexus/` (Contexts + settings live there) **and** carry an `.on('error')` guard, or fd/inotify exhaustion re-throws as an unhandled error and crashes the main process.
- **A stable asset filename behind glass is a stale-image trap.** Banners write a *fresh* filename per save (`banner-<token>.<ext>`) so the `<img>` URL changes and the renderer can't serve the browser-cached previous image; image bytes ride a registered `nexus-asset://` protocol (kept out of the reloaded `NexusTree`), not base64-in-tree.

### Pending focuses

- **Real design-system Components** (Button / Menu / Label / Separator) built from the finished token layer — the prerequisite for replacing ad-hoc one-offs (notably the inline-rename `<input>`, a guessed design) during the live UIX pass.
- **Radius + spacing tokens** — corners (6–16px) + spacing are ad-hoc literals; formalize as scales from Figma.
- **Settings editing UI** is deferred — `.nexus/settings.json` (labels + accent) is the control surface for now.
- **Doc mirror** — a launchd watcher mirrors the React docs into the Obsidian vault (`Atlas/II. Projects/Pommora/II. React`); keep these docs current so the mirror stays useful.
