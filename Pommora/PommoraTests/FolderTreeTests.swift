//
//  FolderTreeTests.swift
//  PommoraTests
//

import Foundation
import Testing
@testable import Pommora

struct FolderTreeTests {
    @Test func skipsLeadingDotEntries() throws {
        let root = try makeFixture(entries: [
            "Visible.md",
            ".pommora",
            ".DS_Store",
            ".git",
        ])
        defer { cleanup(root) }

        let tree = try FolderTree.buildTree(at: root)
        let names = (tree.children ?? []).map(\.name)
        #expect(names == ["Visible"])
    }

    @Test func keepsOnlyMdAndJsonFiles() throws {
        let root = try makeFixture(entries: [
            "page.md",
            "item.json",
            "image.png",
            "doc.pdf",
            "notes.txt",
        ])
        defer { cleanup(root) }

        let tree = try FolderTree.buildTree(at: root)
        let names = (tree.children ?? []).map(\.name).sorted()
        #expect(names == ["item", "page"])
    }

    @Test func stripsExtensionsOnDisplay() throws {
        let root = try makeFixture(entries: ["Note.md", "Task.json"])
        defer { cleanup(root) }

        let tree = try FolderTree.buildTree(at: root)
        let names = Set((tree.children ?? []).map(\.name))
        #expect(names == ["Note", "Task"])
    }

    @Test func sortsFoldersBeforeFilesAlphabeticalWithinEachGroup() throws {
        let root = try makeFixture(entries: [
            "zfile.md",
            "Beta/",
            "alpha.md",
            "Acme/",
        ])
        defer { cleanup(root) }

        let tree = try FolderTree.buildTree(at: root)
        let names = (tree.children ?? []).map(\.name)
        // Folders first (Acme, Beta), then files (alpha, zfile)
        #expect(names == ["Acme", "Beta", "alpha", "zfile"])
    }

    @Test func emptyFolderHasEmptyChildrenNotNil() throws {
        let root = try makeFixture(entries: ["EmptyFolder/"])
        defer { cleanup(root) }

        let tree = try FolderTree.buildTree(at: root)
        let folder = tree.children?.first
        #expect(folder?.kind == .folder)
        #expect(folder?.children?.isEmpty == true)
    }

    @Test func recursesIntoSubfolders() throws {
        let root = try makeFixture(entries: [
            "Sub/",
            "Sub/inner.md",
            "Sub/Nested/",
            "Sub/Nested/deep.json",
        ])
        defer { cleanup(root) }

        let tree = try FolderTree.buildTree(at: root)
        let sub = tree.children?.first { $0.name == "Sub" }
        #expect(sub != nil)
        #expect((sub?.children ?? []).contains { $0.name == "inner" })
        let nested = sub?.children?.first { $0.name == "Nested" }
        #expect(nested != nil)
        #expect((nested?.children ?? []).contains { $0.name == "deep" })
    }

    @Test func nodeKindMatchesExtension() throws {
        let root = try makeFixture(entries: ["a.md", "b.json", "Folder/"])
        defer { cleanup(root) }

        let tree = try FolderTree.buildTree(at: root)
        let byName = Dictionary(uniqueKeysWithValues: (tree.children ?? []).map { ($0.name, $0.kind) })
        #expect(byName["a"] == .page)
        #expect(byName["b"] == .item)
        #expect(byName["Folder"] == .folder)
    }

    // MARK: - Fixture helpers

    /// Creates a temp directory with the given entries. Folder entries end in `/`.
    private func makeFixture(entries: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderTreeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for entry in entries {
            let url = root.appendingPathComponent(entry)
            if entry.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                let parent = url.deletingLastPathComponent()
                if parent != root {
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                try Data().write(to: url)
            }
        }
        return root
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
