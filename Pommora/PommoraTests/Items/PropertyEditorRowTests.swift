import Foundation
import SwiftUI
import Testing

@testable import Pommora

/// Structural tests verifying that `PropertyEditorRow` can be constructed
/// (initialised without crashing) for every `PropertyType` case.
///
/// ViewInspector is not a declared dependency, so we validate through the
/// Swift type system + init path only: if the `PropertyEditorRow` init
/// completes without a runtime trap, the dispatch table is intact.
@Suite("PropertyEditorRowTests")
struct PropertyEditorRowTests {

    // MARK: - Helpers

    private func makeDef(type: PropertyType) -> PropertyDefinition {
        PropertyDefinition(
            id: "prop_\(type.rawValue)",
            name: type.rawValue.capitalized,
            type: type
        )
    }

    private func makeDef(type: PropertyType, selectOptions: [PropertyDefinition.SelectOption]) -> PropertyDefinition {
        PropertyDefinition(
            id: "prop_\(type.rawValue)",
            name: type.rawValue.capitalized,
            type: type,
            selectOptions: selectOptions
        )
    }

    private func makeDef(type: PropertyType, statusGroups: [PropertyDefinition.StatusGroup]) -> PropertyDefinition {
        PropertyDefinition(
            id: "prop_\(type.rawValue)",
            name: type.rawValue.capitalized,
            type: type,
            statusGroups: statusGroups
        )
    }

    // MARK: - Tests (one per PropertyType case)

    @Test("PropertyEditorRow constructs for .number")
    func constructsForNumber() {
        var value: PropertyValue = .number(42.0)
        let row = PropertyEditorRow(
            definition: makeDef(type: .number),
            value: Binding(get: { value }, set: { value = $0 })
        )
        // If we reach here without a crash, dispatch is intact.
        _ = row
    }

    @Test("PropertyEditorRow constructs for .checkbox")
    func constructsForCheckbox() {
        var value: PropertyValue = .checkbox(true)
        let row = PropertyEditorRow(
            definition: makeDef(type: .checkbox),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .date")
    func constructsForDate() {
        var value: PropertyValue = .date(Date())
        let row = PropertyEditorRow(
            definition: makeDef(type: .date),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .datetime")
    func constructsForDatetime() {
        var value: PropertyValue = .datetime(Date())
        let row = PropertyEditorRow(
            definition: makeDef(type: .datetime),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .select")
    func constructsForSelect() {
        let opts = [PropertyDefinition.SelectOption(value: "opt1", label: "Option 1", color: .blue)]
        var value: PropertyValue = .select("opt1")
        let row = PropertyEditorRow(
            definition: makeDef(type: .select, selectOptions: opts),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .multiSelect")
    func constructsForMultiSelect() {
        let opts = [
            PropertyDefinition.SelectOption(value: "a", label: "A", color: nil),
            PropertyDefinition.SelectOption(value: "b", label: "B", color: nil),
        ]
        var value: PropertyValue = .multiSelect(["a"])
        let row = PropertyEditorRow(
            definition: makeDef(type: .multiSelect, selectOptions: opts),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .relation")
    func constructsForRelation() {
        var value: PropertyValue = .relation("01HRELID")
        let row = PropertyEditorRow(
            definition: makeDef(type: .relation),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .url")
    func constructsForURL() {
        var value: PropertyValue = .url(URL(string: "https://example.com")!)
        let row = PropertyEditorRow(
            definition: makeDef(type: .url),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .status with value")
    func constructsForStatus() {
        let groups = PropertyDefinition.StatusGroup.defaultSeed()
        var value: PropertyValue = .status("in_progress")
        let row = PropertyEditorRow(
            definition: makeDef(type: .status, statusGroups: groups),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .status with empty value")
    func constructsForStatusEmpty() {
        let groups = PropertyDefinition.StatusGroup.defaultSeed()
        var value: PropertyValue = .status("")
        let row = PropertyEditorRow(
            definition: makeDef(type: .status, statusGroups: groups),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .lastEditedTime")
    func constructsForLastEditedTime() {
        var value: PropertyValue = .lastEditedTime
        let row = PropertyEditorRow(
            definition: makeDef(type: .lastEditedTime),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .file with refs")
    func constructsForFile() {
        var value: PropertyValue = .file([])
        let row = PropertyEditorRow(
            definition: makeDef(type: .file),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }

    @Test("PropertyEditorRow constructs for .file with non-empty refs")
    func constructsForFileNonEmpty() {
        let ref = FileRef(
            path: ".nexus/attachments/01H/doc.pdf",
            originalName: "doc.pdf",
            addedAt: Date(timeIntervalSince1970: 0),
            mimeType: "application/pdf"
        )
        var value: PropertyValue = .file([ref])
        let row = PropertyEditorRow(
            definition: makeDef(type: .file),
            value: Binding(get: { value }, set: { value = $0 })
        )
        _ = row
    }
}
