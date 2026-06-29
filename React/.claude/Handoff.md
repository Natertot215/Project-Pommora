## Handoff — Pommora React

Two parallel 06-27 → 06-28 React sessions, now reconciled onto one `main` (plus a Swift session, its own root handoff). **A — Table Views Part 1:** cold recon → ratified spec+plan → **SHIPPED** (11 TDD tasks, each simplify-+code-reviewed, suite+typecheck green) on the `views-plumbing` worktree (`d5ed3ac`…`1c892a7`), now **merged to `main`** (this merge supersedes the parallel `pommora-react` Task-6 WIP — zero code overlap with B). **B — Block Drag:** the Notion-style block-handle feature **shipped end-to-end** — rail grips + heading chevron + callout grip + table heading-row grip all drag whole blocks (list-drag-style snap, full reliability set), every step adversarial-reviewed AND live screenshot-verified. The footer is shared.

**Session A ID:** de564e01-aa38-498e-b9f8-5db92904a48a
**Session B ID:** 14fe9a42-feff-4060-a1d6-145b6ece5ec5 (took over the killed `64346d76` mid-MarkdownPM — see the takeover note in Session B)
**Dates:** 06-27-2026 → 06-28-2026


> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Session Summary - A
**Date:** 06-27-2026
**Model:** Opus 4.8
**Compactions:** 7
**Connectors:** none (in-process tooling + web research; no MCP)
**Commands:** `/handoff`
**Worktree:** Part 1 BUILT on the **`views-plumbing`** worktree, branched off `pommora-react`@`3bb170c`; now merged to `main`
**Agents:** Explore (×6 — Swift view-model · React view-plumbing · view/property specs · React UI-primitives · plan compile-grounding ×2 rounds), builder (×1 — Swift app build), general-purpose (×4 — plan logic/coverage · over-engineering · confirmation logic/coverage · Notion linked-DB research)
**Skills:** `superpowers:brainstorming`, `superpowers:writing-plans`, `handoff`

The whole session was design + planning for porting the Swift build's view system to React, build-order **plumbing → table UIX (Figma) → settings dropdown**, with Part 1 specced, planned, reviewed, and parked one confirmation away from execution.

**Recon — React has the foundations, the view layer is a shell:** Three scouts (Swift / React / docs) plus direct source reads established the gap: React already has property-schema CRUD (`crud/schema.ts`), the `PropertyValue` codec (parity with Swift), generic sidecar I/O, the `.nexus/` per-machine file pattern (`io/folds.ts`), a pure view pipeline, and a TanStack table — but the table renders **Title-only** because `flattenRows` never loads page frontmatter (`Detail/Table/TableView.tsx`), so property columns are always empty. The `views[]` sidecar slot exists as a loose passthrough with zero semantics. So it's real foundations, not a wrapper over nothing — but three pillars are missing: a typed persisted view config, property-value loading, and the type-aware pipeline.

**Swift is the contract; verified by source + live screenshots:** Read `SavedView.swift` etc. directly for the on-disk shape, then built + drove the live Swift app (CGEvent-click helper + `screencapture -R`) to capture the View Settings dropdown — a glass-surface popover with a root menu (icon+name header · Edit Properties · Layout · Group · Filter · Sort · "Open Pages In" footer) pushing to sub-panes, plus the Ideas table rendering manual-order status grouping. Read the real `The Nexus/Ideas/_pagecollection.json` as the Rosetta Stone (a live `SavedView` with `order_mode:"manual"` status grouping). The on-disk `SavedView` keys are the cross-build contract React matches key-for-key.

