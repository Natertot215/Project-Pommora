import Foundation
import Testing

@testable import Pommora

/// Covers `CoverAssetStore`: copy → nexus-relative path + file present;
/// collision-suffix loop; hard-cap throw.
@Suite("CoverAssetStoreTests")
struct CoverAssetStoreTests {

    @Test("storeCopiesFileAndReturnsNexusRelativePath")
    func storeCopiesFileAndReturnsNexusRelativePath() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let src = nexus.rootURL.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: src)

        let store = CoverAssetStore()
        let entityID = ULID.generate()
        let path = try await store.store(image: src, for: entityID, in: nexus)

        #expect(path == ".nexus/assets/\(entityID)/photo.png")

        let resolved = nexus.rootURL.appendingPathComponent(path)
        #expect(FileManager.default.fileExists(atPath: resolved.path))
    }

    @Test("collisionGetsDashTwoSuffix")
    func collisionGetsDashTwoSuffix() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let src = nexus.rootURL.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: src)

        let store = CoverAssetStore()
        let entityID = ULID.generate()

        let first = try await store.store(image: src, for: entityID, in: nexus)
        #expect(first == ".nexus/assets/\(entityID)/photo.png")

        let second = try await store.store(image: src, for: entityID, in: nexus)
        #expect(second == ".nexus/assets/\(entityID)/photo-2.png")

        let resolved = nexus.rootURL.appendingPathComponent(second)
        #expect(FileManager.default.fileExists(atPath: resolved.path))
    }

    @Test("hardCapAtOrAbove500MBThrows")
    func hardCapAtOrAbove500MBThrows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // 501 MB reported via a sparse file — exercises the guard without
        // writing the bytes.
        let src = try sparseFile(named: "huge.bin", sizeBytes: 501_000_000, in: nexus.rootURL)

        let store = CoverAssetStore()
        await #expect(
            throws: CoverAssetStore.CoverAssetError.exceedsSizeCap(sizeBytes: 501_000_000)
        ) {
            _ = try await store.store(image: src, for: ULID.generate(), in: nexus)
        }
    }

    @Test("missingSourceThrows")
    func missingSourceThrows() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let src = nexus.rootURL.appendingPathComponent("nope.png")
        let store = CoverAssetStore()
        await #expect(throws: CoverAssetStore.CoverAssetError.sourceNotFound) {
            _ = try await store.store(image: src, for: ULID.generate(), in: nexus)
        }
    }

    // MARK: - Helpers

    /// A file that *reports* `sizeBytes` without writing the bytes (sparse).
    private func sparseFile(named name: String, sizeBytes: Int, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(sizeBytes))
        return url
    }
}
