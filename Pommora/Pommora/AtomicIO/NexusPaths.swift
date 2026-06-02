import Foundation

/// Pure path helpers for every on-disk file the paradigm uses.
/// No I/O except `ensureDirectoryExists`.
enum NexusPaths {

    // MARK: - Per-kind sidecar filenames (flatlayout)

    /// `_pagetype.json` — PageType folder sidecar.
    static let pageTypeSidecarFilename = "_pagetype.json"
    /// `_pagecollection.json` — PageCollection sub-folder sidecar.
    static let pageCollectionSidecarFilename = "_pagecollection.json"
    /// `_itemtype.json` — ItemType folder sidecar.
    static let itemTypeSidecarFilename = "_itemtype.json"
    /// `_itemcollection.json` — ItemCollection sub-folder sidecar.
    static let itemCollectionSidecarFilename = "_itemcollection.json"
    /// `_taskconfig.json` — Tasks singleton sidecar (AgendaTask schema).
    static let taskConfigSidecarFilename = "_taskconfig.json"
    /// `_eventconfig.json` — Events singleton sidecar (AgendaEvent schema).
    static let eventConfigSidecarFilename = "_eventconfig.json"

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

    /// `<nexus>/.nexus/settings.json` — per-Nexus user preferences (Phase 7).
    /// Loaded by SettingsManager; seeded with `Settings.defaultSeed()` on first
    /// launch when no file is present.
    static func settingsFileURL(in nexus: Nexus) -> URL {
        nexusConfigDir(in: nexus).appendingPathComponent("settings.json", isDirectory: false)
    }

    // MARK: - Agenda (sidecar-driven singleton discovery)

    /// File extension for Agenda Tasks: `<title>.task.json`.
    static let taskFileExtension = "task.json"
    /// File extension for Agenda Events: `<title>.event.json`.
    static let eventFileExtension = "event.json"

    /// Default folder name for the Tasks singleton when no folder carrying
    /// `_taskconfig.json` has been seeded yet. Adopter / manager use this as
    /// the seed-target name; once the sidecar exists the folder can be renamed
    /// freely via Finder and discovery keeps working.
    static let defaultTasksFolderName = "Tasks"
    /// Default folder name for the Events singleton (see `defaultTasksFolderName`).
    static let defaultEventsFolderName = "Events"

