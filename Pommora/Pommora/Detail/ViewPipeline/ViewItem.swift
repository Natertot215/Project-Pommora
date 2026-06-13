import Foundation

/// One fetched Page paired with the structural context the view needs to filter,
/// group, and render it. Pure value — no SwiftUI, no disk. Both renderers (custom
/// table + gallery) consume `[ResolvedGroup]` built from these.
///
/// `setLabel` is the vault-scope gallery chip: in vault scope a gallery flattens
/// every Collection/Set into ONE section, so each card carries the label of the
/// Set it lives in (nil for pages sitting directly in a Collection).
struct ViewItem: Identifiable, Equatable, Hashable, Sendable {
    let page: PageMeta
    let parent: PageParent  // Content/PageParent.swift
    let setLabel: String?  // vault-scope gallery chip

    var id: String { page.id }

    // Identity is the page id; hashing it keeps `Hashable` consistent with the
    // synthesized member-wise `Equatable` (equal items share an id → same hash)
    // and lets `ViewItem` back a `Hashable` `RowTarget` without forcing
    // `PageMeta`/`PageParent` to conform.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
