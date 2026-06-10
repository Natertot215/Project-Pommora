import Foundation
import Testing

@testable import Pommora

@Suite("Settings")
struct SettingsTests {

    @Test("default seed carries locked-spec labels")
    func defaultSeedLabels() {
        let s = Settings.defaultSeed()
        #expect(s.version == 1)
        #expect(s.accentColor == nil)

        // Pages-side: distinctive "Vault" + generic "Collection".
        #expect(s.labels.pageType.singular == "Vault")
        #expect(s.labels.pageType.plural == "Vaults")
        #expect(s.labels.pageCollection.singular == "Collection")
        #expect(s.labels.pageCollection.plural == "Collections")

        // Tier-3 + Agenda label pairs.
        #expect(s.labels.project.singular == "Project")
        #expect(s.labels.project.plural == "Projects")
        #expect(s.labels.agendaTask.singular == "Task")
        #expect(s.labels.agendaTask.plural == "Tasks")
        #expect(s.labels.agendaEvent.singular == "Event")
        #expect(s.labels.agendaEvent.plural == "Events")

        // Sidebar sections — no Agenda heading per Phase 8.3. Pages-side
        // defaults to its signature plural "Vaults".
        #expect(s.labels.sidebarSections.pages == "Vaults")
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        var original = Settings.defaultSeed()
        original.accentColor = .purple
        original.labels.pageType = LabelPair(singular: "Library", plural: "Libraries")
        original.labels.agendaTask = LabelPair(singular: "Todo", plural: "Todos")

        let data = try AtomicJSON.encode(original)
        let decoded = try JSONDecoder.iso8601().decode(Settings.self, from: data)

        // ISO8601 encodes whole-second precision; the in-memory Date keeps
        // sub-second fractions, so == on Settings (which compares modifiedAt
        // by ==) fails. Compare structural fields directly instead.
        #expect(decoded.version == original.version)
        #expect(decoded.accentColor == original.accentColor)
        #expect(decoded.labels == original.labels)
        // Date should match to whole-second precision.
        let formatter = ISO8601DateFormatter()
        #expect(
            formatter.string(from: decoded.modifiedAt)
                == formatter.string(from: original.modifiedAt)
        )
    }

    @Test("nil accent color round-trips as missing/null")
    func nilAccentColorRoundTrip() throws {
        let original = Settings.defaultSeed()
        #expect(original.accentColor == nil)
        let data = try AtomicJSON.encode(original)
        let decoded = try JSONDecoder.iso8601().decode(Settings.self, from: data)
        #expect(decoded.accentColor == nil)
    }

    @Test("on-disk JSON uses snake_case CodingKeys")
    func snakeCaseKeys() throws {
        // Seed with a non-nil accent so the optional key is emitted.
        var s = Settings.defaultSeed()
        s.accentColor = .blue
        let data = try AtomicJSON.encode(s)
        let json = String(data: data, encoding: .utf8) ?? ""
        // Spot-check: accent_color + modified_at + sidebar_sections + page_type.
        #expect(json.contains("\"accent_color\""))
        #expect(json.contains("\"modified_at\""))
        #expect(json.contains("\"sidebar_sections\""))
        #expect(json.contains("\"page_type\""))
        #expect(json.contains("\"agenda_task\""))
    }

    @Test("legacy settings.json with retired item label keys still decodes")
    func legacyItemKeysDecodeTolerance() throws {
        // A pre-PagesV2 settings file still carries `item_type` / `item_collection`
        // label pairs and a `sidebar_sections.items` key. Codable ignores keys
        // absent from CodingKeys, so the file must decode cleanly — no crash, no
        // throw — with the page-side labels (including a user rename) preserved.
        let legacyJSON = """
        {
          "version": 1,
          "defaults_version": 2,
          "labels": {
            "sidebar_sections": { "pages": "Shelves", "items": "Items" },
            "page_type":        {"singular": "Vault", "plural": "Vaults"},
            "page_collection":  {"singular": "Collection", "plural": "Collections"},
            "item_type":        {"singular": "Type", "plural": "Types"},
            "item_collection":  {"singular": "Set", "plural": "Sets"},
            "project":          {"singular": "Project", "plural": "Projects"},
            "agenda_task":      {"singular": "Task", "plural": "Tasks"},
            "agenda_event":     {"singular": "Event", "plural": "Events"}
          },
          "modified_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.iso8601().decode(Settings.self, from: legacyJSON)
        #expect(decoded.labels.pageType.plural == "Vaults")
        #expect(decoded.labels.pageCollection.singular == "Collection")
        // User-customized pages section label survives the retired-key load.
        #expect(decoded.labels.sidebarSections.pages == "Shelves")
    }

    @Test("all SettingsAccentColor cases round-trip")
    func allAccentColorsRoundTrip() throws {
        for color in SettingsAccentColor.allCases {
            var s = Settings.defaultSeed()
            s.accentColor = color
            let data = try AtomicJSON.encode(s)
            let decoded = try JSONDecoder.iso8601().decode(Settings.self, from: data)
            #expect(decoded.accentColor == color)
        }
    }
}

extension JSONDecoder {
    fileprivate static func iso8601() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
