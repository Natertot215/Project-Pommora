## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — the detail lives in `Features/*` + `History.md`.

- **PropertiesV2 — the nexus-wide registry.** Definitions live in `.nexus/properties.json` (`{order, defs}`); a Collection's sidecar holds only its assignment-id array; `readNexus` joins the two so every surface gets a resolved schema. Registry mutations serialize; SQLite mirrors it as a regeneratable accelerator.

- **Tables cell + group system.** The full cell-gesture matrix, per-view looks/formats in `column_styles`, band drag, and the reusable table-agnostic editing surfaces in `Detail/Views/PropertyEditing/`. → `Features/TableView.md`.

- **Multi-View Scaffolding + per-type property editors.** The view switcher stack (ViewDropdown · ViewPane · two-door ViewSettings), the G-1 invariant (views never empty where visible), and the Date/Checkbox/Number/Status/Link editor panes. Only the relation/context pickers remain. → [[Views]] + [[Properties]].

- **Icon Picker + Sidebar Ribbon.** The full-Lucide picker in the shared PickerMenu; the ribbon + mode-switched sidebar (surface-launcher model, lazy `agenda:list`, creation via right-click). → [[Icons]] + [[Sidebar]].

- **The Table Grouping Pane (shipped + merged).** Grouping shipped for tables end-to-end — the pane (both doors), the pipeline (structural + sub-group resolver, Location order writing the real filesystem), and the drag surfaces — with the structural-only settings locked view-level beside `group_order`. The tableDnd frozen-closure fix (per-render `cfg` ref) rode along. → [[Views]] `### Grouping` + [[TableView]] + `History.md`.

### Session Summary — The Block Surfaces Brainstorm (Certified)

**Session ID:** abc3bafe-70bc-41e4-adfd-aa052cfee424
**Date:** 07-10-2026
**Model:** Fable 5
**Compactions:** 0
**Connectors:** none
**Commands:** /clear · /handoff
**Agents:** Explore (1x - tier-hardcoding census) · general-purpose (2x - library/prior-art research) · build-breaking-agent (3x - adversarial rounds)
**Skills:** studio-brainstorm · handoff

A full brainstorm arc: Nathan's Contexts rethink became a review-certified spec for the block/tile system, with the contexts question itself deliberately parked.

**The diagnosis reframed the arc:** Nathan opened with two competing Contexts redesigns (user-created groups vs a separate Spaces entity); grounding showed the real disease was **fusion** — the ratified v0.8.0 design reserved block dashboards exclusively to the three tag tiers + Homepage. Mid-session Nathan reframed the deliverable: spec the block system as a host-agnostic invariant that works under ANY contexts resolution ("this is pre-contexts anyways"), and the tiers stay Areas/Topics/Projects. The contexts resolution, sidebar surfaces, and Homepage are all parked for their own pass.

**The artifact:** `Planning/7-10 - Block Surfaces — Decision Log.md`, **review-certified through the full three adversarial rounds** (13 findings, every one independently verified against code before folding). Architecture: a **BlockHost abstraction** (any folder-entity sidecar carrying `blocks[]` — already reserved on disk, empty in Nathan's real Nexus), a tagged-union tile document, three v1 tile types (ULID-named markdown blocks · page embeds · view embeds), **Linked vs Custom views** (Linked = the source's saved view, two-way; Custom = block-owned config querying **nexus-wide** via the property registry, structural grouping generalized to the Collection forest), and full write-through interactivity (D-12: "controlling a Collection's content from a space is the point").

**SurfacePM:** the grid engine decision: an in-house reconstruction of react-grid-layout — vendor its MIT `core` math entry (locally verified React-free, ~1k lines), drop the SSR/breakpoints/touch/react-draggable freight, own components + PommoraDND-style sensors. Survey grounded it: no newer React tile-grid engine exists; Grafana ships RGL + one flushSync patch; Homarr's gridstack fork rotted 590 commits behind: the adopt-and-patch tax SurfacePM avoids.

