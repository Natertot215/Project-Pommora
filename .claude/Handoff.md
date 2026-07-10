## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — the detail lives in `Features/*` + `History.md`.

- **PropertiesV2 — the nexus-wide registry.** Definitions live in `.nexus/properties.json` (`{order, defs}`); a Collection's sidecar holds only its assignment-id array; `readNexus` joins the two so every surface gets a resolved schema. Registry mutations serialize; SQLite mirrors it as a regeneratable accelerator.

- **Tables cell + group system (Phases 1-3).** The full cell-gesture matrix (title navigates · status/select/multi/context open the PickerMenu · numbers inline-edit · urls/files open through IPC · right-click always menus). Per-view looks/formats persist in the SavedView's `column_styles`. Group bands drag to reorder; the reusable editing surfaces live table-agnostic in `Detail/Views/PropertyEditing/`. → `Features/TableView.md`.

- **Multi-View Scaffolding + the per-type property editors.** The per-container view switcher stack (ViewDropdown · ViewPane→SettingsPane rename · two-door ViewSettings), the **G-1 invariant** (views never empty where views can be seen — creation-seed + entry-mint, adopt-only through `saveViewAdopting`), and the Date & Time · Checkbox · Number · Status · Link/URL editor panes (def-level config via registry IPC, per-view look via `column_styles`). Only the relation/context pickers remain. → `Views.md` + `Properties.md`.

- **Icon Picker.** The full-Lucide picker (~1,715 icons, virtualized, `label-control`, non-autofocus search) with native right-click Favorites + a drag-order favorites box, hosted in the shared PickerMenu (which grew the horizontal beak, `center` straddle, auto-flip). **One shared `setIcon` write** covers all six edit-icon sites; `Icon` is a `forwardRef` so the glyph itself anchors the beak. → `Icons.md` + `History.md`.

- **Sidebar Ribbon (merged to main).** The sidebar became a ribbon + mode-switched content column — the surface-launcher model (Homepage photo = a selection; Collections/Contexts/Agenda switch `personalization.sidebarMode`; Nav/Settings inert placeholders), instant mode swap, a lazy `agenda:list` IPC off the tree walk, NexusHeader dissolved (rename → homepage banner title), creation via right-click on the empty mode area. → `Sidebar.md` + `History.md`.

### Session Summary — The Table Grouping Pane (Shipped + Merged)

