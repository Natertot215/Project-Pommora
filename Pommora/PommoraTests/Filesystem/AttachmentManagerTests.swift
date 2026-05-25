import Foundation
import Testing

@testable import Pommora

@Suite("AttachmentManager")
struct AttachmentManagerTests {

    // MARK: - Happy path

    @Test("attachCopiesFileToEntityScopedFolder")
    func attachCopiesFileToEntityScopedFolder() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Write a small source file.
        let src = nexus.rootURL.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: src)  // PNG magic bytes

        let manager = AttachmentManager()
        let entityID = ULID.generate()
        let ref = try await manager.attach(
            file: src, to: entityID, nexusRoot: nexus.rootURL
        )

        // Destination file exists.
        let expectedDest = NexusPaths.attachmentsDir(for: entityID, in: nexus.rootURL)
            .appendingPathComponent("photo.png")
        #expect(FileManager.default.fileExists(atPath: expectedDest.path))

        // FileRef path is nexus-relative POSIX.
        #expect(ref.path == ".nexus/attachments/\(entityID)/photo.png")
        #expect(ref.originalName == "photo.png")
        #expect(!ref.mimeType.isEmpty)
    }

    // MARK: - Size enforcement

    @Test("attachWarnsAbove50MB")
    func attachWarnsAbove50MB() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let src = try sparseFile(named: "big.bin", sizeBytes: 60_000_000, in: nexus.rootURL)

        let manager = AttachmentManager()
        await #expect(
            throws: AttachmentManager.AttachmentError.sizeWarningRequired(sizeBytes: 60_000_000)
        ) {
            _ = try await manager.attach(
                file: src, to: ULID.generate(), nexusRoot: nexus.rootURL,
                requireConfirmation: true
            )
        }
    }

    @Test("attachWithConfirmedSkipsWarn")
    func attachWithConfirmedSkipsWarn() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let src = try sparseFile(named: "big.bin", sizeBytes: 60_000_000, in: nexus.rootURL)

        let manager = AttachmentManager()
        let entityID = ULID.generate()
        // requireConfirmation: false → no warning, attach succeeds.
        let ref = try await manager.attach(
            file: src, to: entityID, nexusRoot: nexus.rootURL,
            requireConfirmation: false
        )
        #expect(ref.path == ".nexus/attachments/\(entityID)/big.bin")
    }

    @Test("attachRejectsAbove500MB")
    func attachRejectsAbove500MB() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // 501 MB — over the hard cap.
        let src = try sparseFile(named: "huge.bin", sizeBytes: 501_000_000, in: nexus.rootURL)

        let manager = AttachmentManager()
        // Hard cap always throws, regardless of requireConfirmation.
        await #expect(
            throws: AttachmentManager.AttachmentError.exceedsSizeCap(sizeBytes: 501_000_000)
        ) {
            _ = try await manager.attach(
                file: src, to: ULID.generate(), nexusRoot: nexus.rootURL,
                requireConfirmation: false
            )
        }
    }

    // MARK: - Accept-list filtering

    @Test("acceptListRejectsMismatch")
    func acceptListRejectsMismatch() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let src = nexus.rootURL.appendingPathComponent("doc.pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: src)  // %PDF magic

        let manager = AttachmentManager()
        let accept = ["image/*"]
        await #expect(
            throws: AttachmentManager.AttachmentError.self
        ) {
            _ = try await manager.attach(
                file: src, to: ULID.generate(), nexusRoot: nexus.rootURL,
                accept: accept
            )
        }
    }

    @Test("acceptListAllowsWildcard")
    func acceptListAllowsWildcard() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let src = nexus.rootURL.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: src)

        let manager = AttachmentManager()
        let entityID = ULID.generate()
        let ref = try await manager.attach(
            file: src, to: entityID, nexusRoot: nexus.rootURL,
            accept: ["image/*"]
        )
        #expect(ref.path.contains(entityID))
        #expect(ref.mimeType.hasPrefix("image/"))
    }

    // MARK: - Collision avoidance

    @Test("collisionSafeFilenameSuffix")
    func collisionSafeFilenameSuffix() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let src = nexus.rootURL.appendingPathComponent("report.pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: src)

        let manager = AttachmentManager()
        let entityID = ULID.generate()

        // First attach — lands as "report.pdf".
        let ref1 = try await manager.attach(
            file: src, to: entityID, nexusRoot: nexus.rootURL
        )
        #expect(ref1.path.hasSuffix("/report.pdf"))

        // Second attach of the same filename — gets "-2" suffix.
        let ref2 = try await manager.attach(
            file: src, to: entityID, nexusRoot: nexus.rootURL
        )
        #expect(ref2.path.hasSuffix("/report-2.pdf"))
        #expect(ref1.path != ref2.path)

        // Both files exist.
        let dir = NexusPaths.attachmentsDir(for: entityID, in: nexus.rootURL)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("report.pdf").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("report-2.pdf").path))
    }

    // MARK: - Source-not-found

    @Test("attachThrowsSourceNotFound")
    func attachThrowsSourceNotFound() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let missing = nexus.rootURL.appendingPathComponent("ghost.txt")
        let manager = AttachmentManager()

        await #expect(throws: AttachmentManager.AttachmentError.sourceNotFound) {
            _ = try await manager.attach(
                file: missing, to: ULID.generate(), nexusRoot: nexus.rootURL
            )
        }
    }

    // MARK: - Helpers

    /// Creates a sparse (or zero-filled) file of exactly `sizeBytes` without
    /// allocating all that memory. Uses `FileHandle.truncate(atOffset:)` which
    /// punches a hole on APFS — fast, near-zero disk use.
    private func sparseFile(named name: String, sizeBytes: Int, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(sizeBytes))
        return url
    }
}
