## Vault Table Reorder — Display-Only Interim (Decision + Deferral)

**Status:** Decided 2026-05-31. Interim ships now; the full per-view ordering/grouping/sort system is deferred to the roadmapped view work (v0.5.0–v0.6.0). Verified against code 2026-05-31 (isolation + dead-code map below).

### Problem

Manual drag-reorder lived in two surfaces writing the **same** container order field:

- **Sidebar** — `List` + `.onMove` → `reorderPages(in:)` / `reorderPageCollections(in:)` (file-level `page_order` / `item_order` / `collection_order`).
- **Detail tables** — SwiftUI `Table` + `.dropDestination` → the *same* `reorderPages(in:)`.

At the **vault/type** level the table additionally attempted **nested** drag (pages inside collection disclosure rows). SwiftUI `Table` does not reliably support that — producing the intermittent mis-target / mis-drop / no-op (`fee6804`) and the "sidebar reorders but the table is out of sync" feeling.

**Root constraint:** SwiftUI `Table` offers **collapsible structural grouping (`DisclosureTableRow`) _XOR_ reliable reorder (flat `.dropDestination`)** — never both, and it has no section headers to group flat rows cleanly. So *vault-level structural collection grouping* + *reliable nested page reorder* cannot coexist on the native Table.

### Decision (interim)

- **Vault/Type detail tables → display-only for ordering.** Remove their drag-reorder. They render rows (including collapsible collection disclosures) in the file-level order and **mirror the sidebar live** (shared `@Observable` managers — verified, no refresh gap).
- **Collection/Set detail tables → keep their drag-reorder.** They are flat + non-structural, so the native flat `.dropDestination` path is reliable. They share the collection's file order with the sidebar (consistent — reorder in either reflects in both). *(Item Sets are single-writer: only the Set's detail view, since `ItemCollectionRow` has no sidebar `.onMove`. Pre-existing, not a regression.)*
- **Collections stay collapsible disclosures** in the vault view (display only).
- **The sidebar remains the place to arrange file-level structural order** — including pages within a collection.
- **Default order fallback = file/creation order, not alphabetical** (shared by both surfaces so they stay mirrored). *(Exact "file order" definition — creation order proposed — pending confirmation.)*

### Why this is the interim, not the full fix

The Notion-style per-view system is already partly scaffolded: `SavedView` + `views[]` exist on every container and already drive **columns** today. The two missing pieces for true per-view ordering are (1) a per-view `order` field and (2) a reliable nested-reorder engine. Making vault tables display-only **now** defers **both** — and crucially also defers the **table-engine decision** (native flat-`Table` vs vendored `visfitness/reorderable` DragGesture vs AppKit `NSOutlineView`) until the view system is actually built, avoiding a premature commitment.

### Scope (verified against code)

**REMOVE** (vault/type drag only — confirmed isolated from inline editing):
- `Detail/PageTypeDetailView.swift` + `Detail/ItemTypeDetailView.swift`: the row `.draggable`, the outer + nested `.dropDestination`, and the `handleDrop` / `handleChildDrop` methods. Each `rows:` closure collapses to pure display (`ForEach(rows) { … DisclosureTableRow { ForEach(kids) { TableRow($0) } } … }`).
- `Detail/SessionRowOrdering.swift` (+ `SessionRowOrderingTests`) — already dead (zero production callers). Delete; fix the stale `SessionRowOrdering` doc-comment in `Detail/DetailRowDragPayload.swift`.
- Retire `DetailReorderPlannerTests.childPageReorderWithinCollectionScopesToKids` + `topLevelDragStillKindSafeWithChildrenPresent` (they pinned the removed vault child-drop).

**KEEP:**
- `Detail/PageCollectionDetailView.swift` + `Detail/ItemCollectionDetailView.swift` `handleDrop` + their `.draggable`/`.dropDestination` (the preserved flat reorder).
- `Detail/DetailReorderPlanner.swift` + `Detail/DetailRowDragPayload.swift` (still used by the collection views).
- The remaining `DetailReorderPlannerTests` (flat-plan + no-op/unknown-id guards + collection-scoped coverage).

**VERIFIED isolation:** removing the vault drag does NOT affect inline property assignment/editing (`PropertyCellEditor` → `updatePageProperty`/`updateItemProperty`, in the columns closure), cell rendering, selection, double-click-to-open (`.simultaneousGesture` on the Title cell), disclosure expand/collapse, context menus (Edit Title / Edit Icon), or relation warming. The drag code is structurally separate; the row `id` it referenced keeps serving `ForEach`/disclosure/pin unchanged.

### Deferred to the view system (v0.5.0–v0.6.0)

- Per-view manual `order` on `SavedView` (true per-view independence, including vault views and a collection view diverging from its sidebar order).
- Reliable nested reorder in the vault/type view + the table-engine decision (flat-`Table` vs `visfitness/reorderable` vs AppKit `NSOutlineView`).
- Group-by (collection = default; group-by-**property** flattens collections — the two are mutually exclusive), per-view sort, multi-saved-view tabs. Sort orders within whatever grouping is active; an active sort disables manual drag (Notion parity).

### For future agents

Vault/Type tables are **intentionally** display-only for ordering — this is a deliberate deferral, not a missing feature to "fix" casually. SwiftUI `Table` cannot do collapsible structural collection grouping **and** reliable nested reorder at once. Re-enabling vault-level reorder requires the per-view-`order` field + the engine decision above. **Collection-level reorder is fully functional and is the correct place for flat page ordering today.** The sidebar owns file-level structural order.
