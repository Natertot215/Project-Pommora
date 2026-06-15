## Planning — Index

Active plan documents live at the top level; `Reference/` holds **non-implemented** approaches kept for their research value; `Superseded/` archives plans whose work has shipped or whose direction was abandoned. Per Studio convention, a completed plan is logged in `History.md` and then either moved to `Superseded/` or removed (git history preserves removed plans); never leave a stale plan presenting as active.

Plans are named `MM-DD-<slug>.md` (earlier files retain their `YYYY-MM-DD-` names). They scope a single feature or refactor into phases and steps (never dates) — `Framework.md` carries the long-term roadmap; planning isolates one body of work.

#### Active

- `06-13-Views-UIX-Fixes.md` — the sequenced Views/toolbar UIX fixes. **The toolbar, Views button, and banner chrome are actively changing** — the doc's flux note is load-bearing; nothing in those sections is settled truth. Covers the toolbar cluster, banner + titles, the banner-menu confinement + per-button menus (next), Gallery, grouping/sorting, and the Layout-pane rework.
- `06-14-React-Rebuild-Roadmap.md` — **exploratory** program-level roadmap for a post-v1 React + TypeScript + Electron rebuild (behavior-identical to the PRD). Phase-sequenced; each phase becomes its own task-plan when greenlit. Backed by two research workflows. A scoped option, not committed work.

#### Reference

- `Reference/06-12-Views-V2-Plan.md` — a **non-implemented** approach: the detailed NSOutlineView-table rebuild plan written during the v0.5.0 Views push, when the SwiftUI custom table failed render review and NSOutlineView looked like the only viable path. It was **never executed as written** — the working detail table (`ViewOutlineTable`, in the app today) instead came out of a short throwaway session that succeeded, and we've built on that since. Kept for its pipeline/port analysis, cross-group-drag design, and task breakdown if the table is ever revisited.

#### Superseded

- `Superseded/06-11-Views-Spec.md` — the v0.5.0 Views cluster spec (SavedView v2, the pure view pipeline, Table + Gallery, Views dropdown, covers/banners). **COMPLETE at v0.5.0**; spec-as-fact → `Features/Views.md`.
- Other shipped/abandoned plans (Sets, PagesV2, Contexts-Decoupling, PagePreviewWindow, ItemsV2, and earlier sweeps) were removed from the tree — git history preserves them; their ship records live in `History.md`.

`Contextv2.md` (the Drop-Relations→Contexts refactor, shipped 2026-06-04, registry #16) still sits at the top level pending archival review.
