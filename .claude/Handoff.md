### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md`.

 - **Two builds — this is the Swift handoff.** Project Pommora ships the same app two ways: **Swift** (this doc) and the **React + Electron** rebuild (`React/.claude/Handoff.md`). Working in React? Read that handoff instead. Everything below is the **Swift** build's current state and remains accurate. *(Latest React work: **PommoraDND**, an in-house drag-and-drop engine replacing dnd-kit, Phases 0–2 in the Interaction Lab — see `React/.claude/Features/DragAndDrop.md`.)*

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary

**Grouping is almost done — interface + view-side rendering — merged to `main`.** The interface shipped first (extended `PropertyGrouping` schema — order modes + date bucketing + empty-group placement + checkbox-nil; the `GroupResolver` work; the redesigned Grouping pane: toggle → inline property picker → Order / Date-By / Options + a secondary empty-group footer), through a full UIX-review pass. Then the **view-side rendering** landed on the same branch and was reviewed (correctness + DRY) before merge: a custom **animated disclosure chevron** matched to the native `DisclosureGroup` chevron (table group rows + the Group-By picker, shared `DisclosureChevron`); group headers render their **variant pill** for Select/Status and **property-icon + medium title** for Date/Checkbox; and **Status grouping** transiently moves its column first as the disclosure column (pinned, force-shown) with the header pill overflowing the narrow column. Plus table polish — group-row indent reclaim, Title column frozen on disclosure (`autoresizesOutlineColumn` off). **
Remaining for grouping:** only the group-header **manual-drag reorder** (Plan Phase 3) and the **drag-between-groups schema-rewrite bug** (see Fix Log). Earlier on `main`: the inline-edit commit lag, stale-property-options reload, and inspector picker-debounce fixes. The broader toolbar/Views context below still stands.

Two threads of work are live: **(1) the Views + toolbar UIX** (SwiftUI — the focus of this session) and **(2) the React + TypeScript rebuild** (the exploratory contingency — `Planning/06-14-React-Rebuild-Roadmap.md`, backed by a Pommora-React Figma library and a partial app scaffold).

On the Views/toolbar thread, the toolbar/banner docs were first truthed-up to reflect that the toolbar, Views button, and banner are **actively-changing, not settled**. The Views button only *"looks"* good — at unknown cost, via methods we're not sure are best or even correct; the inspector folds the Views pill in when toggled (a deviation from Apple-native), the blast radius of the Views-button chrome choices on the rest of the toolbar is unmapped, and whether the banner's edge-to-edge bleed interacts with the toolbar is untested. Reframed `Features/Views.md`, `Planning/06-13-Views-UIX-Fixes.md`, and `Guidelines/Design.md` "Chrome animation"; committed as `283865b`.

The toolbar-wide **"Icon Only / Icon and Text" right-click menu was then found and suppressed.** A live `NSToolbar` introspection probe confirmed it is the **native macOS toolbar display-mode menu** — a stock `NSToolbar` with `allowsDisplayModeCustomization == true` — not app code (an exhaustive grep found zero; Mail and Finder show the same menu with extra items). It was never ours; it surfaced more once the toolbar moved off the default-closed inspector. Suppressed via `WindowToolbarConfigurator`, which sets `allowsDisplayModeCustomization = false` once the toolbar exists and re-asserts on toolbar rebuilds (navigation adds/removes the conditional Views pill, rebuilding the `NSToolbar` and resetting the property). **Confirmed working in production** and committed (`eecdf9f`) — `WindowToolbarConfigurator.swift` + the one-line `ContentView` wiring.

With the native menu gone, the open thread is **button-specific menus in the toolbar.** Right now the banner's "Change Banner / Remove Banner" `.contextMenu` fires when right-clicking toolbar buttons — the banner's `backgroundExtensionEffect()` bleeds it (with its menu) under the toolbar, and the buttons consume only left-clicks, so right-clicks fall through. We're exploring a workaround using the codebase's frame-bound `SecondaryClickMenu` / `onSecondaryClick` overlays (`DesignSystem/SecondaryClickCatcher.swift`): swallow right-clicks on the toolbar buttons so the banner menu fires only on the banner, and use the same overlays to give specific buttons (e.g. the Views button) their own menus. To be wired + validated next session.

**Where it left off.** `main` is clean — the menu fix (`eecdf9f`), the factual doc rewrite, and the Planning-docs reorganization (shipped `Superseded/` plans removed, `06-12-Views-V2-Plan.md` reclassified to `Reference/`) are all committed. The current detail table in the app is `ViewOutlineTable` (`Detail/Table/`).

#### Lessons Learned

