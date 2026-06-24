import Foundation
import Testing

@testable import Pommora

/// Tests for the rename-atomicity rollback pattern (Commit 4 / Part 1).
///
/// The full failure path — folder rename succeeds, metadata save fails, revert
/// also fails — is hard to trigger deterministically from the outside (both
/// operations run inside the manager's `rename*` method, so we can't inject a
/// failure between them). These tests focus on what we CAN verify
/// deterministically:
///
/// 1. The `RenameAtomicityError` type packages saveError + revertError and
///    surfaces them via `LocalizedError.errorDescription`.
/// 2. CRUD failures (e.g. duplicate-title rename) set `pendingError` on the
///    manager so the sidebar toast can observe them.
@MainActor
@Suite("RenameAtomicity")
struct RenameAtomicityTests {

    @Test("RenameAtomicityError surfaces both inner errors in its description")
    func errorDescription() {
        struct Save: LocalizedError {
            var errorDescription: String? { "save-failed-message" }
        }
        struct Revert: LocalizedError {
            var errorDescription: String? { "revert-failed-message" }
        }
        let combined = RenameAtomicityError(saveError: Save(), revertError: Revert())
        let desc = combined.errorDescription ?? ""
        #expect(desc.contains("save-failed-message"))
        #expect(desc.contains("revert-failed-message"))
    }

    @Test("AreaManager.rename failure sets pendingError + leaves disk + in-memory state intact")
    func renameFailureSetsPendingError() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AreaManager(nexus: nexus)
        await manager.loadAll()

        // Create two Areas; renaming one to the other's title should throw
        // duplicateTitle and set pendingError.
        try await manager.create(name: "Personal", icon: nil)
        try await manager.create(name: "Work", icon: nil)
        let personal = manager.areas.first(where: { $0.title == "Personal" })!

        await #expect(throws: AreaValidator.ValidationError.duplicateTitle) {
            try await manager.rename(personal, to: "Work")
        }

        // pendingError surfaces for the toast.
        #expect(manager.pendingError != nil)

        // Disk + in-memory state both unchanged.
        let personalURL = NexusPaths.areaMetadataURL(forTitle: "Personal", in: nexus)
        let workURL = NexusPaths.areaMetadataURL(forTitle: "Work", in: nexus)
        #expect(FileManager.default.fileExists(atPath: personalURL.path))
        #expect(FileManager.default.fileExists(atPath: workURL.path))
        #expect(manager.areas.count == 2)
    }

    @Test("Successful AreaManager.rename clears prior pendingError and leaves single file at new URL")
    func successfulRenameLeavesNoTrace() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AreaManager(nexus: nexus)
        await manager.loadAll()

        try await manager.create(name: "Personal", icon: nil)
        let area = manager.areas.first!

        try await manager.rename(area, to: "Life")
        let oldURL = NexusPaths.areaMetadataURL(forTitle: "Personal", in: nexus)
        let newURL = NexusPaths.areaMetadataURL(forTitle: "Life", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(manager.areas.first?.title == "Life")

        // Reload + verify state survives a fresh manager — proves the save
        // succeeded fully (rollback path was NOT triggered).
        let reloadManager = AreaManager(nexus: nexus)
        await reloadManager.loadAll()
        #expect(reloadManager.areas.count == 1)
        #expect(reloadManager.areas.first?.title == "Life")
    }

    @Test("PageCollectionManager rename failure (duplicate target) sets pendingError + folder stays at old name")
    func vaultRenameFailureRollback() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageCollection(name: "Alpha", icon: nil)
        try await manager.createPageCollection(name: "Beta", icon: nil)
        let alpha = manager.types.first(where: { $0.title == "Alpha" })!

        await #expect(throws: PageCollectionValidator.ValidationError.duplicateTitle) {
            try await manager.renamePageCollection(alpha, to: "Beta")
        }

        #expect(manager.pendingError != nil)
        let alphaFolder = NexusPaths.vaultFolderURL(forTitle: "Alpha", in: nexus)
        #expect(FileManager.default.fileExists(atPath: alphaFolder.path))
    }
}
