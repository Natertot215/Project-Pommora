import Foundation
import Testing

@testable import Pommora

@Suite("DefaultSortConfigTests")
struct DefaultSortConfigTests {

    // MARK: - Helpers

    private func jsonEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func jsonDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func pageTypeJSON(withDefaultSort: Bool) -> String {
        let sortFragment =
            withDefaultSort
            ? #","default_sort":{"direction":"ascending","property_id":"prop_xyz"}"#
            : ""
        return """
            {
              "id": "01HQ000000000000000000AAA",
              "modified_at": "2026-05-24T00:00:00Z",
              "properties": [],
              "schema_version": 1,
              "views": []\(sortFragment)
            }
            """
    }

    private func taskSchemaJSON(withDefaultSort: Bool) -> String {
        let sortFragment =
            withDefaultSort
            ? #","default_sort":{"direction":"ascending","property_id":"prop_xyz"}"#
            : ""
        return """
            {
              "modified_at": "2026-05-24T00:00:00Z",
              "properties": [],
              "schemaVersion": 1,
              "views": []\(sortFragment)
            }
            """
    }

    private func eventSchemaJSON(withDefaultSort: Bool) -> String {
        let sortFragment =
            withDefaultSort
            ? #","default_sort":{"direction":"ascending","property_id":"prop_xyz"}"#
            : ""
        return """
            {
              "modified_at": "2026-05-24T00:00:00Z",
              "properties": [],
              "schemaVersion": 1,
              "views": []\(sortFragment)
            }
            """
    }

    // MARK: - Test 1: legacyDefaultMatchesSpec

    @Test("legacyDefault has propertyID _modified_at and direction descending")
    func legacyDefaultMatchesSpec() {
        let d = DefaultSortConfig.legacyDefault
        #expect(d.propertyID == "_modified_at")
        #expect(d.direction == .descending)
    }

    // MARK: - Test 2: roundTripJSON

    @Test("DefaultSortConfig encodes and decodes symmetrically")
    func roundTripJSON() throws {
        let original = DefaultSortConfig(propertyID: "prop_xyz", direction: .ascending)
        let data = try jsonEncoder().encode(original)
        let decoded = try jsonDecoder().decode(DefaultSortConfig.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Test 3: snakeCaseEncoding

    @Test("DefaultSortConfig encodes propertyID as property_id snake_case key")
    func snakeCaseEncoding() throws {
        let config = DefaultSortConfig(propertyID: "prop_xyz", direction: .ascending)
        let data = try jsonEncoder().encode(config)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"property_id\""))
        #expect(!json.contains("\"propertyID\""))
    }

    // MARK: - Test 4: pageTypeAbsentDefaultSortDecodesToNil

    @Test("PageType without default_sort field decodes to nil defaultSort")
    func pageTypeAbsentDefaultSortDecodesToNil() throws {
        let json = pageTypeJSON(withDefaultSort: false)
        let data = try #require(json.data(using: .utf8))
        var pt = try jsonDecoder().decode(PageType.self, from: data)
        pt.title = "TestVault"  // caller normally sets this from folder name
        #expect(pt.defaultSort == nil)
    }

    // MARK: - Test 5: pageTypePresentDefaultSortRoundTrips

    @Test("PageType with default_sort field encodes and decodes the field correctly")
    func pageTypePresentDefaultSortRoundTrips() throws {
        let sort = DefaultSortConfig(propertyID: "prop_xyz", direction: .ascending)
        var pt = PageType(
            id: "01HQ000000000000000000AAA",
            title: "TestVault",
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date(timeIntervalSince1970: 0),
            defaultSort: sort
        )
        let data = try jsonEncoder().encode(pt)
        var decoded = try jsonDecoder().decode(PageType.self, from: data)
        decoded.title = pt.title
        #expect(decoded.defaultSort == sort)
    }

    // MARK: - Test 8: agendaTaskSchemaAbsentDefaultSortDecodesToNil

    @Test("AgendaTaskSchema without default_sort field decodes to nil defaultSort")
    func agendaTaskSchemaAbsentDefaultSortDecodesToNil() throws {
        let json = taskSchemaJSON(withDefaultSort: false)
        let data = try #require(json.data(using: .utf8))
        let schema = try jsonDecoder().decode(AgendaTaskSchema.self, from: data)
        #expect(schema.defaultSort == nil)
    }

    // MARK: - Test 9: agendaEventSchemaAbsentDefaultSortDecodesToNil

    @Test("AgendaEventSchema without default_sort field decodes to nil defaultSort")
    func agendaEventSchemaAbsentDefaultSortDecodesToNil() throws {
        let json = eventSchemaJSON(withDefaultSort: false)
        let data = try #require(json.data(using: .utf8))
        let schema = try jsonDecoder().decode(AgendaEventSchema.self, from: data)
        #expect(schema.defaultSort == nil)
    }
}
