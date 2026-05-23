//
//  NexusAdopter.swift
//  Pommora
//
//  Adopts the on-disk structure of a folder the user just picked as a Nexus.
//  Top-level folders → Vaults; their direct sub-folders → Collections.
//  Page (`.md`) and Item (`.json`) discovery is handled by `ContentManager`
//  — we only persist the Vault + Collection sidecars; counts here are for
//  the preview-and-confirm sheet.
//

import Foundation

/// A single Vault that adoption will create on disk by dropping `_vault.json`
/// into an existing top-level folder.
struct PlannedVault: Equatable, Sendable, Identifiable {
    var folderURL: URL
    var title: String
    var id: String { folderURL.path }
}

/// A single Collection that adoption will create on disk by dropping
/// `_collection.json` into an existing sub-folder of a Vault.
struct PlannedCollection: Equatable, Sendable, Identifiable {
    var folderURL: URL
    var vaultFolderURL: URL
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
    var pagesPreviewCount: Int
    var itemsPreviewCount: Int
    var skippedTopLevel: [URL]

    init(
        nexusRoot: URL,
        vaults: [PlannedVault],
        collections: [PlannedCollection],
        pagesPreviewCount: Int,
        itemsPreviewCount: Int,
        skippedTopLevel: [URL]
    ) {
        self.id = UUID().uuidString
        self.nexusRoot = nexusRoot
        self.vaults = vaults
        self.collections = collections
        self.pagesPreviewCount = pagesPreviewCount
        self.itemsPreviewCount = itemsPreviewCount
        self.skippedTopLevel = skippedTopLevel
    }

    /// Convenience for "is there anything worth showing the user?". The caller
    /// skips the preview sheet when both lists are empty — the Nexus is still
    /// initialized, the sidebar just stays empty until the user creates Vaults
    /// manually.
    var hasAnythingToAdopt: Bool {
        !vaults.isEmpty || !collections.isEmpty
    }
}

/// Names that are NEVER eligible to become Vaults or Collections, regardless
/// of contents. Matches the existing `PageTypeManager.loadAll` filter set plus
/// well-known cruft folders Pommora should never touch.
private let adoptionExcludedFolderNames: Set<String> = [
    "node_modules",
    ".trash",
    "Agenda",
]

/// Stateless utility that walks a Nexus root and proposes Vault/Collection
/// sidecar writes for any existing folders that don't already have them.
/// Used by `NexusManager.openPicked` immediately after `.nexus/nexus.json`
/// is established.
@MainActor
enum NexusAdopter {

    /// Walks the Nexus root and returns the adoption plan. Pure inspection —
    /// no writes. Safe to call repeatedly; on a second call after `apply`
    /// the returned plan will be empty.
    static func scan(nexusRoot: URL) throws -> AdoptionPlan {
        let allTopLevel = try Filesystem.childFolders(of: nexusRoot)
        let topLevelFolders = allTopLevel.filter { !isExcludedTopLevel($0) }
        let skipped = allTopLevel.filter(isExcludedTopLevel)

        var plannedVaults: [PlannedVault] = []
        var plannedCollections: [PlannedCollection] = []
        var pageCount = 0
        var itemCount = 0

        for folder in topLevelFolders {
            let vaultMetaURL = folder.appendingPathComponent(
                NexusPaths.schemaSidecarFilename, isDirectory: false
            )
            if !Filesystem.fileExists(at: vaultMetaURL) {
                plannedVaults.append(
                    PlannedVault(folderURL: folder, title: folder.lastPathComponent)
                )
            }

            let subFolders = (try? Filesystem.childFolders(of: folder)) ?? []
            for sub in subFolders where !isExcludedSubFolder(sub) {
                let collectionMetaURL =
                    sub.appendingPathComponent(
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

            // Recursive count — what the sidebar will show after adoption.
            pageCount +=
                ((try? Filesystem.descendantFiles(of: folder) { $0.pathExtension == "md" }) ?? [])
                .count
            itemCount +=
                ((try? Filesystem.descendantFiles(of: folder) { url in
                    url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("_")
                }) ?? []).count
        }

        return AdoptionPlan(
            nexusRoot: nexusRoot,
            vaults: plannedVaults,
            collections: plannedCollections,
            pagesPreviewCount: pageCount,
            itemsPreviewCount: itemCount,
            skippedTopLevel: skipped
        )
    }

    /// Writes the planned schema sidecars (`_schema.json`) for vaults + collections.
    /// Each write is atomic via `Filesystem.writeMetadataIntoExistingFolder`.
    /// Failures are collected and re-thrown as a single
    /// `AdoptionError.partialFailure` at the end — partial progress is
    /// preserved because rolling back would mutate folders we just touched.
    static func apply(_ plan: AdoptionPlan) throws {
        var failures: [URL] = []
        var vaultIDByFolder: [URL: String] = [:]
        let now = Date()

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

        for planned in plan.collections {
            let key = planned.vaultFolderURL.standardizedFileURL
            // Two ways to resolve the parent vault's id: we just wrote it
            // (cache hit), or the vault was pre-existing (load from disk).
            // If neither path works, the parent vault sidecar write failed
            // upstream — skip rather than orphan with a bogus id.
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
                    metadata: Collection(
                        id: ULID.generate(),
                        vaultID: vaultID,
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

    /// Mirrors `PageTypeManager.loadAll`'s top-level filter exactly so adoption
    /// proposes Vaults for the same folders the loader will subsequently see.
    private static func isExcludedTopLevel(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") || name.hasPrefix("_") { return true }
        return adoptionExcludedFolderNames.contains(name)
    }

    private static func isExcludedSubFolder(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") || name.hasPrefix("_")
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
