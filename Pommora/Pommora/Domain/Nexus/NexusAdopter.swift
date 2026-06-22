//
//  NexusAdopter.swift
//  Pommora
//
//  Surveys a Nexus root folder, classifies each top-level folder into one of
//  four input shapes, and prepares an AdoptionPlan describing the writes /
//  renames / moves needed to land the on-disk layout in the v0.3.0 flat shape:
//
//      <nexus>/<TypeFolder>/_pagetype.json (or _taskconfig.json
//                                            / _eventconfig.json)
//      <nexus>/<TypeFolder>/<CollectionFolder>/_pagecollection.json
//      <nexus>/<TypeFolder>/<CollectionFolder>/<SetFolder>/_pageset.json
//
//  Shape classifier (per locked decision #7):
//    1. Fresh             — no recognized sidecar; content-sniff always picks
//                           Pages.
//    2. Legacy v0.2       — folder carries `_vault.json` at root (pre-ParadigmV2
//                           PageType sidecar). Sub-folders may carry
//                           `_collection.json`. Renamed in place to per-kind
//                           sidecars.
//    3. paradigmV2 wrap   — folder IS named `Pages` / `Agenda` AND contains
//                           children that look like Types (or the `Tasks/` /
//                           `Events/` singletons inside `Agenda/`).
//                           Children unwrap to root + sidecars rename per depth.
//    4. Already flat      — folder carries one of the per-kind sidecars at
//                           the correct depth. No-op.
//
//  Per locked decision #8: best-effort + log warnings. Pathological folders
//  (two sidecars at the same depth, unknown sidecar filenames, etc.) do not
//  abort the scan. Per locked decision #11: apply is best-effort + idempotent;
//  each folder migration is self-atomic. Single failures don't block others —
//  surfaced via `AdoptionApplyResult.failedFolders`.
//

import Foundation

/// One of the per-kind sidecar filenames the flat layout recognizes.
/// Lives at the top of this file so the shape classifier + apply paths share
/// a single source of truth.
enum AdoptedSidecarKind: Sendable, Equatable {
    case pageType
    case pageCollection
    case pageSet
    case taskConfig
    case eventConfig

    var filename: String {
        switch self {
        case .pageType: return NexusPaths.pageTypeSidecarFilename
        case .pageCollection: return NexusPaths.pageCollectionSidecarFilename
        case .pageSet: return NexusPaths.pageSetSidecarFilename
        case .taskConfig: return NexusPaths.taskConfigSidecarFilename
        case .eventConfig: return NexusPaths.eventConfigSidecarFilename
        }
    }
}

/// A folder that has no recognized sidecar — adoption will write a fresh
/// per-kind sidecar in place. Sidecar-less folders always adopt as Page Types.
struct PlannedFreshSidecar: Equatable, Sendable, Identifiable {
    var folderURL: URL
    var kind: AdoptedSidecarKind
    var title: String

    var id: String { folderURL.path }
}

/// A folder carrying a legacy v0.2 sidecar (`_vault.json` / `_collection.json`)
/// — adoption renames the file in place to the per-kind flat-layout name.
struct PlannedInPlaceRename: Equatable, Sendable, Identifiable {
    var folderURL: URL
    var oldSidecar: String
    var newSidecar: String
    /// Whether this rename targets a Type-level sidecar (top of folder) or a
    /// Collection-level sidecar (one level deep). Purely descriptive — kept
    /// for the preview UI.
    var depth: Depth

    var id: String { folderURL.path + ":" + oldSidecar }

    enum Depth: String, Sendable, Equatable {
        case type
        case collection
    }
}

/// A paradigmV2 wrapper folder (`Pages` / `Agenda`) — adoption unwraps each
/// child to the nexus root, then rewrites the legacy `_schema.json` sidecars
/// at each level to the appropriate per-kind name.
struct PlannedUnwrap: Equatable, Sendable, Identifiable {
    /// The wrapper folder being dissolved (e.g. `<nexus>/Pages/`).
    var wrapperURL: URL
    /// The wrapper's role — which children kinds and sidecars to expect.
    var wrapperKind: WrapperKind
    /// One child of the wrapper that will become a root-level entity post-unwrap.
    var moves: [ChildMove]

    var id: String { wrapperURL.path }

    enum WrapperKind: String, Sendable, Equatable {
        /// `<nexus>/Pages/` — children become PageTypes; their sub-folders
        /// become PageCollections.
        case pages
        /// `<nexus>/Agenda/` — children are the singletons `Tasks/` / `Events/`.
        case agenda
    }

    struct ChildMove: Equatable, Sendable, Identifiable {
        /// The wrapped child folder pre-move (e.g. `<nexus>/Pages/Recipes/`).
        var sourceURL: URL
        /// Destination at the nexus root (e.g. `<nexus>/Recipes/`). May be
        /// suffixed with a timestamp discriminator if the bare destination
        /// already exists (collision case).
        var destURL: URL
        /// The per-kind sidecar that should sit at the top of the moved folder
        /// post-rename (drives Type-level sidecar rewrite).
        var typeSidecar: AdoptedSidecarKind
        /// The per-kind sidecar for one-level-deep sub-folders
        /// (PageCollection). Nil for Agenda children (Tasks/Events have no
        /// collection layer).
        var collectionSidecar: AdoptedSidecarKind?

        var id: String { sourceURL.path }
    }
}

/// A folder that already carries one of the per-kind sidecars. Recorded
/// for summary purposes only — apply skips these. (Legacy-orphan cleanup may
/// still run as a no-op pass on these folders.)
struct PlannedAlreadyFlat: Equatable, Sendable, Identifiable {
    var folderURL: URL
    var kind: AdoptedSidecarKind

    var id: String { folderURL.path }
}

