### Codebase Health Log — Beyond-Scope Cleanup Backlog

> Structural / bloat / maintenance concerns surfaced while doing focused work. NOT bugs — these are health items for dedicated future sweeps. Each entry: location, concern, severity, suggested direction. Tackle opportunistically; don't bundle into unrelated feature commits.

#### Surfaced during Folders removal (2026-05-27)

- **`Sidebar/SidebarSelection.swift` — entity-routing triplication (MEDIUM).** `SelectionTag.matches`, `init?(tag:lookup:)`, and `init?(stateRef:lookup:)` each carry a parallel case-per-entity switch. Every new sidebar-selectable entity must be added in 3+ places (this is exactly what made the Folders add/remove churny). Consider a protocol-based `SelectableEntity` routing layer so an entity registers once. Revisit before the next selectable entity type lands.

- **Pre-existing compiler warnings (LOW, but should be zeroed).** Surfaced by build runs this session, unrelated to folders:
  - `Content/PageContentManager+CRUD.swift` — `result of 'try?' is unused` on the `try? Filesystem.moveToTrash(attachmentsURL, in: nexus)` attachment-cascade lines (Collection + Type-root `deletePage`). Wrap as `_ = try? …` or handle.
  - `Detail/PageTypeDetailView.swift:98`, `Detail/PageCollectionDetailView.swift:87`, `Detail/ItemCollectionDetailView.swift:123`, `Detail/ItemTypeDetailView.swift:136` — `result of call to 'handleDrop(...)' is unused`. The drop handlers return `Bool` that callers discard; either consume or mark `@discardableResult`.
  - `Detail/DetailRowDragPayload.swift:33` — `'nonisolated(unsafe)' is unnecessary for a constant with 'Sendable' type 'UTType'`. Drop the annotation.
  - `PommoraTests/Properties/FileAttachmentEditorTests.swift:51` — `variable 'fm' was never mutated; consider 'let'`.

- **Row-file doc duplication (LOW).** The "only the first sibling ForEach's `.onMove` is honoured inside a DisclosureGroup" SwiftUI-bug explanation is copy-pasted across `PageTypeRow.swift` and (until removal) `PageCollectionRow.swift`. If the unified-item pattern recurs, centralize the rationale in one place (e.g. a `// Guidelines//` note or a shared doc comment) and reference it.

- **`Content/PageContentManager.resolveParent` (LOW).** Returns a bare tuple `(vault:collection:)` and is a brute-force O(N·M) walk (acknowledged in-code; SQLite lookup slated for v0.4.0). Fine for now; revisit when the index-backed lookup lands — and consider a named result type over the tuple.

- **CRUD mirror weight (NOTE, not a defect).** `PageContentManager+CRUD.swift` mirrors create/rename/delete/update across container scopes (Collection + Type-root). This is intentional symmetry, but it's the structure that made the 3-tier folder add expensive. If a 3rd+ page-container scope is ever reconsidered, evaluate a single scope-parameterized CRUD path instead of per-scope overloads.

#### (future entries appended here by later sweeps)
