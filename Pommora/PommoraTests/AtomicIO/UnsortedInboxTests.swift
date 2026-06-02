import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("Filesystem.moveToUnsorted")
struct UnsortedInboxTests {

    @Test("relocates a file from inside the nexus into .unsorted/")
    func relocatesIntoUnsorted() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let source = nexus.rootURL.appendingPathComponent("Stray.md")
        try "homeless".write(to: source, atomically: true, encoding: .utf8)

        let dest = try Filesystem.moveToUnsorted(source, nexusRoot: nexus.rootURL)

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(dest.path.contains("/.unsorted/Stray.md"))
    }

    @Test("preserves relative path under the nexus root")
    func preservesRelativePath() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let typeFolder = nexus.rootURL.appendingPathComponent("Recipes")
        try FileManager.default.createDirectory(at: typeFolder, withIntermediateDirectories: true)
        let source = typeFolder.appendingPathComponent("Stray.md")
        try "mismatched class".write(to: source, atomically: true, encoding: .utf8)

        let dest = try Filesystem.moveToUnsorted(source, nexusRoot: nexus.rootURL)

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(dest.path.contains("/.unsorted/Recipes/Stray.md"))
    }

    @Test("second move of same path gets a timestamp suffix")
    func collisionAddsTimestampSuffix() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let path = nexus.rootURL.appendingPathComponent("Stray.md")

        try "first".write(to: path, atomically: true, encoding: .utf8)
        let first = try Filesystem.moveToUnsorted(path, nexusRoot: nexus.rootURL)

        try "second".write(to: path, atomically: true, encoding: .utf8)
        let second = try Filesystem.moveToUnsorted(path, nexusRoot: nexus.rootURL)

        #expect(first != second)
        #expect(first.lastPathComponent == "Stray.md")
        #expect(second.lastPathComponent.hasPrefix("Stray."))
        #expect(second.lastPathComponent.hasSuffix(".md"))
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test("rejects a source outside the nexus")
    func rejectsExternalSource() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).md")
        try "data".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        #expect {
            _ = try Filesystem.moveToUnsorted(outside, nexusRoot: nexus.rootURL)
        } throws: { error in
            guard case FilesystemError.sourceNotInNexus = error else { return false }
            return true
        }
    }

    @Test(".unsorted contents are excluded from descendantFiles")
    func unsortedExcludedFromDescendantFiles() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // A live file that descendantFiles SHOULD find.
        let live = nexus.rootURL.appendingPathComponent("Live.md")
        try "live".write(to: live, atomically: true, encoding: .utf8)

        // A file relocated into .unsorted that descendantFiles must NOT find.
        let stray = nexus.rootURL.appendingPathComponent("Stray.md")
        try "stray".write(to: stray, atomically: true, encoding: .utf8)
        let buried = try Filesystem.moveToUnsorted(stray, nexusRoot: nexus.rootURL)

        let found = try Filesystem.descendantFiles(of: nexus.rootURL) {
            $0.pathExtension == "md"
        }
        let foundPaths = Set(found.map { $0.standardizedFileURL.path })

        #expect(foundPaths.contains(live.standardizedFileURL.path))
        #expect(!foundPaths.contains(buried.standardizedFileURL.path))
    }
}
