## Handoff — Pommora React

A single 06-27 session that took Collection **Table Views — Part 1 (plumbing)** from cold recon → ratified spec+plan → **SHIPPED**: 11 TDD tasks built, each simplify- + code-reviewed, full suite green + typecheck clean, committed on the **`views-plumbing`** worktree (`d5ed3ac`…`1c892a7`). Next is Part 2 (Figma table + chips) then Part 3 (settings dropdown). **OPEN — the two branches need reconciling:** `views-plumbing` holds the complete Part 1; a parallel React session on `pommora-react` independently committed Task 5 + started its own Task 6. See Next Session.

**Session ID:** de564e01-aa38-498e-b9f8-5db92904a48a
**Dates:** 06-27-2026


> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

**Date:** 06-27-2026
**Model:** Opus 4.8
**Compactions:** 1
**Connectors:** none (in-process tooling + web research; no MCP)
**Commands:** `/handoff`
**Worktree:** Part 1 BUILT on the **`views-plumbing`** worktree (`/Users/nathantaichman/The Studio/Projects/Pommora-views-worktree`), branched off `pommora-react`@`3bb170c` to isolate from the parallel React session
**Agents:** Explore (×6 — Swift view-model · React view-plumbing · view/property specs · React UI-primitives · plan compile-grounding ×2 rounds), builder (×1 — Swift app build), general-purpose (×4 — plan logic/coverage · over-engineering · confirmation logic/coverage · Notion linked-DB research)
**Skills:** `superpowers:brainstorming`, `superpowers:writing-plans`, `handoff`

The session: scouted both builds → established React has the data foundations but the table is a value-less shell → extracted the Swift `SavedView` contract (source + live screenshots) → brainstormed + locked the design with Nathan → wrote the Part-1 plumbing spec + 11-task TDD plan → ran two adversarial review rounds (3 blockers in round 1 → V2; 2 should-fixes in round 2 → folded) → confirmed forward-compat for embedded/context-dashboard views (Notion-validated). Result: ratified, ready to build.

