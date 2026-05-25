import SwiftUI

// MARK: - DualRelationCoordinating

/// Protocol for paired-relation creation. Conforms to `DualRelationCoordinator` via an extension.
/// Defined here so tests can supply a mock without touching the real coordinator.
protocol DualRelationCoordinating {
    func createPairedRelation(
        source sourceKind: DualRelationCoordinator.TypeKind,
        sourcePropertyName: String,
        sourceScope: PropertyDefinition.RelationScope,
        target targetKind: DualRelationCoordinator.TypeKind,
        targetPropertyName: String,
        targetScope: PropertyDefinition.RelationScope,
        nexus: Nexus
    ) throws -> (sourcePropertyID: String, targetPropertyID: String)
}

extension DualRelationCoordinator: DualRelationCoordinating {
    func createPairedRelation(
        source sourceKind: TypeKind,
        sourcePropertyName: String,
        sourceScope: PropertyDefinition.RelationScope,
        target targetKind: TypeKind,
        targetPropertyName: String,
        targetScope: PropertyDefinition.RelationScope,
        nexus: Nexus
    ) throws -> (sourcePropertyID: String, targetPropertyID: String) {
        try DualRelationCoordinator.createPairedRelation(
            source: sourceKind,
            sourcePropertyName: sourcePropertyName,
            sourceScope: sourceScope,
            target: targetKind,
            targetPropertyName: targetPropertyName,
            targetScope: targetScope,
            nexus: nexus
        )
    }
}

// MARK: - RelationPropertyWizardViewModel

/// Scope kind for step 1.
enum WizardScopeKind: String, CaseIterable, Identifiable, Sendable {
    case pageType
    case itemType
    case pageCollection
    case itemCollection
    case contextTier

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pageType:       return "Page Type"
        case .itemType:       return "Item Type"
        case .pageCollection: return "Page Collection"
        case .itemCollection: return "Item Collection"
        case .contextTier:    return "Context Tier"
        }
    }

    /// `contextTier` skips the reverse-name step.
    var requiresReverseName: Bool { self != .contextTier }
}

/// Step enumeration for the wizard.
enum WizardStep: Int, CaseIterable, Sendable {
    case scopeKind = 1
    case target    = 2
    case propName  = 3
    case reverseName = 4
    case allowMultiple = 5
}

/// View-model for `RelationPropertyWizard`. All mutation on the MainActor.
@Observable
@MainActor
final class RelationPropertyWizardViewModel {
    // Step 1
    var selectedScopeKind: WizardScopeKind = .pageType
    // Step 2
    var targetID: String = ""          // Page/Item Type or Collection ID, or "1"/"2"/"3" for tier
    var targetTier: Int = 1
    // Step 3
    var propertyName: String = ""
    // Step 4
    var reverseName: String = ""
    // Step 5
    var allowsMultiple: Bool = false

    var currentStep: WizardStep = .scopeKind
    var isCancelled = false

    // MARK: - Navigation helpers

    var canAdvance: Bool {
        switch currentStep {
        case .scopeKind:     return true
        case .target:        return !targetID.isEmpty
        case .propName:      return !propertyName.trimmingCharacters(in: .whitespaces).isEmpty
        case .reverseName:   return !reverseName.trimmingCharacters(in: .whitespaces).isEmpty
        case .allowMultiple: return true
        }
    }

    func advance() {
        switch currentStep {
        case .scopeKind:
            currentStep = .target
        case .target:
            currentStep = .propName
        case .propName:
            // Skip step 4 for contextTier
            currentStep = selectedScopeKind.requiresReverseName ? .reverseName : .allowMultiple
        case .reverseName:
            currentStep = .allowMultiple
        case .allowMultiple:
            break  // handled by Save
        }
    }

    func back() {
        switch currentStep {
        case .scopeKind:     break
        case .target:        currentStep = .scopeKind
        case .propName:      currentStep = .target
        case .reverseName:   currentStep = .propName
        case .allowMultiple: currentStep = selectedScopeKind.requiresReverseName ? .reverseName : .propName
        }
    }

    var isFirstStep: Bool { currentStep == .scopeKind }

    var stepTitle: String {
        switch currentStep {
        case .scopeKind:     return "Choose Scope"
        case .target:        return "Choose Target"
        case .propName:      return "Property Name"
        case .reverseName:   return "Reverse Name"
        case .allowMultiple: return "Allow Multiple"
        }
    }

    // MARK: - Built args for tests / Save

