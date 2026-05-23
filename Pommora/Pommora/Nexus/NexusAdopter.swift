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
//  Legacy-layout folders at the nexus root (pre-ParadigmV2 shape — Type folders
//  sitting directly under the nexus root) are surfaced via `legacyMigrations`
//  on the plan and relocated into `Pages/` or `Items/` on apply. Content sniff
//  (`.md` → Pages-side, user `.json` → Items-side, empty → Pages-side) classifies
//  the destination; non-Pommora root folders (no sidecar AND no content hints)
//  remain in `skippedTopLevel` and are left untouched. Pulls Phase 10's
//  migration scope into the adopter so the very first onboarding session works
//  against a pre-existing nexus.
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

/// A single legacy-layout folder sitting at the nexus root that adoption will
/// move into the appropriate wrapper (`Pages/` or `Items/`). Pulls Phase 10's
/// user-data migration scope into the adopter — pre-ParadigmV2 nexuses ship
/// Type folders directly under the root (e.g. `<nexus>/Recipes/`); the adopter
/// classifies the side via content sniff and relocates atomically on apply.
struct PlannedLegacyMigration: Equatable, Sendable, Identifiable {
    /// The legacy folder at the nexus root (source of the move).
    var sourceFolderURL: URL
    /// The destination inside the wrapper (e.g. `<nexus>/Pages/Recipes/`).
    var destinationFolderURL: URL
    /// Which wrapper the folder is being relocated into.
    var side: Side
    /// Why the adopter classified this folder as Pages-side vs Items-side —
    /// surfaced in the preview UI so the user can see the reasoning.
    var detectedBy: Detection
    /// Folder name (== title; renames are filename-driven).
    var title: String
    /// True when the source folder lacks any sidecar (neither `_schema.json` nor
    /// the legacy `_vault.json`). On apply, a fresh PageType/ItemType sidecar is
    /// written into the destination after the move.
    var needsFreshSidecar: Bool

    var id: String { sourceFolderURL.path }

    enum Side: String, Sendable, Equatable {
        case pages
        case items
    }

    enum Detection: String, Sendable, Equatable {
        /// At least one `.md` file exists anywhere inside the source folder.
        case markdownChildren
        /// At least one user `.json` file (filename not beginning with `_`)
        /// exists anywhere inside the source folder.
        case jsonChildren
        /// No content hints — defaults to Pages-side (the canonical
        /// pre-ParadigmV2 data shape).
        case emptyFolderDefaultsToPages
    }
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
    /// Legacy-layout Type folders at the nexus root that the adopter will
    /// relocate into `Pages/` or `Items/` on apply. Pre-classified by content
    /// sniff at scan time so the preview can show the destination path.
    var legacyMigrations: [PlannedLegacyMigration]
    /// Folders at the nexus root that aren't one of the reserved wrapper names
    /// (`Pages`, `Items`, `Agenda`), aren't hidden/build cruft, AND don't have
    /// a sidecar that marks them as legacy Pommora data. These are
    /// non-Pommora folders — left untouched.
    var skippedTopLevel: [URL]

    init(
        nexusRoot: URL,
        vaults: [PlannedVault],
        collections: [PlannedCollection],
        itemTypes: [PlannedItemType] = [],
        itemCollections: [PlannedItemCollection] = [],
        pagesPreviewCount: Int,
        itemsPreviewCount: Int,
        legacyMigrations: [PlannedLegacyMigration] = [],
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
        self.legacyMigrations = legacyMigrations
        self.skippedTopLevel = skippedTopLevel
    }

