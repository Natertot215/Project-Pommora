import Foundation

// MARK: - Page pin helpers (custom-table + gallery rows)

extension PageMeta {
    /// Pin wire-record for this page. Single source for the `ViewItem`-driven
    /// custom table + gallery rows (relocated from the retired `DetailRow`).
    var stateRef: EntityStateRef { EntityStateRef(kind: .page, id: id, title: title) }

    @MainActor var isPinned: Bool {
        AppGlobals.pinnedManager?.contains(stateRef) ?? false
    }

    @MainActor func togglePin() {
        AppGlobals.pinnedManager?.toggle(stateRef)
    }
}