    /// Discovers a singleton folder by sidecar filename at the nexus root.
    /// Walks immediate children of `nexusRoot`; returns the first folder that
    /// carries `sidecarFilename` directly inside it. If multiple match
    /// (pathological), returns the first found in directory-listing order and
    /// logs a warning to stderr. If none match (brand-new Nexus, before the
    /// manager seeds the sidecar), returns `<nexusRoot>/<defaultFolderName>/`.
    /// If `contentsOfDirectory` throws (root inaccessible), returns the default
    /// path defensively.
    private static func singletonDir(
        in nexusRoot: URL,
        sidecarFilename: String,
        defaultFolderName: String
    ) -> URL {
        let fm = FileManager.default
        let defaultURL = nexusRoot.appendingPathComponent(defaultFolderName, isDirectory: true)
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: nexusRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return defaultURL
        }
        var matches: [URL] = []
        for child in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue
            else { continue }
            let sidecar = child.appendingPathComponent(sidecarFilename, isDirectory: false)
            if fm.fileExists(atPath: sidecar.path) {
                matches.append(child)
            }
        }
        guard let first = matches.first else { return defaultURL }
        if matches.count > 1 {
            let names = matches.map { $0.lastPathComponent }.joined(separator: ", ")
            let warning =
                "[NexusPaths] WARNING: \(matches.count) folders at root carry \(sidecarFilename) (\(names)). "
                + "Using first found: '\(first.lastPathComponent)'. Resolve by removing duplicate sidecars.\n"
            FileHandle.standardError.write(Data(warning.utf8))
        }
        return first
    }

    /// Folder URL of the Tasks singleton — the unique folder at the nexus root
    /// carrying `_taskconfig.json`. Falls back to `<nexus>/Tasks/` (default
    /// name) when none is present; the manager seeds the sidecar on launch
    /// per locked decision #9, after which discovery returns the seeded folder
    /// (and survives a Finder rename of that folder).
    static func tasksDir(in nexus: Nexus) -> URL {
        singletonDir(
            in: nexus.rootURL,
            sidecarFilename: taskConfigSidecarFilename,
            defaultFolderName: defaultTasksFolderName
        )
    }

    /// Folder URL of the Events singleton — the unique folder at the nexus
    /// root carrying `_eventconfig.json`. See `tasksDir(in:)` for fallback
    /// semantics.
    static func eventsDir(in nexus: Nexus) -> URL {
        singletonDir(
            in: nexus.rootURL,
            sidecarFilename: eventConfigSidecarFilename,
            defaultFolderName: defaultEventsFolderName
        )
    }

    /// `<TasksFolder>/_taskconfig.json` — AgendaTaskSchema sidecar inside the
    /// Tasks singleton (discovered via `tasksDir(in:)`).
    static func taskSchemaURL(in nexus: Nexus) -> URL {
        tasksDir(in: nexus).appendingPathComponent(
            taskConfigSidecarFilename, isDirectory: false
        )
    }

    /// `<EventsFolder>/_eventconfig.json` — AgendaEventSchema sidecar inside
    /// the Events singleton (discovered via `eventsDir(in:)`).
    static func eventSchemaURL(in nexus: Nexus) -> URL {
        eventsDir(in: nexus).appendingPathComponent(
            eventConfigSidecarFilename, isDirectory: false
        )
    }

    /// `<TasksFolder>/<title>.task.json` — single AgendaTask file. Tasks folder
    /// resolved via sidecar-driven discovery.
    static func taskFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        tasksDir(in: nexus)
            .appendingPathComponent("\(title).\(taskFileExtension)", isDirectory: false)
    }

    /// `<EventsFolder>/<title>.event.json` — single AgendaEvent file. Events
    /// folder resolved via sidecar-driven discovery.
    static func eventFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        eventsDir(in: nexus)
            .appendingPathComponent("\(title).\(eventFileExtension)", isDirectory: false)
    }

    // MARK: - Attachments

    /// `<nexus>/.nexus/attachments/<entityID>/` — per-entity attachment folder.
    /// The directory is created lazily by `AttachmentManager.attach`; this
    /// helper only computes the URL.
    static func attachmentsDir(for entityID: String, in nexusRoot: URL) -> URL {
        nexusRoot
            .appendingPathComponent(".nexus", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(entityID, isDirectory: true)
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

    // MARK: - PageType / PageCollection / Content paths (flatlayout)

    /// `<nexus>/<typeFolderName>/` — PageType folder (flatlayout: lives at the
    /// nexus root, no wrapper segment).
    static func pageTypeFolderURL(in nexusRoot: URL, typeFolderName: String) -> URL {
        nexusRoot.appendingPathComponent(typeFolderName, isDirectory: true)
    }

    /// Nexus-typed convenience overload — bridges legacy `(forTitle:in:nexus:)` callers.
    static func pageTypeFolderURL(forTitle title: String, in nexus: Nexus) -> URL {
        pageTypeFolderURL(in: nexus.rootURL, typeFolderName: title)
    }

    /// `<nexus>/<typeFolderName>/_pagetype.json` — PageType schema sidecar.
    static func pageTypeMetadataURL(in nexusRoot: URL, typeFolderName: String) -> URL {
        pageTypeFolderURL(in: nexusRoot, typeFolderName: typeFolderName)
            .appendingPathComponent(pageTypeSidecarFilename, isDirectory: false)
    }

    /// Nexus-typed convenience overload.
    static func pageTypeMetadataURL(forTitle title: String, in nexus: Nexus) -> URL {
        pageTypeMetadataURL(in: nexus.rootURL, typeFolderName: title)
    }

    /// `<nexus>/<typeFolderName>/<collectionFolderName>/` — PageCollection folder
    /// (still nested inside its parent PageType folder).
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

    /// `<nexus>/<typeFolderName>/<collectionFolderName>/_pagecollection.json` — PageCollection schema sidecar.
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
        .appendingPathComponent(pageCollectionSidecarFilename, isDirectory: false)
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
        collectionFolder.appendingPathComponent("\(title).md", isDirectory: false)
    }

    // MARK: - ItemType / ItemCollection paths (flatlayout)

    /// `<nexus>/<typeFolderName>/` — ItemType folder (flatlayout: lives at the
    /// nexus root, no wrapper segment).
    static func itemTypeFolderURL(in nexusRoot: URL, typeFolderName: String) -> URL {
        nexusRoot.appendingPathComponent(typeFolderName, isDirectory: true)
    }

    /// `<nexus>/<typeFolderName>/_itemtype.json` — ItemType schema sidecar.
    static func itemTypeMetadataURL(in nexusRoot: URL, typeFolderName: String) -> URL {
        itemTypeFolderURL(in: nexusRoot, typeFolderName: typeFolderName)
            .appendingPathComponent(itemTypeSidecarFilename, isDirectory: false)
    }

    /// `<nexus>/<typeFolderName>/<collectionFolderName>/` — ItemCollection folder
    /// (still nested inside its parent ItemType folder).
    static func itemCollectionFolderURL(
        in nexusRoot: URL,
        typeFolderName: String,
        collectionFolderName: String
    ) -> URL {
        itemTypeFolderURL(in: nexusRoot, typeFolderName: typeFolderName)
            .appendingPathComponent(collectionFolderName, isDirectory: true)
    }

    /// `<nexus>/<typeFolderName>/<collectionFolderName>/_itemcollection.json` —
    /// ItemCollection schema sidecar.
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
        .appendingPathComponent(itemCollectionSidecarFilename, isDirectory: false)
    }

    // MARK: - Filesystem helper

    static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
