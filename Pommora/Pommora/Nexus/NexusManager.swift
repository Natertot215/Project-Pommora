//
//  NexusManager.swift
//  Pommora
//

import AppKit
import Foundation
import Observation

/// Errors that can surface during nexus lifecycle. Logged to stderr by the
/// manager; UI presentation is deferred to the design pass.
enum NexusError: Error, Equatable {
    case accessDenied
    case corruptIdentity
    case enumerationFailed(String)
    case initFailed(String)
    case resolutionFailed(String)
    case bookmarkSaveFailed(String)
    case appSupportFailed(String)
}

/// Single source of truth for the active nexus. Drives the SwiftUI sidebar via
/// the @Observable macro. Owns the security-scoped access lifecycle.
@MainActor
@Observable
final class NexusManager {
    /// The currently-active nexus, if any. `nil` during first launch before the
    /// user picks a folder.
    var currentNexus: Nexus?

    /// The per-nexus SQLite index, opened alongside `currentNexus`. `nil` when
    /// no nexus is open or when index init failed (degraded mode — index-dependent
    /// surfaces show empty until the next launch rebuilds successfully).
    var currentIndex: PommoraIndex?

    /// Last non-fatal error. UI presentation is deferred to the design pass;
    /// for now the property is just observable state.
    var pendingError: NexusError?

    /// The adoption plan that `openPicked` is currently waiting on user
    /// confirmation for. ContentView observes this and presents
    /// `AdoptionPreviewView` whenever it goes non-nil; the sheet resolves via
    /// `resolveAdoption(_:)`.
    var pendingAdoption: AdoptionPlan?

    /// Property-ID migration plan computed alongside the adoption scan (Phase
    /// C.5). Bundled with `pendingAdoption` so the preview sheet can surface
    /// migration counts in the same UI; resolved by the same
    /// `resolveAdoption(_:)` callback. Nil when no migration is needed.
    var pendingMigrationPlan: PropertyIDMigration.Plan?

    /// True while the adoption scan is walking the Nexus folder. ContentView
    /// shows an "Indexing…" HUD over the sidebar while this is set so the
    /// user knows the brief stall on open is intentional. Obsidian-parity.
    var isIndexing: Bool = false

    /// The URL we currently hold security-scoped access to. Cleared when the
    /// active nexus changes (we stop access on the old before starting on the new).
    private var accessingURL: URL?

    /// Backing continuation for the adoption sheet's async wait. Held in a
    /// stored property because `withCheckedContinuation`'s closure stores it
    /// before the `await` suspends; resumed exactly once by `resolveAdoption`.
    private var adoptionContinuation: CheckedContinuation<Bool, Never>?

    init() {}

    // MARK: - Lifecycle

    /// Called from `ContentView.task` on launch. Resolves the saved bookmark
    /// from app-level state.json, or presents the picker if no bookmark exists.
    func loadOnLaunch() async {
        // Under a unit-test run (XCTest sets this env var) the test-host app must
        // NOT auto-restore the last nexus: resolving a security-scoped bookmark
        // raises a macOS folder-grant prompt and `pickNexus()` opens an NSOpenPanel
        // — both are modal and block the test runner from establishing connection
        // ("test runner hung before establishing connection"), besides interrupting
        // the user. Unit tests build their own temporary nexuses, so skipping
        // launch-restore here is safe. Real app launches never set this var.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        let stateURL: URL
        do {
            stateURL = try NexusStore.appStateURL()
        } catch {
            pendingError = .appSupportFailed(error.localizedDescription)
            return
        }

        guard
            let state = try? AppState.load(from: stateURL),
            let bookmarkData = state.lastNexusBookmark
        else {
            await pickNexus()
            return
        }

        do {
            let (url, isStale) = try NexusBookmark.resolve(bookmarkData)
            try await openExisting(at: url, isStale: isStale, currentState: state, stateURL: stateURL)
        } catch {
            pendingError = .resolutionFailed(error.localizedDescription)
            await pickNexus()
        }
    }

