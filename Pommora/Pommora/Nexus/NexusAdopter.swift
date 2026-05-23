//
//  NexusAdopter.swift
//  Pommora
//
//  Adopts the on-disk structure of a folder the user just picked as a Nexus.
//  ParadigmV2 Phase 6: surveys the three wrapper directories — `Pages/`,
//  `Items/`, `Agenda/` — instead of the nexus root. Top-level folders inside
//  `Pages/` become PageTypes (with their sub-folders becoming PageCollections);
//  top-level folders inside `Items/` become ItemTypes (with their sub-folders
//  becoming ItemCollections). `Agenda/` is filename-discriminated (`.task.json`
//  / `.event.json`) and doesn't require folder scanning.
//
//  Legacy-shaped folders sitting at the nexus root (pre-ParadigmV2 layout)
//  are recorded in `skippedTopLevel` and surfaced to the user; Phase 10's
//  user-data migration owns relocating them into `Pages/`.
//

import Foundation

/// A single PageType that adoption will create on disk by dropping `_schema.json`
/// into an existing folder under `<nexus>/Pages/`.
struct PlannedVault: Equatable, Sendable, Identifiable {
    var folderURL: URL
    var title: String
    var id: String { folderURL.path }
}

/// A single PageCollection that adoption will create on disk by dropping
/// `_schema.json` into an existing sub-folder of a PageType.
struct PlannedCollection: Equatable, Sendable, Identifiable {
    var folderURL: URL
    var vaultFolderURL: URL
    var title: String
    var id: String { folderURL.path }
}

/// A single ItemType that adoption will create on disk by dropping `_schema.json`
/// into an existing folder under `<nexus>/Items/`.
struct PlannedItemType: Equatable, Sendable, Identifiable {
    var folderURL: URL
    var title: String
    var id: String { folderURL.path }
}

/// A single ItemCollection that adoption will create on disk by dropping
/// `_schema.json` into an existing sub-folder of an ItemType.
struct PlannedItemCollection: Equatable, Sendable, Identifiable {
    var folderURL: URL
    var itemTypeFolderURL: URL
    var title: String
    var id: String { folderURL.path }
}

/// The full snapshot of what `NexusAdopter.apply` will write. Equatable so
/// SwiftUI's `.sheet(item:)` can rebuild the preview view on plan replacement.
struct AdoptionPlan: Equatable, Sendable, Identifiable {
    /// Hashed once at construction time to give SwiftUI's `.sheet(item:)` a
    /// stable identity across re-renders.
    let id: String
    var nexusRoot: URL
    var vaults: [PlannedVault]
    var collections: [PlannedCollection]
    var itemTypes: [PlannedItemType]
    var itemCollections: [PlannedItemCollection]
    var pagesPreviewCount: Int
    var itemsPreviewCount: Int
    /// Folders at the nexus root that aren't one of the reserved wrapper names
    /// (`Pages`, `Items`, `Agenda`) and aren't hidden/build cruft. Surfaced as
    /// "skipped — Phase 10 migration owns layout change" in the preview.
    var skippedTopLevel: [URL]

    init(
        nexusRoot: URL,
        vaults: [PlannedVault],
        collections: [PlannedCollection],
        itemTypes: [PlannedItemType] = [],
        itemCollections: [PlannedItemCollection] = [],
        pagesPreviewCount: Int,
        itemsPreviewCount: Int,
        skippedTopLevel: [URL]
    ) {
        self.id = UUID().uuidString
        self.nexusRoot = nexusRoot
        self.vaults = vaults
        self.collections = collections
        self.itemTypes = itemTypes
        self.itemCollections = itemCollections
        self.pagesPreviewCount = pagesPreviewCount
        self.itemsPreviewCount = itemsPreviewCount
        self.skippedTopLevel = skippedTopLevel
    }

    /// Convenience for "is there anything worth showing the user?". The caller
    /// skips the preview sheet when every list is empty — the Nexus is still
    /// initialized, the sidebar just stays empty until the user creates types
    /// manually.
    var hasAnythingToAdopt: Bool {
        !vaults.isEmpty || !collections.isEmpty
            || !itemTypes.isEmpty || !itemCollections.isEmpty
            || !skippedTopLevel.isEmpty
    }
}

/// Folder names always excluded from sub-folder scans (build cruft / hidden).
/// Reserved wrapper names (Pages/Items/Agenda) live on NexusPaths so they're
/// shared with the loader; cruft list stays local.
private let adoptionExcludedSubFolderNames: Set<String> = [
    "node_modules",
    ".trash",
]

/// Stateless utility that walks a Nexus root and proposes `_schema.json`
/// sidecar writes for any existing folders inside the `Pages/` and `Items/`
/// wrappers that don't already have them. Used by `NexusManager.openPicked`
/// immediately after `.nexus/nexus.json` is established.
@MainActor
enum NexusAdopter {

