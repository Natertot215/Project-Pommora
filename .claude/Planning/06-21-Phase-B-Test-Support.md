## Phase B — Test-Support Consolidation

Consolidate the duplicated test-fixture boilerplate, collapse the parallel manager suites, and seed the high-value stress coverage — so phases C–H (all test-gated) are cheaper and safer to verify. Branch: `refactoring-phase-b` off `main`.

### Grounding correction (vs roadmap)

The roadmap said "new target (`PommoraTestSupport`)." Re-grounded against the code: there is a **single** unit-test consumer (`PommoraTests`), and a `PommoraTests/Support/` folder **already exists** (`TempNexus` — 467 call sites — and `FixtureFiles`). A separate Xcode target only pays off when multiple targets import the support code; with one consumer it is pure pbxproj overhead.

**Decision: grow `PommoraTests/Support/`, no new target.** New files auto-include (quirk #2).

### Scope (landed by grounding)

- `TempNexus.make()` — already extracted (467 sites); leave as-is.
- Duplicated inline factories to consolidate: `makePageType` / `makePageCollection` / `makePageSet`, `makePageMeta`, `makeAgendaTask` / `makeAgendaEvent`, `makeIndex(at:)`, and the `PageFrontmatter` + `AtomicYAMLMarkdown.write` page-write boilerplate.
- 3 parallel manager suites (Area / Topic / Project) — ~70% identical create/createDuplicate/rename/delete/loadExisting shapes; **keep** Project's divergent `updateIcon` / `loadAllReadsFixture`.
- `PropertyValue` decode (`Vaults/PropertyValue.swift`) — 10-step probe; the real untested edge is an object carrying **both** FileRef keys and `$rel` (relation-vs-file ambiguity), plus string date/url/select ordering determinism and empty-array handling.
- Stress gaps: Unicode / very-long / control-char titles; malformed-YAML frontmatter; concurrent writes on the shared `dbQueue`.

### Tasks (each a green commit)

**B1 — Entity fixture builders.** New `Support/Fixtures.swift` (split if it grows): `makePageType/Collection/Set`, `makePageMeta`, `writePage(...)`, `makeIndex(at:)`, `makeAgendaTask/Event` — sensible defaults, params only for fields tests vary. Additive; no consumer edits. Build green.

**B2 — Migrate consumers.** Delete the inline `private func make…` copies in the Index / Agenda / Content suites; call the shared builders. Incremental (file-group at a time), build green per group. Net −test-loc; the existing suite is the regression net.

**B3 — Collapse manager suites.** A closure-driven shared helper (create / rename / delete + validator-error type) covering the identical Area/Topic/Project shapes; keep Project's divergent tests separate. **Simplicity gate:** only collapse if the helper stays simpler than the 3 copies — else share fixtures only and stop.

**B4 — Seed stress coverage.** `PropertyValue` FileRef+`$rel` ambiguous object, date-vs-url-vs-select string ordering, empty-array cases; Unicode / long / control-char titles; malformed-YAML frontmatter (lenient-loader behaviour); N concurrent `IndexUpdater` upserts on the shared `dbQueue`.

### Verification

Background builder, `-only-testing:PommoraTests`, verify a non-zero executed count (quirk #1). B1–B3 are pure refactors (green = behaviour-preserved); B4 is new behaviour-coverage (TDD: assert the decode/boundary contract). Stage explicit files per task — never `-A` (entanglement lesson; the parallel React session shares the tree).
