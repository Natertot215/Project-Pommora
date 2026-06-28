## Handoff — Pommora React

Two parallel 06-27 React sessions on one tree (plus a Swift session committing concurrently, its own root handoff). **A — Table Views Part 1:** cold recon → ratified spec → adversarially-reviewed V2 plan, paused one confirmation from execution. **B — Block Drag:** the Notion-style block-handle feature, brainstorm → spec V2 → Phases 1–3 shipped reviewed-green (Phase 3 = handles + gesture + a double-reviewed drag-reliability fix set). The footer is shared.

**Session A ID:** de564e01-aa38-498e-b9f8-5db92904a48a
**Session B ID:** 64346d76-0499-4a65-93e3-71db53bf4d32
**Dates:** 06-27-2026


> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Session Summary - A
**Date:** 06-27-2026
**Model:** Opus 4.8
**Compactions:** 0
**Connectors:** none (in-process tooling only — no MCP called)
**Commands:** `/handoff`
**Worktree:** main checkout (planning only — **no code yet**; per `CLAUDE.md`, Part-1 *execution* should move to the `pommora-react` worktree, then merge to main)
**Agents:** Explore (×5 — Swift view-model · React view-plumbing · view/property specs · React UI-primitives · plan compile-grounding), builder (×1 — Swift app build), general-purpose (×2 — plan logic/coverage review + over-engineering review)
**Skills:** `superpowers:brainstorming`, `superpowers:writing-plans`, `handoff`

The whole session was design + planning for porting the Swift build's view system to React, build-order **plumbing → table UIX (Figma) → settings dropdown**, with Part 1 specced, planned, reviewed, and parked one confirmation away from execution.

**Recon — React has the foundations, the view layer is a shell:** Three scouts (Swift / React / docs) plus direct source reads established the gap: React already has property-schema CRUD (`crud/schema.ts`), the `PropertyValue` codec (parity with Swift), generic sidecar I/O, the `.nexus/` per-machine file pattern (`io/folds.ts`), a pure view pipeline, and a TanStack table — but the table renders **Title-only** because `flattenRows` never loads page frontmatter (`Detail/Table/TableView.tsx`), so property columns are always empty. The `views[]` sidecar slot exists as a loose passthrough with zero semantics. So it's real foundations, not a wrapper over nothing — but three pillars are missing: a typed persisted view config, property-value loading, and the type-aware pipeline.

**Swift is the contract; verified by source + live screenshots:** Read `SavedView.swift` etc. directly for the on-disk shape, then built + drove the live Swift app (CGEvent-click helper + `screencapture -R`) to capture the View Settings dropdown — a glass-surface popover with a root menu (icon+name header · Edit Properties · Layout · Group · Filter · Sort · "Open Pages In" footer) pushing to sub-panes, plus the Ideas table rendering manual-order status grouping. Read the real `The Nexus/Ideas/_pagecollection.json` as the Rosetta Stone (a live `SavedView` with `order_mode:"manual"` status grouping). The on-disk `SavedView` keys are the cross-build contract React matches key-for-key.

