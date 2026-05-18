import SwiftUI

struct SidebarDetailView: View {
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @State private var presentedItem: Item?

    @Environment(SpaceManager.self) private var spaceManager
    @Environment(VaultManager.self) private var vaultManager

    var body: some View {
        Group {
            switch selection {
            case .none:
                emptyState

            case .savedKey(let key):
                ContextDetailPlaceholder(
                    title: key.capitalized,
                    icon: iconForSavedKey(key),
                    accent: nil,
                    supportingLine: "Saved view coming v0.5"
                )

            case .space(let s):
                ContextDetailPlaceholder(
                    title: s.title,
                    icon: s.icon ?? "circle.fill",
                    accent: s.color?.swiftUIColor,
                    supportingLine: "Tier 1 — Space"
                )

            case .topic(let t):
                ContextDetailPlaceholder(
                    title: t.title,
                    icon: t.icon ?? "folder",
                    accent: nil,
                    supportingLine: "Tier 2 — Topic\nParents: \(parentSpaceNames(for: t).joined(separator: ", "))"
                )

            case .subtopic(let s):
                ContextDetailPlaceholder(
                    title: s.title,
                    icon: s.icon ?? "doc.text",
                    accent: nil,
                    supportingLine: "Tier 3 — Sub-topic"
                )

            case .vault(let v):
                VaultDetailView(
                    vault: v,
                    selection: $selection,
                    presentedSheet: $presentedSheet,
                    presentedItem: $presentedItem
                )

            case .collection(let c):
                // We need the parent Vault here too. Find it via VaultManager.
                if let v = lookupVault(forCollection: c) {
                    CollectionDetailView(
                        collection: c,
                        vault: v,
                        selection: $selection,
                        presentedSheet: $presentedSheet,
                        presentedItem: $presentedItem
                    )
                } else {
                    Text("Collection parent vault not found")
                        .foregroundStyle(.red)
                }

            case .page(let p):
                ContextDetailPlaceholder(
                    title: p.title,
                    icon: "doc.text",
                    accent: nil,
                    supportingLine: "Page editor coming v0.6"
                )
            }
        }
        .sheet(item: $presentedItem) { item in
            ItemWindow(item: item)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newSpace:                  NewSpaceSheet()
            case .newTopic:                  NewTopicSheet()
            case .newSubtopic(let t):        NewSubtopicSheet(parent: t)
            case .newVault:                  NewVaultSheet()
            case .newCollection(let v):      NewCollectionSheet(vault: v)
            case .newPage(let c, let v):     NewPageSheet(parent: .collection(c, vault: v))
            case .newPageInVault(let v):     NewPageSheet(parent: .vaultRoot(v))
            case .newItem(let c, let v):     NewItemSheet(collection: c, vault: v)
            case .editTopicParents(let t):   EditTopicParentsSheet(topic: t)
            case .editIcon(let target):      IconPickerSheet(target: target)
            case .editColor(let s):          ColorPickerSheet(space: s)
            }
        }
    }

    private func lookupVault(forCollection c: Pommora.Collection) -> Vault? {
        vaultManager.vaults.first { $0.id == c.vaultID }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Select something from the sidebar")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconForSavedKey(_ key: String) -> String {
        switch key {
        case "homepage": return "house"
        case "calendar": return "calendar"
        case "recents":  return "clock"
        default: return "questionmark.square"
        }
    }

    private func parentSpaceNames(for topic: Topic) -> [String] {
        topic.parents.compactMap { id in
            spaceManager.spaces.first { $0.id == id }?.title
        }
    }
}
