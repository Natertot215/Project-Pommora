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

    // MARK: - Profile fields (v4 → v5)

    @Test("old file without profile fields decodes them to defaults and migrates")
    func profileFieldsAbsentDecodeToDefaults() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // A pre-profile-fields file (no profile_image / profile_subtitle keys; no
        // defaults_version → treated as 0/stale).
        let oldJSON = """
        {
          "version": 1,
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
        let url = NexusPaths.settingsFileURL(in: nexus)
        try oldJSON.data(using: .utf8)!.write(to: url)

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        #expect(m.settings.profileImage == nil)
        #expect(m.settings.profileSubtitle == "")
        #expect(m.pendingError == nil)
    }

    @Test("user-set profile fields survive migration and persist")
    func userProfileFieldsSurviveMigration() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // A v4 file carrying user-customized profile fields.
        var old = Settings.defaultSeed()
        old.defaultsVersion = 4
        old.profileImage = ".nexus/assets/NX/avatar.png"
        old.profileSubtitle = "Wednesday"
        let url = NexusPaths.settingsFileURL(in: nexus)
        try AtomicJSON.write(old, to: url)

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        #expect(m.settings.profileImage == ".nexus/assets/NX/avatar.png")
        #expect(m.settings.profileSubtitle == "Wednesday")

        // The bump (and preserved fields) re-persisted to disk.
        let reloaded = try AtomicJSON.decode(Settings.self, from: url)
        #expect(reloaded.defaultsVersion == Settings.currentDefaultsVersion)
        #expect(reloaded.profileImage == ".nexus/assets/NX/avatar.png")
        #expect(reloaded.profileSubtitle == "Wednesday")
    }

    @Test("updateProfileSubtitle trims whitespace and caps at 30 characters")
    func subtitleTrimmedAndCapped() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        await m.updateProfileSubtitle("  " + String(repeating: "x", count: 50) + "  ")
        #expect(m.settings.profileSubtitle == String(repeating: "x", count: 30))
        #expect(m.pendingError == nil)
    }

    // MARK: - Three-to-two tier collapse (v5 → v6)

    @Test("old three-tier defaults migrate to new two-tier defaults without crashing")
    func oldThreeTierDefaultsMigrateCleanly() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Old file: page_type = "Vault" (old default), page_collection = "Collection"
        // (old middle tier), page_set = "Set". Sidebar pages = "Vaults" (old default).
        let oldJSON = """
        {
          "version": 1,
          "defaults_version": 5,
          "labels": {
            "sidebar_sections": { "pages": "Vaults", "areas": "Areas", "topics": "Topics" },
            "page_type":        { "singular": "Vault",       "plural": "Vaults"       },
            "page_collection":  { "singular": "Collection",  "plural": "Collections"  },
            "page_set":         { "singular": "Set",         "plural": "Sets"         },
            "project":          { "singular": "Project",     "plural": "Projects"     },
            "agenda_task":      { "singular": "Task",        "plural": "Tasks"        },
            "agenda_event":     { "singular": "Event",       "plural": "Events"       }
          },
          "modified_at": "2026-01-01T00:00:00Z"
        }
        """
        let url = NexusPaths.settingsFileURL(in: nexus)
        try oldJSON.data(using: .utf8)!.write(to: url)

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        #expect(m.pendingError == nil)
        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        // page_type was the default "Vault" → new top-tier defaults to "Collection".
        #expect(m.settings.labels.pageCollection.singular == "Collection")
        #expect(m.settings.labels.pageCollection.plural   == "Collections")
        // page_set unchanged.
        #expect(m.settings.labels.pageSet.singular == "Set")
        #expect(m.settings.labels.pageSet.plural   == "Sets")
        // sidebar.pages migrated from old default "Vaults" → "Collections".
        #expect(m.settings.labels.sidebarSections.pages == "Collections")
    }

    @Test("user-customized page_type carries to new top-tier pageCollection")
    func customPageTypeCarriesToPageCollection() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // User renamed "Vault" → "Workspace" in the old three-tier schema.
        let oldJSON = """
        {
          "version": 1,
          "defaults_version": 5,
          "labels": {
            "sidebar_sections": { "pages": "Workspaces", "areas": "Areas", "topics": "Topics" },
            "page_type":        { "singular": "Workspace",   "plural": "Workspaces"   },
            "page_collection":  { "singular": "Collection",  "plural": "Collections"  },
            "page_set":         { "singular": "Set",         "plural": "Sets"         },
            "project":          { "singular": "Project",     "plural": "Projects"     },
            "agenda_task":      { "singular": "Task",        "plural": "Tasks"        },
            "agenda_event":     { "singular": "Event",       "plural": "Events"       }
          },
          "modified_at": "2026-01-01T00:00:00Z"
        }
        """
        let url = NexusPaths.settingsFileURL(in: nexus)
        try oldJSON.data(using: .utf8)!.write(to: url)

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        #expect(m.pendingError == nil)
        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        // Customized page_type "Workspace" carries into new top-tier pageCollection.
        #expect(m.settings.labels.pageCollection.singular == "Workspace")
        #expect(m.settings.labels.pageCollection.plural   == "Workspaces")
        // User-customized sidebar.pages "Workspaces" is NOT the old default "Vaults" →
        // migration does not overwrite it.
        #expect(m.settings.labels.sidebarSections.pages == "Workspaces")
    }

    @Test("user-customized page_set survives three-to-two migration")
    func customPageSetSurvivesMigration() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // User renamed "Set" → "Chapter".
        let oldJSON = """
        {
          "version": 1,
          "defaults_version": 5,
          "labels": {
            "sidebar_sections": { "pages": "Vaults", "areas": "Areas", "topics": "Topics" },
            "page_type":        { "singular": "Vault",       "plural": "Vaults"       },
            "page_collection":  { "singular": "Collection",  "plural": "Collections"  },
            "page_set":         { "singular": "Chapter",     "plural": "Chapters"     },
            "project":          { "singular": "Project",     "plural": "Projects"     },
            "agenda_task":      { "singular": "Task",        "plural": "Tasks"        },
            "agenda_event":     { "singular": "Event",       "plural": "Events"       }
          },
          "modified_at": "2026-01-01T00:00:00Z"
        }
        """
        let url = NexusPaths.settingsFileURL(in: nexus)
        try oldJSON.data(using: .utf8)!.write(to: url)

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        #expect(m.pendingError == nil)
        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        // Customized page_set "Chapter" survives unchanged.
        #expect(m.settings.labels.pageSet.singular == "Chapter")
        #expect(m.settings.labels.pageSet.plural   == "Chapters")
        // Top tier defaults to "Collection" (old page_type was default "Vault").
        #expect(m.settings.labels.pageCollection.singular == "Collection")
    }
}
