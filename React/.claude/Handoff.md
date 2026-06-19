## Handoff — Pommora React

Lean current-state snapshot. Read first at session start. Deep docs: data layer → `Planning/Data-Layer-Handoff.md`; desktop/filesystem → `Planning/Desktop-Filesystem-Integration.md`; design system → `Features/Design.md` + `Features/Typography.md`; drag-and-drop → `Features/DragAndDrop.md`; locked decisions → `History.md`.

### Where the project is

Foundations are down; the **main content pane is the next big piece** — the app navigates and organizes fully, but selecting anything still shows a placeholder ("render coming next"), so it can't yet show or edit a page's content.

- **Data layer — done.** The full write/mutation side caught up to Swift (CRUD, properties, connections, Agenda). Files are canonical; the SQLite index is a regeneratable accelerator off the read path. Tests-only at this level. Detail → `Planning/Data-Layer-Handoff.md`.
- **Design system — done, tokenized, live.** The Figma "Pommora - React" library is the source; the token layer is complete (colour primitives + a swappable accent + tint scale + typography + chips), Lucide icons, and a shared CSS-frost glass Material. Showcase live at https://pommora-design-system.vercel.app (`npm run showcase`). Spec → `Features/Design.md` + `Features/Typography.md`.
- **Desktop app — runs (packaged `Pommora.app` + dev-mode HMR), with a working write path + live auto-refresh.** One `mutate` IPC (create / rename / delete / move / reorder; relative paths resolved under the root), native right-click menus + ⌘N + inline rename on every sidebar row, and a chokidar watcher that re-reads and swaps the tree in place on external changes. Detail → `Planning/Desktop-Filesystem-Integration.md`.
- **Sidebar — fully built, drag-and-drop included.** Renders Contexts + Vaults/Collections/Sets/Pages; create / rename / delete / reorder all from the UI. **Drag-and-drop is shipped + committed** — the bespoke "sidebar" behaviour (Apple-style insertion line + grab ghost, no displacement): every entity reorders within its parent, pages move freely across the tree, sets move between collections, collections and sets stay within their vault, and invalid moves no-op. Followed by a DRY refactor of the sidebar + its data routing (one store write-path, a shared row wrapper, a single slot helper, single-sourced order-key types). typecheck + tests green (320); live-verified. Spec → `Features/DragAndDrop.md`.
- **Drag engine — PommoraDND, in-house (replaced `@dnd-kit`).** The generic sort engines (list/grid/table/board) sit behind the `interactions/drag.tsx` seam and are exercised in the Interaction Lab; so far only the sidebar consumes a drag behaviour (its own, above). View-row adoption + board keyboard are deferred.
- **Repo + branch.** One monorepo, one `main`; the React build is a sub-project under `React/`. Current work (sidebar DnD + the typography rename) is committed on the **`file-watcher`** branch; `main` is a clean ancestor, behind for now — it fast-forwards when we ship the branch. Nothing is pushed to GitHub until Nathan says so.

### Next session

**▶ Build the main content pane, starting with the Page view (read → edit).** Pages are the core entity, and the editor is the deferred keystone.

1. **Read-only page render first** — `react-markdown` + `remark-gfm` (already deps) render the selected page's body; a quick win that makes the shell feel like a real app.
2. **Then the editor** — wire the editing surface (CodeMirror 6 is the candidate, not yet committed); worth a brainstorm/spec pass before building.

After the Page view: vault/context detail **views** (listing a collection's pages) · page **properties** + the frontmatter inspector · then Agenda + the Homepage.

Discipline: a green commit per task with an adversarial review (standard agents), and a live UIX pass with Nathan before any milestone closeout.

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

### Pending focuses

- **Real design-system Components** (Button / Menu / Label / Separator) built from the finished token layer — the prerequisite for replacing ad-hoc one-offs (notably the inline-rename `<input>`, a guessed design) during the live UIX pass.
- **Radius + spacing tokens** — corners (6–16px) + spacing are ad-hoc literals; formalize as scales from Figma.
- **Settings editing UI** is deferred — `.nexus/settings.json` (labels + accent) is the control surface for now.
- **Doc mirror** — a launchd watcher mirrors the React docs into the Obsidian vault (`Atlas/II. Projects/Pommora/II. React`); keep these docs current so the mirror stays useful.
