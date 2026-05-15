//
//  SidebarNode.swift
//  Pommora
//

import Foundation

/// What an entry in the sidebar tree represents.
enum NodeKind: Equatable, Hashable {
    case folder
    case page    // .md file
    case item    // .json file
}

/// A node in the sidebar's recursive tree. Mirrors a folder or content file
/// inside the active nexus, with file extensions stripped from `name` per
/// Pommora's "filename = title" rule.
///
/// `children == nil` means a leaf (file). `children == []` means an empty
/// folder (still rendered, with disclosure but no contents).
struct SidebarNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let kind: NodeKind
    let name: String
    let children: [SidebarNode]?

    init(url: URL, kind: NodeKind, children: [SidebarNode]? = nil) {
        self.id = url
        self.url = url
        self.kind = kind
        self.children = children
        self.name = Self.displayName(for: url, kind: kind)
    }

    private static func displayName(for url: URL, kind: NodeKind) -> String {
        switch kind {
        case .folder:
            return url.lastPathComponent
        case .page, .item:
            return url.deletingPathExtension().lastPathComponent
        }
    }
}
