import Foundation
import Testing

@testable import Pommora

@Suite("FolderFilter") struct FolderFilterTests {

    private func filter(_ paths: [String], root: URL = URL(fileURLWithPath: "/N")) -> FolderFilter {
        FolderFilter(nexusRoot: root, excludedFolders: paths)
    }
    private func url(_ rel: String, root: String = "/N") -> URL {
        URL(fileURLWithPath: root).appendingPathComponent(rel)
    }

    @Test func emptyFilterExcludesNothing() {
        #expect(FolderFilter.empty.isExcluded(url("Archive")) == false)
        #expect(filter([]).isExcluded(url("Archive")) == false)
    }
    @Test func exactTopLevelMatch() {
        let f = filter(["Archive"])
        #expect(f.isExcluded(url("Archive")))
        #expect(f.isExcluded(url("Notes")) == false)
    }
    @Test func anchoredNotSubstring() {
        let f = filter(["Archive"])
        #expect(f.isExcluded(url("Notes/Archive")) == false)
        #expect(f.isExcluded(url("ArchiveOld")) == false)
    }
    @Test func nestedPathAndSubtree() {
        let f = filter(["Projects/Old Stuff"])
        #expect(f.isExcluded(url("Projects/Old Stuff")))
        #expect(f.isExcluded(url("Projects/Old Stuff/2024")))
        #expect(f.isExcluded(url("Projects")) == false)
    }
    @Test func caseInsensitiveAndNormalized() {
        #expect(filter(["Archive"]).isExcluded(url("archive")))
        #expect(filter([" ./Drafts/ "]).isExcluded(url("Drafts")))
    }
    @Test func rejectsEscapesAndEmpty() {
        // Behavioral: an invalid entry must not exclude a real sibling — `Secret`
        // would be excluded if the entry normalized, but "../Secret" / "" are
        // dropped, so a root-level `Secret` stays visible.
        #expect(filter(["../Secret"]).isExcluded(url("Secret")) == false)
        #expect(filter([""]).isExcluded(url("Secret")) == false)
    }

    @Test func normalizeEntryDropsInvalidAndFolds() {
        // Requirement #4: empty / vault-escaping entries are dropped outright.
        #expect(FolderFilter.normalizeEntry("") == nil)
        #expect(FolderFilter.normalizeEntry("   ") == nil)
        #expect(FolderFilter.normalizeEntry("/") == nil)
        #expect(FolderFilter.normalizeEntry("./") == nil)
        #expect(FolderFilter.normalizeEntry("../Secret") == nil)
        #expect(FolderFilter.normalizeEntry("a/../b") == nil)
        // Valid entries are slash-normalized, trimmed, and folded (NFC + lower).
        #expect(FolderFilter.normalizeEntry("Archive") == "archive")
        #expect(FolderFilter.normalizeEntry(" ./Projects/Old/ ") == "projects/old")
        #expect(FolderFilter.normalizeEntry("a//b\\c") == "a/b/c")
    }
    @Test func outsideRootIsNeverExcluded() {
        let f = filter(["Archive"], root: URL(fileURLWithPath: "/N"))
        #expect(f.isExcluded(URL(fileURLWithPath: "/Other/Archive")) == false)
    }

    @Test func childFoldersDropsExcluded() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ff-\(UUID().uuidString)")
        let keep = root.appendingPathComponent("Notes")
        let drop = root.appendingPathComponent("Archive")
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let f = FolderFilter(nexusRoot: root, excludedFolders: ["Archive"])
        let names = try Filesystem.childFolders(of: root, folderFilter: f)
            .map(\.lastPathComponent).sorted()
        #expect(names == ["Notes"])
        let all = try Filesystem.childFolders(of: root).map(\.lastPathComponent).sorted()
        #expect(all == ["Archive", "Notes"])
    }
}
