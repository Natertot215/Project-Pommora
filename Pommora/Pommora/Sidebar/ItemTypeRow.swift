import SwiftUI

/// Phase 8 stub row for an Item Type (Task 8.5). Mirrors `PageTypeRow`'s
/// disclosure shape so child `ItemCollection`s nest cleanly underneath, but
/// without rename, context menus, or settings-label reads — those land with
/// the real Items UI plan. Selection chrome follows the locked spec (paradigm
/// decision #6 / quirk #10): `.listRowBackground(SelectionChrome(...))` at the
/// row-file level, never in-content `.background`.
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
            }
            .onMove { source, destination in
                itemTypeManager.reorderItemCollections(
                    in: itemType, fromOffsets: source, toOffset: destination
                )
            }
        } label: {
            SelectableRow(
                title: itemType.title,
                symbol: itemType.icon ?? "tray.full",
                tag: SelectionTag.itemType(itemType.id),
                selection: $selection,
                accent: nil,
                onSelect: { selection = .itemType(itemType) }
            )
            // No context menu yet — quick-actions land with the real Items UI plan.
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.itemType(itemType.id).matches(selection)
            )
        )
    }
}