/// The full snapshot of what `NexusAdopter.apply` will write. Equatable so
/// SwiftUI's `.sheet(item:)` can rebuild the preview view on plan replacement.
struct AdoptionPlan: Equatable, Sendable, Identifiable {
    /// Stable identity for `.sheet(item:)`.
    let id: String
    var nexusRoot: URL
    /// Shape #1: empty/content-only folders that need a fresh sidecar written.
    var freshSidecars: [PlannedFreshSidecar]
    /// Shape #2: legacy `_vault.json` / `_collection.json` renames in place.
    var inPlaceRenames: [PlannedInPlaceRename]
    /// Shape #3: paradigmV2 wrapper folders to unwrap to root.
    var unwrapSteps: [PlannedUnwrap]
    /// Shape #4: folders already in flat shape (informational, no action).
    var alreadyFlat: [PlannedAlreadyFlat]
    /// Non-Pommora root-level folders left untouched (e.g. user folders the
    /// scanner couldn't classify and that don't carry Pommora signals).
    var skippedTopLevel: [URL]
    /// Pathological-case messages surfaced in the preview UI ("two sidecars
    /// in <folder>; using <name>"; "unknown sidecar <name>"; etc.).
    var warnings: [String]
    /// Populated by `apply` — kept on the plan so re-running with a stale
    /// plan after a partial-failure surfaces the prior failures. Empty on
    /// freshly-scanned plans.
    var failedFolders: [FailedFolder]

    init(
        nexusRoot: URL,
        freshSidecars: [PlannedFreshSidecar] = [],
        inPlaceRenames: [PlannedInPlaceRename] = [],
        unwrapSteps: [PlannedUnwrap] = [],
        alreadyFlat: [PlannedAlreadyFlat] = [],
        skippedTopLevel: [URL] = [],
        warnings: [String] = [],
        failedFolders: [FailedFolder] = []
    ) {
        self.id = UUID().uuidString
        self.nexusRoot = nexusRoot
        self.freshSidecars = freshSidecars
        self.inPlaceRenames = inPlaceRenames
        self.unwrapSteps = unwrapSteps
        self.alreadyFlat = alreadyFlat
        self.skippedTopLevel = skippedTopLevel
        self.warnings = warnings
        self.failedFolders = failedFolders
    }

    /// Fires only for STRUCTURAL migration work (legacy sidecar renames,
    /// paradigmV2 wrapper unwraps, explicit warnings). Fresh-discoverable
    /// folders stay invisible — per-folder adoption is a future Prospect, not
    /// a launch-time bulk prompt. Without this exclusion, every non-Pommora
    /// folder at Nathan's Nexus root (Obsidian-managed folders, personal
    /// organization folders, etc.) would be proposed as a fresh PageType
    /// candidate on every launch — turning the preview into spam.
    var hasAnythingToAdopt: Bool {
        !inPlaceRenames.isEmpty  // legacy v0.2 migration
            || !unwrapSteps.isEmpty  // paradigmV2 wrapper migration
            || !warnings.isEmpty  // explicit issues need user attention
        // freshSidecars deliberately EXCLUDED — non-Pommora folders at root
        // stay invisible to discovery (per-folder adoption UI is a future
        // Prospect).
        // skippedTopLevel deliberately EXCLUDED — same rationale.
    }

    /// Equatable conformance ignores `id` (UUID) so two plans built from the
    /// same input compare equal — useful in tests.
    static func == (lhs: AdoptionPlan, rhs: AdoptionPlan) -> Bool {
        lhs.nexusRoot == rhs.nexusRoot
            && lhs.freshSidecars == rhs.freshSidecars
            && lhs.inPlaceRenames == rhs.inPlaceRenames
            && lhs.unwrapSteps == rhs.unwrapSteps
            && lhs.alreadyFlat == rhs.alreadyFlat
            && lhs.skippedTopLevel == rhs.skippedTopLevel
            && lhs.warnings == rhs.warnings
            && lhs.failedFolders == rhs.failedFolders
    }
}

/// Per-folder failure recorded during apply. The error is stringified at
/// capture time so the struct stays Sendable + Equatable without dragging the
/// Error existential through value semantics.
struct FailedFolder: Equatable, Sendable, Identifiable {
    var folderURL: URL
    var message: String

    var id: String { folderURL.path }
}

/// Aggregated outcome from `apply`. Non-throwing — callers inspect
/// `failedFolders` for the partial-failure list (decision #11).
struct AdoptionApplyResult: Equatable, Sendable {
    var migrated: Int
    var unchanged: Int
    var failedFolders: [FailedFolder]

    var failedCount: Int { failedFolders.count }
}

/// Folder names always excluded from sub-folder scans (build cruft + embedded
/// repos). `Pommora` is the vendored app source / embedded repo, `worktrees`
/// holds git worktrees — neither is user content; both must never be walked
/// or tagged.
private let adoptionExcludedSubFolderNames: Set<String> = [
    "node_modules",
    ".trash",
    "Pommora",
    "worktrees",
]

/// macOS system-noise files that don't count toward a folder's emptiness for
/// wrapper-deletion purposes (decision per Nathan's real Nexus shape).
private let macOSNoiseFilenames: Set<String> = [
    ".DS_Store",
    "Icon\r",
    ".localized",
]

/// Legacy sidecar names from the pre-ParadigmV2 era.
private let legacyVaultSidecarFilename = "_vault.json"
private let legacyCollectionSidecarFilename = "_collection.json"
/// Pre-flatlayout unified sidecar name. The wrapper-layout unwrap reads + rewrites these.
private let paradigmV2UnifiedSidecarFilename = "_schema.json"

/// Stateless utility that walks a Nexus root, classifies each top-level folder
/// into one of the four input shapes, and offers `apply` to land the flat
/// target layout on disk.
@MainActor
enum NexusAdopter {

