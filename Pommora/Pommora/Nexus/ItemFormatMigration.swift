import Foundation

/// One-shot migration that converts every legacy `.json` Item file in a Nexus
/// to the canonical `.md` (YAML-frontmatter + Markdown body) format. Auto-runs
/// UNCONDITIONALLY once at launch via `NexusManager.runFormatMigration` (after
/// `runAdoptionIfNeeded` + `autoTagMissingSidecars`, downstream of the XCTest
/// guard) — NOT gated by the adoption preview's confirm/decline (decision #8).
///
/// Modeled directly on `PropertyIDMigration`:
///   - `scan(at:) -> Plan` — pure: walks the nexus, finds `.json` Item files
///     that have not yet been converted, returns counts for preview /
///     reporting. **No disk writes.**
///   - `apply(_:) -> Report` — executes the Plan: per-`.json` Item, reads it via
///     the migration-only `Item.decodeLegacyJSON`, re-encodes the modeled fields
///     + body into a `.md` twin, then relocates the old `.json` to the nexus
///     `.trash/` (recoverable, never a hard delete). Per-item failures are
///     isolated in `report.failedItems`; the rest of the batch continues.
///   - `runIfNeeded(at:) -> Report` — `apply(scan(at:))`, the single-call entry
///     used by the launch hook + tests.
///
/// **Per-item action (`.json` → `.md`):**
/// 1. If a `.md` file at the twin path (same title, same folder) already
///    exists, it is lenient-decoded and its id compared to the `.json`'s id.
///    - **id MATCH** → the `.md` is a genuine already-migrated twin (a leftover
///      from a partial/interrupted run): the `.json`'s content already lives in
///      the `.md`, so the `.json` is trashed without a rewrite (cleanup), never
///      double-written.
///    - **id MISMATCH** (a *foreign* same-titled `.md` sits beside a real legacy
///      `.json`) → the `.json` is NOT a leftover; trashing it would silently
///      drop a real Item. Route the un-migrated `.json` to the hidden
///      `.unsorted` inbox (tracked + recoverable) rather than convert-over the
///      foreign `.md` or hard-lose the `.json`.
/// 2. Otherwise `Item.decodeLegacyJSON(from: jsonURL)` decodes the legacy Item
///    and `AtomicYAMLMarkdown.encode(frontmatter:body:)` builds a `.md`
///    payload from the modeled fields + body. Legacy `.json` Items are
///    fixed-shape typed records — they hold no foreign frontmatter to preserve,
///    so conversion is a clean re-encode of the modeled fields into the `.md`
///    envelope. The payload is staged into a `SchemaTransaction` and committed,
///    THEN the `.json` is moved to `.trash/`.
///
/// **Idempotent on file transition.** Idempotence is keyed on the `.md` twin's
/// existence, not on a version stamp: a fully-migrated Type has no `.json`
/// members, so `scan` plans nothing and `apply` is a no-op. A partial run (some
/// `.md` written, some not) resumes cleanly — the already-converted `.json`
/// files that still linger are trashed as cleanup, the un-converted ones are
/// converted normally.
///
/// **Interrupt-safe.** The only window where state is inconsistent is between
/// the `.md` commit and the `.json` trash. A crash there leaves a `.md` + its
/// orphan `.json` side by side, sharing an id. The Nexus reads from the `.md`
/// (the only Item read path); the orphan `.json` is invisible to reads, and the
/// next migration run sees a SAME-ID `.md` at the twin path and trashes the
/// leftover `.json` as cleanup. A foreign same-titled `.md` (DIFFERENT id) is
/// never mistaken for this leftover — the loser `.json` routes to `.unsorted`.
///
/// **`.md`-only read path.** Since the dual-format Item code was retired, the
/// legacy `.json` shape is read ONLY here, through `Item.decodeLegacyJSON` (and
/// the twin-collision id probe) — the general `Item.load` / `loadLenient` / the
/// read enumerators are all `.md`-only. This migration runs at launch BEFORE the index is populated, so
/// converted `.md` Items are indexed on the same launch (see
/// `NexusManager.openIndex(for:forceRebuild:)`).
enum ItemFormatMigration {

    // MARK: - Plan

    /// A single `.json` Item file that needs handling.
    struct ItemConversion: Sendable, Equatable {
        /// The legacy `.json` file on disk.
        var jsonURL: URL
        /// The canonical `.md` twin URL (same title, same folder).
        var markdownURL: URL
    }

