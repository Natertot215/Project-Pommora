import Foundation

// MARK: - Plan

/// The output of `DetailReorderPlanner.plan(rows:movingRowID:dropOffset:)`.
/// Carries everything needed to apply a kind-scoped reorder to the relevant
/// subset without touching rows of other kinds.
struct DetailReorderPlan: Equatable {
    enum Kind: Equatable {
        case page
        case collection
        case set
    }

    /// Which kind of row is being moved.
    let kind: Kind
    /// In `Array.move(fromOffsets:toOffset:)` convention, scoped to the
    /// moving row's kind subset (NOT the full mixed-kinds `rows` array).
    let fromOffsets: IndexSet
    /// Insertion offset in the kind subset, again in `Array.move` convention.
    let toOffset: Int
}

// MARK: - Planner

/// Pure helper that converts a flat-table drag-drop into a kind-scoped
/// reorder instruction. A dragged page never reorders collections, and vice
/// versa — each kind reorders only within its own subset.
enum DetailReorderPlanner {
    /// Given the table's current `rows` (mixed kinds, in display order), the id
    /// of the dragged row, and the flat drop offset from `.dropDestination`,
    /// returns a plan that reorders ONLY within the dragged row's kind subset.
    /// Returns nil for a no-op or if the row isn't found.
    static func plan(rows: [DetailRow], movingRowID: String, dropOffset: Int) -> DetailReorderPlan? {
        // 1. locate the dragged row in the flat list
        guard let flatIndex = rows.firstIndex(where: { $0.id == movingRowID }) else { return nil }
        let movingKind = DetailReorderPlan.Kind(rows[flatIndex].kind)

        // 2. same-kind subset, in display order
        let subset = rows.filter { DetailReorderPlan.Kind($0.kind) == movingKind }
        guard let sourceIndex = subset.firstIndex(where: { $0.id == movingRowID }) else { return nil }

        // 3. destination within the subset = count of same-kind rows strictly BEFORE the flat drop point
        let clampedDrop = min(max(dropOffset, 0), rows.count)
        let destInSubset = rows[0..<clampedDrop].filter { DetailReorderPlan.Kind($0.kind) == movingKind }.count

        // 4. no-op guard (SwiftUI Array.move convention: inserting at `from` or `from+1` changes nothing)
        if destInSubset == sourceIndex || destInSubset == sourceIndex + 1 { return nil }

        // 5. plan, scoped to the subset
        return DetailReorderPlan(kind: movingKind, fromOffsets: IndexSet(integer: sourceIndex), toOffset: destInSubset)
    }
}

// MARK: - Kind mapping

extension DetailReorderPlan.Kind {
    /// Maps a `DetailRow.Kind` to the flat `DetailReorderPlan.Kind`.
    init(_ rowKind: DetailRow.Kind) {
        switch rowKind {
        case .page: self = .page
        case .collection: self = .collection
        case .set: self = .set
        }
    }
}
