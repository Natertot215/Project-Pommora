import Foundation
import Testing

@testable import Pommora

/// T1.5 — Collection-level `templateConfig` override layer. ItemCollection gets
/// an optional `ItemTemplateConfig`; PageCollection gets an optional
/// `PageTemplateConfig`. Both encode under `template_config`, all-optional →
/// null-round-trip. The pre-existing `pinned_properties` on ItemCollection must
/// keep round-tripping (no regression).
@Suite("CollectionTemplateConfigTests")
struct CollectionTemplateConfigTests {

    private func folderURL() -> URL {
        URL(fileURLWithPath: "/tmp/\(UUID().uuidString)", isDirectory: true)
    }

    @Test("ItemCollection with templateConfig round-trips equal")
    func itemCollectionWithConfigRoundTrips() throws {
        let original = ItemCollection(
            id: "01HICOLL",
            typeID: "01HITYPE",
            title: "Groceries",
            folderURL: folderURL(),
            modifiedAt: Date(timeIntervalSince1970: 1716480000),
            templateConfig: ItemTemplateConfig(layout: .standard)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ItemCollection.self, from: data)

        #expect(decoded.templateConfig == ItemTemplateConfig(layout: .standard))
        #expect(decoded.templateConfig?.layout == .standard)
    }

    @Test("ItemCollection without templateConfig decodes nil")
    func itemCollectionWithoutConfigDecodesNil() throws {
        let original = ItemCollection(
            id: "01HICOLL",
            typeID: "01HITYPE",
            title: "Groceries",
            folderURL: folderURL(),
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ItemCollection.self, from: data)

        #expect(decoded.templateConfig == nil)
    }

    @Test("ItemCollection template_config encodes under snake_case key")
    func itemCollectionConfigSnakeCaseKey() throws {
        let original = ItemCollection(
            id: "01HICOLL",
            typeID: "01HITYPE",
            title: "Groceries",
            folderURL: folderURL(),
            modifiedAt: Date(timeIntervalSince1970: 1716480000),
            templateConfig: ItemTemplateConfig(layout: .standard)
        )

        let data = try JSONEncoder().encode(original)
        let raw = String(decoding: data, as: UTF8.self)
        #expect(raw.contains("\"template_config\""))
    }

    @Test("ItemCollection pinned_properties still round-trips after the change (no regression)")
    func itemCollectionPinnedPropertiesNoRegression() throws {
        let original = ItemCollection(
            id: "01HICOLL",
            typeID: "01HITYPE",
            title: "Groceries",
            folderURL: folderURL(),
            modifiedAt: Date(timeIntervalSince1970: 1716480000),
            pinnedProperties: ["p1", "p2"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ItemCollection.self, from: data)

        #expect(decoded.pinnedProperties == ["p1", "p2"])
        #expect(decoded.templateConfig == nil)
    }

    @Test("PageCollection with templateConfig round-trips equal")
    func pageCollectionWithConfigRoundTrips() throws {
        let original = PageCollection(
            id: "01HCOLL",
            typeID: "01HVAULT",
            title: "Tasks",
            folderURL: folderURL(),
            modifiedAt: Date(timeIntervalSince1970: 1716480000),
            templateConfig: PageTemplateConfig(defaultBody: "hello")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageCollection.self, from: data)

        #expect(decoded.templateConfig == PageTemplateConfig(defaultBody: "hello"))
        #expect(decoded.templateConfig?.defaultBody == "hello")
    }

    @Test("PageCollection without templateConfig decodes nil")
    func pageCollectionWithoutConfigDecodesNil() throws {
        let original = PageCollection(
            id: "01HCOLL",
            typeID: "01HVAULT",
            title: "Tasks",
            folderURL: folderURL(),
            modifiedAt: Date(timeIntervalSince1970: 1716480000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageCollection.self, from: data)

        #expect(decoded.templateConfig == nil)
    }
}
