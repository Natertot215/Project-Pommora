import Foundation
import Testing

@testable import Pommora

/// `showPageIcon` (per-Nexus page-header icon toggle) contract:
/// - fresh nexus seeds OFF at the current defaults version,
/// - the mutator persists + survives reload,
/// - legacy files lacking the key migrate to the current version with the
///   toggle OFF (brand-new field, nothing to rewrite).
@Suite("Settings showPageIcon")
@MainActor
struct SettingsShowPageIconTests {

    @Test("fresh nexus seeds showPageIcon OFF at current defaults version")
    func freshSeedShowPageIconOff() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        #expect(m.settings.showPageIcon == false)
        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        #expect(m.pendingError == nil)
    }

    @Test("updateShowPageIcon persists and survives reload")
    func updatePersistsAndReloads() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()
        await m.updateShowPageIcon(true)

        #expect(m.settings.showPageIcon == true)

        // Reload from disk to prove the flag was written, not just held in memory.
        let url = NexusPaths.settingsFileURL(in: nexus)
        let reloaded = try AtomicJSON.decode(Settings.self, from: url)
        #expect(reloaded.showPageIcon == true)
        #expect(m.pendingError == nil)
    }

    @Test("legacy settings without show_page_icon migrate to current version, icon OFF")
    func legacyMigratesWithIconOff() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Proven old-release payload (no "defaults_version" → 0; no
        // "show_page_icon"). Migration must climb to current and default the
        // new flag to false.
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
        let url = NexusPaths.settingsFileURL(in: nexus)
        try oldJSON.data(using: .utf8)!.write(to: url)

        let m = SettingsManager(nexus: nexus)
        await m.loadOrSeed()

        #expect(m.settings.showPageIcon == false)
        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        #expect(m.settings.accentColor == .purple)  // user customization preserved
        #expect(m.pendingError == nil)
    }
}