    // MARK: - scan

    /// Walks the Nexus root and returns the adoption plan. Pure inspection —
    /// no writes. Safe to call repeatedly; on a second call after `apply`,
    /// the returned plan classifies migrated folders as `alreadyFlat` and is
    /// effectively a no-op.
    static func scan(nexusRoot: URL, filter: FolderFilter = .empty) throws -> AdoptionPlan {
        var freshSidecars: [PlannedFreshSidecar] = []
        var inPlaceRenames: [PlannedInPlaceRename] = []
        var unwrapSteps: [PlannedUnwrap] = []
        var alreadyFlat: [PlannedAlreadyFlat] = []
        var skipped: [URL] = []
        var warnings: [String] = []

        let topLevel = (try? Filesystem.childFolders(of: nexusRoot)) ?? []
        for folder in topLevel {
            let name = folder.lastPathComponent
            // Skip dotfile-prefixed and underscore-prefixed entries entirely
            // (`.nexus/`, `.trash/`, `.obsidian/`, `.makemd/`, etc.).
            if name.hasPrefix(".") || name.hasPrefix("_") { continue }
            if adoptionExcludedSubFolderNames.contains(name) { continue }
            // Skip user-excluded folders — never classify or sidecar them.
            if filter.isExcluded(folder) {
                skipped.append(folder)
                continue
            }

            do {
                try classifyFolder(
                    folder,
                    filter: filter,
                    freshSidecars: &freshSidecars,
                    inPlaceRenames: &inPlaceRenames,
                    unwrapSteps: &unwrapSteps,
                    alreadyFlat: &alreadyFlat,
                    warnings: &warnings
                )
            } catch {
                // Classification itself failed (e.g. directory unreadable).
                // Record as a warning and continue — never abort the whole scan
                // (decision #8).
                warnings.append(
                    "Failed to classify '\(name)': \(error.localizedDescription)"
                )
            }
        }

        return AdoptionPlan(
            nexusRoot: nexusRoot,
            freshSidecars: freshSidecars,
            inPlaceRenames: inPlaceRenames,
            unwrapSteps: unwrapSteps,
            alreadyFlat: alreadyFlat,
            skippedTopLevel: skipped,
            warnings: warnings
        )
    }

    /// Classifies one top-level folder. Mutates the plan accumulators.
    private static func classifyFolder(
        _ folder: URL,
        filter: FolderFilter = .empty,
        freshSidecars: inout [PlannedFreshSidecar],
        inPlaceRenames: inout [PlannedInPlaceRename],
        unwrapSteps: inout [PlannedUnwrap],
        alreadyFlat: inout [PlannedAlreadyFlat],
        warnings: inout [String]
    ) throws {
        let name = folder.lastPathComponent

        // Shape #3 first — wrapper layout supersedes any sidecars at the
        // wrapper level itself (they shouldn't exist; if they do we treat the
        // folder as wrapper and warn).
        // Guard: only treat the folder as a ParadigmV2 wrapper when it
        // actually has wrapper-shaped children (sub-folders carrying one of
        // the pre-flat legacy sidecars: `_schema.json`, `_vault.json`, or
        // `_collection.json`). A user-created folder that happens to be named
        // "Pages" or "Agenda" but contains regular `.md` / `.json` content
        // must NOT trigger the destructive wrapper-unwrap path.
        if name == "Pages" || name == "Agenda" {
            if folderHasWrapperShapedChildren(folder) {
                try classifyWrapperFolder(
                    folder,
                    filter: filter,
                    unwrapSteps: &unwrapSteps,
                    warnings: &warnings
                )
                return
            }
            // else: fall through to the regular shape #2 / #1 flow.
        }

        // Inspect the folder's top-level sidecars.
        let topLevelSidecars = recognizedSidecarsAt(folder)
        let hasLegacyVault = Filesystem.fileExists(
            at: folder.appendingPathComponent(legacyVaultSidecarFilename, isDirectory: false)
        )

        // Shape #4 — already flat (one of the per-kind Type sidecars present).
        if let flatKind = topLevelSidecars.first {
            // Multiple recognized sidecars at the same level → silent cleanup
            // pass during apply (cleanupLegacyOrphans deletes the non-
            // authoritative co-located sidecars). NOT warned — this fires
            // routinely for nexuses migrated through early flatlayout-4.2
            // versions, and the cleanup is non-destructive (data on disk
            // matches the authoritative sidecar's kind).
            alreadyFlat.append(
                PlannedAlreadyFlat(folderURL: folder, kind: flatKind)
            )
            // Sub-folders: classify each as Collection-sidecar carriers (already
            // flat) or sub-folder-without-sidecar (no work — Pages don't get
            // adoption-time sub-folder fresh-sidecar writes; that's a future
            // PageCollection creation).
            return
        }

        // Shape #2 — legacy v0.2 (`_vault.json` at root).
        if hasLegacyVault {
            inPlaceRenames.append(
                PlannedInPlaceRename(
                    folderURL: folder,
                    oldSidecar: legacyVaultSidecarFilename,
                    newSidecar: NexusPaths.pageTypeSidecarFilename,
                    depth: .type
                )
            )
            // Sub-folders carrying `_collection.json` → rename to `_pagecollection.json`.
            let subFolders = (try? Filesystem.childFolders(of: folder, folderFilter: filter)) ?? []
            for sub in subFolders where !isHiddenOrExcludedSub(sub) {
                let legacyColl = sub.appendingPathComponent(
                    legacyCollectionSidecarFilename, isDirectory: false
                )
                if Filesystem.fileExists(at: legacyColl) {
                    inPlaceRenames.append(
                        PlannedInPlaceRename(
                            folderURL: sub,
                            oldSidecar: legacyCollectionSidecarFilename,
                            newSidecar: NexusPaths.pageCollectionSidecarFilename,
                            depth: .collection
                        )
                    )
                }
            }
            return
        }

        // Shape #1 — fresh. No recognized sidecar; content-sniff classifies
        // as a Page Type (sidecar-less folders always adopt as Page Types).
        freshSidecars.append(
            PlannedFreshSidecar(
                folderURL: folder, kind: contentSniff(folder), title: name
            )
        )
    }

