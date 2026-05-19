import SwiftUI

/// Host view for a standalone EntityRef window. Resolves the ref via
/// AppGlobals managers and renders the matching detail view. Carries
/// its own minimal toolbar with an Expand button that pushes the
/// resolved entity back to the main window via MainWindowRouter.
@MainActor
struct EntityWindowHost: View {
    let ref: EntityRef
    @Environment(\.dismissWindow) private var dismissWindow

    // Local @State bindings required by SidebarDetailView / VaultDetailView.
    // These are never driven by user interaction inside the standalone window;
    // they act as inert sinks so the embedded views compile without restructuring.
    @State private var localSelection: SidebarSelection = .none
    @State private var localSheet: SidebarSheet?
    @State private var localItem: Item?

    var body: some View {
        Group {
            switch ref {
            case .page(let pageID, let vaultID, let collectionID):
                pageBody(pageID: pageID, vaultID: vaultID, collectionID: collectionID)
            case .vault(let vaultID):
                vaultBody(vaultID: vaultID)
            case .space(let spaceID):
                spaceBody(spaceID: spaceID)
            case .topic(let topicID):
                topicBody(topicID: topicID)
            case .subtopic(let subtopicID, let parentTopicID):
                subtopicBody(subtopicID: subtopicID, parentTopicID: parentTopicID)
            case .collection:
                placeholderBody("Collections cannot be opened in a standalone window in v0.2.7.2.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    expand()
                } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Open in main window (commits to Recents)")
            }
        }
        .frame(minWidth: 480, minHeight: 600)
    }

    // MARK: - Body resolvers

    @ViewBuilder
    private func pageBody(pageID: String, vaultID: String, collectionID: String?) -> some View {
        if let contentMgr = AppGlobals.contentManager,
            let vaultMgr = AppGlobals.vaultManager
        {
            let pageRef = PageRef(pageID: pageID, vaultID: vaultID, collectionID: collectionID)
            if let resolved = pageRef.resolve(vaultManager: vaultMgr, contentManager: contentMgr) {
                PageEditorHost(page: resolved.page)
                    .environment(contentMgr)
                    .environment(vaultMgr)
            } else {
                placeholderBody("Page unavailable.")
            }
        } else {
            placeholderBody("Page unavailable.")
        }
    }

    @ViewBuilder
    private func vaultBody(vaultID: String) -> some View {
        if let vaultMgr = AppGlobals.vaultManager,
            let contentMgr = AppGlobals.contentManager,
            let vault = vaultMgr.vaults.first(where: { $0.id == vaultID })
        {
            VaultDetailView(
                vault: vault,
                selection: $localSelection,
                presentedSheet: $localSheet,
                presentedItem: $localItem
            )
            .environment(vaultMgr)
            .environment(contentMgr)
        } else {
            placeholderBody("Vault unavailable.")
        }
    }

    @ViewBuilder
    private func spaceBody(spaceID: String) -> some View {
        if let spaceMgr = AppGlobals.spaceManager,
            let space = spaceMgr.spaces.first(where: { $0.id == spaceID })
        {
            ContextDetailPlaceholder(
                title: space.title,
                icon: space.icon ?? "circle.fill",
                accent: space.color?.swiftUIColor,
                supportingLine: "Tier 1 — Space"
            )
        } else {
            placeholderBody("Space unavailable.")
        }
    }

    @ViewBuilder
    private func topicBody(topicID: String) -> some View {
        if let topicMgr = AppGlobals.topicManager,
            let topic = topicMgr.topics.first(where: { $0.id == topicID })
        {
            ContextDetailPlaceholder(
                title: topic.title,
                icon: topic.icon ?? "folder",
                accent: nil,
                supportingLine: "Tier 2 — Topic"
            )
        } else {
            placeholderBody("Topic unavailable.")
        }
    }

    @ViewBuilder
    private func subtopicBody(subtopicID: String, parentTopicID: String) -> some View {
        if let topicMgr = AppGlobals.topicManager,
            let st = topicMgr.subtopicsByParent[parentTopicID]?.first(where: { $0.id == subtopicID })
        {
            ContextDetailPlaceholder(
                title: st.title,
                icon: st.icon ?? "doc.text",
                accent: nil,
                supportingLine: "Tier 3 — Sub-topic"
            )
        } else {
            placeholderBody("Sub-topic unavailable.")
        }
    }

    @ViewBuilder
    private func placeholderBody(_ message: String) -> some View {
        VStack {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Expand

    private func expand() {
        guard let router = AppGlobals.mainWindowRouter else { return }
        guard let sel = SidebarSelection(entityRef: ref) else { return }
        router.requestExpand(to: sel)
        dismissWindow()
    }
}
