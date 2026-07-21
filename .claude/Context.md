## Context — Pommora React

### Current Focus

The React rebuild of the Swift paradigm reached its finish line at v0.5.0 — Page Previews and the Subfield unification pulled React past where the SwiftUI build ever got. That's the baseline the roadmap counts forward from, not a target still to hit, and it's mostly my own live drive from here.

**v0.6.0 is underway** — the view renderers that only ever existed as names over the finished filter → group → sort pipeline. **Cards** is first, and it's now functionally complete on `cards-view`: the ratified plan across eight phases, a long interaction-hardening campaign, and finally a full drag rework I drove by feel. The card drag went from "very finicky" to solid — the finicky was the cross-zone engine reintroducing everything the proven single-zone engine already solved (no hysteresis, per-frame layout reads, a stale-rect padding hack), so it got rebuilt around row-bucketed hysteresis and a cached-bounds model. The lifted card is now the whole faithful card, group headers spring open when you dwell a drag over them, and dragging a row or card into another folder actually moves it.

That last one runs on a shared optimistic tree-move — a page/set relocation patches the in-memory tree the instant the write lands, so the move (and the sidebar's own reparent) reflects immediately instead of waiting on the vault re-walk. It's the one mechanism behind three surfaces now: the table/cards cross-folder drag and the sidebar reparent.

Merging to `main` is deliberately gated behind two things first. One is a context create/rename bug I just traced — creating a context was very buggy (no icon, a garbled name, keystrokes that never showed), all one root cause: it races a full-vault re-walk before the new row even exists. The other is a full app-wide cleanup pass. v0.5.0 already went out, so pressing on with anything less than the cleanest, most composed codebase would only breed future failures — the sweep is the pre-merge "turn the hurricane house into a luxury hotel" pass, an aggressive hunt for jitter, redundant reloads, double-renders, and separated code a shared mechanism should own. Table still runs alone on `main`; Gallery, List, Calendar, and Timeline are still just names.

Two fixes shipped off that track earlier this run: the **persistent thumbnail cache** (B-6) now existence-prunes at nexus-open instead of evicting to a recents∪pins window, so Preview covers persist across sessions; and a **MarkdownPM table** cell-edit bug — edits didn't repaint until a reload — is fixed.

### Recent Work

#### Cards View — complete renderer + hardening (07-19 → 07-20)

The first v0.6.0 renderer, taken from ratified plan through a full hardening campaign. The renderer itself: the shared container/embed seam, a draggable Set Cards row, flattened disclosure bands, Sort-by-Location flatten, per-value interaction on the table's cell leaves, the two-stage add menu (now "everything not currently shown; picking reveals" — hidden tiers/contexts pane through the context picker), and the native card + banner menus. The hardening: the compact ×-steal value-loss class killed (the × is inert until hover-revealed; the drop gate keys on embed zoom), the link seam made alias-preserving, the number Bar look gated by one divisor predicate across all four surfaces, and the Bloom law made structural — the value/calendar/add pickers live at ONE grid-level host (`CardPickerHost`) that row churn can't tear, with PickerMenu dev-erroring on any mid-open unmount. The settings panes got real floating drag ghosts (the missing chip read as "dragging behind the glass") and their label-primary titles back. → [[CardView]] · [[Cards View — Decision Log]].

#### Card drag rework + shared move/disclose mechanisms (07-20)

The card drag felt "very finicky," and two exploration agents plus a build-breaker traced why: the cross-zone drag engine had reintroduced every problem the proven single-zone engine already solved. So it was rebuilt — row-bucketed hysteresis (the index used to flip-flop across top-aligned unequal-height cards, which was the finicky), a cached-bounds model instead of a `getBoundingClientRect` every pointer-move, a synchronous per-band-entry pad replacing a per-move effect that had left frozen rects a row stale, plus a stranded-drag guard for a release outside the window. The lifted card became a faithful full card rather than a title glyph, by extracting one `CardFace` both the live card and the drag overlay render, inside a `.cards-view`-classed carrier so its size vars resolve; whole-card drag came from moving the engine off pointer capture to window listeners so a tap still clicks.

Three capabilities came out of that base and reach past cards. Group headers spring open when a drag dwells over them for about half a second — engine-agnostic, so cards and the table both get it. A row or card dropped into another folder-band now moves the page (`movePage`) rather than doing nothing. And a shared optimistic tree-move (`treeMove.ts`, unit-tested) patches the in-memory tree the instant any move's write lands — so cross-folder drag and the sidebar's reparent both reflect immediately, and the vault re-walk just confirms. → [[CardView]] · [[Navigation]].

#### Unified Subfield + Scan-Promote (07-17)

The floating preview and the full-pane detail had drifted into two copies of the same footer, so this collapsed them. The Subfield takes one optional scope prop now — a scoped instance (the floating preview) describes its own page off a body it owns, never the single shared live-count slot, because a second writer there would evict the main pane's count.

NavView also picked up the List/Gallery toggle the detail pane already had, plus its own persisted view mode kept separate from the NavWindow's, and the scan on the nav/map side promotes the whole NavWindow into a NavView tab. This is the work that closed the rebuild. → [[Subfield]] · [[Navigation]] · `History.md`.

#### Page Previews (07-16 → 07-17)

Directly advancing on the Multi-Tab Nexus momentum, a parked `open_in` value became a real floating, editable preview window — wiki-clicks open dedup-focused tabs beside the origin instead of a back-only peek, and it stays neutral to the app's own tabs.

The page window and the NavWindow are the same thing under the hood: one chrome, one tab-motion layer, one side-pane, one warm seam. Each origin page remembers its opened tabs across sessions in a synced `page-previews.json`. → [[PagePreview]] · `History.md`.

#### Multi-Tab Nexus (07-14 → 07-16)

The nav model had a fork sitting open for around a month — replace the pane, stack top-bar tabs, or split panes — and it mostly came down to the perf hard-rule: N live tables would wreck scroll, so tabs keep one view mounted and cache the rest per-tab.

Pinned tabs ARE the pin set, never a second stored copy; the whole set travels across devices through a synced `tabs.json`, and every tab carries its own Back/Forward. The empty state became NavView, the full-window recents gallery. It's on `nav-gallery-pins`. → [[Navigation]] §II · `History.md`.

#### SurfacePM — Block Surfaces (07-10 → 07-13)

The composable dashboard layer — a mosaic of draggable, resizable tiles over an in-house tessellation engine, with the Homepage as the removable dev host. It works host-agnostic on purpose, so it exists before any real host does, and it repairs rather than rejects at every level: a foreign or broken tile entry renders inert instead of crashing the surface.

A page embed IS the CM6 editor, flipped read-only in place. View embeds, the geometry locks, and the link-graph host are the pieces still left. → [[SurfacePM]] · `History.md`.

#### Navigation Surface + Auto-Scroll (07-14)

A per-nexus nav-state layer — recents, pins, favorites, all resolved live against the tree so a moved entry follows and a dead one just drops on render — feeding a store and client-side fuzzy search behind the NavPane command surface.

Alongside it, every drag's edge-scroll collapsed onto one shared primitive across seven surfaces, resolving its scroller once at drag start rather than chasing the pointer each frame. → [[Navigation]] · [[PommoraDND]] §II · `History.md`.

### Pending Focuses

- Cards merge to `main` — the renderer, the drag rework, the context-create fix, and the app-wide cleanup pass are all complete on `cards-view`; merge waits only on Nathan's live pass over the drag/menu/main-process surfaces (none CDP-drivable). The a11y pass still owes it — the `noStaticElementInteractions` stubs want real roles/keyboard. → [[CardView]].
- The NavPane toolbar dropdown is still a blank placeholder — what a compact nav dropdown holds versus the fuller NavWindow is an open call before building into it.
- User Sections CRUD — collections render user sections but there's no way to actually make one (`mutate.ts` has no section ops); its own brainstorm → plan → build. → `Sidebar.md`.
- The flattened-mode bundle — "None"/flat grouping plus Flatten and Hide Location — is deferred; the `flat` GroupConfig kind stays reserved. → [[Views]].
- Perf debt: no row virtualization yet (every row mounts, which bites at thousands), and an external value edit doesn't live-refresh an open table. The one-view-mounted multi-tab design deliberately dodges needing table virtualization.
- Canvas — the spec sits at `Planning/6-26 - Canvas Spec.md`, pending adversarial review → plan → build.
- iCloud-sync readiness (future) — `serializeOnFile` can't coordinate with the iCloud daemon under LWW, `.nexus/index.db` needs sync-exclusion, and the walk has to skip `.icloud` placeholders.
- Mobile iOS companion — parked, spec at `.claude/Mobile/MobileSpec.md`, no build commitment.
- Editor deep cut (post-scan-cache): the per-caret line/rail loop still walks every line — the full StateField split (doc-keyed line chrome mapped through changes + a selection-scoped reveal plugin) is the remaining step; needs live-editor verification.
- NotchedPane rebuilds its beak path per frame while a pane animates height, and PickerMenu + NotchedPane each run their own ResizeObserver on the same pane — consolidate to one measurement owner passing size down.
- `useExitPresence`'s default exit window is a raw constant decoupled from the motion tokens — derive it from `duration.slow` + slack or menus flash on close if the tokens are ever retuned.
- IPC error envelopes come in two shapes (`mutate`'s structured PommoraError vs ~20 handlers' bare `error: string`) — one `Result<T>` envelope everywhere removes a consumer-confusion class, net-negative.
- `useDismiss` coordinates with picker portals via per-event DOM queries (`closest`/`querySelector` on `[data-picker-portal]`) — a shared open-picker counter removes the DOM handshake.
- The Toolbar aims its dropdown beaks with hard-coded trio fractions (5/6, center) — any trio change silently misaims them; derive from measured trigger rects like PickerMenu.
- The preview window fetches the same page twice (PageEmbed's body load + PreviewInspector's frontmatter fetch) — lift one `openPage` result to the window and pass both halves down.
- PageView and PreviewWindow each rebuild the full connections index (`buildPageIndex(flattenPages(tree))`) per tree change — a shared hook (routing injected) halves the walk and the copy-paste.
- AutocompletePanel is a hand-rolled body portal that PickerMenu's beak-less surface could host; and when a third boolean-dropdown consumer appears, extract the `useMenuPresence` (open + dismiss + exit-presence) bundle — two consumers today made it indirection, not DRY.
- `group.tsx`'s `cellAt` rebuilds the zone's column model per item per over-flip — hoist lefts/stride/cols to a per-zone computation.
- `sidebarDnd`'s collection/context branch re-filters the sibling set per pointermove — snapshot it at activation (invariant mid-drag).
- View format/grouping/banner saves still trigger a full vault walk (`viewMint`'s non-`skipRefetch` path) — an optimistic view-slice patch skips it; `submitPropertyRename`'s walk wants the same targeted-patch treatment.
- The sidebar mode cross-fade renders two full trees, each building its own DnD index — share the tree-keyed index memo across the exit/enter layers.
- Id-keyed inline renames (ViewPane's view rename, the property-rename channel) each re-roll the 10-line `EditableInput` wrapper `RenamableTitle` provides for path-keyed rows — a state-driven `RenamableLabel` twin unifies them.
- The rest of the gesture family (`sidebarDnd`, the table column drag, `useOptionReorder`/`useStatusReorder`, MarkdownPM's `listDrag`/`blockDrag`, SurfacePM's `pointerDrag`) still hand-roll the skeleton `gesture.ts` now owns — migrate each onto `usePointerGesture()` opportunistically as its file is next touched.
- Latent: TableView's drag-visual memo indexes `columns[colDrag.from]` with a render-time array — a watcher shrinking the columns mid-column-drag is an OOB; bound-check or key by id.
- Latent: `setIcon` on the OPEN page updates the tree node but not `pageDetail.frontmatter.icon` (stale until reselect) — pre-existing; a targeted `pageDetail` patch closes it.
- The group-band "+" (structural Set bands) is a deliberate visual stub awaiting Nathan's creation-affordance design — `createFromMenu` + the optimistic insert now make wiring it trivial once designed.

### Hard Rules

- The dev app runs against the real Nexus, so CDP opens and Escs only unless authorized — and the editor gets driven only on a throwaway page, since typing into a live one autosaves straight to real data.
- Stage explicit paths, never `git add -A` — parallel sessions and Nathan's own uncommitted edits share the tree.
- Never allow planning, brainstorming, or session-specific references to make it into code or documentation. 

### Lessons

- Two-writers-for-one-fact is the defect class the tab and nav work kept breeding — `tab.target` versus the navStack cursor, the tab set versus the pin set, the capture marker versus the thumbnail file. Every real bug reduced to it, and the fix was always one writer or a lockstep rule.
- HMR only goes so far: CSS and React Fast-Refresh work, but CM6 extension code needs ⌘R, `src/main` and preload need a full dev-process restart, a vanilla-extract `*.css.ts` can serve stale (a plain restart heals it, ⌘R never does), and a component's focus-effect / handler / attribute change often gets skipped by Fast-Refresh.
- CDP has two quirks that keep biting: synthetic clicks work on tabs/rows/buttons but never fire PickerMenu items (drive those via `el.click()` in `Runtime.evaluate`), and a non-integer dpr (1.7 on this machine) throws off screenshot clip math — crop the full-frame PNG with PIL instead.
- Where the recent code lives: Multi-Tab under `Tabs/` (`tabsModel.ts` pure with its own tests, `warmCache.ts` for the session LRU, every tab-bar visual knob in `tabBar.css`'s `.tab-bar` block); `select` is the single nav entry point; the New Tab `+` rides a shared `--toolbar-swallow` var on `.app-toolbar`; and the pin toggle shared between list rows and gallery cards is `NavPinButton` in `NavList.tsx`.
- A whole-surface drag handle steals its own children's clicks: the drag engine `setPointerCapture`s on pointerdown, retargeting the derived click to the drag node, so any interactive descendant (a value picker, an add surface) has to stop pointerdown — a container only on its own empty space, so the title still drags. Two smaller ones from the same run: Zod 4's `z.number()` already rejects Infinity/NaN where Zod 3 didn't (a `.catch` codec defaults them for free), and native Electron menus are OS-level — CDP can't screenshot or drive them, so their pure models get unit-tested and the popup needs a human.
- The Cards renderer lives in `Detail/Views/Cards/` with its pure seams unit-tested (`cardsOrder`, `cardValueInput`, `cardsBand`); the cell/card right-click model is single-sourced in `@shared/cellMenu.ts` + `@shared/cardMenu.ts` + `@shared/pageMenu.ts`; cards flatten via **Group By: None** (the `flat` kind, rendered headerless) and order via a **Sort By: Location** entry (reserved `LOCATION_SORT`, Order Location/Custom, resolved through `locationFlat` for its filesystem order), gated on `flattenStructural` so neither can touch a table.

### Fix Log

- `.nexus/activeViews.json` and its per-machine siblings (`folds`, `viewOrders`, `tableHeadingColumns`, `linkTitles`) aren't gitignored — using the switcher on a fresh container creates a would-sync file. They need adding to the Nexus `.gitignore`; `tabs.json` does not, since it's synced on purpose.
- The "File" property icon gets clipped by its vertical row padding on the ViewPane.
- The link-rename field shows a leading empty space — a visual inset, not a stored character (deprioritized).
- Blockquotes inside of codeblocks are unstable and need proper debugging.
- Block-math drag corrupts the doc: a multi-line `$$…$$` span with a blank line inside parses as two halves with orphaned `$$`, and block-dragging it corrupts the document (`blockModel.ts`, test-pinned but unguarded).
- A single-word bullet that wraps drops the word below the marker — only the `line-height` cap made it in so far. → [[MarkdownPM]].
- The Set-Card drag flash (drop snaps back, then jumps on reload) should now be settled by the optimistic reorder patch in `store.mutate` — needs one live confirmation before the Fix Log drops it. → [[CardView]].
