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
        let (nexus, collection, manager) = try await setupPageCollectionRoot()
        defer { TempNexus.cleanup(nexus) }

        // Original page + a real body written to disk.
        try await manager.createPage(name: "Notes", inCollectionRoot: collection)
        let url = NexusPaths.pageFileURL(forTitle: "Notes", in: pageTypeFolder(nexus, collection))
        let original = manager.pages(in: collection).first { $0.title == "Notes" }!
        try await manager.updatePage(original, body: "PRECIOUS BODY", inCollectionRoot: collection)

        // Colliding create must throw.
        await #expect(throws: PageCRUDError.duplicateTitle) {
            _ = try await manager.createPage(name: "Notes", inCollectionRoot: collection)
        }

        // Original file's body must be intact (NOT clobbered) + still one page.
        let reloaded = try PageFile.load(from: url)
        #expect(reloaded.body == "PRECIOUS BODY")
        #expect(reloaded.frontmatter.id == original.id)
        #expect(manager.pages(in: collection).count == 1)
    }

    @Test("createPage duplicate title in same Page Collection throws + original body survives")
    func pageCreateDuplicateInCollectionPreservesBody() async throws {
        let (nexus, collection, coll, manager) = try await setupPageSet()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        let url = NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL)
        let original = manager.pages(inCollection: coll).first!
        try await manager.updatePage(original, body: "PRECIOUS BODY", in: coll, pageCollection: collection)

        await #expect(throws: PageCRUDError.duplicateTitle) {
            _ = try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        }

        let reloaded = try PageFile.load(from: url)
        #expect(reloaded.body == "PRECIOUS BODY")
        #expect(reloaded.frontmatter.id == original.id)
        #expect(manager.pages(inCollection: coll).count == 1)
    }

    @Test("renamePage onto an existing sibling's title throws + both files intact")
    func pageRenameOntoSiblingRejected() async throws {
        let (nexus, collection, coll, manager) = try await setupPageSet()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        try await manager.createPage(name: "Ideas", in: coll, pageCollection: collection)
        let notes = manager.pages(inCollection: coll).first { $0.title == "Notes" }!
        let ideas = manager.pages(inCollection: coll).first { $0.title == "Ideas" }!
        try await manager.updatePage(notes, body: "NOTES BODY", in: coll, pageCollection: collection)
        try await manager.updatePage(ideas, body: "IDEAS BODY", in: coll, pageCollection: collection)

        // Rename "Ideas" → "Notes" (collides with the other page) must throw.
        await #expect(throws: PageCRUDError.duplicateTitle) {
            try await manager.renamePage(ideas, to: "Notes", in: coll, pageCollection: collection)
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
        let (nexus, collection, coll, manager) = try await setupPageSet()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        await #expect(throws: PageCRUDError.duplicateTitle) {
            _ = try await manager.createPage(name: "notes", in: coll, pageCollection: collection)
        }
        #expect(manager.pages(inCollection: coll).count == 1)
    }

    @Test("same Page title in DIFFERENT containers is allowed")
    func pageSameTitleDifferentContainersAllowed() async throws {
        let (nexus, collection, coll, manager) = try await setupPageSet()
        defer { TempNexus.cleanup(nexus) }

        // One in the collection, one in the type-root — different containers.
        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        try await manager.createPage(name: "Notes", inCollectionRoot: collection)

        #expect(manager.pages(inCollection: coll).count == 1)
        #expect(manager.pages(in: collection).count == 1)
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Notes", in: coll.folderURL).path))
        #expect(
            FileManager.default.fileExists(
                atPath: NexusPaths.pageFileURL(forTitle: "Notes", in: pageTypeFolder(nexus, collection)).path
            ))
    }

    @Test("renamePage to its OWN current title does not throw")
    func pageRenameToOwnTitleAllowed() async throws {
        let (nexus, collection, coll, manager) = try await setupPageSet()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        let page = manager.pages(inCollection: coll).first!
        try await manager.updatePage(page, body: "BODY", in: coll, pageCollection: collection)

        // Renaming to the same title is a no-op rename — must NOT false-positive.
        try await manager.renamePage(page, to: "Notes", in: coll, pageCollection: collection)

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
        let (nexus, collection, coll, manager) = try await setupPageSet()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "notes", in: coll, pageCollection: collection)
        let page = manager.pages(inCollection: coll).first { $0.title == "notes" }!
        try await manager.updatePage(page, body: "PRECIOUS BODY", in: coll, pageCollection: collection)

        // Recase: lowercase → titlecase. Same entity, different-case title.
        try await manager.renamePage(page, to: "Notes", in: coll, pageCollection: collection)

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
        let (nexus, collection, coll, manager) = try await setupPageSet()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "Notes", in: coll, pageCollection: collection)
        try await manager.createPage(name: "Ideas", in: coll, pageCollection: collection)
        let notes = manager.pages(inCollection: coll).first { $0.title == "Notes" }!
        let ideas = manager.pages(inCollection: coll).first { $0.title == "Ideas" }!
        try await manager.updatePage(notes, body: "NOTES BODY", in: coll, pageCollection: collection)
        try await manager.updatePage(ideas, body: "IDEAS BODY", in: coll, pageCollection: collection)

        // Rename "Ideas" → "notes" (case-variant of the OTHER page) must throw.
        await #expect(throws: PageCRUDError.duplicateTitle) {
            try await manager.renamePage(ideas, to: "notes", in: coll, pageCollection: collection)
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

    private func pageTypeFolder(_ nexus: Nexus, _ pageCollection: PageCollection) -> URL {
        NexusPaths.collectionFolderURL(in: nexus.rootURL, collectionFolderName: pageCollection.title)
    }

    private static func fm(_ id: String) -> PageFrontmatter {
        PageFrontmatter(
            id: id, icon: nil, tier1: [], tier2: [], tier3: [], properties: [:], createdAt: Date())
    }

    private func setupPageSet() async throws
        -> (Nexus, PageCollection, PageSet, PageContentManager)
    {
        let nexus = try TempNexus.make()
        let collection = PageCollection(
            id: ULID.generate(), title: "V", icon: nil, properties: [], views: [], modifiedAt: Date())
        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.setFolderURL(forTitle: "C", inCollectionTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageSet(
            id: ULID.generate(), parentID: collection.id, title: "C", folderURL: collFolder,
            modifiedAt: Date())

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, collection, coll, manager)
    }

    private func setupPageCollectionRoot() async throws -> (Nexus, PageCollection, PageContentManager) {
        let nexus = try TempNexus.make()
        let collection = PageCollection(
            id: ULID.generate(), title: "V", icon: nil, properties: [], views: [], modifiedAt: Date())
        let collectionFolder = NexusPaths.collectionFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: collectionFolder, withIntermediateDirectories: true)
        try collection.save(to: NexusPaths.collectionMetadataURL(forTitle: "V", in: nexus))

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, collection, manager)
    }

}
