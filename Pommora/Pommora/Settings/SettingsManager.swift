import Foundation
import Observation

/// Per-Nexus settings store. Loads `<nexus>/.nexus/settings.json` on first
/// access; seeds defaults to disk on first launch. Consumed by every UI
/// label-rendering site (sidebar headers, new-X sheet titles, context menu
/// items, breadcrumbs, empty-state copy) once Phase 7 Wave 2 wires the
/// readers — Task 7.2 ships the type definition only.
///
/// Self-contained: no NexusContext validator closures (no entity validation
/// responsibilities), only the Nexus value for path resolution. Mutators
/// (`updateAccentColor`, `updateLabel`) atomic-write through AtomicJSON and
/// bump `modifiedAt` on every write.
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
                self.settings = try AtomicJSON.decode(Settings.self, from: url)
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
        var s = settings
        s.accentColor = color
        s.modifiedAt = Date()
        await persist(s)
    }

    func updateLabel<T>(_ keyPath: WritableKeyPath<SettingsLabels, T>, to newValue: T) async {
        var s = settings
        s.labels[keyPath: keyPath] = newValue
        s.modifiedAt = Date()
        await persist(s)
    }

    private func persist(_ newSettings: Settings) async {
        do {
            let url = NexusPaths.settingsFileURL(in: nexus)
            try AtomicJSON.write(newSettings, to: url)
            self.settings = newSettings
        } catch {
            self.pendingError = error
        }
    }
}
