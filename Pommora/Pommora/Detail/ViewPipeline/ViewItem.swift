import Foundation

/// One fetched Page paired with the structural context the view needs to filter,
/// group, and render it. Pure value — no SwiftUI, no disk. Both renderers (custom
/// table + gallery) consume `[ResolvedGroup]` built from these.
///
/// `setLabel` is the vault-scope gallery chip: in vault scope a gallery flattens
/// every Collection/Set into ONE section, so each card carries the label of the
/// Set it lives in (nil for pages sitting directly in a Collection).
struct ViewItem: Identifiable, Equatable, Sendable {
    let page: PageMeta
    let parent: PageParent  // Content/PageParent.swift
    let setLabel: String?  // vault-scope gallery chip

    var id: String { page.id }
}
