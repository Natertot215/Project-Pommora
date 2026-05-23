import Foundation

/// Pure path helpers for every on-disk file the paradigm uses.
/// No I/O except `ensureDirectoryExists`.
enum NexusPaths {

    // MARK: - Schema sidecar

    /// Unified schema sidecar filename — used by Page Types, Page Collections,
    /// Item Types, Item Collections, AgendaTask schema, AgendaEvent schema.
    /// Replaces per-kind names per ParadigmV2.
    static let schemaSidecarFilename = "_schema.json"

    // MARK: - .nexus/ subdirectories

    static func nexusConfigDir(in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent(".nexus", isDirectory: true)
    }

    static func spacesDir(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("spaces", isDirectory: true)
    }

    static func topicsDir(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("topics", isDirectory: true)
    }

    // MARK: - Single-file paths inside .nexus/

    static func tierConfigURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("tier-config.json", isDirectory: false)
    }

    static func savedConfigURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("saved-config.json", isDirectory: false)
    }

    /// `<nexus>/.nexus/state.json` — per-nexus app state (NavDropdown
    /// Recents/Pinned for v0.2.7.2.1; future per-nexus state lands here).
    static func nexusStateURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("state.json", isDirectory: false)
    }

    static func homepageURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("homepage.json", isDirectory: false)
    }

    // MARK: - Agenda (operational sibling of Pages/Items wrappers)

    /// File extension for Agenda Tasks: `<title>.task.json`.
    static let taskFileExtension = "task.json"
    /// File extension for Agenda Events: `<title>.event.json`.
    static let eventFileExtension = "event.json"

    /// `<nexus>/Agenda/` — wrapper folder containing `Tasks/` and `Events/`.
    static func agendaWrapperDir(in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent("Agenda", isDirectory: true)
    }

    /// `<nexus>/Agenda/Tasks/` — holds `_schema.json` + `<title>.task.json` files.
    static func tasksDir(in nexus: Nexus) -> URL {
        agendaWrapperDir(in: nexus).appendingPathComponent("Tasks", isDirectory: true)
    }

    /// `<nexus>/Agenda/Events/` — holds `_schema.json` + `<title>.event.json` files.
    static func eventsDir(in nexus: Nexus) -> URL {
        agendaWrapperDir(in: nexus).appendingPathComponent("Events", isDirectory: true)
    }

    /// `<nexus>/Agenda/Tasks/_schema.json` — AgendaTaskSchema sidecar.
    static func taskSchemaURL(in nexus: Nexus) -> URL {
        tasksDir(in: nexus).appendingPathComponent(schemaSidecarFilename, isDirectory: false)
    }

    /// `<nexus>/Agenda/Events/_schema.json` — AgendaEventSchema sidecar.
    static func eventSchemaURL(in nexus: Nexus) -> URL {
        eventsDir(in: nexus).appendingPathComponent(schemaSidecarFilename, isDirectory: false)
    }

    /// `<nexus>/Agenda/Tasks/<title>.task.json` — single AgendaTask file.
    static func taskFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        tasksDir(in: nexus)
            .appendingPathComponent("\(title).\(taskFileExtension)", isDirectory: false)
    }

    /// `<nexus>/Agenda/Events/<title>.event.json` — single AgendaEvent file.
    static func eventFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        eventsDir(in: nexus)
            .appendingPathComponent("\(title).\(eventFileExtension)", isDirectory: false)
    }

    // MARK: - Trash (per-nexus recoverable deletes)

    /// Per-nexus trash folder at `<nexus-root>/.trash/`.
    /// Mirrors the structure of the user's content folders — a deleted Page at
    /// `Materials/Notes.md` lands at `.trash/Materials/Notes.md`. Collisions
    /// resolved via timestamp suffix in `Filesystem.moveToTrash`.
    static func trashDir(in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent(".trash", isDirectory: true)
    }

    // MARK: - Contexts file paths

    static func spaceFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        spacesDir(in: nexus).appendingPathComponent("\(title).space.json", isDirectory: false)
    }

    static func topicFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
        topicsDir(in: nexus).appendingPathComponent(title, isDirectory: true)
    }

    static func topicMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
        topicFolderURL(forTitle: title, in: nexus)
            .appendingPathComponent("_topic.json", isDirectory: false)
    }

    static func projectFileURL(
        forTitle title: String,
        inTopicTitled topicTitle: String,
        in nexus: Nexus
    ) -> URL {
        topicFolderURL(forTitle: topicTitle, in: nexus)
            .appendingPathComponent("\(title).project.json", isDirectory: false)
    }

    // MARK: - Vault / Collection / Content paths

    static func vaultFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent(title, isDirectory: true)
    }

    static func vaultMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
        vaultFolderURL(forTitle: title, in: nexus)
            .appendingPathComponent(schemaSidecarFilename, isDirectory: false)
    }

    static func collectionFolderURL(
        forTitle title: String,
        inVaultTitled vaultTitle: String,
        in nexus: Nexus
    ) -> URL {
        vaultFolderURL(forTitle: vaultTitle, in: nexus)
            .appendingPathComponent(title, isDirectory: true)
    }

    static func pageFileURL(forTitle title: String, in collectionFolder: URL) -> URL {
        collectionFolder.appendingPathComponent("\(title).md", isDirectory: false)
    }

    static func itemFileURL(forTitle title: String, in collectionFolder: URL) -> URL {
        collectionFolder.appendingPathComponent("\(title).json", isDirectory: false)
    }

    // MARK: - Filesystem helper

    static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
