## Table Cleanup Fixes — Applied ✓

**Build result:** `** BUILD SUCCEEDED **`
**Files changed:** `ViewOutlineTable.swift`, `ViewTableCells.swift`

---

### Fix 1 — Removed dead `OutlineNode.id` field ✓
- Removed `id: String` property + `id:` init param from `OutlineNode`
- Updated both construction sites in `makeNodes` (`OutlineNode(id:…)` → `OutlineNode(payload:…)`)
- Updated class doc comment (removed "restored by stable id" — that was never wired)

### Fix 2 — Corrected two stale comments ✓
- `nodes` property comment: removed "flat id→node map for selection restoration"
- `reload` doc comment: removed "+ selection (by id)"

### Fix 3 — Pinned hosted-cell SwiftUI identity to row; added `[weak self]` ✓
- Group header cell: `.id(group.id)` added
- Item cell: `.id(viewItem.id)` added; commit closure changed from `{ def, value in self.parent… }` to `{ [weak self] def, value in self?.parent… }`

### Fix 4 — Named magic numbers ✓
- Added `private static let rowHeight: CGFloat = 24` and `private static let maxColumnWidth: CGFloat = 1000`
- `column.maxWidth = 1000` → `column.maxWidth = Self.maxColumnWidth`
- `heightOfRowByItem` returns `Self.rowHeight`; unused `item` param marked `_`

### Fix 5 — Marked unused `shouldSelectItem` parameter ✓
- `item: Any` → `_: Any`

### Fix 6 — Documented synchronous-expansion assumption in `reload` ✓
- Added comment block above `isApplyingUpdate = true` explaining why synchronous reset is safe

### Fix 7 — Collapsed duplicate group-icon cases ✓
- `.structuralCollection: return "folder"` + `.structuralSet: return "folder"` → `.structuralCollection, .structuralSet: return "folder"`

---

**Out of scope (not touched):** `signature(of:)` reload-trigger robustness; swapping Collection detail view to new table.
