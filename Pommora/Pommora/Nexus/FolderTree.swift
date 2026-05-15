//
//  FolderTree.swift
//  Pommora
//

import Foundation

/// Reads a nexus folder from disk and builds a `SidebarNode` tree per Pommora's
/// v0.1 sidebar scope rules.
///
/// Filter rules (decided in the v0.1 brainstorm):
/// - Skip entries whose name starts with `.` (`.pommora/`, `.trash/`, `.git/`,
///   `.DS_Store`, etc.)
/// - For files, only `.md` (Pages) and `.json` (Items) pass — other file types
///   stay invisible (PDFs, images, etc. belong to attachments, not the sidebar)
/// - All folders pass, even if empty
/// - Folders sort first, then files; alphabetical within each group, locale-aware
enum FolderTree {
    private static let pommoraExtensions: Set<String> = ["md", "json"]

    /// Builds a recursive `SidebarNode` rooted at `root`. The root itself is
    /// always treated as a folder; its name comes from `lastPathComponent`.
    /// Sub-folder failures are silently skipped to avoid one bad subdirectory
    /// blanking the entire sidebar.
    static func buildTree(at root: URL) throws -> SidebarNode {
        let children = try buildChildren(of: root)
        return SidebarNode(url: root, kind: .folder, children: children)
    }

    private static func buildChildren(of folder: URL) throws -> [SidebarNode] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )

        var folders: [SidebarNode] = []
        var files: [SidebarNode] = []

        for url in urls {
            // Belt-and-suspenders: .skipsHiddenFiles already filters most dot-files
            // and items with the hidden xattr, but explicit prefix check catches
            // any edge cases (e.g. files Finder hasn't yet flagged hidden).
            if url.lastPathComponent.hasPrefix(".") { continue }

            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory {
                let subChildren = (try? buildChildren(of: url)) ?? []
                folders.append(SidebarNode(url: url, kind: .folder, children: subChildren))
            } else {
                let ext = url.pathExtension.lowercased()
                guard pommoraExtensions.contains(ext) else { continue }
                let kind: NodeKind = (ext == "md") ? .page : .item
                files.append(SidebarNode(url: url, kind: kind))
            }
        }

        return sort(folders) + sort(files)
    }

    private static func sort(_ nodes: [SidebarNode]) -> [SidebarNode] {
        nodes.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