    /// Classifies a paradigmV2 wrapper folder (`Pages` / `Agenda`).
    private static func classifyWrapperFolder(
        _ wrapper: URL,
        filter: FolderFilter = .empty,
        unwrapSteps: inout [PlannedUnwrap],
        warnings: inout [String]
    ) throws {
        let name = wrapper.lastPathComponent
        let kind: PlannedUnwrap.WrapperKind = {
            switch name {
            case "Pages": return .pages
            case "Agenda": return .agenda
            default: return .pages  // unreachable per caller's guard
            }
        }()

        let children = (try? Filesystem.childFolders(of: wrapper, folderFilter: filter)) ?? []
        var moves: [PlannedUnwrap.ChildMove] = []

        for child in children where !isHiddenOrExcludedSub(child) {
            let typeSidecar: AdoptedSidecarKind
            let collectionSidecar: AdoptedSidecarKind?
            switch kind {
            case .pages:
                typeSidecar = .pageType
                collectionSidecar = .pageCollection
            case .agenda:
                // Tasks/Events sub-folders — name-discriminated since Agenda
                // is sidecar-asymmetric. Default to Tasks for unknown names
                // and warn.
                let childName = child.lastPathComponent
                if childName == "Tasks" {
                    typeSidecar = .taskConfig
                } else if childName == "Events" {
                    typeSidecar = .eventConfig
                } else {
                    warnings.append(
                        "Unknown child '\(childName)' inside Agenda/ — "
                            + "treating as Tasks. Move manually if it should be Events."
                    )
                    typeSidecar = .taskConfig
                }
                collectionSidecar = nil  // Agenda has no collection layer
            }

            let destURL = wrapper.deletingLastPathComponent()
                .appendingPathComponent(child.lastPathComponent, isDirectory: true)
            moves.append(
                PlannedUnwrap.ChildMove(
                    sourceURL: child,
                    destURL: destURL,
                    typeSidecar: typeSidecar,
                    collectionSidecar: collectionSidecar
                )
            )
        }

        // A wrapper folder with no children to migrate (e.g. a stale `Agenda/`
        // carrying only a pre-ParadigmV2 `_agenda.json` after Tasks/Events were
        // already unwrapped) has nothing to adopt. Without this guard the empty
        // unwrap step still trips `hasAnythingToAdopt`, re-showing the adoption
        // sheet on every launch. The leftover wrapper stays on disk inert; the
        // user can delete it manually.
        guard !moves.isEmpty else { return }

        unwrapSteps.append(
            PlannedUnwrap(wrapperURL: wrapper, wrapperKind: kind, moves: moves)
        )
    }

    /// Returns the set of recognized per-kind sidecar kinds present at the top
    /// of `folder`. First-found wins on collision; the warning is logged at
    /// the caller.
    private static func recognizedSidecarsAt(_ folder: URL) -> [AdoptedSidecarKind] {
        var found: [AdoptedSidecarKind] = []
        // Ordering matters — first wins for authoritative-sidecar selection
        // (orphan cleanup picks `found.first`). Tier-1 kinds (Types) precede
        // tier-2 kinds (Collections) precede tier-3 kinds (Sets), matching the
        // natural-parent inference rule.
        let allKinds: [AdoptedSidecarKind] = [
            .pageType, .taskConfig, .eventConfig,
            .pageCollection,
            .pageSet,
        ]
        for kind in allKinds {
            let url = folder.appendingPathComponent(kind.filename, isDirectory: false)
            if Filesystem.fileExists(at: url) {
                found.append(kind)
            }
        }
        return found
    }

    /// The adopted kind for a sidecar-less fresh folder — always `.pageType`.
    /// Callers early-return when a recognized sidecar exists, so a sidecar-less
    /// folder always adopts as a Page Type — no content walk needed.
    private static func contentSniff(_ folder: URL) -> AdoptedSidecarKind {
        .pageType
    }

    // MARK: - apply

    /// Executes the plan against disk. Best-effort + idempotent (decision #11).
    /// Each folder migration is self-atomic; single-folder failures land in the
    /// returned `AdoptionApplyResult.failedFolders` list and don't abort the
    /// rest. Re-running on a partially-migrated Nexus is safe — already-flat
    /// folders are skipped.
    @discardableResult
    static func apply(_ plan: AdoptionPlan) -> AdoptionApplyResult {
        var failures: [FailedFolder] = []
        var migrated = 0
        let unchanged = plan.alreadyFlat.count
        let now = Date()
        let fm = FileManager.default

        // Shape #1: write fresh per-kind sidecars
        for fresh in plan.freshSidecars {
            do {
                try writeFreshSidecar(fresh, now: now)
                migrated += 1
            } catch {
                failures.append(
                    FailedFolder(
                        folderURL: fresh.folderURL,
                        message: error.localizedDescription
                    )
                )
            }
        }

        // Shape #2: legacy in-place renames
        for rename in plan.inPlaceRenames {
            do {
                try applyInPlaceRename(rename, fm: fm)
                migrated += 1
            } catch {
                failures.append(
                    FailedFolder(
                        folderURL: rename.folderURL,
                        message: error.localizedDescription
                    )
                )
            }
        }

        // Shape #3: unwrap paradigmV2 wrappers
        for unwrap in plan.unwrapSteps {
            for move in unwrap.moves {
                do {
                    try applyUnwrapMove(move, fm: fm)
                    migrated += 1
                } catch {
                    failures.append(
                        FailedFolder(
                            folderURL: move.sourceURL,
                            message: error.localizedDescription
                        )
                    )
                }
            }
            // Best-effort wrapper deletion — counts macOS noise files as empty.
            // Errors swallowed; not a hard failure (just leaves an empty wrapper
            // the user can delete manually).
            tryDeleteEmptyWrapper(unwrap.wrapperURL, fm: fm)
        }

        // Shape #4: cleanup pass on already-flat folders (delete legacy orphans
        // co-located with a per-kind sidecar — Nathan's real-nexus scenario).
        for flat in plan.alreadyFlat {
            cleanupLegacyOrphans(in: flat.folderURL, fm: fm)
        }

        return AdoptionApplyResult(
            migrated: migrated, unchanged: unchanged, failedFolders: failures
        )
    }

