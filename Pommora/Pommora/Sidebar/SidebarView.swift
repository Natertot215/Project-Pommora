//
//  SidebarView.swift
//  Pommora
//

import SwiftUI

/// The sidebar's content surface. Consumes `NexusManager.currentNexus` and
/// rebuilds the folder tree whenever the active nexus changes.
///
/// Always renders a `List` (possibly empty) so `.safeAreaInset(.top)` on the
/// parent anchors the search field to the top regardless of nexus state.
struct SidebarView: View {
    let manager: NexusManager
    @State private var rootNode: SidebarNode?
    @State private var selection: SidebarNode?

    var body: some View {
        List(selection: $selection) {
            if let root = rootNode, let children = root.children {
                OutlineGroup(children, id: \.id, children: \.children) { node in
                    SidebarRow(node: node)
                        .tag(node)
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .medium)
        .scrollContentBackground(.hidden)
        .task(id: manager.currentNexus?.id) {
            await rebuildTree()
        }
    }

    private func rebuildTree() async {
        guard let nexus = manager.currentNexus else {
            rootNode = nil
            return
        }
        rootNode = try? FolderTree.buildTree(at: nexus.rootURL)
    }
}
