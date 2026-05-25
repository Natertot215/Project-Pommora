import Foundation
import SwiftUI
import Testing

@testable import Pommora

/// Tests for `StatusPicker` — the grouped status popover added in Phase J.3.
///
/// SwiftUI view rendering is not directly testable without ViewInspector, so
/// tests validate the pure-logic methods extracted onto the struct:
/// - `resolveOption(_:)` — finds option + group pair for a value string.
/// - `resolvedColor(for:)` — pill color with group fallback.
/// - Section count from `defaultSeed()` matches the 3 fixed groups.
@Suite("StatusPickerTests")
struct StatusPickerTests {

    // MARK: - Helpers

    private var defaultGroups: [PropertyDefinition.StatusGroup] {
        PropertyDefinition.StatusGroup.defaultSeed()
    }

    private func makePicker(selected: String?) -> StatusPicker {
        var sel = selected
        return StatusPicker(
            selectedValue: Binding(get: { sel }, set: { sel = $0 }),
            statusGroups: defaultGroups,
            onSelect: { _ in }
        )
    }

    // MARK: - Test 1: defaultSeed produces 3 groups

    @Test("StatusGroup.defaultSeed() returns exactly 3 groups")
    func defaultSeedHasThreeGroups() {
        #expect(defaultGroups.count == 3)
    }

    // MARK: - Test 2: total option count across all groups

    @Test("StatusPicker renders options for all groups combined")
    func totalOptionCount() {
        let total = defaultGroups.reduce(0) { $0 + $1.options.count }
        // Default seed: upcoming(1) + in_progress(1) + done(1) = 3
        #expect(total == 3)
    }

    // MARK: - Test 3: resolveOption for known value

    @Test("StatusPicker.resolveOption finds matching option and group")
    func resolveOptionKnownValue() {
        let picker = makePicker(selected: "in_progress")
        let result = picker.resolveOption("in_progress")
        #expect(result != nil)
        #expect(result?.0.value == "in_progress")
        #expect(result?.1.id == .inProgress)
    }

    // MARK: - Test 4: resolveOption for unknown value returns nil

    @Test("StatusPicker.resolveOption returns nil for unknown value")
    func resolveOptionUnknownValue() {
        let picker = makePicker(selected: nil)
        let result = picker.resolveOption("nonexistent_status")
        #expect(result == nil)
    }

    // MARK: - Test 5: resolvedColor uses option color when set

    @Test("StatusPicker.resolvedColor uses option's own color when present")
    func resolvedColorUsesOptionColor() {
        let picker = makePicker(selected: "in_progress")
        // The default seed has in_progress option with color .blue
        let color = picker.resolvedColor(for: "in_progress")
        #expect(color == Color.forSelectColor(.blue))
    }

    // MARK: - Test 6: resolvedColor falls back to group color when option.color is nil

    @Test("StatusPicker.resolvedColor falls back to group color when option has no color override")
    func resolvedColorFallsBackToGroupColor() {
        // Build a group where the option has no color override
        let groupWithNoOptionColor = PropertyDefinition.StatusGroup(
            id: .upcoming,
            label: "Upcoming",
            color: .orange,
            options: [
                PropertyDefinition.StatusOption(
                    value: "not_started", label: "Not started", color: nil, groupID: .upcoming
                )
            ]
        )
        var sel: String? = "not_started"
        let picker = StatusPicker(
            selectedValue: Binding(get: { sel }, set: { sel = $0 }),
            statusGroups: [groupWithNoOptionColor],
            onSelect: { _ in }
        )
        let color = picker.resolvedColor(for: "not_started")
        #expect(color == Color.forSelectColor(.orange))
    }

    // MARK: - Test 7: resolvedColor returns gray for unknown value

    @Test("StatusPicker.resolvedColor returns gray for unknown value")
    func resolvedColorForUnknownValueIsGray() {
        let picker = makePicker(selected: nil)
        let color = picker.resolvedColor(for: "unknown_value")
        #expect(color == Color.forSelectColor(.gray))
    }

    // MARK: - Test 8: group IDs match StatusGroupID enum

    @Test("defaultSeed groups have the correct StatusGroupID values in order")
    func defaultSeedGroupIDs() {
        #expect(defaultGroups[0].id == .upcoming)
        #expect(defaultGroups[1].id == .inProgress)
        #expect(defaultGroups[2].id == .done)
    }

    // MARK: - Test 9: picker constructs without crashing for nil selection

    @Test("StatusPicker constructs without crashing when selectedValue is nil")
    func constructsWithNilSelection() {
        let picker = makePicker(selected: nil)
        _ = picker
    }
}
