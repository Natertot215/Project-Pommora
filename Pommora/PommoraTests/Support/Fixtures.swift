import Foundation

@testable import Pommora

/// Shared entity builders for tests — sensible defaults, params only for the
/// fields a test varies.
enum Fixtures {

    // MARK: - Pages domain

    static func pageType(
        id: String = ULID.generate(),
        title: String = "Notes",
        icon: String? = nil,
        properties: [PropertyDefinition] = [],
        views: [SavedView] = [],
        modifiedAt: Date = Date()
    ) -> PageType {
        PageType(
            id: id, title: title, icon: icon,
            properties: properties, views: views, modifiedAt: modifiedAt
        )
    }

    static func pageCollection(
        id: String = ULID.generate(),
        typeID: String,
        title: String = "Archive",
        folderURL: URL? = nil,
        modifiedAt: Date = Date()
    ) -> PageCollection {
        PageCollection(
            id: id, typeID: typeID, title: title,
            folderURL: folderURL ?? dummyFolderURL(), modifiedAt: modifiedAt
        )
    }

    static func pageSet(
        id: String = ULID.generate(),
        collectionID: String,
        title: String = "Set",
        folderURL: URL? = nil,
        modifiedAt: Date = Date()
    ) -> PageSet {
        PageSet(
            id: id, collectionID: collectionID, title: title,
            folderURL: folderURL ?? dummyFolderURL(), modifiedAt: modifiedAt
        )
    }

    static func pageFrontmatter(
        id: String = ULID.generate(),
        icon: String? = nil,
        tier1: [String] = [], tier2: [String] = [], tier3: [String] = [],
        properties: [String: PropertyValue] = [:],
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) -> PageFrontmatter {
        PageFrontmatter(
            id: id, icon: icon,
            tier1: tier1, tier2: tier2, tier3: tier3,
            properties: properties,
            createdAt: createdAt, modifiedAt: modifiedAt
        )
    }

    static func pageMeta(
        id: String = ULID.generate(),
        title: String = "Hello",
        url: URL? = nil,
        frontmatter: PageFrontmatter? = nil
    ) -> PageMeta {
        PageMeta(
            id: id,
            title: title,
            url: url ?? URL(fileURLWithPath: "/tmp/\(id).md"),
            frontmatter: frontmatter ?? pageFrontmatter(id: id)
        )
    }

    // MARK: - Agenda domain

    static func agendaTask(
        id: String = ULID.generate(),
        title: String = "Buy milk",
        icon: String? = nil,
        description: String = "",
        dueAt: Date? = nil,
        dueFloating: Bool = false,
        dueAllDay: Bool = false,
        startAt: Date? = nil,
        completed: Bool = false,
        completedAt: Date? = nil,
        priority: Int = 0,
        recurrence: Recurrence? = nil,
        alarmOffsets: [TimeInterval] = [],
        calendarID: String? = nil,
        eventkitUUID: String? = nil,
        tier1: [String] = [], tier2: [String] = [], tier3: [String] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        properties: [String: PropertyValue] = [:]
    ) -> AgendaTask {
        AgendaTask(
            id: id, title: title, icon: icon, description: description,
            dueAt: dueAt, dueFloating: dueFloating, dueAllDay: dueAllDay,
            startAt: startAt, completed: completed, completedAt: completedAt,
            priority: priority, recurrence: recurrence, alarmOffsets: alarmOffsets,
            calendarID: calendarID, eventkitUUID: eventkitUUID,
            tier1: tier1, tier2: tier2, tier3: tier3,
            createdAt: createdAt, modifiedAt: modifiedAt, properties: properties
        )
    }

    static func agendaEvent(
        id: String = ULID.generate(),
        title: String = "Standup",
        icon: String? = nil,
        description: String = "",
        startAt: Date = Date(),
        endAt: Date = Date().addingTimeInterval(1800),
        allDay: Bool = false,
        location: String? = nil,
        recurrence: Recurrence? = nil,
        alarmOffsets: [TimeInterval] = [],
        alarmAbsolute: [Date] = [],
        calendarID: String? = nil,
        eventkitUUID: String? = nil,
        tier1: [String] = [], tier2: [String] = [], tier3: [String] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        properties: [String: PropertyValue] = [:]
    ) -> AgendaEvent {
        AgendaEvent(
            id: id, title: title, icon: icon, description: description,
            startAt: startAt, endAt: endAt, allDay: allDay,
            location: location, recurrence: recurrence,
            alarmOffsets: alarmOffsets, alarmAbsolute: alarmAbsolute,
            calendarID: calendarID, eventkitUUID: eventkitUUID,
            tier1: tier1, tier2: tier2, tier3: tier3,
            createdAt: createdAt, modifiedAt: modifiedAt, properties: properties
        )
    }

    // MARK: - Filesystem + index

    /// Writes a `.md` Page (frontmatter + body) into `collectionFolder`, returning
    /// its URL. Defaults to a minimal frontmatter when none is supplied.
    @discardableResult
    static func writePage(
        title: String,
        in collectionFolder: URL,
        frontmatter: PageFrontmatter? = nil,
        body: String = ""
    ) throws -> URL {
        let url = NexusPaths.pageFileURL(forTitle: title, in: collectionFolder)
        try AtomicYAMLMarkdown.write(frontmatter: frontmatter ?? pageFrontmatter(), body: body, to: url)
        return url
    }

    /// Opens (creating if needed) the SQLite index at the nexus root.
    static func index(at nexus: Nexus) throws -> PommoraIndex {
        try PommoraIndex.open(at: nexus.rootURL).0
    }

    // MARK: - Internals

    private static func dummyFolderURL() -> URL {
        URL(fileURLWithPath: "/tmp/pommora-fixture-\(UUID().uuidString)")
    }
}
