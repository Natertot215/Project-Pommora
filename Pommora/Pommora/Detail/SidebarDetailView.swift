import SwiftUI

struct SidebarDetailView: View {
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    /// Last page viewed; surfaces as a ghost breadcrumb trail in the parent
    /// collection or vault view so the user can tap back to it.
    @State private var pageTrail: PageMeta? = nil

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
                    supportingLine: "Tier 2 — Topic"
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
                    editingID: $editingID,
                    justCreatedID: $justCreatedID,
                    trailPage: pageTrail
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
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        trailPage: pageTrail
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

            case .page(let p):
                PageEditorHost(page: p, selection: $selection)
            }
        }
        .onChange(of: selection) { _, newSel in
            switch newSel {
            case .page(let p):
                pageTrail = p
            case .collection, .pageType:
                // Keep trail — child views validate membership before rendering
                // the ghost crumb; irrelevant pages are silently skipped.
                break
            default:
                pageTrail = nil
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
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

}