**The review arc earned its keep:** round 1 falsified "inject rows into TableView" (its `source` coupling includes write-backs) — then round 2's D-12 decision *dissolved* that back into mostly-correct behavior, leaving three named seams (per-instance view resolution off the global `activeViews` slot, persistence routing Linked→sidecar / Custom→payload, embed chrome). Round 2 also caught two `.nexus`-skipping subsystems (connection indexer + `renameCascade`) that must gain host-folder passes for Nathan's markdown-blocks-join-the-link-graph decision. Round 3 forced the nexus-wide Custom View's four sub-decisions (source model, registry schema, batch value IPC, forest grouping) and the B-8 honesty edit (the page-preview surface `open_in` points at is unbuilt).

**Docs reconciled + committed** (`69909d38`): Framework v0.8.0 rewritten to Block Surfaces (SurfacePM), Contexts/Views/PRD/Structure re-pointed to the BlockHost model, the capability-fusion lesson routed to `Guidelines/Design-Lessons.md`.

**Lessons Learned**

- **Reviewer findings can be wrong against product intent, not just code:** round 1's "make embeds read-only" fix was code-sound and still died against PRD:205 + Nathan's actual intent. Verify findings both ways before folding.

- **The single-pane model dissolves whole finding classes:** round 2's "main pane + embed value staleness" scare was impossible by construction (the pane shows the host OR the collection, never both) — Nathan caught it, the reviewers and the main session both missed it. Check the app's structural realities before accepting a coherence bug.

- **Read the library before arguing about it:** the flow-vs-grid recommendation got built on a research agent's summary and died on contact with Nathan ("Please ACTUALLY look into grid layout") — the firsthand README/source read then reversed the recommendation and surfaced the `core` entry that became SurfacePM's foundation.

**Key Files & Insights**

- `Planning/7-10 - Block Surfaces — Decision Log.md` — the certified spec; Sources section holds every verified `file:line`.
- `useActiveView.ts:14` + `TableView.tsx:92-96` — view resolution keys off one global `activeViews[source.id]` slot; the embed host's per-instance seam exists because of this.
- `crud/cascade.ts:20` (`SKIP_TOP_LEVEL ['.nexus','.trash']`) + `index/build.ts:316-326` (pages-only connections) — the two subsystems needing host-folder passes.
- `blocks[]` rides reserved on context sidecars + homepage.json (loose `contextBase`), and every one in Nathan's real Nexus is an empty array — clean codec slate.
- RGL 2.2.3's `./core` export — React-free math (probe at scratchpad `rgl-probe/`), the SurfacePM vendor target.

**User Feedback**

- Nathan drip-feeds decisions mid-turn during brainstorms — fold each immediately into the log, same cadence as live-HMR UIX corrections.
- Locks are kind-specific and generalize: page-lock = no edit/no click-in; view-lock = no configuring, full interacting; the container-wide lock (G-5) is a first-class feature riding the ViewPane's MenuBottomRow.

---

### Working Notes

