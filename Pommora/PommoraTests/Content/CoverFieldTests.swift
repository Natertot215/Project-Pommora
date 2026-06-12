import Foundation
import Testing

@testable import Pommora

/// Covers the cover/banner DATA fields: PageFrontmatter `cover` round-trips and
/// is registered in `modeledKeys`; `banner` round-trips on PageType + PageCollection.
@Suite("CoverFieldTests")
struct CoverFieldTests {

    @Test("coverRoundTripsThroughEncodeDecode")
    func coverRoundTripsThroughEncodeDecode() throws {
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date(timeIntervalSince1970: 0),
            cover: ".nexus/assets/ID/photo.png"
        )
        let data = try JSONEncoder().encode(fm)
        let decoded = try JSONDecoder().decode(PageFrontmatter.self, from: data)
        #expect(decoded.cover == ".nexus/assets/ID/photo.png")
    }

    @Test("coverNilDoesNotEncodeKey")
    func coverNilDoesNotEncodeKey() throws {
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [:], createdAt: Date()
        )
        let data = try JSONEncoder().encode(fm)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("\"cover\""))
    }

    @Test("modeledKeysContainsCover")
    func modeledKeysContainsCover() {
        #expect(PageFrontmatter.modeledKeys.contains("cover"))
    }

    @Test("bannerRoundTripsOnPageType")
    func bannerRoundTripsOnPageType() throws {
        let type = PageType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date(),
            banner: ".nexus/assets/ID/banner.jpg"
        )
        let data = try JSONEncoder().encode(type)
        let decoded = try JSONDecoder().decode(PageType.self, from: data)
        #expect(decoded.banner == ".nexus/assets/ID/banner.jpg")
    }

    @Test("bannerRoundTripsOnPageCollection")
    func bannerRoundTripsOnPageCollection() throws {
        let collection = PageCollection(
            id: ULID.generate(), typeID: ULID.generate(),
            title: "C", folderURL: URL(fileURLWithPath: "/tmp/C"),
            modifiedAt: Date(),
            banner: ".nexus/assets/ID/banner.png"
        )
        let data = try JSONEncoder().encode(collection)
        let decoded = try JSONDecoder().decode(PageCollection.self, from: data)
        #expect(decoded.banner == ".nexus/assets/ID/banner.png")
    }
}