    struct Plan: Sendable, Equatable {
        var nexusRoot: URL
        /// `.json` Item files that will be converted to `.md`.
        var conversions: [ItemConversion]
        /// TOTAL Item Type folders enumerated at the nexus root (including ones
        /// with no `.json` members). Surfaced into the Report for parity with
        /// `PropertyIDMigration`'s "scanned" semantic.
        var itemTypesScanned: Int

        var hasAnyConversion: Bool { !conversions.isEmpty }

        static func empty(at root: URL) -> Plan {
            Plan(nexusRoot: root, conversions: [], itemTypesScanned: 0)
        }
    }

    // MARK: - Report (post-apply)

    struct Report: Sendable, Equatable {
        var itemTypesScanned: Int
        /// `.json` files that were read + written out as a fresh `.md` twin.
        var itemsConverted: Int
        /// Leftover `.json` files (a same-id `.md` twin already present) trashed
        /// as cleanup of a partial run.
        var leftoversCleaned: Int
        /// Un-migrated `.json` files routed to `.unsorted` because a *foreign*
        /// same-titled `.md` (different id) blocked the twin path — converting
        /// over it or trashing the `.json` would silently lose a real Item.
        var collisionsRelocated: Int
        var failedItems: [FailedItem]

        var didAnyWork: Bool {
            itemsConverted > 0 || leftoversCleaned > 0 || collisionsRelocated > 0
        }
        var noOp: Bool { !didAnyWork && failedItems.isEmpty }

        static let empty = Report(
            itemTypesScanned: 0, itemsConverted: 0, leftoversCleaned: 0,
            collisionsRelocated: 0, failedItems: [])
    }

    struct FailedItem: Sendable, Equatable {
        var itemURL: URL
        var message: String
    }

    // MARK: - Entry points

    /// Pure scan — computes a Plan covering every `.json` Item file that needs
    /// handling. No disk writes; safe to call repeatedly.
    static func scan(at nexusRoot: URL) -> Plan {
        var conversions: [ItemConversion] = []
        var itemTypesScanned = 0

        for folder in enumerateRootTypeFolders(at: nexusRoot) {
            let itemSidecar = folder.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
            guard FileManager.default.fileExists(atPath: itemSidecar.path) else { continue }
            itemTypesScanned += 1

            for jsonURL in enumerateJSONItemMembers(in: folder) {
                let title = jsonURL.deletingPathExtension().lastPathComponent
                let markdownURL = NexusPaths.itemFileURL(
                    forTitle: title, in: jsonURL.deletingLastPathComponent())
                conversions.append(
                    ItemConversion(jsonURL: jsonURL, markdownURL: markdownURL))
            }
        }

        return Plan(
            nexusRoot: nexusRoot, conversions: conversions, itemTypesScanned: itemTypesScanned)
    }

    /// Executes a Plan. Per-item failures are isolated; the rest of the batch
    /// continues. Never throws.
    static func apply(_ plan: Plan) -> Report {
        var report = Report.empty
        report.itemTypesScanned = plan.itemTypesScanned

        // `moveToTrash` only consults `nexus.rootURL`; the id is unused by the
        // relocation core, so a synthetic Nexus over the plan's root is safe.
        let nexus = Nexus(id: "", rootURL: plan.nexusRoot)

        for conversion in plan.conversions {
            applyConversion(conversion, nexus: nexus, into: &report)
        }
        return report
    }

    /// Single-call entry. Equivalent to `apply(scan(at:))`. Used by the launch
    /// hook + tests.
    @discardableResult
    static func runIfNeeded(at nexusRoot: URL) -> Report {
        apply(scan(at: nexusRoot))
    }

    // MARK: - Apply helpers

