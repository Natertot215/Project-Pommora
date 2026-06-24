import Foundation
import Testing

@testable import Pommora

/// Regression coverage for the same-container name-collision data-loss bug:
/// creating or renaming a Page to a title a sibling already holds in the
/// SAME container would silently overwrite the other file's body. Locked
/// behavior: REJECT (no auto-rename, no overwrite) via the shared
/// `NameCollisionValidator`.
///
/// Filename = struct name (`NameCollisionTests`) so `-only-testing` actually
/// runs these (branch quirks #1 / #17).
@MainActor
@Suite("NameCollisionTests")
struct NameCollisionTests {

    // MARK: - Pages: collision REJECTED + sibling body PRESERVED

    @Test("createPage duplicate title in same Page Type (type-root) throws + original body survives")
    func pageCreateDuplicateInTypeRootPreservesBody() async throws {
        let (nexus, vault, manager) = try await setupPageTypeRoot()
        defer { TempNexus.cleanup(nexus) }

        // Original page + a real body written to disk.
        try await manager.createPage(name: "Notes", inVaultRoot: vault)
        let url = NexusPaths.pageFileURL(forTitle: "Notes", in: pageTypeFolder(nexus, vault))
        let original = manager.pages(in: vault).first { $0.title == "Notes" }!
        try await manager.updatePage(original, body: "PRECIOUS BODY", inVaultRoot: vault)

        // Colliding create must throw.
        await #expect(throws: PageCRUDError.duplicateTitle) {
            _ = try await manager.createPage(name: "Notes", inVaultRoot: vault)
        }