    /// Convenience for "is there anything worth showing the user?". The caller
    /// skips the preview sheet when every list is empty — the Nexus is still
    /// initialized, the sidebar just stays empty until the user creates types
    /// manually.
    var hasAnythingToAdopt: Bool {
        !vaults.isEmpty || !collections.isEmpty
            || !itemTypes.isEmpty || !itemCollections.isEmpty
            || !legacyMigrations.isEmpty
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

        // Top-level scan — split candidates into legacy migrations (folders that
        // look like Pommora data: have a sidecar OR contain Markdown/JSON) and
        // truly-skipped folders (non-Pommora top-level junk).
        let allTopLevel = (try? Filesystem.childFolders(of: nexusRoot)) ?? []
        let candidates = allTopLevel.filter { url in
            let name = url.lastPathComponent
            if name.hasPrefix(".") || name.hasPrefix("_") { return false }
            if NexusPaths.reservedTopLevelFolderNames.contains(name) { return false }
            if adoptionExcludedSubFolderNames.contains(name) { return false }
            return true
        }

        var legacyMigrations: [PlannedLegacyMigration] = []
        var skipped: [URL] = []

        for folder in candidates {
            // Sidecar detection — `_schema.json` is the unified post-ParadigmV2
            // name; `_vault.json` is the pre-ParadigmV2 PageType sidecar that
            // PageTypeManager.loadAll's auto-heal renames in place. Either marks
            // this folder as Pommora data.
            let hasSchemaSidecar = Filesystem.fileExists(
                at: folder.appendingPathComponent(
                    NexusPaths.schemaSidecarFilename, isDirectory: false
                )
            )
            let hasLegacyVaultSidecar = Filesystem.fileExists(
                at: folder.appendingPathComponent("_vault.json", isDirectory: false)
            )
            let hasAnySidecar = hasSchemaSidecar || hasLegacyVaultSidecar

            // Content sniff — recursive scan for `.md` first (canonical Pages
            // signal), then user-namespaced `.json` (Items signal). The
            // sidecar-only path (Sidecar without content hints) still routes
            // to Pages-side via `emptyFolderDefaultsToPages` since pre-ParadigmV2
            // canonical data was always Page-shaped.
            let hasMarkdown = ((try? Filesystem.descendantFiles(of: folder) { url in
                url.pathExtension == "md"
            }) ?? []).isEmpty == false
            let hasUserJSON = ((try? Filesystem.descendantFiles(of: folder) { url in
                url.pathExtension == "json"
                    && !url.lastPathComponent.hasPrefix("_")
            }) ?? []).isEmpty == false

            // Only migrate folders that either look like Pommora data OR are
            // worth a default-to-Pages relocation because they carry a sidecar.
            // Folders with no sidecar AND no content hints land in `skipped`
            // (genuine non-Pommora junk).
            if !hasAnySidecar && !hasMarkdown && !hasUserJSON {
                skipped.append(folder)
                continue
            }

            let detection: PlannedLegacyMigration.Detection
            let side: PlannedLegacyMigration.Side
            if hasMarkdown {
                detection = .markdownChildren
                side = .pages
            } else if hasUserJSON {
                detection = .jsonChildren
                side = .items
            } else {
                // Sidecar present but no content yet — pre-ParadigmV2 canonical
                // shape was always Pages-side, so default there.
                detection = .emptyFolderDefaultsToPages
                side = .pages
            }

            let destination: URL = {
                switch side {
                case .pages:
                    return NexusPaths.pageTypeFolderURL(
                        in: nexusRoot, typeFolderName: folder.lastPathComponent
                    )
                case .items:
                    return NexusPaths.itemTypeFolderURL(
                        in: nexusRoot, typeFolderName: folder.lastPathComponent
                    )
                }
            }()

            legacyMigrations.append(
                PlannedLegacyMigration(
                    sourceFolderURL: folder,
                    destinationFolderURL: destination,
                    side: side,
                    detectedBy: detection,
                    title: folder.lastPathComponent,
                    needsFreshSidecar: !hasAnySidecar
                )
            )
        }

        return AdoptionPlan(
            nexusRoot: nexusRoot,
            vaults: plannedVaults,
            collections: plannedCollections,
            itemTypes: plannedItemTypes,
            itemCollections: plannedItemCollections,
            pagesPreviewCount: pageCount,
            itemsPreviewCount: itemCount,
            legacyMigrations: legacyMigrations,
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

        // Legacy-layout migrations — relocate root-level Type folders into the
        // appropriate wrapper BEFORE the sidecar writes below run. Each move is
        // independent; failures collect and don't abort the rest. Post-move,
        // any `_vault.json` sidecar inside the moved folder is renamed in place
        // to `_schema.json` (defensive — most cases will already be migrated by
        // PageTypeManager's auto-heal once the loader sees them inside `Pages/`,
        // but Items-side folders + first-launch fresh nexuses need this here).
        let fm = FileManager.default
        for migration in plan.legacyMigrations {
            // Collision: a folder with the same name already exists at the
            // destination. Skip the move + record the failure; the user can
            // resolve manually before re-running adoption.
            if fm.fileExists(atPath: migration.destinationFolderURL.path) {
                failures.append(migration.sourceFolderURL)
                continue
            }
            do {
                try fm.moveItem(
                    at: migration.sourceFolderURL,
                    to: migration.destinationFolderURL
                )
            } catch {
                failures.append(migration.sourceFolderURL)
                continue
            }

            // Post-move: rename `_vault.json` → `_schema.json` inside the moved
            // folder if needed (idempotent; no-op when the new name already
            // exists). Errors swallowed — best-effort, mirrors the auto-heal
            // pattern at PageTypeManager.migrateLegacySidecarsIfNeeded.
            let legacySidecar = migration.destinationFolderURL
                .appendingPathComponent("_vault.json", isDirectory: false)
            let unifiedSidecar = migration.destinationFolderURL
                .appendingPathComponent(
                    NexusPaths.schemaSidecarFilename, isDirectory: false
                )
            if fm.fileExists(atPath: legacySidecar.path),
                !fm.fileExists(atPath: unifiedSidecar.path)
            {
                try? fm.moveItem(at: legacySidecar, to: unifiedSidecar)
            }

            // No sidecar at all (source was a bare folder with content) — write
            // a fresh PageType / ItemType sidecar at the destination so the
            // loader picks it up on next launch.
            if migration.needsFreshSidecar {
                do {
                    switch migration.side {
                    case .pages:
                        try Filesystem.writeMetadataIntoExistingFolder(
                            metadataURL: unifiedSidecar,
                            metadata: PageType(
                                id: ULID.generate(),
                                title: migration.title,
                                icon: nil,
                                properties: [],
                                views: [],
                                modifiedAt: now
                            )
                        )
                    case .items:
                        try Filesystem.writeMetadataIntoExistingFolder(
                            metadataURL: unifiedSidecar,
                            metadata: ItemType(
                                id: ULID.generate(),
                                title: migration.title,
                                icon: nil,
                                properties: [],
                                views: [],
                                modifiedAt: now
                            )
                        )
                    }
                } catch {
                    failures.append(unifiedSidecar)
                }
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
