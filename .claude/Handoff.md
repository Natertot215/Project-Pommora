### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-10 — v0.4.0 shipped to main)

**v0.4.0 is merged: the PagesV2 collapse + the PagePreview real-window rebuild.** The V8 in-window glass card failed first contact (laggy drag, no table opens, a save-bricking validator gap) and was rebuilt the same day as a real `WindowGroup` window that can't act as its own app window, mounting the shared `FrontmatterInspector` at a compact scale. Live-verified end-to-end on The Nexus via an accessibility-driven interaction matrix; 987 tests green. Full record → `History.md` § "v0.4.0"; plan → `Planning/Superseded/PagePreviewWindow.md`. The roadmap renumbered +1 (Views now v0.5.0 … Contexts+Homepage v0.8.0).

#### Lessons Learned

- **The test suite was eating the real `state.json`** (resetBookmark test in the shared container) — the recurring "lost Nexus bookmark" mystery. All app-state paths now divert to a temp dir under XCTest; never let the test host share live state.
- **`windowResizeBehavior(.disabled)` freezes ALL window resizing**, not just zoom — caught only by live AX resize probing, invisible to the suite.
- **Explicit fonts beat environment fonts** — components that hard-code `.font(...)` silently ignore a caller's compact scale; the deference pattern is `@Environment(\.font)` + `inherited ?? default`.
- **Screenshot-verified iteration works**: build → relaunch → `screencapture` → Read → pixel-measure → tune. Chat-pasted images never arrive; captures I take and Read render where Nathan can see them.

#### Next Session (Nathan's standing direction)

**Execute the Contexts Decoupling plan** — the parallel session's ratified work, now unblocked (its gate required this branch landing + clean status, both satisfied):
1. `Planning/06-10-Contexts-Decoupling-Spec.md` — the ratified spec (Projects free-standing tier-3, context relations reset, sidebar tier disclosure rows, Space→Area rename).
2. `Planning/06-10-Contexts-Decoupling-Plan.md` — the adversarially-verified P1–P6 plan. Re-verify its SidebarView line anchors against the landed v0.4.0 file before P1/P3 (the plan says so itself).

Manual one-click checks still owed on v0.4.0 (deferred from the interaction matrix): Mission Control + Cmd-` absence of the preview window; dedupe re-click focus feel; inspector-toggle widen animation feel.

#### Pending Focuses

- Agenda compact-panel surface: hosting decided by the v0.6.0 Agenda UIX work (was undecided post-PreviewWindow-elimination; the PagePreview window pattern is the likely template).
- Launch-tail indexing contract (documented in `Architecture.md`): Finder-dropped pages arrive via CRUD or forced rebuild, not the launch scan.
- `LaunchTrace` breadcrumbs (DEBUG-only) live at the container's `tmp/launch-trace.log` — keep until a few clean weeks of launches, then consider removing.
- Settings full editing UI ships v0.7.0 (post-renumber).

#### Fix Log

- `PageValidator` status/file gap (banned `default:` arm) — exhaustive value-side switch; legacy Ideas/Notes vaults repaired, inert `_itemtype.json` removed.
- Compact routing from detail panes — `PageOpenRouter`, one shared open-path.
- Launch dead-ends: panel abort retry + activation wait; `dismissWindow` deferred out of the first view update.
- Inspector toggle width drift — instant pane mount (transaction) + 840×540 default agreeing with the 630 width floor.
- `AppGlobals.mainWindow` prefix matching (exact `== "main"` never matched SwiftUI's identifiers).
