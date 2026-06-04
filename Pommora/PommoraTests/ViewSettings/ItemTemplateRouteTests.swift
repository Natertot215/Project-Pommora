import Testing

@testable import Pommora

/// T5.1 — the `.itemTemplate` route exists and names its pane to match the
/// Templates row label exactly (no singular/plural drift). The route is
/// payload-free; the pane derives its scope from its own `scope` property.
@Suite("ItemTemplate route")
struct ItemTemplateRouteTests {

    @Test("itemTemplate paneTitle is 'Templates'")
    func paneTitleMatchesRowLabel() {
        #expect(ViewSettingsRoute.itemTemplate.paneTitle == "Templates")
    }

    @Test("itemTemplate is Hashable-equal to itself (payload-free)")
    func payloadFreeEquality() {
        #expect(ViewSettingsRoute.itemTemplate == ViewSettingsRoute.itemTemplate)
    }
}
