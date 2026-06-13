### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-12 — hand-rolled table replaced by a wrapped AppKit `NSOutlineView`; wired + committed on `views-salvage`, 12-item backlog)

This session started as "tweak/clean up the views-salvage table" and immediately became an architecture correction. Nathan ran the existing custom SwiftUI table and rejected the whole approach as non-native hand-rolling — *"this seems like a custom table when my directive was clearly a wrapped real swift table."* That confirmed the standing memory ([[project-views-custom-table-failed-use-appkit]]): wrap **AppKit `NSOutlineView`/`NSTableView`**, don't rebuild a table from SwiftUI primitives. The fix is `ViewOutlineTable` (`Detail/Table/ViewOutlineTable.swift`) + `ViewTableCells.swift` — a thin `NSViewRepresentable` over a view-based `NSOutlineView` that consumes the **existing** pipeline currency (`[ResolvedGroup]` / `[ResolvedColumn]` / `ViewItem`) and hosts the existing SwiftUI cells via `NSHostingView`. Column chrome (resize / reorder / width-persistence), disclosure folding, inset alternating fills, and selection are now native AppKit; only the cell *content* stays SwiftUI.

It was built and refined across several hands-on rounds (each verified by a background `builder` agent, then by Nathan running it): native columns + inset style fixed the "scrolls in a nested frame / wrong background" complaints; a structure-signature reload-guard killed the disclosure jank; `.font(.caption)`→system default fixed the cramped type; selection was disabled (it fought dragging; multi-select deferred); a bulletproof column teardown (re-reading clear loop + dedup-by-id) attacks the duplicate-Title bug; echo-guards on `columnDidMove`/`columnDidResize` (persist only when the value differs from resolved) attack the "any re-render wipes column order/sizing" bug; a `ColumnHeaderView` adds a right-click Hide Property menu; indentation bumped to native 16. A code review (reviewer agent + controller pass) produced a Haiku fix-spec (`Planning/06-12-Table-Cleanup-Fixes.md`) whose mechanical cleanups were applied. Nathan's verdict on the native direction: *"this is actually really good."*

Then a git tangle ate most of the apparent progress. The work was committed to `views-salvage` as `e7719c0` — **but that commit staged only the two new files + docs, NOT the one-line `PageTypeDetailView` swap that actually wires `ViewOutlineTable` in.** So the app kept instantiating the old `CustomTableView`; every "it's still broken" test after that point was against the OLD table. Compounding it, an accidental `views-salvage → main` merge dragged the abandoned custom-table lineage onto `main`; that was recovered (`main` reset to the pre-merge `257a0ff`, fully reversible, nothing pushed). The missing wiring was then found and re-applied + committed as `1e7d4fe`. Nathan's frustration was the whole point of the cornerstone: *"none of the things I talked about got fixed because of this whole thing."*

Left off: **`views-salvage`** at `1e7d4fe`, working tree clean, build green — the native table is now actually wired into the vault detail. **`main`** is clean at `257a0ff`, untouched, **not merged** (deliberately — the work is mid-flight). Because the table was only just wired, the Tier-A fixes (dup, config-persistence, Hide Property) have been committed but **never exercised by Nathan on a wired table** — they are the first thing to verify next session. Nathan also flagged the Hide Property menu as a "weird custom menu" — it should become the native column checklist.

#### Lessons Learned

- **Commit the WIRING with the feature, not just the new files.** The integration point (`CustomTableView(` → `ViewOutlineTable(` in `PageTypeDetailView`) was a modification to an already-tracked file; `e7719c0` staged only the untracked new files, so the table was never instantiated and we chased ghosts for hours. When adding a component, stage the call site that plugs it in — `git status` "clean" doesn't mean "wired." **→ candidate CLAUDE.md quirk**
- **Build-green ≠ wired ≠ verified.** The dup/config/Hide-Property fixes compiled and committed, but were never running because the renderer wasn't mounted. Verify on the actual running surface, not just the build.
- **Native-first, again.** Wrap the AppKit control (`NSOutlineView`) — disclosure, column resize/reorder/persist, alternating rows, keyboard nav come free; a SwiftUI hand-roll can't match the look/feel and re-implements all of it badly. Reinforces [[project-views-custom-table-failed-use-appkit]].
- **Don't merge in-progress work to `main`.** The accidental merge re-introduced the whole abandoned-custom-table lineage. `main` stays clean until the work is verified-clean; then one deliberate merge.

#### Next Session

1. **Verify Tier A on the now-wired table** (Stop + Run a clean build): (a) no duplicate Title on any vault; (b) resize/reorder a column then open/close a page or hide a column → layout HOLDS; (c) right-click a header → Hide Property. If any is still broken on the *wired* table, the committed fix is insufficient — re-investigate from scratch.
2. **Redo the Hide Property menu as the native column checklist** — Nathan: it's currently a "weird custom" single-item menu. Native pattern = right-click header → list ALL columns with checkmarks, click toggles show/hide (needs an un-hide path + the hidden set passed in; Title shown-but-disabled).
3. **Work Tier B** (Fix Log 4–12) in roughly this order: Collections swap + delete the old `CustomTableView` stack (the big clean-baseline item, also kills the cell duplication) → header property-icons + Title=`text.justify` → banner right-click + immersive + title stroke → View-button-out-of-toolbar + 65×36 pill → dropdown material/fill → native row drag → reload-robustness.
4. **Merge `views-salvage` → `main` once verified-clean** — the proper baseline merge. (Nathan asked to merge now; controller flagged it as premature + lineage-dirtying — confirm intent before doing it.)

