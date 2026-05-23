### Planning

Active plan documents live here. Completed plans are logged in `History.md` and moved into `Superseded/`.

#### Active

- **`v0.3.0-Flat-Layout-Plan.md`** — flat on-disk layout refactor: drops `Pages/`/`Items/`/`Agenda/` wrappers; six per-kind sidecars (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`); tagged `flatlayout` between `paradigmV2` and v0.3.0. Moves to `Superseded/` after Phase 6 ships.
- **`v0.3.0-Properties-spec.md`** — conceptual spec for v0.3.0 (locked behavior; no implementation detail)
- **`v0.3.0-Properties-plan.md`** — implementation plan re-derived against post-ParadigmV2 code (5 phases A–E)
- **`v0.2.8-Drag-Reorder.md`** — sidebar + detail-pane drag-reorder; Phase 1 persistence shipped, Phases 2–5 ahead
- **`Page-Editor-Plan.md`** — Page editor work: Blockquote shipped v0.2.7.5; Tables paused (preserved as reference)

#### Superseded

Archived plans for completed/replaced work; preserved for archaeological reference. Items currently archived:

- `ParadigmV2.md` — locked spec for the 2026-05-22/23 paradigm refactor; shipped at tag `paradigmV2` (`36d48c8`)
- `v0.3.0-Properties-implementation.md` — pre-ParadigmV2 implementation draft; replaced by `v0.3.0-Properties-plan.md`
- `v0.3.0-Properties-uncertainty-log.md` — uncertainty log from the same pre-ParadigmV2 pass