    /// Walks the Nexus root and returns the adoption plan. Pure inspection —
    /// no writes. Safe to call repeatedly; on a second call after `apply`
    /// the returned plan will be empty (every folder will already carry its
    /// `_schema.json` sidecar).
    static func scan(nexusRoot: URL) throws -> AdoptionPlan {
        let pagesWrapper = NexusPaths.pagesWrapperDir(in: nexusRoot)
        let itemsWrapper = NexusPaths.itemsWrapperDir(in: nexusRoot)

        // Pages-side scan
        var plannedVaults: [PlannedVault] = []
        var plannedCollections: [PlannedCollection] = []
        var pageCount = 0

        if FileManager.default.fileExists(atPath: pagesWrapper.path) {
            let pageTypeFolders = try Filesystem.childFolders(of: pagesWrapper)
                .filter { !isHidden($0) }
            for folder in pageTypeFolders {
                let metaURL = folder.appendingPathComponent(
                    NexusPaths.schemaSidecarFilename, isDirectory: false
                )
                if !Filesystem.fileExists(at: metaURL) {
                    plannedVaults.append(
                        PlannedVault(folderURL: folder, title: folder.lastPathComponent)
                    )
                }

                let subFolders = (try? Filesystem.childFolders(of: folder)) ?? []
                for sub in subFolders where !isHiddenOrExcludedSub(sub) {
                    let collectionMetaURL = sub.appendingPathComponent(
                        NexusPaths.schemaSidecarFilename, isDirectory: false
                    )
                    if !Filesystem.fileExists(at: collectionMetaURL) {
                        plannedCollections.append(
                            PlannedCollection(
                                folderURL: sub,
                                vaultFolderURL: folder,
                                title: sub.lastPathComponent
                            )
                        )
                    }
                }

                pageCount +=
                    ((try? Filesystem.descendantFiles(of: folder) { $0.pathExtension == "md" }) ?? [])
                    .count
            }
        }

        // Items-side scan
        var plannedItemTypes: [PlannedItemType] = []
        var plannedItemCollections: [PlannedItemCollection] = []
        var itemCount = 0

        if FileManager.default.fileExists(atPath: itemsWrapper.path) {
            let itemTypeFolders = try Filesystem.childFolders(of: itemsWrapper)
                .filter { !isHidden($0) }
            for folder in itemTypeFolders {
                let metaURL = folder.appendingPathComponent(
                    NexusPaths.schemaSidecarFilename, isDirectory: false
                )
                if !Filesystem.fileExists(at: metaURL) {
                    plannedItemTypes.append(
                        PlannedItemType(folderURL: folder, title: folder.lastPathComponent)
                    )
                }

                let subFolders = (try? Filesystem.childFolders(of: folder)) ?? []
                for sub in subFolders where !isHiddenOrExcludedSub(sub) {
                    let collectionMetaURL = sub.appendingPathComponent(
                        NexusPaths.schemaSidecarFilename, isDirectory: false
                    )
                    if !Filesystem.fileExists(at: collectionMetaURL) {
                        plannedItemCollections.append(
                            PlannedItemCollection(
                                folderURL: sub,
                                itemTypeFolderURL: folder,
                                title: sub.lastPathComponent
                            )
                        )
                    }
                }

                itemCount +=
                    ((try? Filesystem.descendantFiles(of: folder) { url in
                        url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("_")
                    }) ?? []).count
            }
        }

        // Skipped top-level — folders at nexus root that aren't one of the
        // reserved wrapper names (Pages/Items/Agenda) and aren't hidden/cruft.
        // Per spec these are legacy-shaped folders awaiting Phase 10 migration.
        let allTopLevel = (try? Filesystem.childFolders(of: nexusRoot)) ?? []
        let skipped = allTopLevel.filter { url in
            let name = url.lastPathComponent
            if name.hasPrefix(".") || name.hasPrefix("_") { return false }
            if NexusPaths.reservedTopLevelFolderNames.contains(name) { return false }
            if adoptionExcludedSubFolderNames.contains(name) { return false }
            return true
        }

        return AdoptionPlan(
            nexusRoot: nexusRoot,
            vaults: plannedVaults,
            collections: plannedCollections,
            itemTypes: plannedItemTypes,
            itemCollections: plannedItemCollections,
            pagesPreviewCount: pageCount,
            itemsPreviewCount: itemCount,
            skippedTopLevel: skipped
        )
    }