        // Original file's body must be intact (NOT clobbered) + still one page.
        let reloaded = try PageFile.load(from: url)
        #expect(reloaded.body == "PRECIOUS BODY")
        #expect(reloaded.frontmatter.id == original.id)
        #expect(manager.pages(in: vault).count == 1)
    }

    @Test("createPage duplicate title in same Page Collection throws + original body survives")
    func pageCreateDuplicateInCollectionPreservesBody() async throws {
        let (nexus, vault, coll, manager) = try await setupPageCollection()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let url = NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL)
        let original = manager.pages(inCollection: coll).first!
        try await manager.updatePage(original, body: "PRECIOUS BODY", in: coll, vault: vault)

        await #expect(throws: PageCRUDError.duplicateTitle) {
            _ = try await manager.createPage(name: "Notes", in: coll, vault: vault)
        }

        let reloaded = try PageFile.load(from: url)
        #expect(reloaded.body == "PRECIOUS BODY")
        #expect(reloaded.frontmatter.id == original.id)
        #expect(manager.pages(inCollection: coll).count == 1)
    }

    @Test("renamePage onto an existing sibling's title throws + both files intact")
    func pageRenameOntoSiblingRejected() async throws {
        let (nexus, vault, coll, manager) = try await setupPageCollection()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        try await manager.createPage(name: "Ideas", in: coll, vault: vault)
        let notes = manager.pages(inCollection: coll).first { $0.title == "Notes" }!
        let ideas = manager.pages(inCollection: coll).first { $0.title == "Ideas" }!
        try await manager.updatePage(notes, body: "NOTES BODY", in: coll, vault: vault)
        try await manager.updatePage(ideas, body: "IDEAS BODY", in: coll, vault: vault)

        // Rename "Ideas" → "Notes" (collides with the other page) must throw.
        await #expect(throws: PageCRUDError.duplicateTitle) {
            try await manager.renamePage(ideas, to: "Notes", in: coll, vault: vault)
        }

        // Both files survive with their original bodies + titles.
        let notesURL = NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL)
        let ideasURL = NexusPaths.pageFileURL(forTitle: "Ideas", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: notesURL.path))
        #expect(FileManager.default.fileExists(atPath: ideasURL.path))
        #expect(try PageFile.load(from: notesURL).body == "NOTES BODY")
        #expect(try PageFile.load(from: ideasURL).body == "IDEAS BODY")
        #expect(manager.pages(inCollection: coll).count == 2)
    }

    @Test("createPage collision is case-insensitive (Notes vs notes)")
    func pageCreateCaseInsensitiveRejected() async throws {
        let (nexus, vault, coll, manager) = try await setupPageCollection()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        await #expect(throws: PageCRUDError.duplicateTitle) {
            _ = try await manager.createPage(name: "notes", in: coll, vault: vault)
        }
        #expect(manager.pages(inCollection: coll).count == 1)
    }

    @Test("same Page title in DIFFERENT containers is allowed")
    func pageSameTitleDifferentContainersAllowed() async throws {
        let (nexus, vault, coll, manager) = try await setupPageCollection()
        defer { TempNexus.cleanup(nexus) }

        // One in the collection, one in the type-root — different containers.
        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        try await manager.createPage(name: "Notes", inVaultRoot: vault)

        #expect(manager.pages(inCollection: coll).count == 1)
        #expect(manager.pages(in: vault).count == 1)
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL).path))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Notes", in: pageTypeFolder(nexus, vault)).path
            ))
    }

    @Test("renamePage to its OWN current title does not throw")
    func pageRenameToOwnTitleAllowed() async throws {
        let (nexus, vault, coll, manager) = try await setupPageCollection()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        let page = manager.pages(inCollection: coll).first!
        try await manager.updatePage(page, body: "BODY", in: coll, vault: vault)

        // Renaming to the same title is a no-op rename — must NOT false-positive.
        try await manager.renamePage(page, to: "Notes", in: coll, vault: vault)

        let url = NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try PageFile.load(from: url).body == "BODY")
        #expect(manager.pages(inCollection: coll).count == 1)
    }

    @Test("renamePage case-only recase (notes → Notes) succeeds + recases file + body intact")
    func pageRenameCaseOnlyRecaseSucceeds() async throws {
        // FIX 1 regression: on a case-insensitive volume (APFS) a self-recase
        // resolves `fileExists(at:)` to the SAME underlying file; renameFile must
        // recase in place via moveItem, NOT throw destinationExists.
        let (nexus, vault, coll, manager) = try await setupPageCollection()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "notes", in: coll, vault: vault)
        let page = manager.pages(inCollection: coll).first { $0.title == "notes" }!
        try await manager.updatePage(page, body: "PRECIOUS BODY", in: coll, vault: vault)

        // Recase: lowercase → titlecase. Same entity, different-case title.
        try await manager.renamePage(page, to: "Notes", in: coll, vault: vault)

        // File is recased on disk (the stored filename now reads "Notes.md") and
        // the body survived the in-place move.
        let recasedURL = NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL)
        #expect(FileManager.default.fileExists(atPath: recasedURL.path))
        let onDiskName = try storedFilename(in: coll.folderURL, matching: "notes.md")
        #expect(onDiskName == "Notes.md")
        #expect(try PageFile.load(from: recasedURL).body == "PRECIOUS BODY")
        #expect(manager.pages(inCollection: coll).count == 1)
        #expect(manager.pages(inCollection: coll).first?.title == "Notes")
    }

    @Test("renamePage onto a DIFFERENT sibling whose title differs only in case still throws")
    func pageRenameOntoCaseVariantSiblingRejected() async throws {
        // Companion to FIX 1: a recase of one's OWN file is allowed, but renaming
        // onto a *different* sibling that happens to differ only in case is still
        // a collision and must throw (no clobber).
        let (nexus, vault, coll, manager) = try await setupPageCollection()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, vault: vault)
        try await manager.createPage(name: "Ideas", in: coll, vault: vault)
        let notes = manager.pages(inCollection: coll).first { $0.title == "Notes" }!
        let ideas = manager.pages(inCollection: coll).first { $0.title == "Ideas" }!
        try await manager.updatePage(notes, body: "NOTES BODY", in: coll, vault: vault)
        try await manager.updatePage(ideas, body: "IDEAS BODY", in: coll, vault: vault)

        // Rename "Ideas" → "notes" (case-variant of the OTHER page) must throw.
        await #expect(throws: PageCRUDError.duplicateTitle) {
            try await manager.renamePage(ideas, to: "notes", in: coll, vault: vault)
        }

        // Both originals intact.
        let notesURL = NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL)
        let ideasURL = NexusPaths.pageFileURL(forTitle: "Ideas", in: coll.folderURL)
        #expect(try PageFile.load(from: notesURL).body == "NOTES BODY")
        #expect(try PageFile.load(from: ideasURL).body == "IDEAS BODY")
        #expect(manager.pages(inCollection: coll).count == 2)
    }

    // MARK: - Shared validator: direct unit coverage

    @Test("NameCollisionValidator: trimmed + case-insensitive collision detection")
    func validatorDetectsCollision() throws {
        let siblings = [
            PageMeta(
                id: "A", title: "Notes",
                url: URL(fileURLWithPath: "/Notes.md"), frontmatter: Self.fm("A"))
        ]
        // Different id, same title (case + whitespace folded) → collision.
        #expect(throws: NameCollisionError.duplicateTitle) {
            try NameCollisionValidator.validate(
                desiredTitle: "  notes  ", siblings: siblings, excludingID: "B")
        }
        // Same id (self) → no collision (rename-to-own-title is fine).
        #expect(throws: Never.self) {
            try NameCollisionValidator.validate(
                desiredTitle: "Notes", siblings: siblings, excludingID: "A")
        }
        // Distinct title → no collision.
        #expect(throws: Never.self) {
            try NameCollisionValidator.validate(
                desiredTitle: "Ideas", siblings: siblings, excludingID: nil)
        }
    }

    // MARK: - Setup helpers

    /// Returns the *case-exact* filename actually stored in `folder` whose name
    /// case-insensitively matches `candidate`. `FileManager.fileExists` +
    /// URL.path are case-folding on APFS, so they can't tell `notes.md` from
    /// `Notes.md`; `contentsOfDirectory` returns the real on-disk case. Used to
    /// prove a recase physically renamed the file rather than no-op'ing.
    private func storedFilename(in folder: URL, matching candidate: String) throws -> String? {
        let entries = try FileManager.default.contentsOfDirectory(
            atPath: folder.path
        )
        return entries.first { $0.caseInsensitiveCompare(candidate) == .orderedSame }
    }

    private func pageTypeFolder(_ nexus: Nexus, _ vault: PageType) -> URL {
        NexusPaths.pageTypeFolderURL(in: nexus.rootURL, typeFolderName: vault.title)
    }

    private static func fm(_ id: String) -> PageFrontmatter {
        PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: Date())
    }

    private func setupPageCollection() async throws
        -> (Nexus, PageType, PageCollection, PageContentManager)
    {
        let nexus = try TempNexus.make()
        let vault = PageType(
            id: ULID.generate(), title: "V", icon: nil, properties: [], views: [], modifiedAt: Date())
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.collectionFolderURL(forTitle: "C", inVaultTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageCollection(
            id: ULID.generate(), typeID: vault.id, title: "C", folderURL: collFolder,
            modifiedAt: Date())

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, vault, coll, manager)
    }

    private func setupPageTypeRoot() async throws -> (Nexus, PageType, PageContentManager) {
        let nexus = try TempNexus.make()
        let vault = PageType(
            id: ULID.generate(), title: "V", icon: nil, properties: [], views: [], modifiedAt: Date())
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, vault, manager)
    }

}
