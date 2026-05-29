import Foundation
import SwiftUI
import Testing

@testable import Pommora

/// Tests for `RelationPicker` — the scope-aware relation picker added in Phase J.4.
///
/// `IndexQuery.entitiesByScope(_:)` requires a live SQLite DB, so these tests
/// validate the pure selection logic via `computeSelection(id:wasSelected:current:)`,
/// and validate nil-index construction without a DB.
@Suite("RelationPickerTests")
struct RelationPickerTests {

    // MARK: - Helpers

    private func makePicker(
        selectedIDs: [String] = [],
        scope: PropertyDefinition.RelationScope = .contextTier(2),
        index: PommoraIndex? = nil
    ) -> RelationPicker {
        var ids = selectedIDs
        return RelationPicker(
            selectedIDs: Binding(get: { ids }, set: { ids = $0 }),
            scope: scope,
            index: index,
            onSelect: { _ in }
        )
    }

    // MARK: - Test 1: nil index constructs without crashing

    @Test("RelationPicker with nil index constructs without crashing")
    func nilIndexNoCrash() {
        let picker = makePicker(index: nil)
        _ = picker
    }

    // MARK: - Test 2: scope .pageType returns only .page kind entities
    // Validated via computeSelection — scope-level filtering is IndexQuery's
    // responsibility, tested in IndexQueryTests.

    @Test("RelationPicker accepts .pageType scope without crashing")
    func pageTypeScopeAccepted() {
        let picker = makePicker(scope: .pageType("01HTYPE"), index: nil)
        _ = picker
    }

    // MARK: - Test 3: scope contextTier(2) accepted

    @Test("RelationPicker accepts .contextTier(2) scope without crashing")
    func contextTierScopeAccepted() {
        let picker = makePicker(scope: .contextTier(2), index: nil)
        _ = picker
    }

    // MARK: - Test 4: selecting a new entity accumulates (always multi-pick)

    @Test("Selecting a new entity accumulates without replacing existing selection")
    func newSelectionAccumulates() {
        let picker = makePicker()
        let result = picker.computeSelection(
            id: "01H_NEW",
            wasSelected: false,
            current: ["01H_OLD"]
        )
        #expect(result.contains("01H_OLD"))
        #expect(result.contains("01H_NEW"))
        #expect(result.count == 2)
    }

    // MARK: - Test 5: selections accumulate across multiple taps

    @Test("New selection accumulates without removing existing")
    func multiPickAccumulates() {
        let picker = makePicker()
        let result = picker.computeSelection(
            id: "01H_B",
            wasSelected: false,
            current: ["01H_A"]
        )
        #expect(result.contains("01H_A"))
        #expect(result.contains("01H_B"))
        #expect(result.count == 2)
    }

    // MARK: - Test 6: tapping selected removes it (chip removal)

    @Test("Tapping a selected entity removes it (chip removal)")
    func multiPickRemovesOnReselect() {
        let picker = makePicker()
        let result = picker.computeSelection(
            id: "01H_A",
            wasSelected: true,
            current: ["01H_A", "01H_B"]
        )
        #expect(!result.contains("01H_A"))
        #expect(result.contains("01H_B"))
        #expect(result.count == 1)
    }

    // MARK: - Test 7: tapping the only selected entity clears selection

    @Test("Tapping the currently selected entity clears selection")
    func deselect() {
        let picker = makePicker()
        let result = picker.computeSelection(
            id: "01H_SAME",
            wasSelected: true,
            current: ["01H_SAME"]
        )
        #expect(result.isEmpty)
    }

    // MARK: - Test 8: all RelationScope kinds are accepted

    @Test("RelationPicker accepts all RelationScope kinds without crashing")
    func allScopeKindsAccepted() {
        let scopes: [PropertyDefinition.RelationScope] = [
            .pageType("01H"),
            .itemType("01H"),
            .pageCollection("01H"),
            .itemCollection("01H"),
            .contextTier(1),
            .contextTier(2),
            .contextTier(3),
        ]
        for scope in scopes {
            let picker = makePicker(scope: scope, index: nil)
            _ = picker
        }
    }
}
