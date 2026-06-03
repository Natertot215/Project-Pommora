import Foundation
import Testing

@testable import Pommora

/// `excludedFolders` (vault-relative folder-exclusion list) contract:
/// - fresh nexus seeds an empty list at the current defaults version,
/// - the field round-trips as a snake_case array in JSON,
/// - legacy files lacking the key migrate to the current version with an
///   empty list (brand-new field, nothing to rewrite).
@Suite("ExcludedFoldersSettings")
@MainActor
struct ExcludedFoldersSettingsTests {

    @Test("fresh seed has empty excludedFolders at current defaults version")
    func freshSeedHasEmptyExcludedFolders() {
        let s = Settings.defaultSeed()
        #expect(s.excludedFolders == [])
        #expect(s.defaultsVersion == Settings.currentDefaultsVersion)
    }

    @Test("excludedFolders round-trips as snake_case array in JSON")
    func roundTripsAsSnakeCaseArray() throws {
        var s = Settings.defaultSeed()
        s.excludedFolders = ["Archive", "Projects/Old"]

        // Round-trip through the production reader/writer (temp file) so we use
        // the same encoder/decoder config the app uses — and avoid the cross-file
        // fileprivate JSONDecoder.iso8601() helper in SettingsTests.swift.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try AtomicJSON.write(s, to: url)

        let json = String(data: try Data(contentsOf: url), encoding: .utf8) ?? ""
        #expect(json.contains("\"excluded_folders\""))

        let decoded = try AtomicJSON.decode(Settings.self, from: url)
        #expect(decoded.excludedFolders == ["Archive", "Projects/Old"])
    }

    @Test("legacy settings without excluded_folders migrate to current version with empty list")
    func legacyFileWithoutExcludedFoldersMigrates() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        // Proven old-release payload (no "defaults_version" → 0; no
        // "excluded_folders"). Migration must climb to current and default the
        // new field to []. accent_color "purple" must be preserved.
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

        #expect(m.settings.excludedFolders == [])
        #expect(m.settings.defaultsVersion == Settings.currentDefaultsVersion)
        #expect(m.settings.accentColor == .purple)  // user customization preserved
        #expect(m.pendingError == nil)
    }
}
