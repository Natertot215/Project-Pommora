### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-10 — v0.4.0 shipped to main)

**Then the Contexts Decoupling shipped on `main`** (994 tests green). The three context tiers became free-standing: Projects decoupled from Topics, Topics dropped `parents`, tier-1 **Space → Area**; all three are now folder + sidecar (`_area.json` / `_topic.json` / `_project.json`) with three sibling managers. The sidebar collapsed to one **Contexts** section (three `square.grid.2x2` disclosure rows + a "Contexts" header) and lost the dead search bar; index schema → v13. Executed subagent-driven, P1–P6 + a spec-voice doc rewrite. Record → `History.md` § "Contexts Decoupling"; decision → registry #18; spec/plan → `Planning/Superseded/`. Post-ship fixes: stale `tier-config.json` "Spaces" labels in Nathan's Nexuses corrected to "Areas" (quirk #17 — data, not code; reload to see it), the `FrontmatterInspector` "Tiers"→"Contexts" label, and `TopicManager` method names made bare to match its siblings.

**Session 2 (concurrent with Contexts Decoupling) — PagePreview rebuilt as a custom `NSPanel`** (supersedes the `WindowGroup` description above). A regular `NSPanel` owned by `PreviewTarget` is natively activating + never-main + key — the one combination no SwiftUI scene type expresses: refocus-from-outside works, it takes keyboard focus, and it never dims the main window. Content stays 100% SwiftUI via `NSHostingView` (same editor / inspector / save path). Commits `9befbfa` (panel) → `e6ae60d` (drop the migration's dead code: `openPagePreview(using:)` param + 5 orphaned `@Environment(\.openWindow)`, the write-only `PreviewTarget.ref`, the dead `dismissWindow(id: "page-preview")`). Also `9f303de` ViewSettings: one shared `LabeledMenuSelector` backs all five "label … value ▾" pickers, the Layout control became that dropdown (was a segmented pill), and the root rows reordered Group-before-Filter. Docs synced: `CLAUDE.md` + `Pages.md` / `PageTypes.md` / `NavDropdown.md`.

#### Lessons Learned

- **The test suite was eating the real `state.json`** (resetBookmark test in the shared container) — the recurring "lost Nexus bookmark" mystery. All app-state paths now divert to a temp dir under XCTest; never let the test host share live state.
- **`windowResizeBehavior(.disabled)` freezes ALL window resizing**, not just zoom — caught only by live AX resize probing, invisible to the suite.
- **Explicit fonts beat environment fonts** — components that hard-code `.font(...)` silently ignore a caller's compact scale; the deference pattern is `@Environment(\.font)` + `inherited ?? default`.
- **Screenshot-verified iteration works**: build → relaunch → `screencapture` → Read → pixel-measure → tune. Chat-pasted images never arrive; captures I take and Read render where Nathan can see them.
- **Only a custom `NSPanel` is "activating + never-main + key" at once** — SwiftUI scenes expose window role/style/resizability but never `canBecomeMain`/`canBecomeKey` (AppKit-only); `windowManagerRole(.associated)` governs Full Screen / Stage Manager, not main-window dimming. Host SwiftUI content in the panel via `NSHostingView` so every component stays reused.

#### Next Session (Nathan's standing direction)

**Context Decoupling + Page Preview Cleanup:** Simple UIX tweaking from both large commits; includes sidebar reconstruction + spacing work and potential page-settings UIX refreshes.

#### Pending Focuses

- Agenda compact-panel surface: hosting decided by the v0.6.0 Agenda UIX work (was undecided post-PreviewWindow-elimination; the PagePreview window pattern is the likely template).
- Launch-tail indexing contract (documented in `Architecture.md`): Finder-dropped pages arrive via CRUD or forced rebuild, not the launch scan.
- `LaunchTrace` breadcrumbs (DEBUG-only) live at the container's `tmp/launch-trace.log` — keep until a few clean weeks of launches, then consider removing.
- Settings full editing UI ships v0.7.0 (post-renumber).

#### Fix Log

- `PageValidator` status/file gap (banned `default:` arm) — exhaustive value-side switch; legacy Ideas/Notes vaults repaired, inert `_itemtype.json` removed.
- Compact routing from detail panes — `PageOpenRouter`, one shared open-path.
- Inspector toggle width drift — instant pane mount (transaction) + 840×540 default agreeing with the 630 width floor.
- `AppGlobals.mainWindow` prefix matching (exact `== "main"` never matched SwiftUI's identifiers).

Outstanding (restored — wiped by the PagesV2 refresh, not yet fixed):

- **Column reorder broken** — drag-reordering table columns; folds into upcoming view-system work.
- **"Modified" not hideable** in the visibility settings.
- **Inline-edit lag** — property value inline edit has a noticeable update buffer.
- **Column layout not persisted** across sessions (+ property columns don't show icons); folds into upcoiming view-system work.
- **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
- **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
- **Agenda description-cap doc mismatch** — specs claim a 1000-char cap but validators enforce none; decide the intended cap or drop the doc claim.
- **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.
- **New property values aren't selectable until an app restart** — adding a value to a property doesn't refresh its picker live; the new option only appears after a relaunch.
- **Pinned-nav title staleness** — changing a page's title doesn't update its title in the pinned section of the nav dropdown until re-pinned (recents update fine, being constantly refreshed). Likely needs a file-watcher (possibly overkill, or naturally resolved once a watcher lands). Non-issue for now.
- **Collection reorder limits** (investigated — not a bug): a vault with one collection + no root pages can't reorder it (inherent SwiftUI `.onMove` — needs ≥2 items in the `ForEach`); and a collection can't be dragged past root Pages (an intentional v0.3.0 no-interleave guard in `PageTypeRow.reorder`, line ~317). Enhancement to allow interleaving collections + pages: drop the cross-set guard + add a mixed `reorderDisclosureItems` path that splits the result back into collection-order + page-order.
- **KNOWN ISSUE; NOTE TO FUTURE** - with the change from relation properties to contexnts, future implementation of tasks + events won't have a way to relate to contexts; we'd cross this bridge when we get there.
