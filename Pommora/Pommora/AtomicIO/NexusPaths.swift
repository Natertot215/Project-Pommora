import Foundation

/// Pure path helpers for every on-disk file the paradigm uses.
/// No I/O except `ensureDirectoryExists`.
enum NexusPaths {

    // MARK: - Schema sidecar

    /// Unified schema sidecar filename — used by Page Types, Page Collections,
    /// Item Types, Item Collections, AgendaTask schema, AgendaEvent schema.
    /// Replaces per-kind names per ParadigmV2.
    static let schemaSidecarFilename = "_schema.json"

    // MARK: - Reserved top-level folder names (ParadigmV2 Phase 6)

    /// Reserved top-level folder names inside a Nexus root. These are wrapper
    /// folders for operational entity kinds (Pages, Items, Agenda) and are
    /// skipped by NexusAdopter when surveying legacy-shaped root folders for
    /// PageType adoption. Phase 10's user-data migration owns the relocation
    /// of legacy root-level type folders into `Pages/`.
    static let reservedTopLevelFolderNames: Set<String> = ["Pages", "Items", "Agenda"]

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
    /// Phase 6 form, taking the nexus root URL directly so callers without a
    /// fully-built Nexus value can still derive the path.
    static func agendaWrapperDir(in nexusRoot: URL) -> URL {
        nexusRoot.appendingPathComponent("Agenda", isDirectory: true)
    }

    /// Nexus-typed convenience overload — defers to the URL form.
    static func agendaWrapperDir(in nexus: Nexus) -> URL {
        agendaWrapperDir(in: nexus.rootURL)
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

    // MARK: - Pages wrapper / PageType / PageCollection / Content paths (ParadigmV2)

    /// `<nexus>/Pages/` — wrapper folder containing PageType sub-folders.
    /// PageTypeManager.loadAll surveys under this path; Phase 6 materializes it
    /// lazily on first load.
    static func pagesWrapperDir(in nexusRoot: URL) -> URL {
        nexusRoot.appendingPathComponent("Pages", isDirectory: true)
    }

    /// Nexus-typed convenience overload.
    static func pagesWrapperDir(in nexus: Nexus) -> URL {
        pagesWrapperDir(in: nexus.rootURL)
    }

    /// `<nexus>/Pages/<typeFolderName>/` — PageType folder.
    static func pageTypeFolderURL(in nexusRoot: URL, typeFolderName: String) -> URL {
        pagesWrapperDir(in: nexusRoot).appendingPathComponent(typeFolderName, isDirectory: true)
    }

    /// Nexus-typed convenience overload — bridges legacy `(forTitle:in:nexus:)` callers.
    static func pageTypeFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
        pageTypeFolderURL(in: nexus.rootURL, typeFolderName: title)
    }

    /// `<nexus>/Pages/<typeFolderName>/_schema.json` — PageType schema sidecar.
    static func pageTypeMetadataURL(in nexusRoot: URL, typeFolderName: String) -> URL {
        pageTypeFolderURL(in: nexusRoot, typeFolderName: typeFolderName)
            .appendingPathComponent(schemaSidecarFilename, isDirectory: false)
    }

