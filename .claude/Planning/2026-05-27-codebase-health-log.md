### Codebase Health Log — Beyond-Scope Cleanup Backlog

> Structural / bloat / maintenance concerns surfaced while doing focused work. NOT bugs — these are health items for dedicated future sweeps. Each entry: location, concern, severity, suggested direction. Tackle opportunistically; don't bundle into unrelated feature commits.

#### Surfaced during Folders removal (2026-05-27)

- **`Sidebar/SidebarSelection.swift` — entity-routing triplication (MEDIUM — PARTIALLY RESOLVED `f088287`).** `SelectionTag.matches(_:)` no longer carries its own pairwise switch — it now derives via `SelectionTag(selection)` + `==`, so `init?(_:)` is the single source of truth for selection→tag. **Still open:** `init?(tag:lookup:)` and `init?(stateRef:lookup:)` remain parallel case-per-entity switches (they do live manager resolution, harder to unify). A protocol-based `SelectableEntity` routing layer would collapse those two as well — revisit before the next selectable entity type lands.

- **Pre-existing compiler warnings — ✅ RESOLVED `f088287`.** All five zeroed; verified by a fresh-compile build (0 errors, no new warnings):
  - `Content/PageContentManager+CRUD.swift` `try?`-unused → extracted a shared `trashAttachments(for:)` helper (do/catch).
  - `handleDrop` result-unused across the 4 detail views → `@discardableResult`.
  - `Detail/DetailRowDragPayload.swift` `nonisolated(unsafe)` → `nonisolated` (NOT removed — the annotation is load-bearing under default-MainActor isolation; only the redundant `unsafe` was dropped).
  - `PommoraTests/Content/MovePageTests.swift` `var fm` → `let`.
  - `PommoraTests/Properties/FileAttachmentEditorTests.swift` discarded `MainActor.run` → `_ =`.

- **Row-file doc duplication (LOW — open).** The "only the first sibling ForEach's `.onMove` is honoured inside a DisclosureGroup" SwiftUI-bug explanation is copy-pasted in `PageTypeRow.swift` (and recurs whenever the unified-item pattern is used). If it recurs again, centralize the rationale in one place and reference it.

- **`Content/PageContentManager.resolveParent` (LOW — open).** Returns a bare tuple `(vault:collection:)` and is a brute-force O(N·M) walk (acknowledged in-code; SQLite lookup slated for v0.4.0). Fine for now; revisit when the index-backed lookup lands — and consider a named result type over the tuple.

- **CRUD mirror weight (NOTE, not a defect).** `PageContentManager+CRUD.swift` mirrors create/rename/delete/update across container scopes (Collection + Type-root). Intentional symmetry, but it's the structure that made the 3-tier folder add expensive. If a 3rd+ page-container scope is ever reconsidered, evaluate a single scope-parameterized CRUD path instead of per-scope overloads.

- **macOS XCTest host connection hang (ENVIRONMENTAL — watch).** During the `f088287` verification the test runner repeatedly hung at the XCTest connection handshake (~332s timeout × 4) despite the app + test bundle building/linking/signing cleanly. Not code-attributable (same suites ran green earlier the same session). If it recurs: quit any running `Pommora.app`, `pkill -9 -f Pommora`, then re-run; or run once from the Xcode GUI to clear the test-host connection state.

#### (future entries appended here by later sweeps)