    func buildSourceScope() -> PropertyDefinition.RelationScope? {
        switch selectedScopeKind {
        case .pageType:       return targetID.isEmpty ? nil : .pageType(targetID)
        case .itemType:       return targetID.isEmpty ? nil : .itemType(targetID)
        case .pageCollection: return targetID.isEmpty ? nil : .pageCollection(targetID)
        case .itemCollection: return targetID.isEmpty ? nil : .itemCollection(targetID)
        case .contextTier:    return .contextTier(targetTier)
        }
    }
}

// MARK: - RelationPropertyWizard

/// Multi-step wizard for creating a new Relation property on a Type.
///
/// Handles both paired (container-scope) and single-side (contextTier) creation.
/// Step 4 (reverse name) is skipped when `selectedScopeKind == .contextTier`.
struct RelationPropertyWizard: View {
    let sourceTypeID: String
    let sourceTypeKind: EntityKind
    let coordinator: any DualRelationCoordinating
    let index: PommoraIndex?
    let onComplete: (Result<(sourcePropertyID: String, reversePropertyID: String?), any Error>) -> Void
    let onCancel: () -> Void

    @State private var vm = RelationPropertyWizardViewModel()
    @State private var availableTargets: [EntityRef] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(vm.stepTitle)
                .font(.headline)

            stepContent

            Divider()

            HStack {
                if !vm.isFirstStep {
                    Button("Back") { vm.back() }
                        .buttonStyle(.borderless)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.borderless)
                if vm.currentStep == .allowMultiple {
                    Button("Save") { commitSave() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Next") { vm.advance() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.canAdvance)
                }
            }
        }
        .padding()
        .frame(minWidth: 340, minHeight: 260)
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch vm.currentStep {
        case .scopeKind:
            WizardScopeKindStep(selectedScopeKind: $vm.selectedScopeKind)
        case .target:
            WizardTargetStep(
                scopeKind: vm.selectedScopeKind,
                targetID: $vm.targetID,
                targetTier: $vm.targetTier
            )
        case .propName:
            WizardNameStep(label: "Property name (this side):", value: $vm.propertyName)
        case .reverseName:
            WizardNameStep(label: "Reverse name (other side):", value: $vm.reverseName)
        case .allowMultiple:
            WizardAllowMultipleStep(allowsMultiple: $vm.allowsMultiple)
        }
    }

    // MARK: - Save

    private func commitSave() {
        // For contextTier: single-side only (no paired reverse)
        if vm.selectedScopeKind == .contextTier {
            let id = ReservedPropertyID.mintUserPropertyID()
            onComplete(.success((sourcePropertyID: id, reversePropertyID: nil)))
            return
        }

        // Container scopes: need a real nexus for DualRelationCoordinator.
        // In this wizard, the nexus is not passed — callers are expected to wrap
        // the coordinator with a pre-bound nexus. Here we surface a not-implemented
        // note; full wiring happens in the Type Settings sheet (post-J.6).
        onComplete(.failure(RelationPropertyWizardError.nexusNotBound))
    }
}

// MARK: - RelationPropertyWizardError

enum RelationPropertyWizardError: Error, Equatable {
    /// The wizard requires a bound nexus for paired-relation creation.
    /// Callers should wrap `DualRelationCoordinator` with a pre-bound nexus closure.
    case nexusNotBound
    /// Target ID was empty at save time.
    case emptyTargetID
}

// MARK: - Step sub-views (isolated, plain value types)

private struct WizardScopeKindStep: View {
    @Binding var selectedScopeKind: WizardScopeKind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(WizardScopeKind.allCases) { kind in
                WizardScopeKindRow(
                    kind: kind,
                    isSelected: selectedScopeKind == kind,
                    onSelect: { selectedScopeKind = kind }
                )
            }
        }
    }
}

private struct WizardScopeKindRow: View {
    let kind: WizardScopeKind
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(kind.displayName)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct WizardTargetStep: View {
    let scopeKind: WizardScopeKind
    @Binding var targetID: String
    @Binding var targetTier: Int

    var body: some View {
        if scopeKind == .contextTier {
            Picker("Tier", selection: $targetTier) {
                Text("Tier 1 (Spaces)").tag(1)
                Text("Tier 2 (Topics)").tag(2)
                Text("Tier 3 (Projects)").tag(3)
            }
            .pickerStyle(.inline)
            .onAppear { targetID = "\(targetTier)" }
            .onChange(of: targetTier) { _, newVal in targetID = "\(newVal)" }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Target ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Enter ID…", text: $targetID)
                    .textFieldStyle(.roundedBorder)
                Text("In a full integration, this picker would list available Types from the index.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct WizardNameStep: View {
    let label: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Enter name…", text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct WizardAllowMultipleStep: View {
    @Binding var allowsMultiple: Bool

    var body: some View {
        Toggle("Allow multiple relations", isOn: $allowsMultiple)
    }
}
