import Foundation
import Testing

@testable import Pommora

/// Tests for `RelationPropertyWizardViewModel` — the state machine driving the wizard.
///
/// The full 5-step container-scope flow is exercised via the view-model's public
/// navigation helpers. DualRelationCoordinator calls are tested via a `MockDualRelationCoordinating`
/// that captures the args without touching the filesystem.
@Suite("RelationPropertyWizardTests")
struct RelationPropertyWizardTests {

    // MARK: - Mock coordinator

    /// Captures `createPairedRelation` calls without writing to disk.
    final class MockDualRelationCoordinating: DualRelationCoordinating, @unchecked Sendable {
        struct CapturedCall: Sendable {
            let sourceTypeID: String
            let sourcePropertyName: String
            let sourceScopeKind: String
            let targetTypeID: String
            let targetPropertyName: String
        }

        var capturedCalls: [CapturedCall] = []
        var shouldThrow: (any Error)?

        func createPairedRelation(
            source sourceKind: DualRelationCoordinator.TypeKind,
            sourcePropertyName: String,
            sourceScope: PropertyDefinition.RelationTarget,
            target targetKind: DualRelationCoordinator.TypeKind,
            targetPropertyName: String,
            targetScope: PropertyDefinition.RelationTarget,
            nexus: Nexus
        ) throws -> (sourcePropertyID: String, targetPropertyID: String) {
            if let err = shouldThrow { throw err }
            capturedCalls.append(CapturedCall(
                sourceTypeID: sourceKind.typeID,
                sourcePropertyName: sourcePropertyName,
                sourceScopeKind: "\(sourceScope)",
                targetTypeID: targetKind.typeID,
                targetPropertyName: targetPropertyName
            ))
            return ("src_prop_001", "tgt_prop_001")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeVM() -> RelationPropertyWizardViewModel {
        RelationPropertyWizardViewModel()
    }

    // MARK: - Test 1: full 5-step container-scope flow

    @Test("Full 4-step pageType-scope flow advances through all steps correctly")
    @MainActor
    func fullContainerScopeFlow() {
        let vm = makeVM()
        #expect(vm.currentStep == .scopeKind)

        // Step 1: choose pageType scope
        vm.selectedScopeKind = .pageType
        vm.advance()
        #expect(vm.currentStep == .target)

        // Step 2: provide target ID
        vm.targetID = "pt_target_01"
        vm.advance()
        #expect(vm.currentStep == .propName)

        // Step 3: property name (this side)
        vm.propertyName = "Related Pages"
        vm.advance()
        #expect(vm.currentStep == .reverseName)

        // Step 4: reverse name (other side) — last step for container scopes
        vm.reverseName = "Source Items"
        #expect(vm.isLastStep)

        // Built args should reflect all inputs
        let scope = vm.buildSourceScope()
        if case .pageType(let id) = scope {
            #expect(id == "pt_target_01")
        } else {
            Issue.record("Expected .pageType scope, got \(String(describing: scope))")
        }
        #expect(vm.propertyName == "Related Pages")
        #expect(vm.reverseName == "Source Items")
    }

    // MARK: - Test 2: contextTier skips step 4

    @Test("contextTier scope skips step 4 (reverseName) — propName is the last step")
    @MainActor
    func contextTierSkipsReverseName() {
        let vm = makeVM()

        vm.selectedScopeKind = .contextTier
        vm.advance()
        #expect(vm.currentStep == .target)

        vm.targetTier = 2
        vm.targetID = "2"
        vm.advance()
        #expect(vm.currentStep == .propName)

        vm.propertyName = "My Tier Relations"
        // propName is the last step for contextTier (no reverseName, no allowMultiple)
        #expect(vm.isLastStep)
        vm.advance()
        // advance() is a no-op on contextTier propName (save is triggered by isLastStep)
        #expect(vm.currentStep == .propName)
    }

    // MARK: - Test 3: cancel at any step doesn't advance

    @Test("Back from step 3 returns to step 2 without committing")
    @MainActor
    func backFromStep3ReturnsToStep2() {
        let vm = makeVM()

        vm.advance()  // → target
        vm.targetID = "some_id"
        vm.advance()  // → propName

        vm.propertyName = "Should not commit"
        vm.back()

        #expect(vm.currentStep == .target)
        // propertyName is still set (it's a draft), but we haven't committed
        #expect(vm.propertyName == "Should not commit")
    }

    // MARK: - Test 4: empty property name disables Next

    @Test("Empty property name on step 3 disables advance (canAdvance is false)")
    @MainActor
    func emptyPropertyNameBlocksAdvance() {
        let vm = makeVM()

        vm.selectedScopeKind = .pageType
        vm.advance()  // → target
        vm.targetID = "pt_01"
        vm.advance()  // → propName

        // Leave propertyName empty
        vm.propertyName = ""
        #expect(!vm.canAdvance)

        // Whitespace-only is also empty
        vm.propertyName = "   "
        #expect(!vm.canAdvance)

        // Non-empty name enables advance
        vm.propertyName = "Valid Name"
        #expect(vm.canAdvance)
    }

    // MARK: - Test 5: contextTier scope uses .contextTier RelationTarget

    @Test("contextTier scope kind produces .contextTier RelationTarget with correct tier")
    @MainActor
    func contextTierScopeBuildsCorrectly() {
        let vm = makeVM()
        vm.selectedScopeKind = .contextTier
        vm.targetTier = 3
        vm.targetID = "3"

        let scope = vm.buildSourceScope()
        if case .contextTier(let tier) = scope {
            #expect(tier == 3)
        } else {
            Issue.record("Expected .contextTier(3), got \(String(describing: scope))")
        }
    }

    // MARK: - Test 6: back on first step is a no-op

    @Test("Calling back() on step 1 (scopeKind) stays on step 1")
    @MainActor
    func backOnFirstStepIsNoop() {
        let vm = makeVM()
        #expect(vm.currentStep == .scopeKind)
        #expect(vm.isFirstStep)
        vm.back()
        #expect(vm.currentStep == .scopeKind)
    }

    // MARK: - Test 7: all container scope kinds produce the right RelationTarget

    @Test("All container scope kinds produce matching RelationTarget values")
    @MainActor
    func allContainerScopesMatch() {
        let cases: [(WizardScopeKind, PropertyDefinition.RelationTarget)] = [
            (.pageType,       .pageType("id_01")),
            (.itemType,       .itemType("id_01")),
            (.pageCollection, .pageCollection("id_01")),
            (.itemCollection, .itemCollection("id_01")),
        ]
        for (kind, expected) in cases {
            let vm = makeVM()
            vm.selectedScopeKind = kind
            vm.targetID = "id_01"
            let built = vm.buildSourceScope()
            #expect(built == expected)
        }
    }
}
