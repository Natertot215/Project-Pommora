import Foundation
import Testing

@testable import Pommora

/// Verifies that deleting an entity cascades to its `.nexus/attachments/<id>/`
/// folder — moving it to the per-nexus trash. One test per entity type.
@MainActor
@Suite("AttachmentCascade")
struct AttachmentCascadeTests {

    // MARK: - Page (collection-scoped)

    @Test("deletePage cascades attachments folder to trash")
    func deletePageCascadesAttachments() async throws {
        let (nexus, vault, coll, manager) = try await setupPage()
        defer { TempNexus.cleanup(nexus) }

        try await manager.createPage(name: "MyCascadePage", in: coll, vault: vault)
        guard let page = manager.pages(inCollection: coll).first else {
            Issue.record("Page not created")
            return
        }

        let attachDir = NexusPaths.attachmentsDir(for: page.id, in: nexus.rootURL)
        try FileManager.default.createDirectory(at: attachDir, withIntermediateDirectories: true)
        let dummyFile = attachDir.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: dummyFile)
        #expect(FileManager.default.fileExists(atPath: attachDir.path))

        try await manager.deletePage(page, inCollection: coll)

        #expect(!FileManager.default.fileExists(atPath: attachDir.path))

        // Attachments folder landed in trash.
        let trashRoot = NexusPaths.trashDir(in: nexus)
        let trashAttachments = trashRoot
            .appendingPathComponent(".nexus/attachments/\(page.id)")
        #expect(FileManager.default.fileExists(atPath: trashAttachments.path))
    }

    // MARK: - AgendaTask

    @Test("deleteTask cascades attachments folder to trash")
    func deleteTaskCascadesAttachments() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaTaskManager(nexus: nexus)
        await manager.loadAll()

        let taskID = ULID.generate()
        let task = AgendaTask(
            id: taskID, title: "CascadeTask", icon: nil,
            description: "",
            dueAt: nil, dueFloating: false, dueAllDay: false,
            startAt: nil,
            completed: false, completedAt: nil,
            priority: 0,
            recurrence: nil,
            alarmOffsets: [],
            calendarID: nil, eventkitUUID: nil,
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: ["type": .select("Task")]
        )
        try await manager.createTask(task)

        let attachDir = NexusPaths.attachmentsDir(for: taskID, in: nexus.rootURL)
        try FileManager.default.createDirectory(at: attachDir, withIntermediateDirectories: true)
        try Data("attachment".utf8).write(to: attachDir.appendingPathComponent("file.txt"))
        #expect(FileManager.default.fileExists(atPath: attachDir.path))

        try await manager.deleteTask(task)

        #expect(!FileManager.default.fileExists(atPath: attachDir.path))

        let trashAttachments = NexusPaths.trashDir(in: nexus)
            .appendingPathComponent(".nexus/attachments/\(taskID)")
        #expect(FileManager.default.fileExists(atPath: trashAttachments.path))
    }

    // MARK: - AgendaEvent

    @Test("deleteEvent cascades attachments folder to trash")
    func deleteEventCascadesAttachments() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }
        let manager = AgendaEventManager(nexus: nexus)
        await manager.loadAll()

        let eventID = ULID.generate()
        let event = AgendaEvent(
            id: eventID, title: "CascadeEvent", icon: nil,
            description: "",
            startAt: Date(timeIntervalSince1970: 1_716_480_000),
            endAt: Date(timeIntervalSince1970: 1_716_483_600),
            allDay: false,
            location: nil, recurrence: nil,
            alarmOffsets: [], alarmAbsolute: [],
            calendarID: nil, eventkitUUID: nil,
            tier1: [], tier2: [], tier3: [],
            createdAt: Date(), modifiedAt: Date(),
            properties: ["type": .select("Event")]
        )
        try await manager.createEvent(event)

        let attachDir = NexusPaths.attachmentsDir(for: eventID, in: nexus.rootURL)
        try FileManager.default.createDirectory(at: attachDir, withIntermediateDirectories: true)
        try Data("attachment".utf8).write(to: attachDir.appendingPathComponent("invite.pdf"))
        #expect(FileManager.default.fileExists(atPath: attachDir.path))

        try await manager.deleteEvent(event)

        #expect(!FileManager.default.fileExists(atPath: attachDir.path))

        let trashAttachments = NexusPaths.trashDir(in: nexus)
            .appendingPathComponent(".nexus/attachments/\(eventID)")
        #expect(FileManager.default.fileExists(atPath: trashAttachments.path))
    }

    // MARK: - Setup helpers

    private func setupPage() async throws -> (Nexus, PageType, PageCollection, PageContentManager) {
        let nexus = try TempNexus.make()
        let vault = PageType(
            id: ULID.generate(), title: "V", icon: nil,
            properties: [], views: [], modifiedAt: Date())
        let vaultFolder = NexusPaths.vaultFolderURL(forTitle: "V", in: nexus)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try vault.save(to: NexusPaths.vaultMetadataURL(forTitle: "V", in: nexus))

        let collFolder = NexusPaths.collectionFolderURL(forTitle: "C", inVaultTitled: "V", in: nexus)
        try FileManager.default.createDirectory(at: collFolder, withIntermediateDirectories: true)
        let coll = PageCollection(
            id: ULID.generate(),
            typeID: vault.id,
            title: "C",
            folderURL: collFolder,
            modifiedAt: Date()
        )

        let manager = PageContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, vault, coll, manager)
    }
}