    // MARK: - autoTagMissingSidecars (silent three-tier auto-tag)

    /// Silent three-level walk that writes missing per-kind sidecars so
    /// Finder-built structure is first-class on the next launch. The launch
    /// caller runs it UNCONDITIONALLY after `runAdoptionIfNeeded` (whether the
    /// adoption preview was shown / confirmed / declined) and BEFORE
    /// `openIndex`.
    ///
    /// **Idempotent + silent.** No prompts, no UI; failures logged to stderr
    /// and never abort. Skips dotfile-prefixed (`.nexus/`, `.obsidian/`,
    /// `.trash/`) and underscore-prefixed folder names plus the
    /// `adoptionExcludedSubFolderNames` set (`node_modules`, `.trash`).
    ///
    /// **Depth-aware kind selection:**
    /// - Depth 0 unknown → content-sniff via `contentSniff` → always
    ///   `_pagetype.json` (sidecar-less folders adopt as Page Types).
    /// - Depth 1, parent has `_pagetype.json` → write `_pagecollection.json`.
    /// - Depth 2, parent has `_pagecollection.json` → write `_pageset.json`.
    /// - Depth 3+ folders stay sidecar-less — Types, Collections, and Sets
    ///   are the only auto-tagged kinds; deeper folders roll up into the Set.
    ///
    /// **Paradigm-shift note:** overrides the previous "non-Pommora folders
    /// at root stay invisible to discovery" rule. Anything at the Nexus
    /// root without a dotfile/underscore prefix is now presumed Pommora-tagged
    /// on first launch and silently classified. This is the cost of "build
    /// via Finder" — the user has chosen this Nexus as a Pommora root.
    static func autoTagMissingSidecars(
        at nexusRoot: URL, filter: FolderFilter = .empty
    ) {
        let now = Date()
        // Depth 0: Nexus root children
        let topLevel = (try? Filesystem.childFolders(of: nexusRoot, folderFilter: filter)) ?? []
        for folder in topLevel where !shouldSkipForAutoTag(folder) {
            tagDepth0IfMissing(folder, now: now)
            // After depth-0 tagging, descend into this folder for depth-1
            // work (even if we wrote the sidecar just now, we still want to
            // seed Collections inside).
            walkDepth1(folder, now: now, filter: filter)
            // Self-heal co-located legacy/orphan sidecars. A depth-0 stray
            // (e.g. an inert `_pagecollection.json` co-located with this
            // folder's type sidecar, from an old wrapper unwrap) is
            // non-authoritative — `cleanupOrphansAt` keeps the Type sidecar
            // (`recognizedSidecarsAt.first`) and deletes the rest. IndexBuilder
            // only reads `_pagecollection.json` at depth 1, so a depth-0 stray
            // is inert; legitimate depth-1 collection sidecars are the sole
            // recognized sidecar in their own folder and are spared.
            cleanupLegacyOrphans(in: folder, fm: FileManager.default, filter: filter)
        }
    }

    // MARK: autoTag — depth helpers

    /// Writes `_pagetype.json` if the folder has no recognized sidecar yet.
    /// Existing legacy sidecars are NOT touched here — the regular adoption
    /// path handles those.
    private static func tagDepth0IfMissing(_ folder: URL, now: Date) {
        let existing = recognizedSidecarsAt(folder)
        guard existing.isEmpty else { return }
        let title = folder.lastPathComponent
        do {
            try writeAutoTagTypeSidecar(at: folder, title: title, now: now)
        } catch {
            logAutoTagFailure(error, at: folder, depth: 0)
        }
    }

    /// Walks the Collections inside `typeFolder` and writes missing
    /// `_pagecollection.json` sidecars, then descends one more level so each
    /// Collection's Sets get tagged too. Three tiers total — auto-tagging
    /// stops at the Set level.
    private static func walkDepth1(_ typeFolder: URL, now: Date, filter: FolderFilter = .empty) {
        // Re-read parent id after depth-0 write — the type sidecar should
        // now exist (or have existed before this run).
        guard let typeID = loadTypeParentID(at: typeFolder) else { return }
        let children = (try? Filesystem.childFolders(of: typeFolder, folderFilter: filter)) ?? []
        for child in children where !shouldSkipForAutoTag(child) {
            tagDepth1IfMissing(child, typeID: typeID, now: now)
            // Descend AFTER tagging so a freshly-tagged Collection immediately
            // gets its Sets tagged in the same pass. Re-read the collection id
            // from the sidecar that now exists (or pre-existed).
            if let collectionID = loadCollectionParentID(at: child) {
                walkDepth2(child, collectionID: collectionID, now: now, filter: filter)
            }
        }
    }

