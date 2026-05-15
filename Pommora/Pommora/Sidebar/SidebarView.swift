//
//  SidebarView.swift
//  Pommora
//

import SwiftUI

/// The sidebar's content surface. Consumes `NexusManager.currentNexus` and
/// rebuilds the folder tree whenever the active nexus changes.
///
/// Three states:
/// 1. No nexus open → "No Nexus Open" empty state
/// 2. Nexus open but folder has no visible content → "Empty Nexus" empty state
/// 3. Nexus open with content → recursive `OutlineGroup` of `SidebarNode`
///
/// The search field lives on `ContentView` (anchored via `.safeAreaInset`)
/// rather than here, keeping this view focused on tree rendering.
struct SidebarView: View {
    let manager: NexusManager
    @State private var rootNode: SidebarNode?
    @State private var selection: SidebarNode?

    var body: some View {
        Group {
            if let root = rootNode, let children = root.children, !children.isEmpty {
                List(selection: $selection) {
                    OutlineGroup(children, id: \.id, children: \.children) { node in
                        SidebarRow(node: node)
                            .tag(node)
                    }
                }
                .listStyle(.sidebar)
                .environment(\.sidebarRowSize, .medium)
                .scrollContentBackground(.hidden)
            } else if manager.currentNexus != nil {
                ContentUnavailableView(
                    "Empty Nexus",
                    systemImage: "folder",
                    description: Text("This nexus has no visible Pommora content yet.")
                )
            } else {
                ContentUnavailableView(
                    "No Nexus Open",
                    systemImage: "tray",
                    description: Text("Pick a folder to use as your Pommora nexus.")
                )
            }
        }
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
