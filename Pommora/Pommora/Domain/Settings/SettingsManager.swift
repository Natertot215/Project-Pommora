import Foundation
import Observation

/// Per-Nexus settings store. Loads `<nexus>/.nexus/settings.json` on first
/// access; seeds defaults to disk on first launch. Consumed by every UI
/// label-rendering site (sidebar headers, new-X sheet titles, context menu
/// entries, breadcrumbs, empty-state copy) once Phase 7 Wave 2 wires the
/// readers — Task 7.2 ships the type definition only.
///
/// Self-contained: no NexusContext validator closures (no entity validation
/// responsibilities), only the Nexus value for path resolution. Mutators route
/// through `mutate(_:)`, a read-modify-write that re-reads the freshest
/// `settings.json` from disk, applies the one changed field, and atomic-writes
/// it back — so a field changed by another writer (e.g. the React build) since
/// load isn't clobbered. Every write bumps `modifiedAt`.
@MainActor
@Observable
final class SettingsManager {
    private(set) var settings: Settings = .defaultSeed()
    var pendingError: (any Error)?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadOrSeed() async {
        let url = NexusPaths.settingsFileURL(in: nexus)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let decoded = try AtomicJSON.decode(Settings.self, from: url)
                let migrated = Settings.migrate(decoded)
                self.settings = migrated
                // Re-persist only when migration actually changed something so
                // the file mtime stays stable across launches on current defaults.
                if migrated != decoded {
                    try AtomicJSON.write(migrated, to: url)
                }
            } catch {
                self.pendingError = error
                self.settings = .defaultSeed()
            }
        } else {
            self.settings = .defaultSeed()
            do {
                try AtomicJSON.write(settings, to: url)
            } catch {
                self.pendingError = error
            }
        }
    }

    func updateAccentColor(_ color: SettingsAccentColor?) async {
        await mutate { $0.accentColor = color }
    }

    func updateShowPageIcon(_ on: Bool) async {
        await mutate { $0.showPageIcon = on }
    }

    /// Sets (or clears, with nil) the nexus-relative profile-image path shown in
    /// the sidebar header. The image bytes are copied into `.nexus/assets/` by
    /// `CoverAssetStore` at the call site; this only persists the path.
    func updateProfileImage(_ relativePath: String?) async {
        await mutate { $0.profileImage = relativePath }
    }

    /// Sets the sidebar-header subtitle. Trimmed + capped at 30 characters so the
    /// stored value can never exceed the header's budget regardless of caller.
    func updateProfileSubtitle(_ text: String) async {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        await mutate { $0.profileSubtitle = trimmed }
    }

    func updateLabel<T>(_ keyPath: WritableKeyPath<SettingsLabels, T>, to newValue: T) async {
        await mutate { $0.labels[keyPath: keyPath] = newValue }
    }

    /// Read-modify-write: re-read the freshest `settings.json` from disk, apply the
    /// single field this mutation changes, then write it back. Re-reading is what
    /// stops a cross-writer clobber — another writer (e.g. the React build) may have
    /// changed an unrelated field since we loaded, and a whole-struct overwrite of
    /// our stale in-memory copy would silently erase it. Falls back to the in-memory
    /// value when the file is missing or unreadable.
    private func mutate(_ transform: (inout Settings) -> Void) async {
        let url = NexusPaths.settingsFileURL(in: nexus)
        var s = (try? AtomicJSON.decode(Settings.self, from: url)).map(Settings.migrate) ?? settings
        transform(&s)
        s.modifiedAt = Date()
        do {
            try AtomicJSON.write(s, to: url)
            self.settings = s
        } catch {
            self.pendingError = error
        }
    }
}
