import Foundation
import Testing

@testable import Pommora

/// Auto-migration contract: stale default fields get rewritten to current defaults
/// on `loadOrSeed`; user-customized fields are preserved.
///
/// `defaultsVersion` tracks which set of defaults was seeded.  When
/// `defaultsVersion < Settings.currentDefaultsVersion`, `Settings.migrate(_:)`
/// runs per-version steps before the in-memory `Settings` is accepted.  If the
/// migrated value differs from what was on disk, `SettingsManager` re-persists.
@Suite("Settings auto-migration")
@MainActor
struct SettingsManagerAutoMigrationTests {

    // MARK: - Fresh nexus seeds current defaults

    @Test("fresh nexus creates settings.json with current default values")
    func freshNexusCreatesDefaultSettings() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let url = NexusPaths.settingsFileURL(in: nexus)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        #expect(m.pendingError == nil)
    }

    // MARK: - Unchanged settings are not rewritten

    @Test("already-current settings file is not rewritten on reload")
    func unchangedSettingsAreNotRewrittenOnLoad() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        let url = NexusPaths.settingsFileURL(in: nexus)
        let mtimeBefore = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        // Re-open on same nexus (simulates re-launch on current defaults).
        let m2 = SettingsManager(nexus: nexus)
        await m2.loadOrSeed()

        let mtimeAfter = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        // File must not have been rewritten — mtime unchanged.
        #expect(mtimeBefore == mtimeAfter)
        #expect(m2.pendingError == nil)
    }

    // MARK: - Stale defaults migrate; user customizations survive

    @Test("stale defaultsVersion auto-migrates while preserving user accent color")
    func staleDefaultsAutoMigratePreservingAccent() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Build a settings payload that looks like an old release:
        //   - defaultsVersion = 0 (pre-migration; absent from JSON means 0)
        //   - user-customized accent_color = .purple
        //   - all other fields at whatever the old defaults were (here we use the
        //     current seed values since v0 → v1 has no field-rename steps yet —
        //     the migration scaffold still exercises the version-bump path).
        let oldJSON = """
        {
          "version": 1,
          "accent_color": "purple",
          "labels": {
            "sidebar_sections": { "pages": "Vaults", "items": "Types" },
            "page_type":        { "singular": "Vault",       "plural": "Vaults"       },
            "page_collection":  { "singular": "Collection",  "plural": "Collections"  },
            "item_type":        { "singular": "Type",        "plural": "Types"        },
            "item_collection":  { "singular": "Set",         "plural": "Sets"         },
            "project":          { "singular": "Project",     "plural": "Projects"     },
            "agenda_task":      { "singular": "Task",        "plural": "Tasks"        },
            "agenda_event":     { "singular": "Event",       "plural": "Events"       }
          },
          "modified_at": "2026-01-01T00:00:00Z"
        }
        """
        // Note: no "defaults_version" key → decoder treats it as 0 (stale).

        let url = NexusPaths.settingsFileURL(in: nexus)
        try oldJSON.data(using: .utf8)!.write(to: url)

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        // Migration must bump defaultsVersion to current.
        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        // User customization MUST be preserved.
        #expect(m.settings.accentColor == .purple)
        // No error.
        #expect(m.pendingError == nil)

        // Verify the bumped version was persisted.
        let reloaded = try AtomicJSON.decode(Settings.self, from: url)
        #expect(reloaded.defaultsVersion == Settings.currentDefaultsVersion)
        #expect(reloaded.accentColor == .purple)
    }

    // MARK: - Corrupt file falls back to defaults

    @Test("corrupt settings.json falls back to defaults and surfaces a pendingError")
    func corruptSettingsFallsBackToDefaults() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Write garbage JSON.
        let url = NexusPaths.settingsFileURL(in: nexus)
        try "{ not valid json !!!".data(using: .utf8)!.write(to: url)

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        // Must fall back to current defaults.
        #expect(m.settings.accentColor == nil)
        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        // Must surface an error.
        #expect(m.pendingError != nil)
    }
}
