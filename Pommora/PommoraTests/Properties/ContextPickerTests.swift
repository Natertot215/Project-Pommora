import Foundation
import SwiftUI
import Testing

@testable import Pommora

/// Tests for `ContextPicker` — the scope-aware context-link picker added in Phase J.4.
///
/// `IndexQuery.entitiesByContextTarget(_:)` requires a live SQLite DB, so these tests
/// validate the pure selection logic via `computeSelection(id:wasSelected:current:)`,
/// and validate nil-index construction without a DB.
@Suite("ContextPickerTests")
struct ContextPickerTests {

    // MARK: - Helpers

    private func makePicker(
        selectedIDs: [String] = [],
        scope: PropertyDefinition.RelationTarget = .contextTier(2),
        index: PommoraIndex? = nil
    ) -> ContextPicker {
        var ids = selectedIDs
        return ContextPicker(
            selectedIDs: Binding(get: { ids }, set: { ids = $0 }),
            scope: scope,
            index: index,
            onSelect: { _ in }
        )
    }

    // MARK: - Test 1: nil index constructs without crashing

    @Test("ContextPicker with nil index constructs without crashing")
    func nilIndexNoCrash() {
        let picker = makePicker(index: nil)
        _ = picker
    }

    // MARK: - Test 2: scope .contextTier returns flat (tier-only post-Relations-redesign)

    @Test("ContextPicker accepts .contextTier scope without crashing")
    func contextTierScopeAccepted2() {
        let picker = makePicker(scope: .contextTier(1), index: nil)
        _ = picker
    }

    // MARK: - Test 3: scope contextTier(2) accepted

    @Test("ContextPicker accepts .contextTier(2) scope without crashing")
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

    // MARK: - Test 8: contextTier scopes accepted

    @Test("ContextPicker accepts contextTier scopes without crashing")
    func contextTierScopesAccepted() {
        let scopes: [PropertyDefinition.RelationTarget] = [
            .contextTier(1),
            .contextTier(2),
            .contextTier(3),
        ]
        for scope in scopes {
            let picker = makePicker(scope: scope, index: nil)
            _ = picker
        }
    }

    // MARK: - Test 9: a new selection appends to the END (preserves order)
    // The reskinned checkbox+chip rows render candidates in scope order; the
    // selection array must append new picks rather than prepend, so chip order
    // stays stable as the user toggles.

    @Test("Selecting a new entity appends to the end, preserving prior order")
    func newSelectionAppendsToEnd() {
        let picker = makePicker()
        let result = picker.computeSelection(
            id: "01H_C",
            wasSelected: false,
            current: ["01H_A", "01H_B"]
        )
        #expect(result == ["01H_A", "01H_B", "01H_C"])
    }

    // MARK: - Test 10: removing a middle selection keeps the rest in order

    @Test("Removing a middle selection keeps the remaining order intact")
    func removeMiddlePreservesOrder() {
        let picker = makePicker()
        let result = picker.computeSelection(
            id: "01H_B",
            wasSelected: true,
            current: ["01H_A", "01H_B", "01H_C"]
        )
        #expect(result == ["01H_A", "01H_C"])
    }
}