    /// Writes `_pagecollection.json` if the folder has no recognized sidecar.
    private static func tagDepth1IfMissing(
        _ folder: URL, typeID: String, now: Date
    ) {
        let existing = recognizedSidecarsAt(folder)
        guard existing.isEmpty else { return }
        let title = folder.lastPathComponent
        do {
            try writeAutoTagCollectionSidecar(
                at: folder, title: title, typeID: typeID, now: now
            )
        } catch {
            logAutoTagFailure(error, at: folder, depth: 1)
        }
    }

    /// Walks the Sets inside `collectionFolder` and writes missing
    /// `_pageset.json` sidecars. Depth-3+ folders stay sidecar-less — they
    /// roll up into the Set above them.
    private static func walkDepth2(
        _ collectionFolder: URL, collectionID: String, now: Date, filter: FolderFilter = .empty
    ) {
        let children = (try? Filesystem.childFolders(of: collectionFolder, folderFilter: filter)) ?? []
        for child in children where !shouldSkipForAutoTag(child) {
            tagDepth2IfMissing(child, collectionID: collectionID, now: now)
        }
    }

    /// Writes `_pageset.json` if the folder has no recognized sidecar.
    private static func tagDepth2IfMissing(
        _ folder: URL, collectionID: String, now: Date
    ) {
        let existing = recognizedSidecarsAt(folder)
        guard existing.isEmpty else { return }
        let title = folder.lastPathComponent
        do {
            try writeAutoTagSetSidecar(
                at: folder, title: title, collectionID: collectionID, now: now
            )
        } catch {
            logAutoTagFailure(error, at: folder, depth: 2)
        }
    }

    // MARK: autoTag — sidecar writers (silent)

    /// Reads the parent `_pagetype.json` sidecar to extract the id used as FK
    /// on freshly-tagged child sidecars. Returns nil if the type sidecar
    /// doesn't exist or decoding fails (silent — failures don't abort).
    private static func loadTypeParentID(at folder: URL) -> String? {
        let ptURL = folder.appendingPathComponent(
            NexusPaths.pageTypeSidecarFilename, isDirectory: false
        )
        guard let pt = try? PageType.load(from: ptURL) else { return nil }
        return pt.id
    }

