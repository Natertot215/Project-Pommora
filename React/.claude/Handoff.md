## Handoff — Pommora React

A single 06-27 session that took Collection **Table Views — Part 1 (plumbing)** from cold recon to a **ratified, execution-ready** spec + plan (two adversarial review rounds, all findings folded). **Nothing is implemented yet — the next move is to BUILD it**, in the `pommora-react` worktree. A live **Swift** parallel session committed on `main` all day (its own root handoff). Read the **execution playbook** (Next Session) first; it's the whole point of this doc.

**Session ID:** de564e01-aa38-498e-b9f8-5db92904a48a
**Dates:** 06-27-2026


> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

**Date:** 06-27-2026
**Model:** Opus 4.8
**Compactions:** 0
**Connectors:** none (in-process tooling + web research; no MCP)
**Commands:** `/handoff`
**Worktree:** planned/reviewed on the `main` checkout; **execution moves to the `pommora-react` worktree** (set up this session — see playbook)
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

### Next Session — EXECUTE Part 1 (start here)

**State:** Table Views Part-1 plumbing is **specced, planned, and RATIFIED** (two review rounds, all folded — do **NOT** re-review; build it). Nothing is implemented yet. 11 TDD tasks, each an independent green commit.

**Where to build — the `pommora-react` worktree:**
- Path: `/Users/nathantaichman/The Studio/Projects/Pommora-react-worktree` (branch `pommora-react`, fast-forwarded to `main` this session → current, not stale; carries the ratified plan + spec).
- Build React code **there** (per `CLAUDE.md`); merge `pommora-react` → `main` once Part 1 greens. Swift parallel session is on `main` — keep staging explicit.
- The plan + spec are at `React/.claude/Planning/6-27 - Table Views Plumbing {Plan,Spec}.md` inside the worktree. If `main` advanced, `git -C <worktree> merge --ff-only main` (or rebase) first.
- Worktree `node_modules`: Vitest/Node gate only; if it's missing run `npm install` in the worktree. TDD = `npx vitest run <file>`; no app launch for the Part-1 green bar.

**How:** **subagent-driven** (recommended) — fresh agent per task, review the diff between each; or inline. Go **Task 1 → 11 in order** (1–8 pure, 9–10 main-side IPC, 11 integration). Each task: failing test → run (fail) → minimal impl → run (pass) → green commit. The plan's per-task **Interfaces (Produces/Consumes)** + Global Constraints are the spec for each agent; the synthetic fixture is the conformance check.

**Green bar for Part 1:** a hand-seeded view config renders real, correctly sorted/grouped columns with live property values — no settings UI. Then **Part 2** (Nathan designs the table in Figma → build the table + chips as direct `design-system/components/Chips/` components, routed to the `ResolvedColumn[]` / `ResolvedGroup[]` seams; inline cell editor with glass-control chip pickers, plain inputs, a "Calendar" date placeholder, native menus for simple actions) → **Part 3** (the View Settings glass-surface dropdown + panes + operator picker + view rename/dup/delete + `open_in` + `display_as`). Keep embedded/context-dashboard views unblocked (view-source-agnostic).

### Pending Focuses

- **Table Views Parts 2 & 3** — see the playbook above; both gated on Part-1 plumbing greening.
- **Break-things skill (Nathan-requested)** — a reusable adversarial-fuzzing skill from `Guidelines/Adversarial-Review-Log.md`: break-attempt taxonomy + the "toddler" method + a `{keys}×{positions}×{nesting}×{adjacency}` generator → break→repro→fix catalog before any UI feature is "done."
- **Canvas** — spec parked at `Planning/6-26 - Canvas Spec.md`, pending its adversarial review → plan → build. React-first; `.canvas` is the cross-build contract.
- **Caret on other surfaces** — drawn caret shipped on the page editor; extend to table cells + the inline-rename input.
- **Subfield reorder + live-stats + custom items** — `Features/Subfield.md` § Roadmap.
- **Icon picker** — build `Components/IconPicker` + wire the icon frontmatter save.
- **Real design-system Components** (Button / Menu / Label / Separator / **Chips**) from the token layer.
- **Radius + spacing tokens** — lift from Figma (still ad-hoc literals).
- **Settings editing UI** deferred — `.nexus/settings.json` is the control surface.
- **One-time Biome normalization** — defer to a tree with no parallel uncommitted edits.
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
