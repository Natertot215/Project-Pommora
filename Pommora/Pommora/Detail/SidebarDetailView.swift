import SwiftUI

struct SidebarDetailView: View {
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    @State private var presentedItem: Item?

    @Environment(SpaceManager.self) private var spaceManager
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(PageContentManager.self) private var contentManager

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
                    supportingLine: "Saved view coming v0.6.0"
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

            case .project(let p):
                ContextDetailPlaceholder(
                    title: p.title,
                    icon: p.icon ?? "doc.text",
                    accent: nil,
                    supportingLine: "Tier 3 — Project"
                )

            case .pageType(let t):
                PageTypeDetailView(
                    pageType: t,
                    selection: $selection,
                    presentedSheet: $presentedSheet,
                    presentedItem: $presentedItem,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID
                )

            case .collection(let c):
                // We need the parent Vault here too. Find it via PageTypeManager
                // (primary: typeID match; fallback: parent-folder-name match).
                if let v = lookupVault(forCollection: c) {
                    PageCollectionDetailView(
                        collection: c,
                        vault: v,
                        selection: $selection,
                        presentedSheet: $presentedSheet,
                        presentedItem: $presentedItem,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Collection parent vault not found")
                            .foregroundStyle(.red)
                            .font(.headline)
                        Text("Collection title: \(c.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Collection typeID: \(c.typeID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("Parent folder name: \(c.folderURL.deletingLastPathComponent().lastPathComponent)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("Known vault IDs (\(vaultManager.types.count)):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(vaultManager.types, id: \.id) { vt in
                            Text("  \(vt.title): \(vt.id)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }

            case .folder(let f):
                if let v = lookupVault(forFolder: f) {
                    FolderDetailView(
                        folder: f,
                        vault: v,
                        selection: $selection,
                        presentedSheet: $presentedSheet,
                        presentedItem: $presentedItem,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Folder parent vault not found")
                            .foregroundStyle(.red)
                            .font(.headline)
                        Text("Folder title: \(f.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Folder typeID: \(f.typeID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }

            case .page(let p):
                PageEditorHost(page: p)

            case .itemType(let t):
                ItemTypeDetailView(
                    type: t,
                    selection: $selection,
                    presentedSheet: $presentedSheet,
                    presentedItem: $presentedItem,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID
                )

            case .itemCollection(let c):
                ItemCollectionDetailView(
                    collection: c,
                    selection: $selection,
                    presentedSheet: $presentedSheet,
                    presentedItem: $presentedItem,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID
                )
            }
        }
        .sheet(item: $presentedItem) { item in
            ItemWindow(item: item)
        }
        .onAppear {
            AppGlobals.presentItemAction = { item in
                presentedItem = item
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .editTopicParents(let t): EditTopicParentsSheet(topic: t)
            case .editIcon(let target): IconPickerSheet(target: target)
            case .editColor(let s): ColorPickerSheet(space: s)
            }
        }
    }

    /// Find the PageType that owns this PageCollection.
    ///
    /// Primary: match by `typeID` (the relationship stored on disk in
    /// `_pagecollection.json`).
    ///
    /// Fallback: match by parent folder name. PageCollection sub-folders sit
    /// directly inside their owning PageType's folder, so `c.folderURL`'s
    /// parent is the PageType folder. This rescues users whose pre-flatlayout
    /// `_collection.json` carried a `vault_id` that no longer matches any
    /// current PageType id (e.g. ID was regenerated during a re-init, or
    /// the user manually rebuilt the PageType while keeping the Collection
    /// folder intact).
    private func lookupVault(forCollection c: PageCollection) -> PageType? {
        if let v = vaultManager.types.first(where: { $0.id == c.typeID }) {
            return v
        }
        let parentFolderName = c.folderURL.deletingLastPathComponent().lastPathComponent
        return vaultManager.types.first { $0.title == parentFolderName }
    }

    /// Find the PageType that owns this Folder. Primary: `folder.typeID`.
    /// Fallback: the grandparent folder name — a Folder sits at
    /// `<nexus>/<Type>/<Collection>/<Folder>/`, so two `deletingLastPathComponent`
    /// hops yield the owning PageType folder.
    private func lookupVault(forFolder f: Folder) -> PageType? {
        if let v = vaultManager.types.first(where: { $0.id == f.typeID }) {
            return v
        }
        let grandparentFolderName = f.folderURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent
        return vaultManager.types.first { $0.title == grandparentFolderName }
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
        case "recents": return "clock"
        default: return "questionmark.square"
        }
    }

    private func parentSpaceNames(for topic: Topic) -> [String] {
        topic.parents.compactMap { id in
            spaceManager.spaces.first { $0.id == id }?.title
        }
    }
}
