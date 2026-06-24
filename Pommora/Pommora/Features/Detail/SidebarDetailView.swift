import SwiftUI

struct SidebarDetailView: View {
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var editingID: String?
    @Binding var justCreatedID: String?
    /// Last page viewed; surfaces as a ghost breadcrumb trail in the parent
    /// collection or vault view so the user can tap back to it.
    @State private var pageTrail: PageMeta? = nil

    @Environment(PageCollectionManager.self) private var collectionManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(AreaManager.self) private var areaManager
    @Environment(TopicManager.self) private var topicManager
    @Environment(ProjectManager.self) private var projectManager

    var body: some View {
        Group {
            switch selection {
            case .none:
                emptyState

            case .savedKey(let key):
                // The Nexus header row selects `savedKey("homepage")` → the
                // Homepage dashboard. Any other saved key stays blank.
                if key == "homepage" {
                    HomepageDetailView()
                } else {
                    Color.clear
                }

            case .area(let s):
                ContextDetailPlaceholder(
                    title: s.title,
                    icon: s.icon ?? "circle.fill",
                    accent: nil,
                    supportingLine: "Tier 1 — Area",
                    onRename: { try? await areaManager.rename(s, to: $0) },
                    onIconChange: { try? await areaManager.updateIcon(s, to: $0) }
                )

            case .topic(let t):
                ContextDetailPlaceholder(
                    title: t.title,
                    icon: t.icon ?? "folder",
                    accent: nil,
                    supportingLine: "Tier 2 — Topic",
                    onRename: { try? await topicManager.rename(t, to: $0) },
                    onIconChange: { try? await topicManager.updateIcon(t, to: $0) }
                )

            case .project(let p):
                ContextDetailPlaceholder(
                    title: p.title,
                    icon: p.icon ?? "doc.text",
                    accent: nil,
                    supportingLine: "Tier 3 — Project",
                    onRename: { try? await projectManager.rename(p, to: $0) },
                    onIconChange: { try? await projectManager.updateIcon(p, to: $0) }
                )

            case .pageCollection(let t):
                PageCollectionDetailView(
                    pageCollection: t,
                    selection: $selection,
                    presentedSheet: $presentedSheet,
                    editingID: $editingID,
                    justCreatedID: $justCreatedID,
                    trailPage: pageTrail
                )

            case .collection(let c):
                // We need the parent Vault here too. Find it via PageCollectionManager
                // (primary: typeID match; fallback: parent-folder-name match).
                if let v = lookupVault(forCollection: c) {
                    CollectionSetDetailView(
                        collection: c,
                        pageCollection: v,
                        selection: $selection,
                        presentedSheet: $presentedSheet,
                        editingID: $editingID,
                        justCreatedID: $justCreatedID,
                        trailPage: pageTrail
                    )
                } else {
                    VStack(alignment: .leading, spacing: PUI.Spacing.md) {
                        Text("Collection parent vault not found")
                            .foregroundStyle(.red)
                            .font(.headline)
                        Text("Collection title: \(c.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Collection typeID: \(c.parentID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("Parent folder name: \(c.folderURL.deletingLastPathComponent().lastPathComponent)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("Known vault IDs (\(collectionManager.types.count)):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(collectionManager.types, id: \.id) { vt in
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
            case .collection, .pageCollection:
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
            }
        }
    }

    /// Find the PageCollection that owns this PageCollection.
    ///
    /// Primary: match by `typeID` (the relationship stored on disk in
    /// `_pagecollection.json`).
    ///
    /// Fallback: match by parent folder name. PageCollection sub-folders sit
    /// directly inside their owning PageCollection's folder, so `c.folderURL`'s
    /// parent is the PageCollection folder. This rescues users whose pre-flatlayout
    /// `_collection.json` carried a `vault_id` that no longer matches any
    /// current PageCollection id (e.g. ID was regenerated during a re-init, or
    /// the user manually rebuilt the PageCollection while keeping the Collection
    /// folder intact).
    private func lookupVault(forCollection c: PageSet) -> PageCollection? {
        if let v = collectionManager.types.first(where: { $0.id == c.parentID }) {
            return v
        }
        let parentFolderName = c.folderURL.deletingLastPathComponent().lastPathComponent
        return collectionManager.types.first { $0.title == parentFolderName }
    }

    private var emptyState: some View {
        VStack(spacing: PUI.Spacing.md) {
            Image(systemName: "sidebar.left")
                .font(PUI.Typography.Fixed.f36)
                .foregroundStyle(.secondary)
            Text("Select something from the sidebar")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
