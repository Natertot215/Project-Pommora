import Foundation
import Testing

@testable import Pommora

/// Coverage for the per-view visibility-toggle semantics and the
/// visibility-list builder (`SavedViewMutations`), plus the `show_banner`
/// round-trip on `SavedView`.
///
/// Toggle semantics (new, single-list model):
///   - Hide: append to `hiddenProperties`; `propertyOrder` is UNCHANGED.
///   - Un-hide: remove from `hiddenProperties`; `propertyOrder` is UNCHANGED.
///   Row positions are preserved — un-hiding never moves a property to the top.
@Suite struct SavedViewMutationsTests {
    private func makeView() -> SavedView {
        SavedView(
            id: "view_01HVIEW",
            propertyOrder: ["_title", "prop_a", "prop_b"],
            hiddenProperties: []
        )
    }

    // MARK: - applyToggle

    @Test func hideAppendsToHiddenLeavesOrderIntact() {
        var view = makeView()
        SavedViewMutations.applyToggle(&view, propertyID: "prop_a", currentlyVisible: true)
        // propertyOrder is unchanged — the row keeps its position in the list.
        #expect(view.propertyOrder == ["_title", "prop_a", "prop_b"])
        #expect(view.hiddenProperties == ["prop_a"])
    }

    @Test func unhideRemovesFromHiddenLeavesOrderIntact() {
        var view = SavedView(
            id: "view_01HVIEW",
            propertyOrder: ["_title", "prop_a", "prop_b"],
            hiddenProperties: ["prop_a"]
        )
        SavedViewMutations.applyToggle(&view, propertyID: "prop_a", currentlyVisible: false)
        // Position preserved — prop_a stays between _title and prop_b.
        #expect(view.propertyOrder == ["_title", "prop_a", "prop_b"])
        #expect(view.hiddenProperties == [])
    }

    @Test func unhideWhenNotInOrderLeavesOrderUntouched() {
        // A property absent from propertyOrder (stale/unaccounted) still only
        // has its hiddenProperties entry removed; no insertion into propertyOrder.
        var view = SavedView(
            id: "view_01HVIEW",
            propertyOrder: ["_title", "prop_b"],
            hiddenProperties: ["prop_a"]
        )
        SavedViewMutations.applyToggle(&view, propertyID: "prop_a", currentlyVisible: false)
        #expect(view.propertyOrder == ["_title", "prop_b"])
        #expect(view.hiddenProperties == [])
    }

    @Test func modifiedAtIsToggleable() {
        var view = SavedView(
            id: "view_01HVIEW",
            propertyOrder: ["_title", ReservedPropertyID.modifiedAt],
            hiddenProperties: []
        )
        // Hide it — propertyOrder stays the same.
        SavedViewMutations.applyToggle(
            &view, propertyID: ReservedPropertyID.modifiedAt, currentlyVisible: true)
        #expect(view.propertyOrder == ["_title", ReservedPropertyID.modifiedAt])
        #expect(view.hiddenProperties == [ReservedPropertyID.modifiedAt])
        // Un-hide it — propertyOrder still the same.
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
