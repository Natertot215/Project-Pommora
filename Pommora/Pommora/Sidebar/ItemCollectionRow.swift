import SwiftUI

/// Stub leaf row for an Item Collection. No rename / context menu / nested
/// Item leaves yet.
struct ItemCollectionRow: View {
    let collection: ItemCollection
    @Binding var selection: SidebarSelection

    var body: some View {
        SelectableRow(
            title: collection.title,
            symbol: "tray",
            tag: SelectionTag.itemCollection(collection.id),
            selection: $selection,
            accent: nil
        )
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.itemCollection(collection.id).matches(selection)
            )
        )
    }
}
