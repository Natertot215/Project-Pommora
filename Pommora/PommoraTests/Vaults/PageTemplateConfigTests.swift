import Testing
import Foundation
@testable import Pommora

@Suite struct PageTemplateConfigTests {
    @Test func fullConfigRoundTrips() throws {
        let c = PageTemplateConfig(layout: .reserved, defaultBody: "body", openIn: .preview)
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(PageTemplateConfig.self, from: data) == c)
    }
    @Test func openInFullPageRoundTrips() throws {  // guards the `full_page` raw value
        let c = PageTemplateConfig(openIn: .fullPage)
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(PageTemplateConfig.self, from: data) == c)
    }
    @Test func pageTypeWithNilTemplateRoundTrips() throws {  // back-compat guard
        let t = PageType(
            id: "01H", title: "T", icon: nil, properties: [], views: [],
            modifiedAt: .init(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(t)
        #expect(try JSONDecoder().decode(PageType.self, from: data).templateConfig == nil)
    }
}