    /// Presents NSOpenPanel and routes through the init-or-load flow on the
    /// picked folder. Cancellation is silent (no error, no state change).
    func pickNexus() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let suggested = homeURL.appendingPathComponent("PommoraNexus", isDirectory: true)
        panel.directoryURL = FileManager.default.fileExists(atPath: suggested.path) ? suggested : homeURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        await openPicked(at: url)
    }

    #if DEBUG
    /// Deletes the app-level state.json so the next launch behaves as first
    /// launch. Does not touch any nexus folder on disk or App Support per-nexus
    /// data. Wired to a Debug menu command.
    func resetBookmark() {
        if let stateURL = try? NexusStore.appStateURL() {
            try? FileManager.default.removeItem(at: stateURL)
        }
        if let url = accessingURL {
            NexusBookmark.stopAccessing(url)
            accessingURL = nil
        }
        currentIndex = nil
        currentNexus = nil
    }
    #endif

    // MARK: - Private init/load flow

    /// Opens an existing nexus we already have a bookmark for. Refreshes the
    /// bookmark if the OS reports it as stale.
    private func openExisting(
        at url: URL,
        isStale: Bool,
        currentState: AppState,
        stateURL: URL
    ) async throws {
        guard NexusBookmark.startAccessing(url) else {
            pendingError = .accessDenied
            await pickNexus()
            return
        }
        replaceAccessingURL(with: url)

        let identityURL = nexusIdentityURL(in: url)
        let identity: NexusIdentity
        do {
            identity = try NexusIdentity.load(from: identityURL)
        } catch {
            pendingError = .corruptIdentity
            return
        }

        if isStale {
            do {
                let fresh = try NexusBookmark.create(for: url)
                var updated = currentState
                updated.lastNexusBookmark = fresh
                try updated.save(to: stateURL)
            } catch {
                pendingError = .bookmarkSaveFailed(error.localizedDescription)
            }
        }

        do {
            _ = try NexusStore.nexusDataDir(nexusID: identity.id)
        } catch {
            pendingError = .appSupportFailed(error.localizedDescription)
        }

        // Always offer adoption — re-opening a Nexus that pre-dates this
        // feature is the primary use case (existing Nexuses don't have
        // `_schema.json` sidecars yet, and may carry legacy `_vault.json` /
        // `_collection.json` files that the adopter migrates). The scan is
        // idempotent: if every top-level folder is already adopted, the
        // sheet doesn't appear.
        await runAdoptionIfNeeded(at: url)

        // F.1.j — silent three-level auto-tag pass. Runs unconditionally
        // after legacy adoption (whether the preview sheet was shown or
        // not, whether the user confirmed or declined). Writes missing
        // per-kind sidecars so Finder-built structure is first-class on
        // the next IndexBuilder walk. Idempotent + silent.
        NexusAdopter.autoTagMissingSidecars(at: url)

        let nexus = Nexus(id: identity.id, rootURL: url)
        await openIndex(for: nexus)
        currentNexus = nexus
    }

    /// Routes a freshly-picked URL through init (empty/silent or non-empty/confirm)
    /// or load (existing `.nexus/`), then always runs the adoption scan so
    /// existing folders without `_schema.json` sidecars (or carrying legacy
    /// `_vault.json` / `_collection.json` files from the pre-ParadigmV2
    /// layout) can be adopted into the Pages / Items / Agenda wrappers
    /// (Obsidian-parity).
    private func openPicked(at url: URL) async {
        let nexusConfigDir = url.appendingPathComponent(".nexus", isDirectory: true)
        let identityURL = nexusConfigDir.appendingPathComponent("nexus.json", isDirectory: false)
        let fm = FileManager.default

        let identity: NexusIdentity
        if fm.fileExists(atPath: nexusConfigDir.path) {
            do {
                identity = try NexusIdentity.load(from: identityURL)
            } catch {
                pendingError = .corruptIdentity
                return
            }
        } else {
            let visibleEntries: [String]
            do {
                visibleEntries = try fm.contentsOfDirectory(atPath: url.path)
                    .filter { !$0.hasPrefix(".") }
            } catch {
                pendingError = .enumerationFailed(error.localizedDescription)
                return
            }

            if !visibleEntries.isEmpty {
                guard confirmInitialization(for: url) else { return }
            }

            do {
                try fm.createDirectory(at: nexusConfigDir, withIntermediateDirectories: true)
                identity = NexusIdentity(id: ULID.generate())
                try identity.save(to: identityURL)
            } catch {
                pendingError = .initFailed(error.localizedDescription)
                return
            }
        }

        // Always offer adoption — covers both first-time init AND re-opens
        // of Nexuses that pre-date this feature. The scan is idempotent;
        // fully-adopted Nexuses produce an empty plan and skip the sheet.
        await runAdoptionIfNeeded(at: url)

        // F.1.j — silent three-level auto-tag pass. Runs unconditionally
        // after legacy adoption (whether the preview sheet was shown or
        // not, whether the user confirmed or declined). Writes missing
        // per-kind sidecars so Finder-built structure is first-class on
        // the next IndexBuilder walk. Idempotent + silent.
        NexusAdopter.autoTagMissingSidecars(at: url)

        replaceAccessingURL(with: url)
        guard NexusBookmark.startAccessing(url) else {
            pendingError = .accessDenied
            return
        }

        do {
            let bookmark = try NexusBookmark.create(for: url)
            let stateURL = try NexusStore.appStateURL()
            var state = (try? AppState.load(from: stateURL)) ?? AppState()
            state.lastNexusBookmark = bookmark
            try state.save(to: stateURL)
        } catch {
            pendingError = .bookmarkSaveFailed(error.localizedDescription)
        }

        do {
            _ = try NexusStore.nexusDataDir(nexusID: identity.id)
        } catch {
            pendingError = .appSupportFailed(error.localizedDescription)
        }

        let nexus = Nexus(id: identity.id, rootURL: url)
        await openIndex(for: nexus)
        currentNexus = nexus
    }

    /// Scans the freshly-initialized Nexus root for adoptable folders. If
    /// there's anything to adopt, hands off to the SwiftUI sheet via
    /// `pendingAdoption` and awaits the user's Adopt / Skip decision. If the
    /// scan finds nothing, the function silently returns — the Nexus is
    /// already initialized; the sidebar will just be empty.
    private func runAdoptionIfNeeded(at url: URL) async {
        isIndexing = true
        defer { isIndexing = false }

        let plan: AdoptionPlan
        do {
            plan = try NexusAdopter.scan(nexusRoot: url)
        } catch {
            pendingError = .enumerationFailed(error.localizedDescription)
            return
        }

        // v0.3.0 Phase C.5: scan property-ID migration alongside adoption so
        // the preview sheet can show counts for both. Migration scan is pure
        // (no disk writes); cost is one directory enumeration + decode per
        // Type sidecar — fast even on large nexuses.
        let migrationPlan = PropertyIDMigration.scan(at: url)

        // The preview is a CONSENT surface — show it only when the user
        // genuinely needs to decide: adopting a new folder, or acknowledging a
        // LOSSY migration change (context-tier-targeted relation drop). A pure
        // lossless normalization (`hasAnyMigration` but no
        // `requiresAcknowledgment`) applies SILENTLY — no surprise launch modal.
        let needsPreview = plan.hasAnythingToAdopt || migrationPlan.requiresAcknowledgment

        if needsPreview {
            // The sheet should be visible WITHOUT the indexing HUD competing for
            // attention behind it. Drop the indexing flag before awaiting the
            // user's decision, then re-raise it only while `apply` is writing
            // sidecars.
            isIndexing = false
            let confirmed = await presentAdoptionPreview(plan, migrationPlan: migrationPlan)
            guard confirmed else { return }

            isIndexing = true
            // Adoption apply: best-effort + idempotent (decision #11) — never
            // throws. Skipped when nothing to adopt.
            if plan.hasAnythingToAdopt {
                let result = NexusAdopter.apply(plan)
                if result.failedCount > 0 {
                    let preview = result.failedFolders.prefix(3)
                        .map { "\($0.folderURL.lastPathComponent): \($0.message)" }
                        .joined(separator: "; ")
                    pendingError = .initFailed(
                        "Adoption completed with \(result.failedCount) failures (\(preview))."
                    )
                }
            }
            // Migration apply: same best-effort + idempotent contract. Runs for
            // ANY migration work the confirmed plan carries (lossy + lossless),
            // not just the acknowledged drop.
            if migrationPlan.hasAnyMigration {
                applyMigrationSurfacingFailures(migrationPlan)
            }
        } else if migrationPlan.hasAnyMigration {
            // Pure lossless normalization — no adoption, no lossy events.
            // Apply HEADLESSLY (no preview). `isIndexing` is already true here
            // from the function top; the existing `defer` clears it.
            applyMigrationSurfacingFailures(migrationPlan)
        }
        // else: nothing to adopt + nothing to migrate — fall through to the
        // format migration below (handled by defer on return).

        // Item `.json` → `.md` format migration. Runs HEADLESSLY after the
        // property-ID pass (so any newly-written `.md` already carries ID-keyed
        // properties): it converts recoverable copies (old `.json` → `.trash/`),
        // never a lossy hard delete, so no consent gate is warranted. Idempotent
        // + interrupt-safe; a fully-migrated Nexus is a no-op. Same XCTest-guard
        // coverage as the property-ID migration (this whole path is downstream
        // of `loadOnLaunch`'s guard).
        applyFormatMigrationSurfacingFailures(at: url)
    }

    /// Applies the Item `.json` → `.md` format migration and surfaces any
    /// per-item failures via `pendingError`. Mirrors
    /// `applyMigrationSurfacingFailures` so both headless migrations report
    /// failures the same way.
    private func applyFormatMigrationSurfacingFailures(at url: URL) {
        let report = ItemFormatMigration.runIfNeeded(at: url)
        guard !report.failedItems.isEmpty else { return }
        let preview = report.failedItems.prefix(3)
            .map { "\($0.itemURL.lastPathComponent): \($0.message)" }
            .joined(separator: "; ")
        pendingError = .initFailed(
            "Item format migration completed with \(report.failedItems.count) failures (\(preview))."
        )
    }

    /// Applies a property-ID migration plan and surfaces any per-Type failures
    /// via `pendingError`. Single source of truth for the failure-summary
    /// string so the preview-confirmed path and the headless path stay DRY.
    private func applyMigrationSurfacingFailures(_ migrationPlan: PropertyIDMigration.Plan) {
        let migration = PropertyIDMigration.apply(migrationPlan)
        guard !migration.failedTypes.isEmpty else { return }
        let preview = migration.failedTypes.prefix(3)
            .map { "\($0.typeFolderURL.lastPathComponent): \($0.message)" }
            .joined(separator: "; ")
        pendingError = .initFailed(
            "Property-ID migration completed with \(migration.failedTypes.count) failures (\(preview))."
        )
    }

    /// Publishes `plan` (and an optional `migrationPlan`) for ContentView's
    /// sheet to pick up, then suspends until `resolveAdoption(_:)` resumes
    /// with the user's decision. Returns the boolean confirmation for BOTH
    /// adoption + migration apply (Phase C.5 unified preview).
    private func presentAdoptionPreview(
        _ plan: AdoptionPlan,
        migrationPlan: PropertyIDMigration.Plan
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            adoptionContinuation = continuation
            pendingMigrationPlan = migrationPlan.hasAnyMigration ? migrationPlan : nil
            pendingAdoption = plan
        }
    }

    /// Called from `AdoptionPreviewView`'s buttons (or from ContentView when
    /// the sheet is dismissed without an explicit choice). Resumes the
    /// `presentAdoptionPreview` continuation with `confirmed` and clears the
    /// presented sheet. Safe to call when no continuation is pending —
    /// becomes a no-op.
    func resolveAdoption(_ confirmed: Bool) {
        let cont = adoptionContinuation
        adoptionContinuation = nil
        pendingAdoption = nil
        pendingMigrationPlan = nil
        cont?.resume(returning: confirmed)
    }

    // MARK: - Helpers

    /// Opens the per-nexus SQLite index and (if needed) triggers a full rebuild
    /// via `IndexBuilder`. On any failure the index is left nil and a
    /// `.initFailed` error is surfaced — the nexus remains usable without it
    /// (degraded mode). Internal so tests can call directly.
    func openIndex(for nexus: Nexus) async {
        do {
            let (idx, needsRebuild) = try PommoraIndex.open(at: nexus.rootURL)
            self.currentIndex = idx
            if needsRebuild {
                isIndexing = true
                defer { isIndexing = false }
                try await IndexBuilder.populate(index: idx, from: nexus)
                // Stamp the version ONLY after a successful populate, so a
                // thrown/rolled-back rebuild leaves the version absent and the
                // next launch retries instead of locking in an empty index.
                try idx.markSchemaVersionCurrent()
            }
        } catch {
            currentIndex = nil
            pendingError = .initFailed("Index init failed: \(error.localizedDescription)")
        }
    }

    private func nexusIdentityURL(in nexusURL: URL) -> URL {
        nexusURL
            .appendingPathComponent(".nexus", isDirectory: true)
            .appendingPathComponent("nexus.json", isDirectory: false)
    }

    /// Stops access on the previously-held URL (if any) before the caller
    /// begins access on a new one. Maintains the sandbox ref-count discipline.
    private func replaceAccessingURL(with newURL: URL) {
        if let old = accessingURL, old != newURL {
            NexusBookmark.stopAccessing(old)
        }
        accessingURL = newURL
    }

    private func confirmInitialization(for url: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Initialize as Pommora Nexus?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Initialize")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