    private static func applyConversion(
        _ conversion: ItemConversion, nexus: Nexus, into report: inout Report
    ) {
        // Re-check the twin path at apply time: scan may have run earlier and a
        // concurrent run / earlier conversion in this batch could have created
        // it. A file at the twin path is NOT automatically a leftover — it could
        // be a foreign same-titled `.md` owned by a different Item. Compare ids
        // before deciding (an id-blind trash would silently drop a real `.json`).
        if Filesystem.fileExists(at: conversion.markdownURL) {
            resolveTwinCollision(conversion, nexus: nexus, into: &report)
            return
        }

        // Fresh conversion: read via the migration-only legacy `.json` decoder,
        // re-encode the modeled fields + body into the `.md` envelope, stage +
        // commit, then relocate the `.json` to trash. A legacy `.json` Item is a
        // fixed-shape typed record — it carries no foreign frontmatter to
        // preserve, so a plain (non-preserving) encode is correct.
        do {
            let item = try Item.decodeLegacyJSON(from: conversion.jsonURL)
            let payload = try AtomicYAMLMarkdown.encode(
                frontmatter: item.frontmatter, body: item.description)

            let txn = SchemaTransaction()
            txn.stage(payload: payload, to: conversion.markdownURL)
            try txn.commit()
        } catch {
            report.failedItems.append(
                FailedItem(
                    itemURL: conversion.jsonURL,
                    message: "conversion skipped: \(error)"))
            return
        }

        // `.md` is committed; now retire the `.json`. A failure here leaves a
        // recoverable orphan `.json` (the read path prefers the `.md`); report it
        // but count the conversion as done — the next run cleans the leftover.
        do {
            try Filesystem.moveToTrash(conversion.jsonURL, in: nexus)
        } catch {
            report.failedItems.append(
                FailedItem(
                    itemURL: conversion.jsonURL,
                    message: "json trash failed (md written, orphan json left): \(error)"))
        }
        report.itemsConverted += 1
    }

    /// A file occupies the `.json`'s twin path. Decide between two outcomes by
    /// comparing ids (NOT by mere path existence):
    ///   • id MATCH → genuine already-migrated twin → trash the `.json` (cleanup).
    ///   • id MISMATCH (or the existing `.md` is undecodable / id-less) → a
    ///     foreign file holds the path; the `.json` is still un-migrated. Trashing
    ///     it would lose a real Item, so route it to `.unsorted` (tracked +
    ///     recoverable) instead.
    private static func resolveTwinCollision(
        _ conversion: ItemConversion, nexus: Nexus, into report: inout Report
    ) {
        // Both ids come from the same decode surfaces the read path uses:
        // `loadLenient` for the `.md` twin (tolerant; synthesizes an id only for
        // a truly id-less file), `decodeLegacyJSON` for the `.json`.
        let twinID = (try? Item.loadLenient(from: conversion.markdownURL))?.id
        let jsonID = (try? Item.decodeLegacyJSON(from: conversion.jsonURL))?.id

        if let twinID, let jsonID, twinID == jsonID {
            trashLeftover(conversion.jsonURL, nexus: nexus, into: &report)
        } else {
            relocateCollision(conversion.jsonURL, nexus: nexus, into: &report)
        }
    }

    private static func trashLeftover(
        _ jsonURL: URL, nexus: Nexus, into report: inout Report
    ) {
        do {
            try Filesystem.moveToTrash(jsonURL, in: nexus)
            report.leftoversCleaned += 1
        } catch {
            report.failedItems.append(
                FailedItem(
                    itemURL: jsonURL,
                    message: "leftover json trash failed: \(error)"))
        }
    }

    /// Routes an un-migrated `.json` whose twin path is occupied by a foreign
    /// (different-id) `.md` to the hidden `.unsorted` inbox — tracked, recoverable,
    /// and never converted-over the foreign file.
    private static func relocateCollision(
        _ jsonURL: URL, nexus: Nexus, into report: inout Report
    ) {
        do {
            try Filesystem.moveToUnsorted(jsonURL, nexusRoot: nexus.rootURL)
            report.collisionsRelocated += 1
        } catch {
            report.failedItems.append(
                FailedItem(
                    itemURL: jsonURL,
                    message: "twin-collision json relocate to .unsorted failed: \(error)"))
        }
    }

    // MARK: - Enumeration (mirrors PropertyIDMigration)

    /// Top-level scan of the nexus root for adoption-eligible folders (skips
    /// `.`-prefixed + `_`-prefixed siblings — matches PropertyIDMigration +
    /// NexusAdopter's exclusion rule).
    private static func enumerateRootTypeFolders(at nexusRoot: URL) -> [URL] {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: nexusRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return [] }
        return entries.filter { url in
            let name = url.lastPathComponent
            if name.hasPrefix(".") || name.hasPrefix("_") { return false }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                && isDir.boolValue
        }
    }

    /// Every `.json` Item member under an Item Type folder (recursing into
    /// Collection sub-folders). Excludes per-kind sidecars (`_…`) — same
    /// predicate as PropertyIDMigration's item enumerator. The `.skipsHiddenFiles`
    /// option keeps the walk out of `.trash` / `.unsorted` / other dot-folders.
    private static func enumerateJSONItemMembers(in typeFolder: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: typeFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var results: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "json", !url.lastPathComponent.hasPrefix("_") {
                results.append(url)
            }
        }
        return results
    }
}
