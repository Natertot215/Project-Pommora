## Planning — Index

Active plan documents live at the top level; `Reference/` holds **non-implemented** approaches kept for their research value; `Superseded/` archives plans whose work has shipped or whose direction was abandoned. Per Studio convention, a completed plan is logged in `History.md` and then removed (git history preserves removed plans); never leave a stale plan presenting as active.

Plans are named `MM-DD-<slug>.md`. They scope a single feature or refactor into phases and steps (never dates) — `Framework.md` carries the long-term roadmap; planning isolates one body of work.

#### Active

- `06-13-Views-UIX-Fixes.md` — the sequenced Views / toolbar UIX fixes. The toolbar, Views button, and banner chrome are actively in flux — the doc's flux note is load-bearing; nothing there is settled truth. Covers the toolbar cluster, banner + titles, Gallery, grouping/sorting, and the Layout-pane rework.

#### Reference

- `Reference/06-11-Views-Spec.md` — the v0.5.0 Views cluster design spec; Views shipped (spec-as-fact → `// Features//Views.md`). Kept for research value.
- `Reference/06-12-Views-V2-Plan.md` — a non-implemented NSOutlineView-table rebuild plan, never executed as written (the shipped `ViewOutlineTable` came from a separate throwaway session). Kept as a researched alternative.

#### Superseded

- (empty) — shipped or abandoned plans are removed from the tree; git history preserves them, and their ship records live in `History.md`.
