### Planning

Active plan documents live here. Completed plans are logged in `History.md` and moved into `Superseded/`.

#### Active

- **`v0.3.0-Properties-spec.md`** — conceptual spec for v0.3.0 (locked behavior; no implementation detail)
- **`v0.3.0-Properties-plan.md`** — implementation plan re-derived against post-ParadigmV2 code (5 phases A–E)
- **`v0.2.8-Drag-Reorder.md`** — sidebar + detail-pane drag-reorder; Phase 1 persistence shipped (`5a264f0`), Phase 2 UX shipped (`9cd8cd1`); Items-side rows + NavDropdown reorder + Phase 4 detail-pane Table reorder still queued

> **Retired 2026-05-23 — `Page-Editor-Plan.md`**: shipped content (Blockquote v0.2.7.5, HR, Lists) folded into `// Features//PageEditor.md` + `// Guidelines//Markdown.md`; deferred Tables spec (column-alignment open question, Stages 3.A–3.D, risk inventory) moved into `// Features//PageEditor.md → Tables — to be implemented`.

#### Superseded

Archived plans for completed/replaced work; preserved for archaeological reference. Items currently archived:

- `ParadigmV2.md` — locked spec for the 2026-05-22/23 paradigm refactor; shipped at tag `paradigmV2` (`36d48c8`)
- `v0.3.0-Flat-Layout-Plan.md` — flat on-disk layout refactor (drops `Pages/`/`Items/`/`Agenda/` wrappers; six per-kind sidecars); shipped at tag `flatlayout` (`049df19`), followed by a 5-commit post-ship hardening cluster
- `v0.3.0-Properties-implementation.md` — pre-ParadigmV2 implementation draft; replaced by `v0.3.0-Properties-plan.md`
- `v0.3.0-Properties-uncertainty-log.md` — uncertainty log from the same pre-ParadigmV2 pass
