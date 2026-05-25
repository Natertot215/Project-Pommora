import SwiftUI

/// Stub row for an Item Type. Disclosure-style to nest `ItemCollection`s; no
/// rename, context menu, or settings-label reads yet.
struct ItemTypeRow: View {
    let itemType: ItemType
    @Binding var selection: SidebarSelection
    @State private var expanded: Bool = false

    @Environment(ItemTypeManager.self) private var itemTypeManager

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(itemTypeManager.itemCollections(in: itemType)) { coll in
                ItemCollectionRow(
                    collection: coll,
                    selection: $selection
                )
                .tag(SelectionTag.itemCollection(coll.id))
            }
            .onMove { source, destination in
                withAnimation(.snappy) {
                    itemTypeManager.reorderItemCollections(
                        in: itemType, fromOffsets: source, toOffset: destination
                    )
                }
            }
        } label: {
            SelectableRow(
                title: itemType.title,
                symbol: itemType.icon ?? "tray.full",
                tag: SelectionTag.itemType(itemType.id),
                selection: $selection,
                accent: nil
            )
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.itemType(itemType.id).matches(selection)
            )
        )
    }
}
