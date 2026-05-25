import SwiftUI

struct ItemTypeRow: View {
    let itemType: ItemType
    @Binding var selection: SidebarSelection
    let nexus: Nexus
    let index: PommoraIndex?
    @State private var expanded: Bool = false
    @State private var showingTypeSettings: Bool = false

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(SettingsManager.self) private var settingsManager

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
            .contextMenu {
                let typeLabel = settingsManager.settings.labels.itemType.singular
                Button("\(typeLabel) Settings…") {
                    showingTypeSettings = true
                }
            }
        }
        .listRowBackground(
            SelectionChrome(
                isSelected: SelectionTag.itemType(itemType.id).matches(selection)
            )
        )
        .sheet(isPresented: $showingTypeSettings) {
            TypeSettingsSheet(
                itemType: itemType,
                itemTypeManager: itemTypeManager,
                nexus: nexus,
                index: index,
                onDismiss: { showingTypeSettings = false }
            )
            .interactiveDismissDisabled()
        }
    }
}