- **UI iteration runs in dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R**, and **`src/main`/preload need a full dev-process restart** (electron-vite builds main ONCE at launch). Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev`; relaunch with `-- --remote-debugging-port=9222` to keep CDP.

- **HMR is NOT trustworthy for two classes:** (1) vanilla-extract `*.css.ts` — a style edit can serve stale compiled CSS; a plain restart heals it, ⌘R never does. (2) A component's focus effect / handler / attribute change — Fast-Refresh often skips it. (Plain `.css` DOES HMR reliably.)

- **The dev app runs against Nathan's REAL Nexus** (`/Users/nathantaichman/The Nexus`). UI value writes are his data; CDP must open + Esc only, never pick/commit — unless he authorizes a mutating gesture. Native OS menus don't render in the DOM; reach those ops through `window.nexus.*` via `Runtime.evaluate`.

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (two passes, the ONLY type gate) + `npx vitest run` + `env -u ELECTRON_RUN_AS_NODE npm run build`. Biome auto-formats on write — never run it, never hand-align.

- **Parallel sessions / edits** — stage explicit paths, never `-A`. Unattributed `M`/`D` files are almost always Nathan's, left uncommitted on purpose.

- **main is ahead of origin, unpushed** — Nathan pushes in batches on his own call; merge ≠ push.

### Next Session

**1. The Block Surfaces plan** — gated on **Nathan's Figma designs for the handle/hover chrome (G-8)**; once they land, run `superpowers:writing-plans` off the certified decision log. The build spine: SurfacePM (vendored RGL core + sensors) → block doc/IPC → tile types → embed seams → link-graph extensions.

**2. The contexts-resolution brainstorm** — the deliberately-parked companion pass: do-nothing / user-created groups / Spaces entity, the sidebar surfaces (D-10), contexts-as-hosts (B-2), Homepage's shape. The BlockHost abstraction is the room left for it; `Guidelines/Design-Lessons.md` carries its lesson.

**3. The G-5 container view-lock** — standalone-buildable anytime (ViewPane MenuBottomRow lock dimming SettingsPane/ViewPanes container-wide, synced, view CRUD included).

**4. The Navigation system** — the prior arc's next (Navigation Window + Dropdown + Inspector, → [[Navigation]] + [[Inspector]]).

**5. Redesign the Filter authoring pane** — engine shipped, pane pulled for redesign; rebuild from `Planning/7-9 - View Filtering — Decision Log.md` (serializer `filterModel.ts` recoverable at `02042c57^`).

**6. The relation (context) pickers** (Properties.md Pending) + **the non-Table renderers** (Cards · List · Gallery · Calendar · Timeline).

### Pending Focuses

- **User Sections CRUD (the "Add Heading" feature).** Collections can render user-created sections but there's no way to make one (`mutate.ts` has zero section ops). Its own brainstorm→plan→build. → `Sidebar.md` Pending.

- **"None"/flat grouping + Flatten + Hide Location** — the flattened-mode bundle, deliberately deferred (→ [[Views]] `### Grouping`; the `flat` GroupConfig kind stays reserved).

- **(Perf) Standing debt:** (1) no row virtualization — every row MOUNTS, bites at thousands. (2) External VALUE edits don't live-refresh an open table. Container-surgical reconcile is the designed escalation at real scale.

- **Number editor eyeball items (Nathan may tune, not bugs):** Decimals "Hidden", fraction wording, bar clamp edges, the strokeless bar look, field widths. Knobs in `numberEditor.css.ts` / `textPicker.css.ts` / `formatValue.ts`.

- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending adversarial review → plan → build. Distinct from Block Surfaces (free-placement drawing inside Pages); shares the file-per-entity + single-live-editor patterns.

- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the codebase is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.

- **Automatic Scrolling** — must-have for views + MarkdownPM.

- **iCloud-sync readiness (future):** in-process `serializeOnFile` can't coordinate with the iCloud daemon — cross-device is last-writer-wins. `.nexus/index.db` needs sync-exclusion; the walk must skip `.icloud` placeholders.

- **Mobile iOS companion (parked):** spec at `.claude/Mobile/MobileSpec.md`; step 1 is a `window.nexus` bridge shim + a native iCloud Swift plugin. No build commitment.

### Fix Log

- **`.nexus/activeViews.json` + per-machine siblings aren't gitignored (live).** Neither it nor `folds`/`viewOrders`/`tableHeadingColumns`/`linkTitles` are ignored — using the switcher on a fresh container creates a would-sync file. Add to the Nexus `.gitignore` (or scaffold it).

- **The "File" property icon gets clipped** by its vertical row padding on the ViewPane.

- **The link rename field shows a leading empty space (DEPRIORITIZED).** A visual inset, not a stored/typed char. Log it, don't chase it.

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either corrupts the doc (`MarkdownPM/editor/blockModel.ts`, test-pinned, unguarded).

- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → `Features/MarkdownPM.md`.

### Handoff Rules

- **Never record a correction-to-obvious as a discovery.** Write the durable truth as if always so; silently fix what contradicts it. A fresh agent shouldn't be able to tell a mistake was made.

- **Resolve = delete + route, never tag.** When an entry's done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.

- **One block per session, updated in place.** Compactions bump the count, they don't add sections. Carry still-open Pending + Fix Log to a fresh session; compress the prior session's block into Recent Work.

- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.

- **Parallel sessions share this one doc** — a concurrent session adds its own labeled block; Cornerstone + footer shared; never edit another session's block.
