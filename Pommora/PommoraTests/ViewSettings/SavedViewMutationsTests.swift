import Foundation
import Testing

@testable import Pommora

/// Coverage for the ported per-view visibility-toggle semantics and the
/// visibility-list builder (`SavedViewMutations`), plus the `show_banner`
/// round-trip on `SavedView`.
@Suite struct SavedViewMutationsTests {
    private func makeView() -> SavedView {
        SavedView(
            id: "view_01HVIEW",
            propertyOrder: ["_title", "prop_a", "prop_b"],
            hiddenProperties: []
        )
    }

    // MARK: - applyToggle

    @Test func hideRemovesFromOrderAndAppendsHidden() {
        var view = makeView()
        SavedViewMutations.applyToggle(&view, propertyID: "prop_a", currentlyVisible: true)
        #expect(view.propertyOrder == ["_title", "prop_b"])
        #expect(view.hiddenProperties == ["prop_a"])
    }

    @Test func unhideReinsertsAfterTitle() {
        var view = SavedView(
            id: "view_01HVIEW",
            propertyOrder: ["_title", "prop_b"],
            hiddenProperties: ["prop_a"]
        )
        SavedViewMutations.applyToggle(&view, propertyID: "prop_a", currentlyVisible: false)
        #expect(view.propertyOrder == ["_title", "prop_a", "prop_b"])
        #expect(view.hiddenProperties == [])
    }

    @Test func unhideWithoutTitleLeadInsertsAtFront() {
        var view = SavedView(
            id: "view_01HVIEW",
            propertyOrder: ["prop_b"],
            hiddenProperties: ["prop_a"]
        )
        SavedViewMutations.applyToggle(&view, propertyID: "prop_a", currentlyVisible: false)
        #expect(view.propertyOrder == ["prop_a", "prop_b"])
    }

    @Test func modifiedAtIsToggleable() {
        var view = SavedView(
            id: "view_01HVIEW",
            propertyOrder: ["_title", ReservedPropertyID.modifiedAt],
            hiddenProperties: []
        )
        // Hide it.
        SavedViewMutations.applyToggle(
            &view, propertyID: ReservedPropertyID.modifiedAt, currentlyVisible: true)
        #expect(view.propertyOrder == ["_title"])
        #expect(view.hiddenProperties == [ReservedPropertyID.modifiedAt])
        // Un-hide it.
        SavedViewMutations.applyToggle(
            &view, propertyID: ReservedPropertyID.modifiedAt, currentlyVisible: false)
        #expect(view.propertyOrder == ["_title", ReservedPropertyID.modifiedAt])
        #expect(view.hiddenProperties == [])
    }

    @Test func titleToggleIsNoOp() {
        var view = makeView()
        SavedViewMutations.applyToggle(
            &view, propertyID: ReservedPropertyID.title, currentlyVisible: true)
        #expect(view.propertyOrder == ["_title", "prop_a", "prop_b"])
        #expect(view.hiddenProperties == [])
    }

    // MARK: - visibilityColumns

    @Test func visibilityColumnsIncludeTiersAndModifiedExcludeCover() {
        let resolved: [PropertyDefinition] = [
            PropertyDefinition(id: "_title", name: "Title", type: .url),
            PropertyDefinition(id: "prop_a", name: "Author", type: .select),
            PropertyDefinition(id: ReservedPropertyID.tier1, name: "Areas", type: .relation),
            PropertyDefinition(id: "cover", name: "Cover", type: .file),
        ]
        let cols = SavedViewMutations.visibilityColumns(resolved: resolved)
        let ids = cols.map(\.id)
        #expect(ids.contains(ReservedPropertyID.tier1))
        #expect(ids.contains(ReservedPropertyID.modifiedAt))
        #expect(!ids.contains("cover"))
        #expect(ids.contains("_title"))
    }

    // MARK: - show_banner round-trip

    @Test func showBannerRoundTrips() throws {
        let view = SavedView(id: "view_01HVIEW", showBanner: false)
        let data = try JSONEncoder().encode(view)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains(#""show_banner":false"#))
        let decoded = try JSONDecoder().decode(SavedView.self, from: data)
        #expect(decoded.showBanner == false)
    }

    @Test func showBannerAbsentDecodesNil() throws {
        let json = #"{"id":"view_01HVIEW","name":"Table","type":"table"}"#
        let decoded = try JSONDecoder().decode(SavedView.self, from: Data(json.utf8))
        #expect(decoded.showBanner == nil)
    }
}
