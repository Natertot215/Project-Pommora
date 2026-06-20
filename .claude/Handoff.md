### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md`.

 - **Two builds — this is the Swift handoff.** Project Pommora ships the same app two ways: **Swift** (this doc) and the **React + Electron** rebuild (`React/.claude/Handoff.md`). Working in React? Read that handoff instead. *(The React rebuild is actively in flux — a live session works it in the `pommora-main-preview` worktree; its uncommitted work there is its own, don't bundle it into Swift commits.)*

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary

**6-19 (Swift) — mostly UIX enhancements + some sidebar refactoring; the prior focuses remain.** Two things settled, both on `main` (local, not pushed):

1. **Sidebar re-done + enhanced.** The Homepage/Calendar/Recents saved-leaves give way to a **Nexus header banner** — per-Nexus avatar · folder-name title · custom-or-today's-date subtitle — as the first **scrolling** row of the sidebar List (own Section, native selection + `.listRowBackground` chrome). **Calendar + Recents leaves were knowingly removed** (managers stay; only the surfacing went — "until we figure out what to do with them"). Editing is right-click-scoped per element: avatar → picture, title → **Rename** (renames the nexus folder via `NexusManager.renameRoot`, which requests a one-time parent-folder grant at nexus load), subtitle → Edit Subtitle. On-disk: `profile_image` + `profile_subtitle` in `settings.json`; avatar bytes in `.nexus/assets/<nexusID>/`. In-app "coming vX" copy blanked. Then a **sidebar DRY pass** (Opus subagents, build- + diff-verified): `InlineRenameState` across the 7 rows, `SidebarConfirmation` dialog props + shared cancel button, `IconPickerSheet`/banner helpers — net −12 lines. Decision + on-disk shape → `History.md`; behavior → `Features/Sidebar.md`.

2. **Toolbar — parked: "if it ain't broken, don't fix it."** We acknowledged the toolbar / Views-button / banner chrome is finicky and has been a multi-week time sink for marginal gain; an early-session attempt to re-group it natively was **reverted**. The native `NSToolbar` display-mode menu is already suppressed (`WindowToolbarConfigurator`, `eecdf9f`). The button-specific-menu idea is **dropped, not deferred** — no further toolbar churn without a concrete, high-value reason.

**6-19 (React) — image banners, live container views, + a Swift-aligned `src` reorg** (live + uncommitted in the `pommora-main-preview` worktree on `main`):

1. **Banner** — one shared image banner *behind the glass* for Vault / Collection / Context / Homepage: native picker → copied to `.nexus/assets/<id>/banner-<token>.<ext>` (a fresh filename per write sidesteps the browser-image-cache stale-image trap) → served over a registered `nexus-asset://` protocol; native macOS Change/Remove menu; one `setBanner` mutate op for every owner kind.
2. **Homepage + Collections are now selectable entities with their own views** — the sidebar nexus header *is* the homepage; collections are clickable and share Vault's view via `ContainerView` (vault + collection = the same view principles, `source.kind` the divergence seam).
3. **Renderer reorg → mirrors Swift** — flat `components/` + `views/` → `Detail/` (`DetailPane` router · `DetailScaffold`≈ViewSurface · `Scope`≈DetailScope · `ContainerView`/`HomepageView`/`ContextView`/`PageView`) + `Detail/Table/` + `Detail/Banner/` + `Sidebar/` + `Components/`; the `styles.css` monolith split into co-located stylesheets. Green: 331 tests. Full state → `React/.claude/Handoff.md`.

#### Lessons Learned

- **Toolbar finickiness → leave it.** The toolbar/banner chrome cost weeks for little; "if it ain't broken, don't fix it" is the standing call. Don't reopen it casually.
- **Sidebar list-row alignment = reclaim the chevron gutter.** A non-disclosure row (the header banner) sits at SwiftUI's reserved chevron indent; a **negative `.listRowInsets` leading** pulls it back — the SwiftUI-List analog of the detail table's `ChevronlessOutlineView.frameOfCell` shift. Tuned to `-8`.
- **Verify subagent claims against the code.** The DRY-analysis agents produced false positives (a "missing guard" that was present; a `.area.singular` property that doesn't exist) — caught by reading the real code before acting. The cornerstone, applied to delegated work.
- **Trust `xcodebuild`, not SourceKit** (reaffirmed): same-module "Cannot find type X" / "No such module 'Nuke'" squiggles are false; builds were green (1269 tests).

#### Next Session

- **Live-test the nexus rename** — right-click the header title → Rename → the one-time parent-folder grant prompt → folder renames + title updates. Build-verified, not yet behavior-verified.
- **Continue the Views build** (the focuses remain, per `06-13-Views-UIX-Fixes.md`): **Gallery** build-out, **sorting** UIX, **Fix 3 — Layout-pane revision + type dual-write**, **Fix 1b — Edit Icon → IconPicker popover** (needs Nathan's row pick).
- **Sidebar DRY round 2** (deferred, low-priority): `TierDisclosureRow` reuse `SelectableRow`, a shared two-zone `reorder()` helper, `UserSectionHeader` reuse the rename field, a `SidebarToast` manager-protocol.

#### Pending Focuses

- **Rest of the Views build** (per `06-13-Views-UIX-Fixes.md`): Gallery, sorting UIX, Layout-pane rework, Edit-Icon popover. **Grouping is done** (merged; remaining = group-header manual-drag reorder + the drag-between-groups bug, both in Fix Log).
- **Swift improvements from the React data-layer slice — reserve a dedicated session.** `Planning/Reference/Swift-Improvements-from-React-Rebuild.md` distills what completely slicing the data layer apart to fuel the React rebuild taught us about the Swift side — concrete, valuable improvements. Set aside a session to review it and apply them.
- **Nexus rename — needs a live end-to-end pass** (the parent-grant prompt + actual folder rename).
- **Toolbar — intentionally parked** (see Session Summary). Not a focus.
- **`main` is local-only** — the session's Swift work is committed but not pushed to `origin`.

#### Fix Log

- **Drag-between-groups schema rewrite "refuses to land"** (table, property/Status grouping) — dragging a row into a *different* property bucket should rewrite that property, but the drop is rejected. **Diagnosed, not yet fixed**: the rewrite path is wired + persists (`RowDragCoordinator.rewriteProperty` → `ViewSurface.rewriteDraggedProperty` → `updatePageProperty`). The failure is upstream in `ViewOutlineTable.Coordinator.dropTarget`: a root-level drop (`proposedItem == nil`) is only resolvable via the structural `.ungrouped` band, which doesn't exist under property grouping (the empty bucket is `.propertyBucket(value: nil)`) → returns nil → `validateDrop` → `[]` → rejected. Likely fix: retarget the drop onto the hovered bucket via `setDropItem(group, dropChildIndex: NSOutlineViewDropOnItemIndex)` before validating. **Confirm-symptom first:** does it land when dropping squarely on an existing row inside the target group, failing only in gaps / on the header?
- **Backspace on checkbox / list item** should auto-delete the syntax — UNIMPLEMENTED (feature-add).
- **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.
- **Agenda doc mismatches** — `AgendaEventManagerError._status` doc-vs-guard; description-cap (specs say 1000, validators enforce none).
- **Pinned-nav title staleness** on rename until re-pinned.
- **NOTE TO FUTURE** — relation properties are replaced by contexts, so future tasks/events lack a context-relation path; cross when reached.

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-not-yet-fixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home.

#### Document pointers

- Roadmap → `Framework.md` · ship log → `History.md` · PRD → `PommoraPRD.md` · branch quirks + hard rules → `CLAUDE.md`
- Auto-loaded rules → `// rules//` (`MarkdownPM.md` scoped to the editor); `Review-Discipline.md` at the Studio-level `// The Studio //.claude//rules//` · sidebar spec → `Features/Sidebar.md` · Views spec (toolbar/banner now parked) → `Features/Views.md` · per-entity specs → `Features/*.md`
