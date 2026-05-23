import SwiftUI

/// Phase 8 stub row for an Item Collection (Task 8.5). Mirrors
/// `PageCollectionRow`'s leaf shape but without rename, context menus, or
/// nested Item leaf rows — those land with the real Items UI plan. Selection
/// chrome follows the locked spec (quirk #10): `.listRowBackground(...)` at
/// the row-file level, never in-content `.background`.
struct ItemCollectionRow: View {
    let collection: ItemCollection
    @Binding var selection: SidebarSelection

    var body: some View {
        SelectableRow(
            title: collection.title,
            // ItemCollection carries no icon field on disk; literal "tray"
            // mirrors the Pages-side default ("folder") with the Items-side
            // tray motif.
            symbol: "tray",
            tag: SelectionTag.itemCollection(collection.id),
            selection: $selection,
            accent: nil,
            onSelect: { selection = .itemCollection(collection) }
        )
        // No context menu yet — quick-actions land with the real Items UI plan.
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.itemCollection(collection.id).matches(selection)
            )
        )
    }
}
