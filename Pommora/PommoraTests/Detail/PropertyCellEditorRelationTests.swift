import Foundation
import SwiftUI
import Testing

@testable import Pommora

/// Construction tests for `PropertyCellEditor`'s `.relation` case — the inline
/// Table-cell relation editor wired to `RelationPicker`.
///
/// `RelationPicker` loads candidates from a live SQLite DB via
/// `IndexQuery.entitiesByTarget(_:)`, so these tests validate that the editor
/// constructs without a DB (`index: nil`) and across the relation-definition
/// shapes the cell must tolerate — a relation with a target, a relation with no
/// stored value, and the defensive no-target case (the property validator
/// prevents it, but `relationTarget` is typed optional). The SwiftUI body is
/// never evaluated here (it reads `@Environment` injected only at the app root —
/// see quirk #16); selection + load behavior is covered by `RelationPickerTests`.
@Suite("PropertyCellEditorRelationTests")
struct PropertyCellEditorRelationTests {

    // MARK: - Helper

    private func makeEditor(
        relationTarget: PropertyDefinition.RelationTarget?,
        value: PropertyValue?,
        index: PommoraIndex? = nil
    ) -> PropertyCellEditor {
        let definition = PropertyDefinition(
            id: "prop_rel_test",
            name: "Linked",
            type: .relation,
            relationTarget: relationTarget
        )
        return PropertyCellEditor(
            definition: definition,
            value: value,
            relationResolver: { _ in nil },
            commit: { _ in },
            index: index
        )
    }

    // MARK: - Tests

    @Test("Relation editor constructs with a target + nil index without crashing")
    func relationWithTargetNilIndexConstructs() {
        let editor = makeEditor(
            relationTarget: .contextTier(2),
            value: .relation(["01H_TARGET"]),
            index: nil
        )
        _ = editor
    }

    @Test("Relation editor constructs with no stored value (unset cell)")
    func relationWithNoValueConstructs() {
        let editor = makeEditor(relationTarget: .contextTier(1), value: nil)
        _ = editor
    }

    @Test("Relation editor constructs when relationTarget is nil (defensive case)")
    func relationWithNilTargetConstructs() {
        let editor = makeEditor(relationTarget: nil, value: nil)
        _ = editor
    }
}
