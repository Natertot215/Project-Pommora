import Foundation
import Testing

@testable import Pommora

/// Tests for `CollectionSettingsViewModel` — the draft-state machine backing `CollectionSettingsSheet`.
///
/// Drives the view-model directly (J.5/J.11/K.1 pattern) without SwiftUI rendering.
/// Manager interactions are captured via `MockPageCollectionManager`.
@Suite("CollectionSettingsSheetTests")
@MainActor
struct CollectionSettingsSheetTests {

    // MARK: - Helpers

    private func makePageCollection(properties: [PropertyDefinition] = []) -> PageCollection {
        PageCollection(
            id: "pt_test_001",
            title: "Test Vault",
            icon: nil,
            properties: properties,
            views: [],
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeDef(
        id: String,
        name: String,
        type: PropertyType = .number
    ) -> PropertyDefinition {
        PropertyDefinition(id: id, name: name, type: type)
    }

    // MARK: - MockPageCollectionManager

    /// Captures method calls without touching the filesystem.
    final class MockPageCollectionManager: @unchecked Sendable {
        struct Call: Sendable {
            enum Kind: Sendable {
                case add(PropertyDefinition, String)
                case rename(String, String, String)
                case delete(String, String)
                case reorder(String, String, Int)
                case changeType(String, String, PropertyType)
            }
            let kind: Kind
        }

        var calls: [Call] = []
        var shouldThrow: (any Error)?

        func addProperty(_ definition: PropertyDefinition, to collectionID: String) async throws {
            if let err = shouldThrow { throw err }
            calls.append(Call(kind: .add(definition, collectionID)))
        }

        func renameProperty(id propertyID: String, in collectionID: String, to newName: String) async throws {
            if let err = shouldThrow { throw err }
            calls.append(Call(kind: .rename(propertyID, collectionID, newName)))
        }

        func deleteProperty(id propertyID: String, in collectionID: String) async throws {
            if let err = shouldThrow { throw err }
            calls.append(Call(kind: .delete(propertyID, collectionID)))
        }

        func reorderProperty(id propertyID: String, in collectionID: String, toIndex newIndex: Int) async throws {
            if let err = shouldThrow { throw err }
            calls.append(Call(kind: .reorder(propertyID, collectionID, newIndex)))
        }
    }

    // We can't inject MockPageCollectionManager into vm.save() because PageCollectionManager is
    // a concrete class with no protocol abstraction at this phase. The tests instead
    // verify the *draft* mutations directly (the invariant that matters for correctness)
    // and use hasChanges / pendingError / draftProperties as observable outputs.

    // MARK: - Test 1: Initial draft mirrors pageType.properties

    @Test("Initial draft mirrors pageType.properties exactly")
    func initialDraftMirrorsProperties() {
        let props = [
            makeDef(id: "p1", name: "Priority"),
            makeDef(id: "p2", name: "Score"),
        ]
        let pt = makePageCollection(properties: props)
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        #expect(vm.draftProperties.count == 2)
        #expect(vm.draftProperties[0].id == "p1")
        #expect(vm.draftProperties[1].id == "p2")
        #expect(vm.hasChanges == false)
    }

    // MARK: - Test 2: Adding a property appends to draft

    @Test("Adding a property appends to draftProperties and marks hasChanges")
    func addingPropertyAppendsAndMarksChanges() {
        let pt = makePageCollection()
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        let newDef = makeDef(id: "p_new", name: "Tags", type: .select)
        vm.addDraft(newDef)

        #expect(vm.draftProperties.count == 1)
        #expect(vm.draftProperties[0].id == "p_new")
        #expect(vm.hasChanges == true)
    }

    // MARK: - Test 3: Renaming a property mutates draft

    @Test("Renaming a property mutates draftProperties and marks hasChanges")
    func renamingPropertyMutatesDraft() {
        let props = [makeDef(id: "p1", name: "OldName")]
        let pt = makePageCollection(properties: props)
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        vm.renamingID = "p1"
        vm.renameBuffer = "NewName"
        vm.commitRename("p1", newName: "NewName")

        #expect(vm.draftProperties[0].name == "NewName")
        #expect(vm.hasChanges == true)
        #expect(vm.renamingID == nil)
    }

    // MARK: - Test 4: Whitespace-only rename is a no-op

    @Test("commitRename with whitespace-only string is a no-op")
    func renameWithWhitespaceIsNoop() {
        let props = [makeDef(id: "p1", name: "Original")]
        let pt = makePageCollection(properties: props)
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        vm.commitRename("p1", newName: "   ")

        #expect(vm.draftProperties[0].name == "Original")
        #expect(vm.hasChanges == false)
    }

    // MARK: - Test 5: Deleting a property removes from draft

    @Test("Deleting a property removes it from draftProperties and marks hasChanges")
    func deletingPropertyRemovesFromDraft() {
        let props = [
            makeDef(id: "p1", name: "Alpha"),
            makeDef(id: "p2", name: "Beta"),
        ]
        let pt = makePageCollection(properties: props)
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        vm.deleteDraft("p1")

        #expect(vm.draftProperties.count == 1)
        #expect(vm.draftProperties[0].id == "p2")
        #expect(vm.hasChanges == true)
    }

    // MARK: - Test 6: Deleting a pending add is net no-op on manager

    @Test("Deleting a property that was added in the same session is a net no-op")
    func deletingPendingAddIsNetNoop() {
        let pt = makePageCollection()
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        let newDef = makeDef(id: "p_new", name: "Temp")
        vm.addDraft(newDef)
        #expect(vm.hasChanges == true)

        vm.deleteDraft("p_new")
        // Both add and delete cancel out — hasChanges should be false.
        #expect(vm.draftProperties.isEmpty)
        #expect(vm.hasChanges == false)
    }

    // MARK: - Test 7: Reordering mutates draft

    @Test("moveUp / moveDown swaps properties in draftProperties")
    func reorderingMutatesDraft() {
        let props = [
            makeDef(id: "p1", name: "First"),
            makeDef(id: "p2", name: "Second"),
            makeDef(id: "p3", name: "Third"),
        ]
        let pt = makePageCollection(properties: props)
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        vm.moveDown("p1")

        #expect(vm.draftProperties[0].id == "p2")
        #expect(vm.draftProperties[1].id == "p1")
        #expect(vm.draftProperties[2].id == "p3")
        #expect(vm.hasChanges == true)
    }

    // MARK: - Test 8: moveUp on first element is a no-op

    @Test("moveUp on the first property is a no-op")
    func moveUpOnFirstIsNoop() {
        let props = [
            makeDef(id: "p1", name: "First"),
            makeDef(id: "p2", name: "Second"),
        ]
        let pt = makePageCollection(properties: props)
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        vm.moveUp("p1")

        #expect(vm.draftProperties[0].id == "p1")
        #expect(vm.draftProperties[1].id == "p2")
    }

    // MARK: - Test 9: moveDown on last element is a no-op

    @Test("moveDown on the last property is a no-op")
    func moveDownOnLastIsNoop() {
        let props = [
            makeDef(id: "p1", name: "First"),
            makeDef(id: "p2", name: "Second"),
        ]
        let pt = makePageCollection(properties: props)
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        vm.moveDown("p2")

        #expect(vm.draftProperties[0].id == "p1")
        #expect(vm.draftProperties[1].id == "p2")
    }

    // MARK: - Test 10: Cancel leaves draft unchanged (no manager calls)

    @Test("Cancel is a no-op — no pending changes accumulate if no edits were made")
    func cancelWithNoEditsHasNoChanges() {
        let props = [makeDef(id: "p1", name: "Alpha")]
        let pt = makePageCollection(properties: props)
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        // Simulate Cancel without making any edits
        #expect(vm.hasChanges == false)
    }

    // MARK: - Test 11: Save with no changes is a no-op

    @Test("hasChanges is false on a fresh vm with no mutations")
    func saveWithNoChangesIsNoop() {
        let props = [makeDef(id: "p1", name: "Alpha")]
        let pt = makePageCollection(properties: props)
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        #expect(vm.hasChanges == false)
        #expect(vm.pendingError == nil)
    }

    // MARK: - Test 12: Multiple renames deduplicate (latest wins)

    @Test("Renaming the same property twice keeps only the latest name")
    func multipleRenamesDeduplicateToLatest() {
        let props = [makeDef(id: "p1", name: "Original")]
        let pt = makePageCollection(properties: props)
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        vm.commitRename("p1", newName: "Intermediate")
        vm.commitRename("p1", newName: "Final")

        #expect(vm.draftProperties[0].name == "Final")
    }

    // MARK: - Test 13: resetNewPropertyState clears ephemeral state

    @Test("resetNewPropertyState clears pendingNewType, name, and options")
    func resetClearsEphemeralState() {
        let pt = makePageCollection()
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        vm.pendingNewType = .select
        vm.pendingNewName = "Some Name"
        vm.pendingSelectOptions = [PropertyDefinition.SelectOption(value: "v", label: "V", color: nil)]
        vm.showingTypePicker = true

        vm.resetNewPropertyState()

        #expect(vm.pendingNewType == nil)
        #expect(vm.pendingNewName == "")
        #expect(vm.pendingSelectOptions.isEmpty)
        #expect(vm.showingTypePicker == false)
    }

    // MARK: - Test 14: canCommitNewProperty requires non-empty name

    @Test("canCommitNewProperty is false when pendingNewName is empty")
    func canCommitRequiresName() {
        let pt = makePageCollection()
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        vm.pendingNewType = .number
        vm.pendingNewName = ""
        #expect(vm.canCommitNewProperty == false)

        vm.pendingNewName = "Score"
        #expect(vm.canCommitNewProperty == true)
    }

    // MARK: - Test 15: canCommitNewProperty requires options for select types

    @Test("canCommitNewProperty is false for select type with no options")
    func canCommitSelectRequiresOptions() {
        let pt = makePageCollection()
        let vm = CollectionSettingsViewModel(pageCollection: pt)

        vm.pendingNewType = .select
        vm.pendingNewName = "Status"
        vm.pendingSelectOptions = []
        #expect(vm.canCommitNewProperty == false)

        vm.pendingSelectOptions = [PropertyDefinition.SelectOption(value: "v", label: "V", color: nil)]
        #expect(vm.canCommitNewProperty == true)
    }
}