    /// Nexus-typed convenience overload.
    static func pageTypeMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
        pageTypeMetadataURL(in: nexus.rootURL, typeFolderName: title)
    }

    /// `<nexus>/Pages/<typeFolderName>/<collectionFolderName>/` — PageCollection folder.
    static func pageCollectionFolderURL(
        in nexusRoot: URL,
        typeFolderName: String,
        collectionFolderName: String
    ) -> URL {
        pageTypeFolderURL(in: nexusRoot, typeFolderName: typeFolderName)
            .appendingPathComponent(collectionFolderName, isDirectory: true)
    }

    /// Nexus-typed convenience overload (legacy parameter shape).
    static func pageCollectionFolderURL(
        forTitle title: String,
        inPageTypeTitled pageTypeTitle: String,
        in nexus: Nexus
    ) -> URL {
        pageCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: pageTypeTitle,
            collectionFolderName: title
        )
    }

    /// `<nexus>/Pages/<typeFolderName>/<collectionFolderName>/_schema.json` — PageCollection schema sidecar.
    static func pageCollectionMetadataURL(
        in nexusRoot: URL,
        typeFolderName: String,
        collectionFolderName: String
    ) -> URL {
        pageCollectionFolderURL(
            in: nexusRoot,
            typeFolderName: typeFolderName,
            collectionFolderName: collectionFolderName
        )
        .appendingPathComponent(schemaSidecarFilename, isDirectory: false)
    }

    // MARK: - Legacy aliases (pre-ParadigmV2 vocabulary)
    //
    // Existing call sites still use `vaultFolderURL` / `vaultMetadataURL` /
    // `collectionFolderURL(forTitle:inVaultTitled:in:)`. Phase 6 redirects
    // them to the new `Pages/` wrapper so on-disk layout shifts in one step;
    // a follow-up rename pass will retire the legacy names. Keeping the
    // aliases here is the stub-and-progressively-replace seam.

    static func vaultFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
        pageTypeFolderURL(in: nexus.rootURL, typeFolderName: title)
    }

    static func vaultMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
        pageTypeMetadataURL(in: nexus.rootURL, typeFolderName: title)
    }

    static func collectionFolderURL(
        forTitle title: String,
        inVaultTitled vaultTitle: String,
        in nexus: Nexus
    ) -> URL {
        pageCollectionFolderURL(
            in: nexus.rootURL,
            typeFolderName: vaultTitle,
            collectionFolderName: title
        )
    }

    static func pageFileURL(forTitle title: String, in collectionFolder: URL) -> URL {
        collectionFolder.appendingPathComponent("\(title).md", isDirectory: false)
    }

    static func itemFileURL(forTitle title: String, in collectionFolder: URL) -> URL {
        collectionFolder.appendingPathComponent("\(title).json", isDirectory: false)
    }

    // MARK: - Items wrapper / ItemType / ItemCollection paths (ParadigmV2)

    /// `<nexus>/Items/` — wrapper folder containing ItemType sub-folders.
    /// Defined for Phase 6; Task 5.3 (Phase 5) only declares the helper —
    /// ItemTypeManager.loadAll reads under this path and currently returns
    /// empty until Phase 6 materializes the wrapper on disk. Stub-and-
    /// progressively-replace per branch quirk #8.
    static func itemsWrapperDir(in nexusRoot: URL) -> URL {
        nexusRoot.appendingPathComponent("Items", isDirectory: true)
    }

    /// `<nexus>/Items/<typeFolderName>/` — ItemType folder.
    static func itemTypeFolderURL(in nexusRoot: URL, typeFolderName: String) -> URL {
        itemsWrapperDir(in: nexusRoot).appendingPathComponent(typeFolderName, isDirectory: true)
    }

    /// `<nexus>/Items/<typeFolderName>/_schema.json` — ItemType schema sidecar.
    static func itemTypeMetadataURL(in nexusRoot: URL, typeFolderName: String) -> URL {
        itemTypeFolderURL(in: nexusRoot, typeFolderName: typeFolderName)
            .appendingPathComponent(schemaSidecarFilename, isDirectory: false)
    }

    /// `<nexus>/Items/<typeFolderName>/<collectionFolderName>/` — ItemCollection folder.
    static func itemCollectionFolderURL(
        in nexusRoot: URL,
        typeFolderName: String,
        collectionFolderName: String
    ) -> URL {
        itemTypeFolderURL(in: nexusRoot, typeFolderName: typeFolderName)
            .appendingPathComponent(collectionFolderName, isDirectory: true)
    }

    /// `<nexus>/Items/<typeFolderName>/<collectionFolderName>/_schema.json` — ItemCollection schema sidecar.
    static func itemCollectionMetadataURL(
        in nexusRoot: URL,
        typeFolderName: String,
        collectionFolderName: String
    ) -> URL {
        itemCollectionFolderURL(
            in: nexusRoot,
            typeFolderName: typeFolderName,
            collectionFolderName: collectionFolderName
        )
        .appendingPathComponent(schemaSidecarFilename, isDirectory: false)
    }

    // MARK: - Filesystem helper

    static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
