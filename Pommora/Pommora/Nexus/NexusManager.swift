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

    /// Last non-fatal error. UI presentation is deferred to the design pass;
    /// for now the property is just observable state.
    var pendingError: NexusError?

    /// The URL we currently hold security-scoped access to. Cleared when the
    /// active nexus changes (we stop access on the old before starting on the new).
    private var accessingURL: URL?

    init() {}

    // MARK: - Lifecycle

    /// Called from `ContentView.task` on launch. Resolves the saved bookmark
    /// from app-level state.json, or presents the picker if no bookmark exists.
    func loadOnLaunch() async {
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

        let identityURL = pommoraIdentityURL(in: url)
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

        currentNexus = Nexus(id: identity.id, rootURL: url)
    }

    /// Routes a freshly-picked URL through init (empty/silent or non-empty/confirm)
    /// or load (existing `.pommora/`).
    private func openPicked(at url: URL) async {
        let pommoraDir = url.appendingPathComponent(".pommora", isDirectory: true)
        let identityURL = pommoraDir.appendingPathComponent("nexus.json", isDirectory: false)
        let fm = FileManager.default

        let identity: NexusIdentity
        if fm.fileExists(atPath: pommoraDir.path) {
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
                try fm.createDirectory(at: pommoraDir, withIntermediateDirectories: true)
                identity = NexusIdentity(id: ULID.generate())
                try identity.save(to: identityURL)
            } catch {
                pendingError = .initFailed(error.localizedDescription)
                return
            }
        }

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

        currentNexus = Nexus(id: identity.id, rootURL: url)
    }

    // MARK: - Helpers

    private func pommoraIdentityURL(in nexusURL: URL) -> URL {
        nexusURL
            .appendingPathComponent(".pommora", isDirectory: true)
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
        alert.messageText = "Initialize as Pommora nexus?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Initialize")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