    /// Reads the parent `_pagecollection.json` sidecar to extract the id used
    /// as FK on freshly-tagged child Set sidecars. Returns nil if the
    /// collection sidecar doesn't exist or decoding fails (silent — failures
    /// don't abort).
    private static func loadCollectionParentID(at folder: URL) -> String? {
        let pcURL = folder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename, isDirectory: false
        )
        guard let pc = try? PageCollection.load(from: pcURL) else { return nil }
        return pc.id
    }

    private static func writeAutoTagTypeSidecar(
        at folder: URL, title: String, now: Date
    ) throws {
        let metaURL = folder.appendingPathComponent(
            NexusPaths.pageTypeSidecarFilename, isDirectory: false)
        try Filesystem.writeMetadataIntoExistingFolder(
            metadataURL: metaURL,
            metadata: PageType(
                id: ULID.generate(), title: title, icon: nil,
                properties: [], views: [], modifiedAt: now
            )
        )
    }

    private static func writeAutoTagCollectionSidecar(
        at folder: URL,
        title: String,
        typeID: String,
        now: Date
    ) throws {
        let metaURL = folder.appendingPathComponent(
            NexusPaths.pageCollectionSidecarFilename, isDirectory: false)
        try Filesystem.writeMetadataIntoExistingFolder(
            metadataURL: metaURL,
            metadata: PageCollection(
                id: ULID.generate(),
                typeID: typeID,
                title: title,
                folderURL: folder,
                modifiedAt: now
            )
        )
    }

    private static func writeAutoTagSetSidecar(
        at folder: URL,
        title: String,
        collectionID: String,
        now: Date
    ) throws {
        let metaURL = folder.appendingPathComponent(
            NexusPaths.pageSetSidecarFilename, isDirectory: false)
        try Filesystem.writeMetadataIntoExistingFolder(
            metadataURL: metaURL,
            metadata: PageSet(
                id: ULID.generate(),
                collectionID: collectionID,
                title: title,
                folderURL: folder,
                modifiedAt: now
            )
        )
    }

    /// Auto-tag exclusion rule: skip dotfile-prefixed, underscore-prefixed,
    /// and the `adoptionExcludedSubFolderNames` set. Matches the existing
    /// scan-walk skip predicate for legacy adoption.
    private static func shouldSkipForAutoTag(_ folder: URL) -> Bool {
        let name = folder.lastPathComponent
        if name.hasPrefix(".") || name.hasPrefix("_") { return true }
        if adoptionExcludedSubFolderNames.contains(name) { return true }
        return false
    }

    /// Best-effort DEBUG log for an auto-tag sidecar write failure. Silent in
    /// release; failures never abort the walk.
    private static func logAutoTagFailure(_ error: any Error, at folder: URL, depth: Int) {
        #if DEBUG
        FileHandle.standardError.write(
            Data("autoTag depth-\(depth) write failed at \(folder.path): \(error)\n".utf8))
        #endif
    }

    // MARK: - Legacy fresh-sidecar writer (scan/apply path)

    /// Writes a fresh per-kind sidecar based on the folder's content sniff.
    private static func writeFreshSidecar(
        _ fresh: PlannedFreshSidecar, now: Date
    ) throws {
        let metaURL = fresh.folderURL.appendingPathComponent(
            fresh.kind.filename, isDirectory: false
        )
        switch fresh.kind {
        case .pageType:
            try Filesystem.writeMetadataIntoExistingFolder(
                metadataURL: metaURL,
                metadata: PageType(
                    id: ULID.generate(),
                    title: fresh.title,
                    icon: nil,
                    properties: [],
                    views: [],
                    modifiedAt: now
                )
            )
        case .taskConfig:
            try Filesystem.writeMetadataIntoExistingFolder(
                metadataURL: metaURL, metadata: AgendaTaskSchema.defaultSeed()
            )
        case .eventConfig:
            try Filesystem.writeMetadataIntoExistingFolder(
                metadataURL: metaURL, metadata: AgendaEventSchema.defaultSeed()
            )
        case .pageCollection, .pageSet:
            // Fresh PageCollection / PageSet writes are not initiated by the
            // LEGACY adopter for top-level folders — those land via creation
            // flows inside the app, or via the silent `autoTagMissingSidecars`
            // pass below for Finder-built folders. If we somehow get here
            // through the scan/apply path, no-op. (Defensive — classifyFolder
            // routes Types only into freshSidecars.)
            break
        }
    }

    /// Atomic rename of a legacy sidecar to its per-kind name.
    private static func applyInPlaceRename(
        _ rename: PlannedInPlaceRename, fm: FileManager
    ) throws {
        let oldURL = rename.folderURL.appendingPathComponent(
            rename.oldSidecar, isDirectory: false
        )
        let newURL = rename.folderURL.appendingPathComponent(
            rename.newSidecar, isDirectory: false
        )
        // Idempotence: if the new name already exists, drop the legacy file.
        if fm.fileExists(atPath: newURL.path) {
            if fm.fileExists(atPath: oldURL.path) {
                try fm.removeItem(at: oldURL)
            }
            return
        }
        try fm.moveItem(at: oldURL, to: newURL)
    }

    /// Moves one wrapper child to the nexus root, then rewrites sidecars +
    /// deletes legacy orphans inside the now-moved folder.
    private static func applyUnwrapMove(
        _ move: PlannedUnwrap.ChildMove, fm: FileManager
    ) throws {
        // Collision-on-unwrap: append timestamp discriminator per
        // `Filesystem.moveToTrash`'s pattern (decision #8).
        let finalDest: URL
        if fm.fileExists(atPath: move.destURL.path) {
            finalDest = suffixedWithTimestamp(move.destURL)
        } else {
            finalDest = move.destURL
        }
        try fm.moveItem(at: move.sourceURL, to: finalDest)

        // Post-move sidecar rewrites. AFTER successful move, rename
        // `_schema.json` (and legacy v0.2 names) → per-kind sidecar.
        rewriteSidecar(
            in: finalDest, to: move.typeSidecar, fm: fm,
            legacyNames: [paradigmV2UnifiedSidecarFilename, legacyVaultSidecarFilename]
        )

        // Sub-folders: rewrite collection-level sidecars when applicable.
        if let collectionKind = move.collectionSidecar {
            let subFolders = (try? Filesystem.childFolders(of: finalDest)) ?? []
            for sub in subFolders where !isHiddenOrExcludedSub(sub) {
                rewriteSidecar(
                    in: sub, to: collectionKind, fm: fm,
                    legacyNames: [
                        paradigmV2UnifiedSidecarFilename, legacyCollectionSidecarFilename,
                    ]
                )
            }
        }
    }

    /// In a single folder, rename any of the listed legacy sidecar names to
    /// the target per-kind name. Per decision #11 + idempotence:
    /// - if the target already exists, delete any legacy orphans alongside it.
    /// - if no legacy file exists either, this is a no-op.
    /// - the FIRST legacy name found wins (mirrors classifier first-found rule).
    private static func rewriteSidecar(
        in folder: URL,
        to target: AdoptedSidecarKind,
        fm: FileManager,
        legacyNames: [String]
    ) {
        let targetURL = folder.appendingPathComponent(target.filename, isDirectory: false)
        let targetExists = fm.fileExists(atPath: targetURL.path)

        if targetExists {
            // Cleanup pass — delete every legacy orphan alongside the target.
            for legacy in legacyNames {
                let legacyURL = folder.appendingPathComponent(legacy, isDirectory: false)
                if fm.fileExists(atPath: legacyURL.path) {
                    try? fm.removeItem(at: legacyURL)
                }
            }
            return
        }

        // No target yet — pick the first legacy name present and rename it,
        // then delete any remaining legacy orphans.
        var renamedFromLegacy = false
        for legacy in legacyNames {
            let legacyURL = folder.appendingPathComponent(legacy, isDirectory: false)
            guard fm.fileExists(atPath: legacyURL.path) else { continue }
            if !renamedFromLegacy {
                do {
                    try fm.moveItem(at: legacyURL, to: targetURL)
                    renamedFromLegacy = true
                } catch {
                    // Couldn't move; try the next legacy candidate.
                    continue
                }
            } else {
                // Already renamed once — anything left over is an orphan.
                try? fm.removeItem(at: legacyURL)
            }
        }
    }

    /// Deletes orphan sidecars co-located with the authoritative per-kind
    /// sidecar on an already-flat folder. Two categories of orphan:
    ///
    /// 1. **Legacy sidecars** — `_vault.json` / `_collection.json` / `_schema.json`
    ///    left over from earlier paradigm states (Nathan's nexus state when
    ///    paradigmV2 added `_schema.json` without removing the pre-existing
    ///    legacy files; or when flatlayout renamed `_schema.json` to per-kind
    ///    but left _schema.json behind).
    ///
    /// 2. **Co-located per-kind sidecars** — a folder carrying TWO recognized
    ///    per-kind sidecars (e.g. `_pagetype.json` AND `_pagecollection.json`
    ///    at the same level). This was caused by an early flatlayout-4.2 bug
    ///    that wrote the wrong sidecar during wrapper unwrap. Subsequent
    ///    runs of the corrected logic write the right one, but the orphan
    ///    persists. Rule: only ONE per-kind sidecar is valid at a folder's
    ///    top level; the rest are orphans. "Which one is authoritative" is
    ///    decided by `recognizedSidecarsAt`'s order (pageType > taskConfig >
    ///    eventConfig > pageCollection > pageSet), which matches the
    ///    natural-parent inference (a folder at root carrying both is a Type,
    ///    not a Collection, because Collections must live inside a Type, and
    ///    Sets inside a Collection).
    ///
    /// Scope: this pass visits the Type folder + one level deep (Collections)
    /// only. Set folders at depth 2 are never walked, so a legitimate
    /// `_pageset.json` is never touched; a stray `_pageset.json` co-located
    /// with a Type or Collection sidecar at depths 0–1 IS deleted (it orders
    /// last, so it never wins the authoritative pick).
    private static func cleanupLegacyOrphans(
        in folder: URL, fm: FileManager, filter: FolderFilter = .empty
    ) {
        cleanupOrphansAt(
            folder, fm: fm,
            legacyNames: [
                legacyVaultSidecarFilename, paradigmV2UnifiedSidecarFilename,
            ])
        // One-level-deep cleanup (Collections inside this Type). Honor the
        // user exclusion filter so a nested excluded sub-folder is never touched.
        let subFolders = (try? Filesystem.childFolders(of: folder, folderFilter: filter)) ?? []
        for sub in subFolders where !isHiddenOrExcludedSub(sub) {
            cleanupOrphansAt(
                sub, fm: fm,
                legacyNames: [
                    legacyCollectionSidecarFilename, paradigmV2UnifiedSidecarFilename,
                ])
        }
    }

    /// Per-folder orphan cleanup. Picks the authoritative per-kind sidecar
    /// (first in `recognizedSidecarsAt` order) and deletes everything else:
    /// other per-kind sidecars at this level + any of the listed legacy names.
    /// No-op if the folder carries no recognized per-kind sidecar.
    private static func cleanupOrphansAt(
        _ folder: URL, fm: FileManager, legacyNames: [String]
    ) {
        let perKindPresent = recognizedSidecarsAt(folder)
        guard let authoritative = perKindPresent.first else { return }

        // Delete co-located per-kind sidecars beyond the authoritative one.
        for other in perKindPresent.dropFirst() {
            let url = folder.appendingPathComponent(other.filename, isDirectory: false)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
        // Delete legacy orphans alongside the authoritative sidecar.
        for legacy in legacyNames {
            let url = folder.appendingPathComponent(legacy, isDirectory: false)
            if url.lastPathComponent == authoritative.filename { continue }
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Deletes a wrapper folder when it (and its descendants) is empty modulo
    /// macOS system-noise files. Best-effort — failures swallowed.
    private static func tryDeleteEmptyWrapper(_ wrapper: URL, fm: FileManager) {
        guard fm.fileExists(atPath: wrapper.path) else { return }
        let contents =
            (try? fm.contentsOfDirectory(
                at: wrapper, includingPropertiesForKeys: nil, options: []
            )) ?? []
        // Filter out macOS noise — wrapper is "empty" if everything left is noise.
        let meaningfulChildren = contents.filter { url in
            !macOSNoiseFilenames.contains(url.lastPathComponent)
        }
        guard meaningfulChildren.isEmpty else { return }
        try? fm.removeItem(at: wrapper)
    }

    // MARK: - Helpers

    /// Returns `true` when at least one non-hidden child folder of `folder`
    /// carries one of the pre-flat legacy sidecar files: `_schema.json`
    /// (ParadigmV2 unified sidecar), `_vault.json` (pre-ParadigmV2 PageType
    /// sidecar), or `_collection.json` (pre-ParadigmV2 Collection sidecar).
    ///
    /// This is the structural guard that prevents user-created folders named
    /// "Pages" or "Agenda" from being mistakenly treated as ParadigmV2
    /// wrappers and having their contents destructively unwrapped.
    /// A real wrapper has children that look like Types or Agenda singletons;
    /// a user folder with ordinary `.md` / `.json` content does not.
    private static func folderHasWrapperShapedChildren(_ folder: URL) -> Bool {
        let children = (try? Filesystem.childFolders(of: folder)) ?? []
        let legacySidecarCandidates = [
            paradigmV2UnifiedSidecarFilename,  // "_schema.json"
            legacyVaultSidecarFilename,  // "_vault.json"
            legacyCollectionSidecarFilename,  // "_collection.json"
        ]
        for child in children where !isHiddenOrExcludedSub(child) {
            for filename in legacySidecarCandidates {
                let sidecarURL = child.appendingPathComponent(filename, isDirectory: false)
                if Filesystem.fileExists(at: sidecarURL) {
                    return true
                }
            }
        }
        return false
    }

    private static func isHidden(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") || name.hasPrefix("_")
    }

    private static func isHiddenOrExcludedSub(_ url: URL) -> Bool {
        if isHidden(url) { return true }
        return adoptionExcludedSubFolderNames.contains(url.lastPathComponent)
    }

    /// Inserts a `.YYYYMMDD-HHMMSS-XXXX` discriminator into a folder URL.
    /// Mirrors `Filesystem.suffixedWithTimestamp` (which is fileprivate to
    /// Filesystem.swift); kept local here so adopter doesn't need to widen
    /// that helper's visibility.
    private static func suffixedWithTimestamp(_ url: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timestamp = formatter.string(from: Date())
        let discriminator = String(UUID().uuidString.prefix(4))
        let stamp = "\(timestamp)-\(discriminator)"
        let ext = url.pathExtension
        let withoutExt = url.deletingPathExtension()
        if ext.isEmpty {
            return withoutExt.appendingPathExtension(stamp)
        }
        return withoutExt.appendingPathExtension(stamp).appendingPathExtension(ext)
    }
}
