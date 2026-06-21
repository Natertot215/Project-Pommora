## Handoff — Pommora React

Lean current-state snapshot. Read first at session start. Shipped detail → `History.md`; roadmap → `Framework.md`; deep specs → `Planning/`; build/run traps → `Guidelines/Build-Gotchas.md`.

### Where the project is

Foundations, the **container views**, and the **page editor (MarkdownPM)** are down — selecting a page renders an editable Markdown surface. The data layer is caught up to Swift (headless — CRUD, properties, connections, Agenda; files canonical, SQLite a regeneratable accelerator off the read path). The desktop app runs (packaged `Pommora.app` + dev-mode HMR) with a working write path + live auto-refresh: one `mutate` IPC, native right-click menus + ⌘N + inline rename, a chokidar watcher re-reading the tree on external change. The sidebar is fully built — Contexts + Vaults/Collections/Sets/Pages, create/rename/delete/reorder, drag-and-drop shipped. The design system is tokenized + live (showcase at https://pommora-design-system.vercel.app, `npm run showcase`).

What remains: a handful of editor constructs (callouts, wikilink resolution, image/latex, folding) and one **persistent list/line-editing issue** (below) that needs real tracing, not another patch.

**Repo + branch.** One monorepo, one `main`; React is a sub-project under `React/`. The live session works in the **`pommora-main-preview` worktree on `main`**; everything is **committed locally on `main`** there — **nothing pushed to GitHub** until Nathan says so.

### Next session

**▶ The persistent list / line-editing issue — trace it before patching (top editor priority).** Several surface fixes were tried and reverted; the next pass must trace from the initial CodeMirror decoration + line-geometry build, not guess.

**Remaining editor constructs:** `::` callouts (→ portable `> [!type]`) · wikilink 3-state resolution (resolved / phantom / ambiguous) · image + latex service seams · heading folding (chevron + `.nexus/folds.json`) · the `[[` autocomplete panel · native OS context menu + stats footer · placing the zoom slider.

**After the editor:** page properties + frontmatter inspector · Agenda surfacing · the Homepage's dynamic widgets.

Discipline: a green commit per task with an adversarial review (standard agents), and a live UIX pass with Nathan before any milestone closeout.

### Working notes

- UI iteration runs in **dev mode (HMR)** — keep `npm run dev` up; renderer edits hot-reload. Don't ⌘Q it.
- **Main-process edits need a dev-server restart.** A real recurring trap: if a mutation silently doesn't persist, suspect a stale main and restart `npm run dev`. Repackage the Dock app only at milestones.
- Runs against a **test nexus** (`~/test`). It must be a *managed* nexus (`.nexus/nexus.json` + sidecars) for reorder to persist on read — an adopted folder with no identity ignores on-disk order.
- A GUI app can't launch from the agent shell (no Aqua session) — Nathan is the visual verifier, or the agent drives via screen control when he's away.
- **Parallel sessions happen** — the working tree isn't guaranteed yours. Never bundle or revert unattributed changes; use **path-limited commits** (`git commit -- <paths>`).

### Lessons learned (durable)

- vanilla-extract vars are hashed, so plain CSS can't read them; the `theme-vars.css.ts` bridge re-exports them as stable `var(--…)` — one source across `.ts` and `.css`.
- The packaged renderer must serve over the registered **`app://` scheme**, never `file://` (Vite's ES-module scripts hit module CORS over `file://` → blank window). Dev over http is unaffected.
- **better-sqlite3 is dual-ABI** (Node ≠ Electron). `node_modules` stays Node-ABI so the vitest gate is reliable; electron-builder rebuilds for Electron at package time; `db.ts` lazy-requires it so an ABI mismatch degrades to a cold index instead of crashing (the index is off the read path).
- The live watcher must watch `.nexus/` (Contexts + settings live there) **and** carry an `.on('error')` guard, or fd/inotify exhaustion re-throws as an unhandled error and crashes the main process.
- **A stable asset filename behind glass is a stale-image trap.** Banners write a *fresh* filename per save (`banner-<token>.<ext>`) so the `<img>` URL changes and the renderer can't serve the browser-cached previous image; image bytes ride a registered `nexus-asset://` protocol (kept out of the reloaded `NexusTree`), not base64-in-tree.

### Pending focuses

- **Real design-system Components** (Button / Menu / Label / Separator) from the finished token layer — the prerequisite for replacing ad-hoc one-offs (notably the guessed inline-rename `<input>`) during the live UIX pass.
- **Radius + spacing tokens** — corners + spacing are ad-hoc literals; formalize as scales from Figma.
- **Doc mirror** — a launchd watcher mirrors these docs into the Obsidian vault (`Atlas/II. Projects/Pommora/II. React`); keep them current so the mirror stays useful.
