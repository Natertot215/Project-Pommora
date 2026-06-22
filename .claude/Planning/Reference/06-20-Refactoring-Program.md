## Refactoring Program (A–H) — Retrospective

The Swift codebase-health program (`refactoring` / `refactoring-phase-b`, 2026-06-20→21), consolidated to `main`. Behavior-neutral throughout — the test suite (1,272 → 1,294) was the neutrality gate at every green commit. The driving roadmap (`06-20-Refactoring-Roadmap.md`) was retired on completion; the changelog record lives in `History.md`. Net ≈ −600 Swift lines across 38 files, behavior unchanged.

#### What shipped, by phase

- **A — Decisions + cleanup.** Ratified the unsettled on-disk shapes (adopted-Page id, `opt_<ULID>` minting, `context_links` ULID, one `schemaVersion` source, `loadAll` heal-on-read kept); removed Area color (Areas icon-only).
- **B — Test support.** Shared `Fixtures` into `PommoraTests/Support/`; the parallel Context-manager suites collapsed behind a test-only protocol.
- **C — Reorg + primitives.** The `Core` / `Components` / `Domain` / `Features` grouping; `Core` absorbed the one-file utility folders; ULID alphabet + formatters single-sourced; `FilterBuilder` split from `IndexQuery`.
- **D — Row primitive.** One `SidebarRow` behind all seven sidebar rows. The drag-ghost `labelColor` patch is intentionally retained.
- **E — DRY non-divergent families.** SavedView scope→id + `currentView` hoisted; `collisionSafeName` shared by the asset importers; Page-CRUD triplication routed through one scope-parameterized path.
- **G — God-files.** `ViewSurface` split into Cover/Rename/Delete extensions; duplicated View-Settings rows hoisted to `Components` (`SelectableOptionRow` / `LabeledToggleRow`).
- **H — Modernization.** Concurrency / typed-throws idioms brought current; a `withPendingError` helper DRY'd the manager error-handling.

#### Grounding overrode the roadmap

- **F (manual → synthesized `Codable`) dropped** — synthesized `Decodable` throws on a missing in-CodingKeys key instead of using the property default, so the pervasive defensive `decodeIfPresent ?? default` can't be synthesized.
- **`NexusAdopter` + `PageTypeManager` kept unified** (not split) — splitting `PageTypeManager` would regress `private(set)` encapsulation on its observable state; both were internally cleaned instead.

The recurring lesson: a roadmap line is a hypothesis until grounded against code — F's premise, the manager splits, and several E/H items all changed on contact with the real code.