    /// Writes the planned `_schema.json` sidecars for PageTypes + PageCollections
    /// + ItemTypes + ItemCollections, auto-creating the wrapper folders so a
    /// fresh nexus ends up with the `Pages/`, `Items/`, `Agenda/Tasks/` and
    /// `Agenda/Events/` layout in place even when nothing is adopted. Each
    /// write is atomic via `Filesystem.writeMetadataIntoExistingFolder`.
    /// Failures are collected and re-thrown as a single
    /// `AdoptionError.partialFailure` at the end — partial progress is
    /// preserved because rolling back would mutate folders we just touched.
    static func apply(_ plan: AdoptionPlan) throws {
        var failures: [URL] = []
        let now = Date()

        // Auto-create wrapper folders (idempotent — mkdir -p equivalent).
        let wrappers: [URL] = [
            NexusPaths.pagesWrapperDir(in: plan.nexusRoot),
            NexusPaths.itemsWrapperDir(in: plan.nexusRoot),
            NexusPaths.agendaWrapperDir(in: plan.nexusRoot),
            NexusPaths.agendaWrapperDir(in: plan.nexusRoot)
                .appendingPathComponent("Tasks", isDirectory: true),
            NexusPaths.agendaWrapperDir(in: plan.nexusRoot)
                .appendingPathComponent("Events", isDirectory: true),
        ]
        for url in wrappers {
            do {
                try NexusPaths.ensureDirectoryExists(url)
            } catch {
                failures.append(url)
            }
        }

        // PageType sidecars
        var vaultIDByFolder: [URL: String] = [:]
        for planned in plan.vaults {
            let vaultID = ULID.generate()
            let metaURL = planned.folderURL.appendingPathComponent(
                NexusPaths.schemaSidecarFilename, isDirectory: false
            )
            do {
                try Filesystem.writeMetadataIntoExistingFolder(
                    metadataURL: metaURL,
                    metadata: PageType(
                        id: vaultID,
                        title: planned.title,
                        icon: nil,
                        properties: [],
                        views: [],
                        modifiedAt: now
                    )
                )
                vaultIDByFolder[planned.folderURL.standardizedFileURL] = vaultID
            } catch {
                failures.append(metaURL)
            }
        }

        // PageCollection sidecars
        for planned in plan.collections {
            let key = planned.vaultFolderURL.standardizedFileURL
            let vaultID: String
            if let cached = vaultIDByFolder[key] {
                vaultID = cached
            } else if let loaded = try? PageType.load(
                from: key.appendingPathComponent(
                    NexusPaths.schemaSidecarFilename, isDirectory: false
                )
            ) {
                vaultID = loaded.id
                vaultIDByFolder[key] = vaultID
            } else {
                continue
            }

            let metaURL = planned.folderURL.appendingPathComponent(
                NexusPaths.schemaSidecarFilename, isDirectory: false
            )
            do {
                try Filesystem.writeMetadataIntoExistingFolder(
                    metadataURL: metaURL,
                    metadata: PageCollection(
                        id: ULID.generate(),
                        typeID: vaultID,
                        title: planned.title,
                        folderURL: planned.folderURL,
                        modifiedAt: now
                    )
                )
            } catch {
                failures.append(metaURL)
            }
        }

        // ItemType sidecars
        var itemTypeIDByFolder: [URL: String] = [:]
        for planned in plan.itemTypes {
            let itemTypeID = ULID.generate()
            let metaURL = planned.folderURL.appendingPathComponent(
                NexusPaths.schemaSidecarFilename, isDirectory: false
            )
            do {
                try Filesystem.writeMetadataIntoExistingFolder(
                    metadataURL: metaURL,
                    metadata: ItemType(
                        id: itemTypeID,
                        title: planned.title,
                        icon: nil,
                        properties: [],
                        views: [],
                        modifiedAt: now
                    )
                )
                itemTypeIDByFolder[planned.folderURL.standardizedFileURL] = itemTypeID
            } catch {
                failures.append(metaURL)
            }
        }

        // ItemCollection sidecars
        for planned in plan.itemCollections {
            let key = planned.itemTypeFolderURL.standardizedFileURL
            let itemTypeID: String
            if let cached = itemTypeIDByFolder[key] {
                itemTypeID = cached
            } else if let loaded = try? ItemType.load(
                from: key.appendingPathComponent(
                    NexusPaths.schemaSidecarFilename, isDirectory: false
                )
            ) {
                itemTypeID = loaded.id
                itemTypeIDByFolder[key] = itemTypeID
            } else {
                continue
            }

            let metaURL = planned.folderURL.appendingPathComponent(
                NexusPaths.schemaSidecarFilename, isDirectory: false
            )
            do {
                try Filesystem.writeMetadataIntoExistingFolder(
                    metadataURL: metaURL,
                    metadata: ItemCollection(
                        id: ULID.generate(),
                        typeID: itemTypeID,
                        title: planned.title,
                        folderURL: planned.folderURL,
                        modifiedAt: now
                    )
                )
            } catch {
                failures.append(metaURL)
            }
        }

        if !failures.isEmpty {
            throw AdoptionError.partialFailure(failures)
        }
    }

    // MARK: - Exclusion

    private static func isHidden(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") || name.hasPrefix("_")
    }

    private static func isHiddenOrExcludedSub(_ url: URL) -> Bool {
        if isHidden(url) { return true }
        return adoptionExcludedSubFolderNames.contains(url.lastPathComponent)
    }
}

enum AdoptionError: LocalizedError, Equatable {
    /// Some sidecar writes failed. The URLs that failed are preserved so the
    /// caller can surface them if needed; previously-written sidecars stay
    /// in place (intentional: re-running adoption is idempotent).
    case partialFailure([URL])

    var errorDescription: String? {
        switch self {
        case .partialFailure(let urls):
            return "Some Nexus sidecars failed to write: "
                + urls.map { $0.path }.joined(separator: ", ")
        }
    }
}
