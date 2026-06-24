import Foundation
import Testing

@testable import Pommora

@MainActor
@Suite("Filesystem.moveToTrash")
struct FilesystemTrashTests {

    @Test("moves a single file preserving relative path")
    func movesFile() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let source = nexus.rootURL.appendingPathComponent("Notes.md")
        try "hello".write(to: source, atomically: true, encoding: .utf8)

        let dest = try Filesystem.moveToTrash(source, in: nexus)

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(dest.path.contains("/.trash/Notes.md"))
    }

    @Test("moves a folder preserving relative path")
    func movesFolder() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let collection = nexus.rootURL.appendingPathComponent("Materials")
        try FileManager.default.createDirectory(at: collection, withIntermediateDirectories: true)
        let nested = collection.appendingPathComponent("Notes.md")
        try "data".write(to: nested, atomically: true, encoding: .utf8)

        let dest = try Filesystem.moveToTrash(collection, in: nexus)

        #expect(!FileManager.default.fileExists(atPath: collection.path))
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(dest.path.contains("/.trash/Materials"))
        let restoredNote = dest.appendingPathComponent("Notes.md")
        #expect(FileManager.default.fileExists(atPath: restoredNote.path))
    }

    @Test("second delete of same path gets timestamp suffix")
    func collisionAddsTimestampSuffix() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let path = nexus.rootURL.appendingPathComponent("Notes.md")

        try "first".write(to: path, atomically: true, encoding: .utf8)
        let first = try Filesystem.moveToTrash(path, in: nexus)

        try "second".write(to: path, atomically: true, encoding: .utf8)
        let second = try Filesystem.moveToTrash(path, in: nexus)

        #expect(first != second)
        #expect(first.lastPathComponent == "Notes.md")
        #expect(second.lastPathComponent.hasPrefix("Notes."))
        #expect(second.lastPathComponent.hasSuffix(".md"))
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test("rejects source outside the nexus")
    func rejectsExternalSource() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).md")
        try "data".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        #expect {
            _ = try Filesystem.moveToTrash(outside, in: nexus)
        } throws: { error in
            guard case FilesystemError.sourceNotInNexus = error else { return false }
            return true
        }
    }
}