**Design locked with Nathan:** One portable view config (definitions + ergonomic state in sidecar `views[]`); the **active-view pointer is per-machine** in `.nexus/activeViews.json` (NOT the sidecar — avoids sync churn, mirrors folds); values loaded **from files** (frontmatter, property-ID keyed, lazy batch IPC), never SQLite; grouping only for select/status/checkbox/date (status manual-order, 3 groups enum-locked); **multi-key sort** (a deliberate superset — Swift's pipeline is single-key, and Nathan green-lit going above Swift: > "the hard rule is a suggestion lmao"); chips are **direct components in `design-system/components/Chips/`** built on the existing `tokens/chip.css.ts` (not Swift ports, not inline spans); status-before-title hoist is **render-time, Part 2**; date cell is a "Calendar" placeholder for now.

**Spec → 3-way adversarial review → leaner V2 plan:** Wrote the Part-1 spec, then ran compile-grounding + logic/coverage + over-engineering reviewers (standard agents, per Review-Discipline). They earned their keep — **3 real blockers**: filter `op` strings are snake_case raw values (`is`, `greater_than`, `on_or_after`…) not camelCase (would've broken parity), `mintDefaultView` can't import `main/ids.ts` from `shared/` (→ `'view_default'` sentinel, real ULID assigned in main on save), and the Ideas fixture isn't in-repo (→ synthetic fixture). Plus should-fixes (cut `context.ts` — `Detail/Scope.ts` already has `findContext`; `ResolvedColumn` = `{id,kind}` only; hoist → Part 2; type-complete sort like Swift with `isSortable` as a Part-3 picker filter). Folded into V2: 11 tasks, leaner than the original 14.

**Where it stands — one confirmation from execution:** Awaiting Nathan on (a) the **recursive AND/OR filter shape** (`FilterGroup` whose `rules` can hold nested groups — a clean superset where flat filters stay Swift-compatible; he asked for "filter and/or'd"), and (b) the execution path — a focused confirmation-review round on the V2 fixes (recommended, since round 1 found 3 blockers) then **subagent-driven** execution (recommended for 11 TDD tasks) vs inline.

**Lessons Learned**

- **The Swift app can be driven headlessly for screenshots** — no `cliclick`/Quartz on this host, but a compiled Swift `CGEvent` helper (`scratchpad/click <x> <y>`) posts clicks and `screencapture -x -R<x,y,w,h>` captures a window region (host has Accessibility + Screen Recording). Window bounds via `osascript … get {position, size} of window 1`. Reason in fractions of the capture region, not displayed-image pixels (the Read render scale varies).

- **Swift renders `property_order` verbatim — there is NO auto-hoist** of the grouped/sorted column before Title (`VisiblePropertyOrder` / `TableColumnResolver` are verbatim; Ideas' status-first order was a manual column drag). So "status before title when grouped" is **net-new React behavior**, not a port — building it render-time in Part 2.

- **Swift's view pipeline is single-key sort and shape-inference-based**, not the multi-key / declared-type model I'd assumed — both are React improvements going *above* Swift (sanctioned). The filter **evaluator** honors a wider operator matrix than the **picker** offers; Part 1 ports the evaluator (tier relations filter by membership, user relation/file are presence-only).

- **Don't actuate settings on the live nexus** — toggling sort/group/visibility in the View Settings dropdown persists to the real sidecar. Screenshot panes read-only; never flip a control on Nathan's data.

**Key Files & Insights**

- `Planning/6-27 - Table Views Plumbing Spec.md` + `Planning/6-27 - Table Views Plumbing Plan.md` (V2) — the ratified spec + 11-task plan (both **uncommitted**).
- Swift port targets: `Domain/Collections/SavedView.swift` (contract + lenient group decode), `Features/Detail/ViewPipeline/{GroupResolver,SortComparator,DateBucket,VisiblePropertyOrder}.swift`, `Features/Detail/Table/TableColumnResolver.swift`, `Features/ViewSettings/FilterPane.swift` (the snake_case op vocabulary).
- React seams to build on: `shared/{views(new),types,schemas,properties,propertyValue}.ts`, `main/{paths,sidecarIO,ids}.ts`, `main/io/folds.ts` (the activeViews pattern), `Detail/Scope.ts` (`findContext` — reuse for chip resolution), `Detail/Table/{TableView,pipeline}.tsx/ts` (superseded by `Detail/Views/`).
- Live nexus uses `_pagecollection.json` everywhere (`_pagetype.json` is legacy/trash only) — React's convention already matches; no migration.

**Landmines**

- **Live Swift parallel session committed all day** (banner editor, cross-build `modified_at`, `Context.md`, etc.; newest 16:55). Touches root `.claude/*`, `Pommora/**.swift`, and shared React/cross-build files. **Stage explicit paths, never `-A`**; don't revert its work.
- **Planning docs uncommitted** — `Planning/6-27 - *` are the only working-tree changes; commit just those two explicitly as the baseline before any code.
- **Swift app left running** — built to `…/DerivedData/Pommora-…/Build/Products/Debug/Pommora.app` and launched for screenshots (its Ideas active-view was switched gallery→table, a harmless per-machine `state.json` change). Quit it if it's in the way.

**Session Pointers**

- The first review round found 3 real blockers on a spec/plan that *looked* clean — don't ratify a plan on your own assertion. The V2 fixes are grounded in the reviewers' cited Swift `file:line`s; a focused confirmation round before execution is cheap insurance.

**User Feedback**

- "the hard rule is a suggestion lmao — if we go above swift that's fine" — the "catch up to Swift, don't go ahead" guideline is soft; React may lead (multi-key sort, recursive filters), with Swift aligning later.
- "we already have chip styles in react … chips used are direct components created in // Chips" — build chip components in `design-system/components/Chips/` from the existing styles; don't port Swift's.
- "status goes before title when grouped by" — Nathan wants it even though Swift doesn't auto-do it.
- On process: write the plan, then `/writing-plans`; reviews run as standard agents.

**Uncertain**

- The **recursive filter shape** is proposed (nested `FilterGroup` in `rules`), not yet confirmed by Nathan — Task 1 + Task 6 change if he only wants the top-level AND/OR toggle.
- Whether the live Swift parallel session is still active at handoff time, and whether any of its commits touch files Part-1 execution will edit (`shared/types.ts`, `main/index.ts`, `preload/index.ts` are the overlap risk).

### Session Summary - B
**Date:** 06-27-2026
**Model:** Opus 4.8
**Compactions:** 2
**Connectors:** none (Electron CDP for live UI verification; no MCP)
**Commands:** `/compact`, `/handoff`
**Worktree:** main checkout — Nathan declined the isolation worktree ("I'll close my server"); all work + commits on `main`
**Agents:** general-purpose (×7 — adversarial review: 3 on the spec, 2 on Phase-1 `blockAt`, 2 on Phase-2 mover)
**Skills:** `superpowers:brainstorming` (process), `handoff`

Three editor bug-fixes, then the Notion-style block-drag feature from brainstorm to mid-Phase-3 — adversarial review at every step caught real bugs before they shipped.

**Three editor fixes shipped first:** The fold **chevron drifting** below callouts — CM positions its gutter from a height-MODEL that estimates off-screen variable-height lines at the default height, so every gutter chevron below a callout/fold drifted by a scroll-dependent amount; fixed by anchoring the chevron to the line as a `::before`. The **inspector h-scroll** — `overflow:hidden` still leaves a scrollable box, so a text-selection drag panned the shell to reveal the parked inspector; `overflow:clip` (not a scroll container). **Cell spell-check** — the cell editor lives inside the table widget's `contentEditable=false` host, which suppresses inherited spell-check; opted in via `contentAttributes`. Commits `dc89887` / `d6a26fe` / `2428ab3`.

**Block-drag brainstorm → spec, "reuse" oversold:** Brainstormed the full Notion-style model one-question-at-a-time (top-level reorder; chevron does fold+drag double-duty; lists grab at item-1 via a side handle; tables reuse their grip; callout-nested gets handles, blockquote-nested deferred; table stays in V1 despite cost). The spec's "reuse wholesale" thesis was **overstated** — 3 spec reviewers found 5 load-bearing falsehoods: `collectCands` is list-*geometry* not a filter; the table grip is *inert* for dragging + its widget swallows pointer events; folded-heading drag *loses* fold state; the chevron is a `::before` not a real node; taxonomy holes let HR/math fall into paragraphs. Rewrote V2. → `Planning/6-27 - Block Drag Spec.md`.

**Phases 1–2 shipped reviewed-green:** **Phase 1** (`5e1089f`) — `blockAt(doc,pos)→{from,to,kind}`, the keystone resolver; its logic reviewer caught a real high-frequency bug (list lazy-continuation split the list — a wrapped item orphaned as a paragraph) that had passed 12/12 happy-path tests; fixed continuation-aware. **Phase 2** (`dc72224`) — `BlockRange` broadening (the move primitives take a plain range; list-drag stays byte-identical) + `blockMoveChanges` (blank-aware: a block owns its trailing blank); logic caught 3 edge bugs — trailing-newline EOF double-blank, blank-line drop targets gluing, dropping on the block's own preceding blank — all fixed + pinned.

**Phase 3 shipped reviewed-green:** `blockStarts` enumerator + `blockHandles` (rail grips on para/code/list block-starts) + `blockDrag` (press grip → drag → `blockMoveChanges`). After the build-and-show fixes (single-pass O(n) `blockStarts` killing the lag; the blockquote-bar `::before` collision; first-row handle alignment), a **full non-testable interaction sweep** (4 agents) surfaced the real defects and Nathan chose the **full HIGH-set fix**: (1) a **silent drop-corruption class** — `blockMoveChanges` guaranteed a blank *below* a moved block but never *above* it or at the cut hole, so a drop onto a glue-adjacent seam lazily-continued a list / merged paragraphs; fixed with a two-seam `sep()` blank-guard (+4 regression tests); (2) **scroll-during-drag staleness** + no auto-scroll → candidates re-measure on scroll + an edge auto-scroll rAF loop; (3) **no abort** → Escape/window-blur cancel + a `done` re-entrancy guard; (4) the **accent line** now hugs the boundary above (`coordsAtPos(at-1).bottom`), folded/off-screen candidates gated out. Two adversarial reviews (corruption sound across ~40 inputs; gesture lifecycle clean), simplifier found nothing to cut, 678 green. **LOW-1** (gutter grip = whole list, glyph = one item) is **intended** (Nathan); **LOW-F4** (a double-blank source gap leaves a leading blank — cosmetic, renders identically) deferred. Heading-drag (chevron press-to-drag) is Phase 4, not wired.

**Isolated dev server (9223, Test Nexus):** `electron-vite dev --remoteDebuggingPort=9223` on `~/test`, own Vite, for build-and-show without touching Nathan's vault. **Config altered:** to open the Test Nexus I set the `pommora-react` userData `lastNexusPath` from `/Users/nathantaichman/The Nexus` (real vault) to `~/test`; original backed up at `scratchpad/pommora.json.orig-TheNexus` — **restore it** or the next launch opens the wrong nexus.

**Lessons Learned**

- The discipline ran *forward* this time (review before ship), and `12/12 green` was, repeatedly, exactly when the bug was hiding — the `blockAt` continuation bug + all 3 `blockMoveChanges` edge bugs passed happy-path tests + typecheck while broken. Adversarial agents at the pure-function layer caught them before any UI existed. Logged as the "Block Drag — the discipline, applied" coda in `Guidelines/Adversarial-Review-Log.md`.

- A "reuse" claim is a hypothesis until the code proves it: the table grip was *inert* for dragging (not a reuse), `collectCands` was list-geometry (not a filterable source). Reading the cited code turned the spec from confident-wrong to honest.

- **CM6 gutter drift generalizes:** CM positions any gutter from its visible-viewport-measured height MODEL (off-screen lines estimated at default height), so a gutter element below a variable-height block (callout/fold) drifts. A content-anchored `::before` is the fix — same pattern now in the chevron + the block handles.

- A `decorations.compute(['doc'])` recomputes on **every keystroke**; an O(n²) helper inside it makes the editor unusably laggy. Block-start enumeration had to be a single pass.

**Key Files & Insights**

- `editor/blockModel.ts` — `blockAt` + single-pass `blockStarts`. `editor/listDragModel.ts` — `BlockRange` + `blockMoveChanges` (blank-aware mover, sibling of the list mover, not a generalization of it). `editor/blockHandles.ts` (new) — rail-grip decoration. `editor/blockDrag.ts` (new) — the gesture (copies listDrag's overlay/shade; TODO: extract shared). `Styles.css` — `.md-block-handle::before` + the chevron content-anchor + the inspector `overflow:clip`.
- `Planning/6-27 - Block Drag Spec.md` (V2). `Guidelines/Adversarial-Review-Log.md` — the discipline coda.
- Committed: `dc89887` · `d6a26fe` · `2428ab3` · `5e1089f` · `dc72224`; **Phase 3 (this commit):** `blockModel.ts` + `.test`, `listDragModel.ts` + `.test`, `blockHandles.ts`, `blockDrag.ts`, `index.tsx`, `Styles.css`.

**Landmines**

- **Dev config altered** — `pommora-react` userData `lastNexusPath` = `~/test` (was `The Nexus`). Restore from `scratchpad/pommora.json.orig-TheNexus`, or the app reopens the Test Nexus instead of the real vault.
- **The 9223 dev server is running** (my `electron-vite dev`, Test Nexus) — not Nathan's; leave or kill.

**Session Pointers**

- Build-and-show is the UI verification mode (Nathan confirms live on 9223); pure logic gets adversarial agent review. Don't *assert* the gesture works — the "grab doesn't work" report is unresolved pending Nathan's re-test after the lag fix.
- The chevron's content-anchored `::before` (drift-proof) is the template for every block handle — never a CM `gutter()`.

**User Feedback**

- "each task must get an adversarial review" — every implementation phase ships green THEN gets its own review before the next.
- On handles: "in-line with the content of the first row, not the line itself" (align the grip to the first row's text, wrap-safe) + "only on hover for the gutters, just like the chevron."
- "the line for dragging (the accent) should follow the line height of the heading above, not right in the middle."
- "Table in V1" — keep table-drag in V1 despite it being the biggest net-new piece.

**Uncertain**

- The drag gesture is reviewed-green but **not yet live-confirmed by Nathan** — the non-unit-testable behaviors (scroll-during-drag, edge auto-scroll, Escape-abort, the accent hugging the boundary) need a human at the editor; that's the mandatory post-functional UIX check, still open.
- The loose-list call (blank-separated list items split into *separate* drag-blocks) is pinned-split; Nathan's to change.

---

### Working Notes

- UI iteration runs in **dev mode (HMR)** — keep `npm run dev` up; renderer edits hot-reload, **but CM6 widget/extension code needs a full ⌘R / `Page.reload`** (only CSS hot-swaps), and a freshly-added module sometimes needs one reload past HMR. Don't ⌘Q it.
- **Main-process edits need a dev-server restart** (IPC, native menus, preload); a stale main can silently drop a mutation.
- Runs against a **test nexus** (`~/test`) — a *managed* nexus (carries `.nexus/`) so reorder/settings persist. The running app opens its `lastNexusPath`, not `TEST_NEXUS_PATH`.
- The agent **can** screenshot + drive the React UI headlessly via Electron + CDP (`--remoteDebuggingPort` → `Page.captureScreenshot` / `Input.dispatchMouseEvent`); the **Swift** app via the CGEvent-click + `screencapture -R` rig above. Nathan is the primary visual verifier.
- **Parallel sessions happen** — never bundle or revert unattributed changes; **stage explicit paths** (`git add <paths>`), never `-A`.
- `Context.md` (current build-state companion) now exists (added by the parallel session) — keep it current alongside this journey doc.

### Next Sessions

- **(B) Live-confirm Block Drag Phase 3, then Phases 4–5.** Phase 3 (handles + gesture + the full HIGH-set reliability fixes) shipped reviewed-green this commit; the open post-functional UIX check is Nathan's live test of scroll-during-drag, edge auto-scroll, Escape-abort, and the accent hugging the boundary. Then **Phase 4** — the chevron's fold+drag dual-role (press→drag the section + fold-teardown-on-move) — and **Phase 5** — the table-grip→`startBlockDrag` React bridge. Deferred follow-up: hoist the duplicated `Overlay` + shade + line-walk shared by `listDrag` + `blockDrag` into one module (touches shipped listDrag — a human-scoped call). **Restore the dev config** (`scratchpad/pommora.json.orig-TheNexus` → `pommora-react` userData).
- **(A) Execute Table Views Part 1.** Confirm the recursive-filter shape + the execution path, commit the two Planning docs as the baseline, then run the 11-task plan (subagent-driven, fresh agent per task, diff review between). Move to the `pommora-react` worktree for the code. After Part 1 greens, Nathan designs the table in Figma → Part 2 routes the UI to the seams (`ResolvedColumn[]` / `ResolvedGroup[]` / per-cell data), with chips as direct `design-system/components/Chips/` components.
- **(A) Carryover editor work:** **Callouts** are functionally hardened (delete-guard + adversarial fuzz pass, `Guidelines/Adversarial-Review-Log.md`); remaining: tables-inside-callouts (deferred). Create unicode up-down + back-forth auto-transform for `<>` / `><`. Add "Styles" to tables → style = column would remove gutter padding + hide table lines (solves the markdown column problem).
- **(A) Live-verify the heading-column toggle end-to-end** — menu → toggle → persist → reload is unit-tested + typecheck-clean, but not confirmed by a real in-app toggle.

### Pending Focuses

- **(B) Block Drag V2 — nesting** (separate spec): interior drop-slots inside callouts, the guard table (table / heading / callout can't nest in a box), cross-container re-prefix, the `depth` field. Deferred from V1; the V1 mover + reindent already prove the cross-container re-prefix.
- **Table Views Parts 2 & 3 (new)** — Part 2: the Figma-designed table UIX + chip components + inline cell editor (glass-control chip pickers, plain inputs, "Calendar" date placeholder, native menus for simple actions) routed to the Part-1 seams. Part 3: the View Settings dropdown (glass-surface `Popover` root menu → Layout/Sort/Filter/Group/EditProperties panes) + the operator *picker* + view rename/dup/delete + `open_in` + `display_as` variants. Both gated on Part-1 plumbing.
- **Break-things skill (Nathan-requested)** — a reusable adversarial-fuzzing skill from `Guidelines/Adversarial-Review-Log.md`: a break-attempt taxonomy (input transforms · deletion/caret combo matrix · nesting · adjacency · layout edges · fix-induced regressions) + the "toddler" method + a `{keys}×{positions}×{nesting}×{adjacency}` generator → a break→repro→fix catalog before any UI feature is called done.
- **Canvas** — spec parked at `Planning/6-26 - Canvas Spec.md`, pending its adversarial review → plan → build. React-first; the `.canvas` format is the cross-build contract. Confirm the `border` token (grey-30%) lands when canvas builds.
- **Caret on the other editor surfaces** — drawn caret + custom hover cursor shipped on the page editor (`editor/caret.ts`); extending to table cells + the inline-rename input is the remainder.
- **Subfield reorder + live-stats + custom items** — registry/order/persistence are the seams; `Features/Subfield.md` § Roadmap.
- **Icon picker** — build `Components/IconPicker` + wire the icon's frontmatter save (Swift `IconPicker` is the spec; wants a shared dropdown-animation primitive).
- **Real design-system Components** (Button / Menu / Label / Separator / **Chips**) from the token layer — prerequisite for replacing one-offs (notably the inline-rename `<input>`).
- **Radius + spacing tokens** — still ad-hoc literals; lift from Figma.
- **Settings editing UI** deferred — `.nexus/settings.json` is the control surface (labels + accent + `subfield`).
- **One-time Biome normalization** — defer to a tree with no parallel uncommitted edits.
- **Unsorted bin → folder + sidecar (paradigm, ratify first)** — move "unsorted" off a config file onto a real `Unsorted/` folder with an `_unsortedconfig.json` sidecar (the folder-with-sidecar pattern). Win is interop (another Markdown app could share the folder). On-disk shape — ratify before building.

### Fix Log

- **Aliased `[[A|B]]` vs cell-pipe** — a `|` in an aliased connection collides with cell-pipe escaping inside a table cell; autocomplete only inserts alias-free `[[Title]]`. Open paradigm call.
- **Table links non-clickable** — no input handling for the rendered link inside a cell; proposed single-click navigate + right-click edit.
- **Bullet single-word wrap drops the word below the marker** — a `-`/`•`/`+`/`→` item whose content is one long unbroken word drops the whole word to the next line; the marker-space hide that would fix it didn't survive CM6's replace decoration. Only the `line-height` cap shipped. → `Features/MarkdownPM.md` § Known issues.
- **Recents submenu on "Open Nexus"** allows trashed folders to appear; opening one pulls it out of trash.

### Handoff Rules

- **Resolve = delete + route, never tag.** When an entry here (Pending Focus, Landmine, Uncertain, Fix Log) is genuinely done, push its real outcome to the canonical doc (`History.md` / `Features/*` / `Framework.md`) and delete the line — no `(Resolved)` / `(Superseded)` tombstones. In parallel, you may delete a resolved Landmine/Uncertain from another session's block (removal only) even though the rest of their block stays frozen.
- **Keep the Fix Log current.** Acknowledged-but-unfixed issues get a 1–2 sentence entry; remove on resolve.
- **One block per session, updated in place.** Compactions bump a `Compactions` count, they don't add sections. Push spec/decision content to its canonical home; carry still-open Pending Focuses forward to a fresh *sequential* session.
- **Markdown only, no new folder** (per Nathan) — this doc stays the single `React/.claude/Handoff.md`, not a routed `Handoffs/` dir, regardless of the skill's `Handoff`/`Session`/`Sessions` filename shapes or its config route.
- **Parallel sessions share this one doc.** Each concurrent React session gets its own labeled block (`### Session Summary - A`, `- B`, …) with its own metadata + sections; the Cornerstone top matter is shared above all blocks, written once; list every session ID in the header. The agent running `/handoff` is the newcomer (next free letter; A = the block already in the file) — never edit another session's block, only write/refresh your own. The footer (Working Notes / Next Session / Pending Focuses / Fix Log / Handoff Rules) is shared. **Next Session lives once in the footer** (→ `### Next Sessions` when parallel), never per block. (The Swift build keeps its own separate root handoff.)