**Session ID:** c3e6af60-f1ea-4e19-9507-08776f15d04a
**Dates:** 07-05 → 07-09-2026
**Model:** Opus 4.8 → Fable 5 (switched at the grouping arc's start)
**Compactions:** 9
**Connectors:** none (CDP available; this arc Nathan was the live eyes over HMR — no CDP driving needed)
**Commands:** /compact · /model · /handoff
**Agents:** Explore (10x - grounding/research) · build-breaking-agent (10x - spec ×3 + plan ×3 + prior arcs) · code-simplifier (5x - plan advisory + post-merge pass + prior arcs)
**Skills:** studio-brainstorm · `superpowers:writing-plans` · `superpowers:executing-plans` · handoff

The grouping arc, end to end in one day: brainstorm → 3-round-certified decision log → 3-round-attacked plan + simplifier advisory → inline TDD build (12 tasks) → a long live-HMR UIX loop → merged to main → post-merge simplifier pass. Grouping is **shipped for tables**; the deferred ledger lives in [[Views]] `### Grouping`, the render truth in [[TableView]] `II. Groupings`. The Icon Picker + Ribbon arcs this session also carried are compressed into Recent Work.

**The pane (both doors).** Group By is an in-pane vertical disclosure (the Swift GroupingPane precedent — Reveal, not PaneSlider); Order/Date By/Sub-Group are PickerControl rows; the middle region shows the set hierarchy (each set disclosing its sub-group behind the sidebar's Reveal motion, hidden by default, hideChevrons-aware, chips draggable for the global sub-order), the read-only preview (Default/Reversed), or the flat Custom chip list; footings (Ungrouped Top/Bottom · Separation Dash/Slash · a real Hide Empty Groups checkbox) ride the ViewSettings Format recipe with PickerControl pickers. Order labels: Select/Status = Default/Reversed/Custom · Date = Ascending/Descending + Date By (default Month) · Location = Custom/Location.

**Locked — the structural-only settings live VIEW-level** (`structural_order_mode` · `sub_group` · `ungrouped_placement` · `date_separator`, beside `group_order`): the view has ONE `group` slot that a Group By switch replaces wholesale, so anything that must survive the round trip can't live on the config object. The spec originally extended the structural GroupConfig — certified through three adversarial rounds — and the **simplifier** then caught the preservation branch as a no-op, forcing the view-level restatement (the `group_order` precedent, whose own code comment names the reason). → `History.md`.

**Locked — Order = Location mirrors the filesystem.** The pipeline skips `orderGroups` (preserving `group_order` for the flip back to Custom), and a same-parent band/pane reorder writes `reorderChildren`; the cross-tree reparent writes `group_order` in EVERY mode (slot preservation). The gate needed TWO edit sites — the pipeline skip AND the drop router — and review caught that a pipeline-only fold would have made Location-mode drags silently no-op.

**Locked — Sub-Group is a second resolver stage.** Sets stay top bands, sub-sets flatten, descendant pages re-bucket by the property with one GLOBAL bucket order (a cross-set bucket drag arrives as `reparent` but is STILL a global reorder, never a move) and per-set composite `set/bucket` collapse keys; a row dropped into another set's bucket writes property-then-move (the property first, while the page still has its current path). Date group headings follow the column's applied date format (`formatBucketLabel`); sub-bucket headers sit at data-row rhythm (`--subband-gap-top`).

**The tableDnd frozen-closure bug (real, latent, fixed).** TableRowDnd's context value memoizes on `[drag.id]`, freezing `begin` — and with it the whole computeSlot/reassign/reorderTo closure chain — at mount-time props; hit-testing survived only because rows ride refs. Found because the F-2 row-drop tests committed through a stale `subTargets`; fixed at the source with a per-render `cfg` ref (the commitBandRef discipline). Same debugging also caught a hook placed after TableView's early returns — that file's own comment warns about exactly this.

**The live-HMR feedback loop.** Nathan drove the dev app while the pane built, firing ~15 corrections mid-task (icon swaps, `label-control` picker tone, real property icons via a new `propertyTypeIconName`, the pairing-only sub-tier sizing, disclosure-on-the-left, collapsed date middle, PickerControl footings — which made the native `value-menu` IPC consumerless and deleted). The **list-outline rail went design-system-global** (`--list-outline-*` in theme-vars beside `--drag-line`; MarkdownPM's outliner re-pointed, the pane rail centered under the parent icon). Verdict: > Nathan: "Holy fuck im never going back to opus."

### Lessons Learned

- **A one-slot config field can't host settings that must survive the slot being replaced.** The view's single `group` object is swapped wholesale on a Group By switch, so "preserved" fields on it are destroyed by construction — view-level siblings (the `group_order` precedent) are the home. Three adversarial rounds certified the wrong shape; the SIMPLIFIER caught it, because the no-op was visible only in the code's own write path.

- **Folding a pipeline-side gate without walking the write path ships a silent no-op.** The Location-order fix needed the pipeline skip AND the drop-router branch; review round 2's two Highs were both "the fold never reconciled with the drag router." Blast-radius the writers, not just the readers.

- **A context value memoized on narrow deps freezes every closure behind it.** tableDnd's `[drag.id]` memo froze `begin` → the whole gesture chain read mount-time props; refs (rows) kept working, callbacks didn't. Mutable gesture config belongs in a per-render ref.

- **Hooks after early returns bite silently in big components.** The `subTargets` memo landed below TableView's `if (!ctx) return` and read stale state; the file's own dataRows comment warns about it. In a 1,400-line component, grep for the early returns before inserting a hook.

- **A nav that clears a sibling with PADDING still spans under it and wins hit-testing** (the ribbon's click-eater); use `margin` so elements are physically disjoint. And a transparent border insets a fill but squashes that corner's radius — inset with margin.

### Key Files & Insights

- `Pommora/src/renderer/src/Components/Detail/GroupingPane.tsx` + `groupingDnd.tsx` + `groupingPane.css.ts` — the pane; the pane drag is the BAND engine's pure model (bandDndModel) rehosted, because paneDnd's two-region vocabulary has no parent/nest concept.
- `pipeline/group.ts` — `structuralSubGrouped` + `groupRows` (the one group-by core) + `placeTail` (every ungrouped emit) + `subGroupKey`; `bucketOrder` exported for the pane.
- `Table/TableView.tsx` — the drop router's mode branch, `subTargets`, the sub-group `groupPropId` cluster; `Table/tableDnd.tsx` — the `cfg` ref.
- `shared/views.ts` — the four view-level fields + `decodeSubGroup`; GroupConfig itself untouched.

### User Feedback

- Footings must match the ViewSettings Format-footer recipe exactly; grouping pickers read `label-control`; property options in pickers show their REAL icons (def icon, else the type glyph); sub-tier sizing only when two Order rows pair; sub-groups disclose hidden-by-default behind the sidebar's motion, honoring hideChevrons.
- Live-HMR interjections are the working UIX review — fold each immediately, don't queue (→ memory `live-hmr-feedback-cadence`).

### Next Session

**1. Redesign the Filter authoring pane.** The **filter engine shipped to main** — the pipeline applies any stored `filter` with the full operator/target/`values[]`/`none` matrix (evaluator, codec, `contextOptions`), all tested. A FilterPane was built (both doors, on the Grouping/Sorting chassis) and driven through a long live-UIX loop, then **pulled before merge — Nathan: "filter works but design is bad and must be redone."** Both leaves fall back to blank. The rebuild starts from the **ratified decision log + plan in `Planning/` (`7-9 - View Filtering — Decision Log.md`)** — flat rule rows serializing onto the recursive `FilterGroup`, the Matches (All/Any/None) header + per-row And/Or connectors, the shape-based lock predicate, the stay-open chip picker — all 3-round-certified and hardened by a shipped-code review; only the *visual* is up for redesign. `filterModel.ts` (the pure encode/decode serializer) was removed with the pane — rebuild it from the log or the git history at `02042c57^`.

**2. The Navigation system** — the next arc after filtering, cutting across the **Navigation Window**, the **Navigation Dropdown**, and the **Inspector** (→ [[Navigation]] + [[Inspector]]).

**3. The last per-type property editor: the relation (context) pickers** (Properties.md Pending). The editor-pane trio + `PickerControl` + the per-view/def-level write split in `PropertiesPane.tsx` are the pattern.

**4. The non-Table renderers** (Cards · List · Gallery · Calendar · Timeline) — `PropertyEditing/` and the pipeline are renderer-agnostic and waiting; each type's grouping gets its own surface (→ [[Views]] `### Grouping`).

**5. User Sections CRUD** — the deferred "Add Heading" sidebar feature (Pending Focuses).

### Pending Focuses

- **"None"/flat grouping + Flatten + Hide Location** — the flattened-mode bundle, deliberately deferred (→ [[Views]] `### Grouping` for the ledger; the `flat` GroupConfig kind stays reserved).

- **User Sections CRUD (the "Add Heading" feature).** Collections can *render* user-created sections but there's no way to *make* one (read-only orphans; `mutate.ts` has zero section ops). An "Add Heading" entry on the Collections right-click menu, section rename, drag-a-Collection-into-a-section. Its own brainstorm→plan→build. → `Sidebar.md` Pending.

- **(Perf) Standing debt:** (1) no row virtualization — every row MOUNTS, bites at thousands. (2) External VALUE edits don't live-refresh an open table (`loadValues` runs per container-open). Container-surgical reconcile is the designed escalation at real scale.

- **Number editor eyeball items (Nathan may tune, not bugs):** Decimals "Hidden", fraction wording, bar clamp edges, the strokeless bar look, field widths. Knobs in `numberEditor.css.ts` / `textPicker.css.ts` / `formatValue.ts`.

- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending adversarial review → plan → build.

- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the codebase is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.

- **Automatic Scrolling** — must-have for views + MarkdownPM.

- **iCloud-sync readiness (future):** in-process `serializeOnFile` can't coordinate with the iCloud daemon — cross-device is last-writer-wins. `.nexus/index.db` needs sync-exclusion; the walk must skip `.icloud` placeholders.

- **Mobile iOS companion (parked):** spec at `.claude/Mobile/MobileSpec.md`; step 1 is a `window.nexus` bridge shim + a native iCloud Swift plugin. No build commitment.

### Fix Log

- **`.nexus/activeViews.json` + per-machine siblings aren't gitignored (live).** Neither it nor `folds`/`viewOrders`/`tableHeadingColumns`/`linkTitles` are ignored — using the switcher on a fresh container creates a would-sync file. Add to the Nexus `.gitignore` (or scaffold it).

- **Group By Location** locks certain configurations; custom order isn't truly independent from the filesystem and is buggy.

- **The "File" property icon gets clipped** by its vertical row padding on the ViewPane.

- **The link rename field shows a leading empty space (DEPRIORITIZED).** A visual inset, not a stored/typed char. Likeliest: `TextPicker`'s left padding or `nativeCaret`'s position-only blind spot. Log it, don't chase it.

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either corrupts the doc (`MarkdownPM/editor/blockModel.ts`, test-pinned, unguarded).

- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → `Features/MarkdownPM.md`.

### Working Notes

- **UI iteration runs in dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R**, and **`src/main`/preload need a full dev-process restart** (electron-vite builds main ONCE at launch; a new IPC won't exist until relaunch — bit `agenda:list` AND the grouping `value-menu` this session). Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev`; relaunch with `-- --remote-debugging-port=9222` to keep CDP.

- **HMR is NOT trustworthy for two classes:** (1) vanilla-extract `*.css.ts` — a style edit can serve stale compiled CSS; a plain restart heals it, ⌘R never does. (2) A component's focus effect / handler / attribute change — Fast-Refresh often skips it. (Plain `.css` DOES HMR reliably.)

- **The dev app runs against Nathan's REAL Nexus.** UI value writes are his data; CDP must open + Esc only, never pick/commit — unless he authorizes a mutating gesture. Location-mode grouping drags write the REAL filesystem — test in a throwaway Collection. Native OS menus don't render in the DOM; reach those ops through `window.nexus.*` via `Runtime.evaluate`.

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (two passes, the ONLY type gate) + `npx vitest run` + `env -u ELECTRON_RUN_AS_NODE npm run build`. Biome auto-formats on write — never run it, never hand-align.

- **Parallel sessions / edits** — stage explicit paths, never `-A`. Unattributed `M`/`D` files are almost always Nathan's, left uncommitted on purpose; fold them into a related commit when he says so (his Planning-doc cleanup got its own chore commit this session).

- **main is ~32 commits ahead of origin, unpushed** — Nathan pushes in batches on his own call; merge ≠ push.

### Handoff Rules

- **Never record a correction-to-obvious as a discovery.** Write the durable truth as if always so; silently fix what contradicts it. A fresh agent shouldn't be able to tell a mistake was made.

- **Resolve = delete + route, never tag.** When an entry's done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.

- **One block per session, updated in place.** Compactions bump the count, they don't add sections. Carry still-open Pending + Fix Log to a fresh session.

- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.

- **Parallel sessions share this one doc** — a concurrent session adds its own labeled block; Cornerstone + footer shared; never edit another session's block.