**Design locked with Nathan:** One portable view config (definitions + ergonomic state in sidecar `views[]`); the **active-view pointer is per-machine** in `.nexus/activeViews.json` (NOT the sidecar — avoids sync churn, mirrors folds); values loaded **from files** (frontmatter, property-ID keyed, lazy batch IPC), never SQLite; grouping only for select/status/checkbox/date (status manual-order, 3 groups enum-locked); **multi-key sort** (a deliberate superset — Swift's pipeline is single-key, and Nathan green-lit going above Swift: > "the hard rule is a suggestion lmao"); chips are **direct components in `design-system/components/Chips/`** built on the existing `tokens/chip.css.ts` (not Swift ports, not inline spans); status-before-title hoist is **render-time, Part 2**; date cell is a "Calendar" placeholder for now.

**Spec → 3-way adversarial review → leaner V2 plan:** Wrote the Part-1 spec, then ran compile-grounding + logic/coverage + over-engineering reviewers (standard agents, per Review-Discipline). They earned their keep — **3 real blockers**: filter `op` strings are snake_case raw values (`is`, `greater_than`, `on_or_after`…) not camelCase (would've broken parity), `mintDefaultView` can't import `main/ids.ts` from `shared/` (→ `'view_default'` sentinel, real ULID assigned in main on save), and the Ideas fixture isn't in-repo (→ synthetic fixture). Plus should-fixes (cut `context.ts` — `Detail/Scope.ts` already has `findContext`; `ResolvedColumn` = `{id,kind}` only; hoist → Part 2; type-complete sort like Swift with `isSortable` as a Part-3 picker filter). Folded into V2: 11 tasks, leaner than the original 14.

**Where it stands — one confirmation from execution:** Awaiting Nathan on (a) the **recursive AND/OR filter shape** (`FilterGroup` whose `rules` can hold nested groups — a clean superset where flat filters stay Swift-compatible; he asked for "filter and/or'd"), and (b) the execution path — a focused confirmation-review round on the V2 fixes (recommended, since round 1 found 3 blockers) then **subagent-driven** execution (recommended for 11 TDD tasks) vs inline.

**Then the session became the React design-system + View Settings build (post-compaction).** Far past Part-1 planning: rerouted `GlassPane` off liquid `@samasante/liquid-glass` onto a native CSS frost; built the **View Settings dropdown (Part 3)** — a generic scope-routed toolbar button (`Detail/ViewSettingsScope.ts`) → `ViewPane` root menu + Properties-pane schema CRUD (create/rename/icon/delete; select/multi seed a starter option) — on a shared `MenuSurface`. Authored the **Bloom `dropdown-menu`** open + `dropdown-menu-out` **retract** (one shared `useExitPresence` hook; on the toolbar dropdowns, the wikilink autocomplete, and the IconPicker). Tokenized motion (`--disclosure`) / shadow (`--shadow-standard`) / input (`--input-field`), bumped the shell slide to 280ms, and DRY'd the sidebar/inspector/chevron motion onto the tokens. Routed `IconPicker` onto `GlassPane` + the Bloom motion. Closed out by **deleting the ⌘D `GlassTuner` and the `DropdownAnimationLab`** (trial-and-error tooling — the frost is baked into `PANE_FROST`, the curve into `animations.css.ts`) + a code-simplifier cleanup pass (dead `FrostParams.fill` + an unused re-export removed; verified typecheck-green). Full motion system → `Features/Interaction.md`; locked decisions → `History.md`.

**Lessons Learned**

- **The Swift app can be driven headlessly for screenshots** — no `cliclick`/Quartz on this host, but a compiled Swift `CGEvent` helper (`scratchpad/click <x> <y>`) posts clicks and `screencapture -x -R<x,y,w,h>` captures a window region (host has Accessibility + Screen Recording). Window bounds via `osascript … get {position, size} of window 1`. Reason in fractions of the capture region, not displayed-image pixels (the Read render scale varies).

- **Swift renders `property_order` verbatim — there is NO auto-hoist** of the grouped/sorted column before Title (`VisiblePropertyOrder` / `TableColumnResolver` are verbatim; Ideas' status-first order was a manual column drag). So "status before title when grouped" is **net-new React behavior**, not a port — building it render-time in Part 2.

- **Swift's view pipeline is single-key sort and shape-inference-based**, not the multi-key / declared-type model I'd assumed — both are React improvements going *above* Swift (sanctioned). The filter **evaluator** honors a wider operator matrix than the **picker** offers; Part 1 ports the evaluator (tier relations filter by membership, user relation/file are presence-only).

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
- On process: write the plan, then `/writing-plans`; reviews run as standard agents.

**Uncertain**

- The **recursive filter shape** is proposed (nested `FilterGroup` in `rules`), not yet confirmed by Nathan — Task 1 + Task 6 change if he only wants the top-level AND/OR toggle.
- Whether the live Swift parallel session is still active at handoff time, and whether any of its commits touch files Part-1 execution will edit (`shared/types.ts`, `main/index.ts`, `preload/index.ts` are the overlap risk).

### Session Summary - B
**Date:** 06-27-2026
**Model:** Opus 4.8
**Compactions:** 6
**Connectors:** none (Electron CDP for live UI verification + screenshots; no MCP)
**Commands:** `/compact`, `/handoff`
**Worktree:** main checkout — Nathan declined the isolation worktree ("I'll close my server"); all work + commits on `main`
**Agents:** general-purpose (×14 — interaction sweep ×4, adversarial reviews ×5, systematic-debugging investigators ×2, CDP screenshot-verify ×1, earlier spec/phase reviews ×2), code-simplifier (×2)
**Skills:** `superpowers:brainstorming`, `superpowers:systematic-debugging`, `handoff`

Three editor bug-fixes, then the Notion-style block-drag feature built end-to-end — handles, gesture, heading/callout/table drag handles — adversarial-reviewed AND live screenshot-verified at every step. Four feature commits: `a8b06ff` `783be5e` `119dd50` `d9839b8`.

**Restored after a kill + a full MarkdownPM cleanup pass (this session, `14fe9a42`).** The original `64346d76` was killed mid-MarkdownPM polish; this session recovered its uncommitted work as a checkpoint (`b8eef9a` — blockquote drag grip + app-wide drawn caret), iterated the callout-nested blockquote bar (still open — see Fix Log), then ran a **full cleanup + code-review pass on existing MarkdownPM** (4 read-only review agents → 1 implementer → 1 adversarial verifier, then re-verified the gates myself). Landed: dead code removed (`isOrderedListLine`/`isDashBulletLine`, `CheckboxWidget.bracketTo`, `Overlay.destroy`); ~6 DRY consolidations (a single `lineOffsets`, the `blockAt`/`blockStarts` merge resolving the `TODO(DRY)`, one quote predicate+strip, `listFormatOf`, heading-shape under `headingParts`, `lineRightEdge`→`lineElementAt`); two correctness fixes (a callout no longer reports/demotes as a quote; menu callout default `[!note]`→`[!callout]` matching the typed shorthand); CSS hex/var cleanup (`rgba`→`#0000008c` var, no-op `color-mix` removed, grip-glyph + 14px grip recipe DRY'd); comment-bloat trim. **Typecheck clean, 300 tests green (independently re-run).** The block-math `$$…blank…$$` drag-corruption bug was deliberately left out of this cosmetic sweep (it's a real behavioral fix — see Fix Log).

**Three editor fixes shipped first:** The fold **chevron drifting** below callouts — CM positions its gutter from a height-MODEL that estimates off-screen variable-height lines at the default height, so every gutter chevron below a callout/fold drifted by a scroll-dependent amount; fixed by anchoring the chevron to the line as a `::before`. The **inspector h-scroll** — `overflow:hidden` still leaves a scrollable box, so a text-selection drag panned the shell to reveal the parked inspector; `overflow:clip` (not a scroll container). **Cell spell-check** — the cell editor lives inside the table widget's `contentEditable=false` host, which suppresses inherited spell-check; opted in via `contentAttributes`. Commits `dc89887` / `d6a26fe` / `2428ab3`.

**Block-drag brainstorm → spec, "reuse" oversold:** Brainstormed the full Notion-style model one-question-at-a-time (top-level reorder; chevron does fold+drag double-duty; lists grab at item-1 via a side handle; tables reuse their grip; callout-nested gets handles, blockquote-nested deferred; table stays in V1 despite cost). The spec's "reuse wholesale" thesis was **overstated** — 3 spec reviewers found 5 load-bearing falsehoods: `collectCands` is list-*geometry* not a filter; the table grip is *inert* for dragging + its widget swallows pointer events; folded-heading drag *loses* fold state; the chevron is a `::before` not a real node; taxonomy holes let HR/math fall into paragraphs. Rewrote V2. → `Planning/6-27 - Block Drag Spec.md`.

**Phases 1–2 shipped reviewed-green:** **Phase 1** (`5e1089f`) — `blockAt(doc,pos)→{from,to,kind}`, the keystone resolver; its logic reviewer caught a real high-frequency bug (list lazy-continuation split the list — a wrapped item orphaned as a paragraph) that had passed 12/12 happy-path tests; fixed continuation-aware. **Phase 2** (`dc72224`) — `BlockRange` broadening (the move primitives take a plain range; list-drag stays byte-identical) + `blockMoveChanges` (blank-aware: a block owns its trailing blank); logic caught 3 edge bugs — trailing-newline EOF double-blank, blank-line drop targets gluing, dropping on the block's own preceding blank — all fixed + pinned.

**Phase 3 shipped reviewed-green:** `blockStarts` enumerator + `blockHandles` (rail grips on para/code/list block-starts) + `blockDrag` (press grip → drag → `blockMoveChanges`). After the build-and-show fixes (single-pass O(n) `blockStarts` killing the lag; the blockquote-bar `::before` collision; first-row handle alignment), a **full non-testable interaction sweep** (4 agents) surfaced the real defects and Nathan chose the **full HIGH-set fix**: (1) a **silent drop-corruption class** — `blockMoveChanges` guaranteed a blank *below* a moved block but never *above* it or at the cut hole, so a drop onto a glue-adjacent seam lazily-continued a list / merged paragraphs; fixed with a two-seam `sep()` blank-guard (+4 regression tests); (2) **scroll-during-drag staleness** + no auto-scroll → candidates re-measure on scroll + an edge auto-scroll rAF loop; (3) **no abort** → Escape/window-blur cancel + a `done` re-entrancy guard; (4) the **accent line** now hugs the boundary above (`coordsAtPos(at-1).bottom`), folded/off-screen candidates gated out. Two adversarial reviews (corruption sound across ~40 inputs; gesture lifecycle clean), simplifier found nothing to cut, 678 green. **LOW-1** (gutter grip = whole list, glyph = one item) is **intended** (Nathan); **LOW-F4** (a double-blank source gap leaves a leading blank — cosmetic, renders identically) deferred.

**Phase 4 heading-drag via a shared gesture factory (`783be5e`):** Rather than a third copy of the ~100-line gesture, extracted `createBlockDragGesture({ gate, onClick?, onDragStart? })` and instantiated it for the grips + the chevron — chevron = fold on sub-threshold release, drag on threshold-cross. A folded heading **auto-unfolds at drag-start**: two systematic-debugging investigators (Nathan asked for them) proved a fold can't survive the relocating single-replace edit (CM's `mapPos` collapses interior positions to a span endpoint, orphaning the fold), so dropping it first sidesteps the remap entirely.

**Live-feedback rounds — snap, callout, table, box-edge (`119dd50`, `d9839b8`):** **List-drag-style snap** — each block offers two boundaries (above/below); the line snaps to the nearer edge + flips at the midpoint, instead of floating mid-gap. **Callout grip** wired as a real drag handle (it was a `pointer-events:none` placeholder; removing that lets the `::after` target its line → the gesture fires) + gutter-only reveal. **Table heading-row action grip** drags the whole table — extracted a callable `startBlockDrag` the React widget invokes (capture to `scrollDOM` dodges the widget-rerender capture-drop; right-click still opens the header menu, other rows still reorder). **Drag line sits OUTSIDE boxes** — reads the line's DOM box edge (`getBoundingClientRect`), not the inner text coords, so it lands on a callout's outer border, not inside.

**Verification held throughout — a screenshot agent stood in for Nathan:** Every feature got an adversarial review (all clean or LOW/cosmetic, folded in) + a simplify pass (hoisted the `.cm-line` walk to `editor/lineDom.ts`). Since Nathan went to bed mid-session, a **CDP screenshot agent** drove the live 9223 editor and visually confirmed all of it (line outside the callout border, the snap-flip at midpoints, the table grip starting a doc-level drag, gutter-only grips), leaving the test page unmutated — the post-functional UIX check, delegated.

**Isolated dev server (9223, Test Nexus):** `electron-vite dev --remoteDebuggingPort=9223` on `~/test`, own Vite, for build-and-show without touching Nathan's vault. **Config altered:** to open the Test Nexus I set the `pommora-react` userData `lastNexusPath` from `/Users/nathantaichman/The Nexus` (real vault) to `~/test`; original backed up at `scratchpad/pommora.json.orig-TheNexus` — **restore it** or the next launch opens the wrong nexus.

**Lessons Learned**

- The discipline ran *forward* this time (review before ship), and `12/12 green` was, repeatedly, exactly when the bug was hiding — the `blockAt` continuation bug + all 3 `blockMoveChanges` edge bugs passed happy-path tests + typecheck while broken. Adversarial agents at the pure-function layer caught them before any UI existed. Logged as the "Block Drag — the discipline, applied" coda in `Guidelines/Adversarial-Review-Log.md`.

- A "reuse" claim is a hypothesis until the code proves it: the table grip was *inert* for dragging (not a reuse), `collectCands` was list-geometry (not a filterable source). Reading the cited code turned the spec from confident-wrong to honest.

- **CM6 gutter drift generalizes:** CM positions any gutter from its visible-viewport-measured height MODEL (off-screen lines estimated at default height), so a gutter element below a variable-height block (callout/fold) drifts. A content-anchored `::before` is the fix — same pattern now in the chevron + the block handles.

- A `decorations.compute(['doc'])` recomputes on **every keystroke**; an O(n²) helper inside it makes the editor unusably laggy. Block-start enumeration had to be a single pass.

**Key Files & Insights**

- `editor/blockModel.ts` — `blockAt` + single-pass `blockStarts`. `editor/listDragModel.ts` — `BlockRange` + `blockMoveChanges` (blank-aware mover, sibling of the list mover, not a generalization of it). `editor/blockHandles.ts` (new) — rail-grip decoration. `editor/blockDrag.ts` (new) — the gesture (copies listDrag's overlay/shade; TODO: extract shared). `Styles.css` — `.md-block-handle::before` + the chevron content-anchor + the inspector `overflow:clip`.
- `Planning/6-27 - Block Drag Spec.md` (V2). `Guidelines/Adversarial-Review-Log.md` — the discipline coda.
- Commits: editor fixes `dc89887`·`d6a26fe`·`2428ab3`; block-drag `5e1089f`·`dc72224`·`a8b06ff` (Phases 1–3 + HIGH-set) · `783be5e` (Phase 4 heading-drag) · `119dd50` (snap + callout grip) · `d9839b8` (table drag + box-edge line + `lineDom.ts`).
- New since Phase 3: `editor/lineDom.ts` (shared `.cm-line` DOM walk), the exported `startBlockDrag` + the `createBlockDragGesture` factory in `blockDrag.ts`, `collectCands`'s two-boundary model + `bottomAbove`/box-edge geometry, the callout/table grip wiring (`Tables/widget.tsx` `tableDrag` → `startBlockDrag`; `Tables/TableView.tsx` row-0 grip).

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

- Screenshot-verified, but **Nathan's own full live UIX pass is still owed** — he confirmed callout drag + the line-outside-callout fix live before bed, but the whole drag *feel* (snap responsiveness, table drag, heading fold-vs-drag) wants his eyes when he's back.
- **C — blockquote/codeblock above-below spacing is NOT done.** Nathan wants bq/cb separated from surrounding text like callouts/lists (the callout `--callout-gap` look). Left undone deliberately: visual CSS with a caret-risk (the no-line-margin gotcha) needing his visual confirm + a mechanism choice (margin vs an inset-box `::before`).
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

- **(B) Block Drag is feature-complete, reviewed + screenshot-verified.** Phases 1–4 + callout-drag + table-drag shipped (`a8b06ff`→`d9839b8`); this session added the bq/code/callout **outer-gap spacing** (6px via an inset-`::after` float — CM6 can't take line margins), the shared **`dragChrome`** Overlay+shade, the **callout-grip Delete menu** (`e6dbeb7`), and the **table-grip right-click guard** (`7ac6f0e`). Open: **(1)** Nathan's own full live UIX pass of the drag feel — *and* confirm the callout Delete menu live (it's a native OS menu touching main+preload, so it needs a dev restart and can't be screenshotted); **(2)** line-INTO-callout interior drop slots (V2 nesting, deferred); **(3)** finish the gesture-lifecycle unification — `dragChrome` shares the Overlay+shade but `listDrag` still runs its own `onMove`/`finish`, so it lacks Escape/blur abort + a done-guard that folding it onto `startBlockDrag` would give it (the review's one open LOW finding).
- **(A) Table Views Part 1 SHIPPED → Part 2, then Part 3.** Part 1 (11 TDD tasks, simplify-+code-reviewed, suite+typecheck green) shipped on `views-plumbing` (`d5ed3ac`…`1c892a7`) and is **merged to `main` this commit** — supersedes the parallel `pommora-react` Task-6 WIP, so run all React work from `main` now (pipeline in `renderer/src/Detail/Views/pipeline/`, main IO in `main/io/activeViews.ts` + `main/crud/{views,loadValues}.ts`, on-disk contract in `shared/views.ts`; decisions → `History.md`). **Part 2** — the Figma-designed table UIX + chips (direct `design-system/components/Chips/` on `tokens/chip.css.ts`, shared by select/multi/status, NOT Swift ports) routed to the `ResolvedColumn[]`/`ResolvedGroup[]` seams; inline cell editor (glass chip pickers, plain inputs, "Calendar" date placeholder, native menus); render concerns deferred from Part 1 land here (group/sort **column hoist before `_title`**, column widths, relation/tier chip resolution via `Detail/Scope.ts` `findContext`). **Part 3 — UNDERWAY** (`Planning/6-28 - Table Views Part 3 — View Settings.md`): the View Settings glass dropdown shell, scope-derived routing (`Detail/ViewSettingsScope.ts` — generic toolbar, pane chosen by selection), the `ViewPane` root menu, and the **Properties pane** (schema CRUD: create/rename/icon/delete; select+multi-select seed a starter option) are built; the glass + motion are **done** — `GlassPane` is native CSS frost (baked `PANE_FROST`, tuner removed), every pane opens with the **Bloom `dropdown-menu`** + retracts on close, IconPicker is on the same glass+motion, and motion/shadow/input are tokenized (`--disclosure`/`--shadow-standard`/`--input-field`). **Pending:** Grouping/Sort/Filter/Layout/Visibility panes + operator picker, the Properties rich editor (options/format/change-type/duplicate/reorder), and view rename/dup/delete wiring the `views:save/reorder/delete` + `activeViews` IPC already shipped in Part 1.
- **(A) Carryover editor work:** **Callouts** are functionally hardened (delete-guard + adversarial fuzz pass, `Guidelines/Adversarial-Review-Log.md`); remaining: tables-inside-callouts (deferred). Create unicode up-down + back-forth auto-transform for `<>` / `><`. Add "Styles" to tables → style = column would remove gutter padding + hide table lines (solves the markdown column problem).
- **(A) Live-verify the heading-column toggle end-to-end** — menu → toggle → persist → reload is unit-tested + typecheck-clean, but not confirmed by a real in-app toggle.

### Pending Focuses

- **(B) Block Drag V2 — nesting** (separate spec): interior drop-slots inside callouts (the line-INTO-callout Nathan flagged), the guard table (table / heading / callout can't nest in a box), cross-container re-prefix, the `depth` field. Deferred from V1; the V1 mover + reindent already prove the cross-container re-prefix.
- **(A) Part-1 deferred cleanups (Nathan's call):** (1) extract one generic `.nexus` map-store factory for the 3 identical stores (folds / tableHeadingColumns / activeViews — same lenient-read / merge-write / empty-deletes shape across module + IPC + preload); (2) a borderline `relPosix(root,abs)` helper (`loadValues` + `watcher` share the `relative().split(sep).join('/')` idiom).
- **(A) Date-bucket cross-build follow-ups (Nathan's call):** (1) the date-only off-by-one fixed in React (date-only buckets by its stored UTC date) still exists in Swift's `DateBucket` (`Calendar.current` on a UTC-parsed date) — align Swift or leave; (2) timed `datetime` values still bucket display-local (matches Swift) — switch to UTC for cross-machine determinism, or keep.
- **Table Views Part 2 (table UIX) + Part 3 (View Settings, UNDERWAY)** — see Next Sessions. Part-1 plumbing shipped + merged; Part 3's shell + Properties pane built (`Planning/6-28 - Table Views Part 3 — View Settings.md`), remaining panes pending.
- **(A) Motion-token DRY backlog** — the remaining hardcoded `120ms` snappy-hover pair (`Sidebar.css:55` row hover + `:141` section reveal) has no matching token; decide adopt `--duration-fast` or add a `snappy` token. Full duration inventory (CSS + JS-driven) in `Features/Interaction.md` § Duration inventory. Also: `materials/index.ts` exports an **orphaned `EdgeLensGlass`** (zero consumers — prune or keep as lab API, Nathan's call).
- **(A) Autocomplete retract in table cells** — the wikilink autocomplete blooms/retracts in the page editor; in a table cell, IF picking also closes the cell editor, the portaled panel unmounts before its retract plays (would cut, not retract). Keep the panel alive through its exit there if it bugs.
- **Break-things skill (Nathan-requested)** — a reusable adversarial-fuzzing skill from `Guidelines/Adversarial-Review-Log.md`: a break-attempt taxonomy (input transforms · deletion/caret combo matrix · nesting · adjacency · layout edges · fix-induced regressions) + the "toddler" method + a `{keys}×{positions}×{nesting}×{adjacency}` generator → a break→repro→fix catalog before any UI feature is called done.
- **Canvas** — spec parked at `Planning/6-26 - Canvas Spec.md`, pending its adversarial review → plan → build. React-first; the `.canvas` format is the cross-build contract. Confirm the `border` token (grey-30%) lands when canvas builds.
- **Caret on the other editor surfaces** — drawn caret + custom hover cursor shipped on the page editor (`editor/caret.ts`); extending to table cells + the inline-rename input is the remainder.
- **Subfield reorder + live-stats + custom items** — registry/order/persistence are the seams; `Features/Subfield.md` § Roadmap.
- **Icon picker** — chrome done (`GlassPane` frost + Bloom open/retract, centered over a scrim); remaining: the Figma symbol-grid body + wiring the icon's frontmatter save (Swift `IconPicker` is the spec).
- **Real design-system Components** (Button / Menu / Label / Separator / **Chips**) from the token layer — prerequisite for replacing one-offs (notably the inline-rename `<input>`).
- **Radius + spacing tokens** — still ad-hoc literals; lift from Figma.
- **Settings editing UI** deferred — `.nexus/settings.json` is the control surface (labels + accent + `subfield`).
- **Biome config vs code (repo-wide)** — `biome.json` declares `quoteStyle:"double"` + organizeImports, but the codebase is hand-written single-quote / no-semicolon (internally consistent; the format hook isn't converting quotes). Settle once: config-to-match-code OR reformat-repo-to-config — defer to a tree with no parallel uncommitted edits.
- **Unsorted bin → folder + sidecar (paradigm, ratify first)** — move "unsorted" off a config file onto a real `Unsorted/` folder with an `_unsortedconfig.json` sidecar (the folder-with-sidecar pattern). Win is interop (another Markdown app could share the folder). On-disk shape — ratify before building.

### Fix Log

- **Aliased `[[A|B]]` vs cell-pipe** — a `|` in an aliased connection collides with cell-pipe escaping inside a table cell; autocomplete only inserts alias-free `[[Title]]`. Open paradigm call.
- **Table links non-clickable** — no input handling for the rendered link inside a cell; proposed single-click navigate + right-click edit.
- **Bullet single-word wrap drops the word below the marker** — a `-`/`•`/`+`/`→` item whose content is one long unbroken word drops the whole word to the next line; the marker-space hide that would fix it didn't survive CM6's replace decoration. Only the `line-height` cap shipped. → `Features/MarkdownPM.md` § Known issues.
- **Recents submenu on "Open Nexus"** allows trashed folders to appear; opening one pulls it out of trash.
- **Callout-nested blockquote bar — cap clips/squares (open).** With the callout owning `::before` and the nested quote's fill+bar sharing the one `::after`, a rounded fill + an unclipped rounded-cap bar is unreachable in two pseudo-elements — every CSS variant clips the cap or squares the fill (a line `background` can't round). Current state: a `box-shadow` inset bar over the rounded `::after` fill (cap rounds on the outer-left only). The grounded fix (CSS review): make the bar a **real DOM widget per `md-bq-in` line** — the `GripWidget` mount path, caps via the existing `md-bq-in-first/last` classes. Not built; the `.md-bq-in*` rules are left at the box-shadow version.
- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span containing a blank line parses as two halves with orphaned `$$`; block-dragging either half corrupts the document ([blockModel.ts](React/src/renderer/src/MarkdownPM/editor/blockModel.ts) — test-pinned, unguarded). A real behavioral fix (guard or parser), deliberately excluded from the cosmetic cleanup pass.

### Handoff Rules

- **Resolve = delete + route, never tag.** When an entry here (Pending Focus, Landmine, Uncertain, Fix Log) is genuinely done, push its real outcome to the canonical doc (`History.md` / `Features/*` / `Framework.md`) and delete the line — no `(Resolved)` / `(Superseded)` tombstones. In parallel, you may delete a resolved Landmine/Uncertain from another session's block (removal only) even though the rest of their block stays frozen.
- **Keep the Fix Log current.** Acknowledged-but-unfixed issues get a 1–2 sentence entry; remove on resolve.
- **One block per session, updated in place.** Compactions bump a `Compactions` count, they don't add sections. Push spec/decision content to its canonical home; carry still-open Pending Focuses forward to a fresh *sequential* session.
- **Markdown only, no new folder** (per Nathan) — this doc stays the single `React/.claude/Handoff.md`, not a routed `Handoffs/` dir, regardless of the skill's `Handoff`/`Session`/`Sessions` filename shapes or its config route.
- **Parallel sessions share this one doc.** Each concurrent React session gets its own labeled block (`### Session Summary - A`, `- B`, …) with its own metadata + sections; the Cornerstone top matter is shared above all blocks, written once; list every session ID in the header. The agent running `/handoff` is the newcomer (next free letter; A = the block already in the file) — never edit another session's block, only write/refresh your own. The footer (Working Notes / Next Session / Pending Focuses / Fix Log / Handoff Rules) is shared. **Next Session lives once in the footer** (→ `### Next Sessions` when parallel), never per block. (The Swift build keeps its own separate root handoff.)
