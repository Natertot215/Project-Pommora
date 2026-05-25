import Foundation
import SwiftUI
import Testing

@testable import Pommora

/// Tests for `PropertyTypePicker` and `PropertyType.userCreatable`.
@Suite("PropertyTypePickerTests")
struct PropertyTypePickerTests {

    // MARK: - Test 1: userCreatable enumerates exactly 10 cases

    @Test("PropertyType.userCreatable enumerates exactly 10 cases")
    func userCreatableCountIs10() {
        #expect(PropertyType.userCreatable.count == 10)
    }

    // MARK: - Test 2: lastEditedTime is NOT in userCreatable

    @Test("PropertyType.userCreatable does NOT include .lastEditedTime")
    func lastEditedTimeExcluded() {
        let excluded = PropertyType.userCreatable.first(where: { $0 == .lastEditedTime })
        #expect(excluded == nil)
    }

    // MARK: - Test 3: the 10 expected cases are all present

    @Test("PropertyType.userCreatable contains all 10 expected property types")
    func expectedCasesPresent() {
        let expected: Set<PropertyType> = [
            .number, .checkbox, .date, .datetime,
            .select, .multiSelect, .status, .url, .relation, .file,
        ]
        let actual = Set(PropertyType.userCreatable)
        #expect(actual == expected)
    }

    // MARK: - Test 4: each type has a non-empty display name

    @Test("All userCreatable types have a non-empty displayName")
    func allTypesHaveDisplayName() {
        for type_ in PropertyType.userCreatable {
            #expect(!type_.displayName.isEmpty)
        }
    }

    // MARK: - Test 5: each type has a non-empty picker icon

    @Test("All userCreatable types have a non-empty pickerIcon")
    func allTypesHavePickerIcon() {
        for type_ in PropertyType.userCreatable {
            #expect(!type_.pickerIcon.isEmpty)
        }
    }

    // MARK: - Test 6: PropertyTypePicker constructs without crashing (nil selected)

    @Test("PropertyTypePicker constructs with nil selected binding without crashing")
    @MainActor
    func pickerConstructsWithNilSelected() {
        var selected: PropertyType? = nil
        let picker = PropertyTypePicker(
            selected: .init(get: { selected }, set: { selected = $0 }),
            onSelect: { _ in }
        )
        _ = picker
    }

    // MARK: - Test 7: onSelect callback is called with the correct type

    @Test("PropertyTypePicker.onSelect is called with the tapped PropertyType")
    @MainActor
    func onSelectCalledWithCorrectType() {
        var selected: PropertyType? = nil
        var receivedType: PropertyType? = nil
        let picker = PropertyTypePicker(
            selected: .init(get: { selected }, set: { selected = $0 }),
            onSelect: { type in receivedType = type }
        )
        // Simulate selection by calling the callback directly (no SwiftUI driver needed)
        picker.onSelect(.relation)
        #expect(receivedType == .relation)
    }

    // MARK: - Test 8: no duplicate entries in userCreatable

    @Test("PropertyType.userCreatable contains no duplicate entries")
    func noDuplicates() {
        let arr = PropertyType.userCreatable
        let unique = Set(arr)
        #expect(arr.count == unique.count)
    }
}
