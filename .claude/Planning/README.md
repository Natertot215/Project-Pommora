### Planning

Active plan documents live here. Completed plans move to `Superseded/` (preserved for posterity); a brief mention of the ship lands in `History.md`.

#### Active

- **`View-Settings-button-chrome-plan.md`** — Chrome-only first slice of the v0.3.1.x Storage View Redesign. Tasks 1-4 (button + popover shell + scope wiring + ContentView insertion) shipped this session; **Task 5 (visual-approval smoke on all 9 surfaces) is the remaining open item** before the plan retires to Superseded. Architectural principle locked here: static button position at ContentView level + adaptive popover content via `ViewSettingsScope` derived reactively from `sidebarSelection` — the pattern every follow-up panes patch builds on.
- **`View-Settings-research-notes.md`** — Research findings (Notion UX patterns + SwiftUI primitives) for the v0.3.1.x panes work (Layout / Property Visibility / Sort / Filter / Group / Edit Properties). Fed into the chrome plan already; feeds the next plan (panes) when it's drafted. Notion menu structure, SwiftUI component choices, delivery slices, open questions — all locked decisions captured here.

#### Superseded (shipped or no-longer-applicable)

- **`Superseded/2026-05-25-Items-Detail-Views-plan-COMPLETE.md`** — 11-task plan for the storage detail-view buildout (replace stubs + drag-reorder). Tasks 1-11 all shipped via parallel executor agents 2026-05-25 (commits `adcb66c` → `55bf8c3`). Plan documented for reference; will not be revisited.

#### Next plan likely to draft

**v0.3.1.x panes** — the second slice of the Storage View Redesign series, on top of the chrome slice. Scope: Layout pane (Table active, others muted) + Property Visibility pane (strikethrough toggle) wired to `ViewConfig`-backed `views[]` storage on `PageCollection` + `ItemCollection`. After that, drip Sort → Filter → Group → Edit Properties per the locked Approach B in research notes. Open with `superpowers:writing-plans` to draft; `superpowers:subagent-driven-development` to execute.