**Locked design (in the spec/plan — this is the contract):** One **portable view config** in the sidecar `views[]` (matching Swift's `SavedView` keys); **active-view pointer per-machine** in `.nexus/activeViews.json` (not the sidecar — no sync churn); values loaded **from files** (frontmatter, property-ID keyed, lazy batch IPC), never SQLite; grouping only for select/status/checkbox/date with **status manual-order**; **multi-key sort** + **recursive AND/OR filters** (deliberate supersets of Swift — Nathan: "going above Swift is fine"); chips are **direct components in `design-system/components/Chips/`** (built on `tokens/chip.css.ts`, not Swift ports); status-before-title hoist + column widths are **Part-2 render concerns**.

**Both Collection AND Set views handled** — one container-relative path (`CollectionNode`/`SetNode` share `{sets,pages}`); Sets/Sub-Sets become nested disclosure groups; empty Sets appear (tree built from the folder walk); Set views inherit the ancestor Collection's schema. Nathan's question caught real gaps (views weren't threaded into the tree; no schema-inheritance; set-sidecar persistence by kind) — all fixed in the plan.

**Embedded/context-dashboard views stay forward-compatible (not scoped, just not blocked):** the pipeline is **view-source-agnostic** (`resolveView({view, rows, schema})` is pure). A future embed = `{ target_collection_id, SavedView }` stored with the dashboard, reusing the same pipeline. Notion research validated this exactly: linked-DB view config lives with the embed, references the source by stable id, source owns schema+data+its own views. Guardrail recorded in the spec — never couple a view's source to the container it renders.

**Lessons Learned**

- **Swift renders `property_order` verbatim — no auto-hoist** of status-before-title (Ideas was hand-ordered). Swift's view pipeline is also **single-key sort** and **shape-inference** based. So React's multi-key + declared-type-branch + the status hoist are all deliberate supersets, framed as such (not false "ports").
- **Filter `op` strings are snake_case raw values** (`is`, `greater_than`, `on_or_after`…), and Part 1 ports the **evaluator** matrix (wider than the picker): tier relations filter by membership, user relation/file presence-only. `_modified_at` filters as a date (`declaredType`→`last_edited_time`). `PropertyType` enum values are snake_case (`multi_select`/`last_edited_time`) — distinct from camelCase `PropertyValue.kind` tags; `switch` on the snake_case.
- **`shared/` can't import `main/`** — `mintDefaultView` uses a `'view_default'` sentinel id; `main` swaps a real `view_<ulid>` (`newId()`) on first save.
- **The live vault isn't in-repo** → the conformance fixture is **synthetic** (`__fixtures__/collection-with-status.json`), not the real Ideas sidecar.
- **Drive the Swift app for screenshots** via a compiled `CGEvent` click helper + `screencapture -R` (no cliclick/Quartz on this host; reason in capture-region fractions, not displayed pixels).

**Key Files & Insights**

- **Plan + spec (ratified, committed):** `React/.claude/Planning/6-27 - Table Views Plumbing Plan.md` (11 TDD tasks) + `…Spec.md`. The plan's **Global Constraints** govern every task.
- Swift port targets: `Domain/Collections/SavedView.swift`, `Features/Detail/ViewPipeline/{GroupResolver,SortComparator,DateBucket,VisiblePropertyOrder}.swift`, `Features/Detail/Table/TableColumnResolver.swift`, `Features/ViewSettings/FilterPane.swift`.
- React seams: `shared/{propertyValue,properties,schemas,types}.ts`, `main/{ids,paths,sidecarIO}.ts`, `main/io/folds.ts` (the activeViews pattern), `main/readNexus.ts` (needs `meta.views` read — Task 1), `Detail/Scope.ts` (`findContext` — Part-2 chip resolution), `Detail/Table/` (→ `Detail/Views/`).

**Landmines**

- **Live Swift parallel session on `main`** — stage explicit paths, never `-A`. As of handoff, `main` also carried the parallel session's uncommitted `Styles.css` + `folding.ts` (NOT mine — left untouched).
- **Swift app left running** (built for screenshots; Ideas active-view flipped gallery→table, a harmless per-machine state change). Quit if underfoot.
- **Worktree `node_modules`** is for the Vitest/Node gate; a GUI launch needs `./node_modules/.bin/electron --version` once. Part-1 TDD is Vitest only — no launch needed for green.

**Uncertain**

- Whether the Swift parallel session is still active; its commits touch `shared/types.ts` / `main/index.ts` / `preload/index.ts` — the Part-1 overlap files. Re-pull `main` into the worktree before/while executing if it advances.

---

### Working Notes

- UI iteration runs in **dev mode (HMR)**; CM6 widget/extension code needs a full ⌘R / `Page.reload` (only CSS hot-swaps). Main-process edits (IPC, native menus, preload) need a dev-server restart. Don't ⌘Q the live session.
- Runs against a **test nexus** (`~/test`, managed, carries `.nexus/`). The app opens its `lastNexusPath`.
- The agent can screenshot + drive the React UI headlessly (Electron `--remoteDebuggingPort` → CDP) and the Swift app (CGEvent + `screencapture -R`). Nathan is primary visual verifier.
- **Parallel sessions happen** — never bundle/revert unattributed changes; stage explicit paths. The Swift build keeps its own separate root handoff.
- `Context.md` (current build-state companion) exists (added by the parallel session) — keep it current alongside this journey doc.

### Next Session — Part 2 (then Part 3), after the branches reconcile

**Part 1 is SHIPPED** — 11 TDD tasks, each simplify- + code-reviewed, full suite + typecheck green, on the **`views-plumbing`** worktree (`d5ed3ac`…`1c892a7`). Do NOT rebuild it. The pipeline lives in `renderer/src/Detail/Views/pipeline/`; main-side IO in `main/io/activeViews.ts` + `main/crud/{views,loadValues}.ts`; the on-disk contract in `shared/views.ts`. Decisions → `History.md`.

**FIRST — reconcile the two branches (Nathan's call):** `views-plumbing` (`/Users/nathantaichman/The Studio/Projects/Pommora-views-worktree`) holds the complete Part 1 on top of `pommora-react`@`3bb170c`. The parallel React session on **`pommora-react`** independently committed Task 5 (`3bb170c`, which bundled my group files) and left an uncommitted Task-6 WIP there (a `filter.test.ts` using a non-canonical `options`/`default` schema shape) plus a `vitest.config` __dirname fix (which `views-plumbing` already has, identical, as `4368895`). `views-plumbing` is the keeper — merge it to `main` (or onto a reconciled `pommora-react`) and supersede the parallel Task-6 WIP. Then run all React work from one worktree.

**Part 2 — table UIX (Nathan designs in Figma):** build the table + chips as direct `design-system/components/Chips/` components (on `tokens/chip.css.ts`, shared by select/multi/status — NOT Swift ports), routed to the `ResolvedColumn[]` / `ResolvedGroup[]` seams from `resolveView`. Inline cell editor: glass-control chip pickers, plain inputs, a "Calendar" date placeholder, native menus for simple actions. Render concerns deferred from Part 1 land here: the group/sort **column hoist before `_title`**, **column widths**, **relation/tier chip resolution** (`Detail/Scope.ts` `findContext`). Replace TableView's minimal render.

**Part 3 — View Settings:** the glass-surface dropdown + Sort/Filter/Group/Layout panes + the operator picker (narrower than the evaluator matrix) + view rename/dup/delete + `open_in` + `display_as`. Wire the `views:save/reorder/delete` + `activeViews` IPC already shipped in Part 1. Keep embedded/context-dashboard views unblocked (the pipeline is view-source-agnostic).

### Pending Focuses

- **Table Views Parts 2 & 3** — see Next Session. Part-1 plumbing is SHIPPED on `views-plumbing`.
- **Part-1 deferred cleanups (Nathan's call):** (1) extract one generic `.nexus` map-store factory for the 3 identical stores (folds / tableHeadingColumns / activeViews — same lenient-read / merge-write / empty-deletes shape across module + IPC + preload); (2) a borderline `relPosix(root,abs)` helper (`loadValues` + `watcher` share the `relative().split(sep).join('/')` idiom).
- **Break-things skill (Nathan-requested)** — a reusable adversarial-fuzzing skill from `Guidelines/Adversarial-Review-Log.md`: break-attempt taxonomy + the "toddler" method + a `{keys}×{positions}×{nesting}×{adjacency}` generator → break→repro→fix catalog before any UI feature is "done."
- **Canvas** — spec parked at `Planning/6-26 - Canvas Spec.md`, pending its adversarial review → plan → build. React-first; `.canvas` is the cross-build contract.
- **Caret on other surfaces** — drawn caret shipped on the page editor; extend to table cells + the inline-rename input.
- **Subfield reorder + live-stats + custom items** — `Features/Subfield.md` § Roadmap.
- **Icon picker** — build `Components/IconPicker` + wire the icon frontmatter save.
- **Real design-system Components** (Button / Menu / Label / Separator / **Chips**) from the token layer.
- **Radius + spacing tokens** — lift from Figma (still ad-hoc literals).
- **Settings editing UI** deferred — `.nexus/settings.json` is the control surface.
- **Biome config vs code (repo-wide)** — `biome.json` declares `quoteStyle:"double"` + organizeImports, but the whole codebase is hand-written single-quote / no-semicolon (internally consistent; the format hook isn't converting quotes in the worktree). Settle once: set the config to match the code, OR reformat the repo to the config.
- **Unsorted bin → folder + sidecar (paradigm, ratify first)** — move "unsorted" onto a real `Unsorted/` folder + `_unsortedconfig.json` (folder-with-sidecar). Interop win. On-disk shape — ratify before building.

### Fix Log

- **Aliased `[[A|B]]` vs cell-pipe** — a `|` in an aliased connection collides with cell-pipe escaping; autocomplete only inserts alias-free `[[Title]]`. Open paradigm call.
- **Table links non-clickable** — no input handling for a rendered link inside a cell; proposed single-click navigate + right-click edit.
- **Bullet single-word wrap drops the word below the marker** — the marker-space hide didn't survive CM6's replace decoration; only the `line-height` cap shipped. → `Features/MarkdownPM.md` § Known issues.
- **Recents submenu on "Open Nexus"** lists trashed folders; opening one pulls it out of trash.

### Handoff Rules

- **Resolve = delete + route, never tag.** A done entry's real outcome goes to its canonical doc (`History.md` / `Features/*` / `Framework.md`); delete the line — no `(Resolved)` tombstones.
- **One block per session, updated in place.** Compactions bump a `Compactions` count, not new sections. Carry still-open Pending Focuses to a fresh *sequential* session.
- **Markdown only, single file** (per Nathan) — this stays `React/.claude/Handoff.md`, not a routed `Handoffs/` dir, regardless of the skill's filename shapes/config route.
- **Parallel React sessions share this doc** as `### Session Summary - A/B/…` blocks under the shared Cornerstone top matter; the newcomer takes the next free letter and never edits another's block (except removing a resolved Landmine/Uncertain). The footer is shared. The Swift build keeps its own separate root handoff.