#### Pending Focuses

- **`main` merge of the Views work** — deferred until the table is verified + Tier B is meaningfully done; do it as ONE clean merge (a regular merge re-introduces the abandoned-custom-table lineage — consider squash if a clean `main` history matters).
- Agenda compact-panel surface: hosting decided by the v0.6.0 Agenda UIX work.
- Launch-tail indexing contract (`Architecture.md`): Finder-dropped pages arrive via CRUD / forced rebuild, not the launch scan.
- Settings full editing UI ships v0.7.0.

#### Fix Log

**Native table — `views-salvage` (items 1–12, the active backlog):**

*Tier A — fix COMMITTED in `e7719c0`, now wired (`1e7d4fe`), but UNVERIFIED by Nathan on the wired table — verify first, rework if still broken:*
1. **Duplicate Title columns** — bulletproof teardown in `rebuildColumns` (re-reading clear loop + dedup-by-id). Supersedes the weaker `outlineTableColumn`-detach attempt that Nathan saw fail (Systems vault). UNVERIFIED.
2. **Column order/sizing wiped on any re-render** (hide a property / edit a property / open-close a page) — echo-guards on `columnDidMove`/`columnDidResize` (persist only when the new value differs from resolved) + `isRebuildingColumns` async suppression. `updateView`/`mutateViews` themselves were confirmed sound (read-modify-write). UNVERIFIED.
3. **Column-header right-click → Hide Property** — implemented (`ColumnHeaderView.menu(for:)`), but Nathan flagged the single-item menu as "weird custom." REDO as the native column checklist (see Next Session #2).

*Tier B — NOT built:*
4. **Banner right-click → Change / Remove Banner** — `setBanner(_:)` already accepts `nil` (removal); `CoverAssetStore.delete` for the file. `ContainerBannerView`.
5. **Banner immersive** — fill the toolbar area + extend into the title area (window titlebar transparency / overlay).
6. **Banner title + icon stroke** — labelSecondary 2pt stroke so the title stays legible over the banner image.
7. **Column header property icons** — headers are text-only `NSTableColumn` titles; show each column's `iconName`; Title header icon → `text.justify`. Needs a custom `NSTableHeaderCell` (draw symbol + text).
8. **Native row drag-drop** — reorder + drag-between-groups with the native insertion line; replace the hand-rolled drag. `dragCoordinator`/`buildDropContext` are carried into `ViewOutlineTable` but unused — route the native `NSOutlineView` drag delegates into the existing `GroupDropPlanner`/`DropContext`.
9. **Collections still on the OLD table** — `PageCollectionDetailView:275` still constructs `CustomTableView`. Swap to `ViewOutlineTable`, fix nested-collection indentation, and DELETE the old stack (`CustomTableView` + `ColumnLayout`, `ColumnDragController`, `RowDragCoordinator`, `RowDragGeometry`, `TableHeaderRow`, `TableGroupRow`, `TableRowView`, `TableSelectionModel`). Also resolves the temporary cell duplication (`CellIconGlyph`/`CellPropertyHost` vs `TableRowView`'s privates).
10. **"Icon & Text" toggle on every toolbar button** — caused by the View dropdown button being a shared `NSToolbar` item. Move it OUT of the shared toolbar, render it conditionally within the storage (vault/collection) detail view, as a SEPARATE 65×36pt pill (not grouped with the other 3).
11. **Views dropdown panel** — use the same material as the other dropdowns (currently different); replace selection outlines with quaternary fill (per Figma).
12. **Reload-trigger robustness** (code-review finding) — `signature(of:)` excludes property values + the relation-resolver cache, so it relies on `modifiedAt` bumping (brittle on nil-`modifiedAt`) and relation/tier cells go stale after the async `contextDisplay.warm`. Include property values + refresh on warm.

**Carried (pre-existing, unrelated to the table):**
- **Inline-edit lag** — property-value inline edit has a noticeable commit buffer.
- **Stale property options** — newly-added Select/Status options aren't selectable until restart; needs a running-build repro to pin the picker path.
- **Backspace on checkbox / list item** should auto-delete the syntax — UNIMPLEMENTED (feature-add).
- **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.
- **Agenda doc mismatches** — `AgendaEventManagerError._status` doc-vs-guard; description-cap (specs say 1000, validators enforce none).
- **Pinned-nav title staleness** on rename until re-pinned (likely a future file-watcher fix).
- **NOTE TO FUTURE** — relation properties are replaced by contexts, so future tasks/events lack a context-relation path; cross when reached.

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-not-yet-fixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home.

#### Document pointers

- Roadmap → `Framework.md` · ship log → `History.md` · PRD → `PommoraPRD.md` · branch quirks + hard rules → `CLAUDE.md`
- Native-table cleanup spec → `Planning/06-12-Table-Cleanup-Fixes.md` · Views spec-as-fact → `Features/Views.md`
- Per-entity specs → `Features/*.md`