- **The toolbar-wide "Icon / Text" menu is the native `NSToolbar` display-mode menu, not app code.** Suppress with `allowsDisplayModeCustomization = false`, applied *after* the toolbar exists and re-asserted on rebuilds (SwiftUI resets it). The earlier "leaked context menu" theory was a conflation that cost days. **→ candidate CLAUDE.md quirk.**
- **A live introspection probe beats grep-and-guess for "is this our code or the OS?"** Reading the actual `NSToolbar`'s properties into a verdict file settled in minutes what guessing couldn't — exactly the LOOK-don't-guess the cornerstone demands.
- **The banner menu reaches toolbar buttons** because `backgroundExtensionEffect()` bleeds the banner (carrying its `.contextMenu`) under the toolbar while the buttons consume only left-clicks. Frame-bound AppKit overlays (`SecondaryClickMenu` / `onSecondaryClick`) are the codebase's tool for scoping a right-click to one view.
- **Trust `xcodebuild`, not SourceKit** (reaffirmed): the "Cannot find `NexusManager` / `SidebarSelection`" same-module squiggles during the toolbar edits were all false; builds were green (1,214 tests).

#### Next Session — ViewsV2 continuation

1. Mark the toolbar menu **RESOLVED** in `06-13-Views-UIX-Fixes.md` (the fix shipped as `eecdf9f`).
2. **Button-specific toolbar menus:** confine the banner menu to the banner — swallow right-clicks on the toolbar buttons (Views pill, trio, back-forward) via the frame-bound overlays — and establish the per-button menu pattern (Views button as the example; its menu *content* is the deferred display-toggle feature). Validate live.
3. Continue the `06-13` Views/toolbar UIX sequence — the in-flux toolbar/banner items, then Gallery, grouping/sorting, the Layout-pane rework.

The React thread continues in parallel as the contingency exploration.

#### Pending Focuses

- **Toolbar / Views-button / banner chrome is actively-changing** (flux docs: `Features/Views.md`, `Planning/06-13-Views-UIX-Fixes.md`, `Guidelines/Design.md`): the Views button "looks" good at unknown cost via unknown-if-best methods; the inspector-adoption deviation; the untested banner↔toolbar bleed interaction.
- **Button-specific toolbar menus + banner-menu confinement** — the next-session task above.
- **Rest of the Views build (per `06-13-Views-UIX-Fixes.md`):** build out **Gallery** properly; **grouping is done** (interface + view-side rendering merged to `main`; remaining is only the group-header manual-drag reorder + the drag-between-groups bug, both tracked — Plan Phase 3 + Fix Log); **sorting UIX** still to do; **Fix 3 — Layout-pane revision + type dual-write**; **Fix 1b — Edit Icon → IconPicker popover** (needs Nathan's pick on which rows).
- **Views-button display toggle — DEFERRED** ("Display as Icon Only / Icon + Title"); this is the intended content for the future Views-button right-click menu, blocked until the per-button menu pattern is settled.
- **Title baseline-on-icon (Fix 2 polish)** — the detail title text should baseline on the icon's bottom edge; a plain `Label` centers them. Not yet applied.

#### Fix Log

- **Drag-between-groups schema rewrite "refuses to land"** (table, property/Status grouping) — dragging a row into a *different* property bucket should rewrite that property (e.g. change a page's Status), but the drop is rejected. **Diagnosed, not yet fixed** (`grouping-redesign` branch): the rewrite path is fully wired + persists (`RowDragCoordinator.rewriteProperty` → `ViewSurface.rewriteDraggedProperty` → `updatePageProperty`) — NOT un-wired. The failure is upstream in `ViewOutlineTable.Coordinator.dropTarget`: an `NSOutlineView` root-level drop (`proposedItem == nil`, which is what it proposes when dragging toward the top-level bucket headers) is only resolvable via the structural `.ungrouped` band — which **doesn't exist under property grouping** (the empty bucket is a `.propertyBucket(value: nil)`, not `.ungrouped`) — so it returns nil → `validateDrop` returns `[]` → rejected. Likely fix: retarget the drop onto the bucket under the cursor via `setDropItem(group, dropChildIndex: NSOutlineViewDropOnItemIndex)` before validating (and/or map a property-grouped root drop to the hovered bucket). **Confirm-symptom first:** does it land when dropping squarely *on an existing row* inside the target group, and fail only in the gaps / on the header / empty area? That observation locks the root cause before the fix.
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
- Auto-loaded rules → `// rules//` (`MarkdownPM.md` scoped to the editor); `Review-Discipline.md` moved up to the Studio-level `// The Studio //.claude//rules//` — applies across all projects · Views spec-as-fact (toolbar/banner sections in flux) → `Features/Views.md` · per-entity specs → `Features/*.md`
