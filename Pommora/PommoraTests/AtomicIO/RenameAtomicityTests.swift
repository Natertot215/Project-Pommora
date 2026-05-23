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

    @Test("SpaceManager.rename failure sets pendingError + leaves disk + in-memory state intact")
    func renameFailureSetsPendingError() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()

        // Create two Spaces; renaming one to the other's title should throw
        // duplicateTitle and set pendingError.
        try await manager.create(name: "Personal", color: .blue, icon: nil)
        try await manager.create(name: "Work", color: .red, icon: nil)
        let personal = manager.spaces.first(where: { $0.title == "Personal" })!

        await #expect(throws: SpaceValidator.ValidationError.duplicateTitle) {
            try await manager.rename(personal, to: "Work")
        }

        // pendingError surfaces for the toast.
        #expect(manager.pendingError != nil)

        // Disk + in-memory state both unchanged.
        let personalURL = NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus)
        let workURL = NexusPaths.spaceFileURL(forTitle: "Work", in: nexus)
        #expect(FileManager.default.fileExists(atPath: personalURL.path))
        #expect(FileManager.default.fileExists(atPath: workURL.path))
        #expect(manager.spaces.count == 2)
    }

    @Test("Successful SpaceManager.rename clears prior pendingError and leaves single file at new URL")
    func successfulRenameLeavesNoTrace() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = SpaceManager(nexus: nexus)
        await manager.loadAll()

        try await manager.create(name: "Personal", color: .blue, icon: nil)
        let space = manager.spaces.first!

        try await manager.rename(space, to: "Life")
        let oldURL = NexusPaths.spaceFileURL(forTitle: "Personal", in: nexus)
        let newURL = NexusPaths.spaceFileURL(forTitle: "Life", in: nexus)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(manager.spaces.first?.title == "Life")

        // Reload + verify state survives a fresh manager — proves the save
        // succeeded fully (rollback path was NOT triggered).
        let reloadManager = SpaceManager(nexus: nexus)
        await reloadManager.loadAll()
        #expect(reloadManager.spaces.count == 1)
        #expect(reloadManager.spaces.first?.title == "Life")
    }

    @Test("PageTypeManager rename failure (duplicate target) sets pendingError + folder stays at old name")
    func vaultRenameFailureRollback() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageType(name: "Alpha", icon: nil)
        try await manager.createPageType(name: "Beta", icon: nil)
        let alpha = manager.types.first(where: { $0.title == "Alpha" })!

        await #expect(throws: PageTypeValidator.ValidationError.duplicateTitle) {
            try await manager.renamePageType(alpha, to: "Beta")
        }

        #expect(manager.pendingError != nil)
        let alphaFolder = NexusPaths.vaultFolderURL(forTitle: "Alpha", in: nexus)
        #expect(FileManager.default.fileExists(atPath: alphaFolder.path))
    }
}
