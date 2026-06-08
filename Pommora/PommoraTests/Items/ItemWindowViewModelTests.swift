import Foundation
import Testing

@testable import Pommora

/// B1 — `ItemWindowViewModel` skeleton: init hydration of every draft from the
/// source Item, and the `isFilled` predicate that classifies falsy vs filled
/// property values. Pure logic; no store, no disk.
@Suite("ItemWindowViewModel") @MainActor
struct ItemWindowViewModelTests {
    /// Builds a VM with no-op seams. `onRename` echoes back the item it was
    /// constructed with (the skeleton never calls it, but it must be non-nil).
    /// `type` and `onUpdateProperty` are injectable so seam-driven tests can pin
    /// the schema (which decides `pinnedIDs`) and observe the property save.
    private func makeVM(
        item: Item,
        type: ItemType = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        ),
        onUpdateProperty: @escaping (String, PropertyValue) async throws -> Void = { _, _ in }
    ) -> ItemWindowViewModel {
        ItemWindowViewModel(
            item: item,
            itemType: type,
            collection: nil,
            onUpdateProperty: onUpdateProperty,
            onUpdateIcon: { _ in },
            onUpdateBody: { _ in },
            onRename: { _ in item },
            onDeleteItem: {}
        )
    }

    private func makeItem(
        icon: String?,
        description: String,
        tier1: [String] = [],
        tier3: [String] = [],
        properties: [String: PropertyValue] = [:]
    ) -> Item {
        Item(
            id: ULID.generate(), title: "Sample", icon: icon, description: description,
            tier1: tier1, tier2: [], tier3: tier3, properties: properties,
            createdAt: Date(), modifiedAt: Date()
        )
    }

    @Test func hydratesDraftsFromItem() {
        let item = makeItem(
            icon: "star", description: "the body",
            tier1: ["a"], tier3: ["c"], properties: ["p": .select("x")]
        )
        let vm = makeVM(item: item)

        #expect(vm.draftTitle == "Sample")
        #expect(vm.draftIcon == "star")
        #expect(vm.draftBody == "the body")
        #expect(vm.draftProperties["p"] == .select("x"))
        #expect(vm.draftTier1 == ["a"])
        #expect(vm.draftTier3 == ["c"])
    }

    @Test func isFilledClassifiesFalsyVsFilled() {
        // Falsy: the ways a value can exist yet show nothing.
        #expect(ItemWindowViewModel.isFilled(nil) == false)
        #expect(ItemWindowViewModel.isFilled(.null) == false)
        #expect(ItemWindowViewModel.isFilled(.multiSelect([])) == false)
        #expect(ItemWindowViewModel.isFilled(.relation([])) == false)
        #expect(ItemWindowViewModel.isFilled(.select("")) == false)
        #expect(ItemWindowViewModel.isFilled(.status("")) == false)

        // Filled: anything with content, including zero/false primitives.
        #expect(ItemWindowViewModel.isFilled(.select("x")) == true)
        #expect(ItemWindowViewModel.isFilled(.multiSelect(["a"])) == true)
        #expect(ItemWindowViewModel.isFilled(.number(0)) == true)
        #expect(ItemWindowViewModel.isFilled(.checkbox(false)) == true)
    }

    // MARK: - B2: handlePropertyChange
    //
    // The seam call is fire-and-forget (`Task { try? await onUpdateProperty }`).
    // To observe it without sleeps, `onUpdateProperty` resumes a continuation —
    // the synchronous draft/surfaced effects are asserted inside the continuation
    // body (right after calling the handler) and the captured seam value after
    // the await. Safe because the VM's Task holds `self` strongly, so the VM
    // survives until the seam fires.

    @Test func assignSetsDraftAndCallsSeam() async {
        let item = makeItem(icon: nil, description: "")
        let seamValue: PropertyValue = await withCheckedContinuation { continuation in
            let vm = makeVM(item: item, onUpdateProperty: { _, value in continuation.resume(returning: value) })
            vm.handlePropertyChange("p", .select("x"))
            #expect(vm.draftProperties["p"] == .select("x"))
        }
        #expect(seamValue == .select("x"))
    }

    @Test func clearNonPinnedRemovesAndSurfaces() async {
        // No promoted properties → "p" is non-pinned → clear surfaces it.
        let item = makeItem(icon: nil, description: "", properties: ["p": .select("x")])
        let seamValue: PropertyValue = await withCheckedContinuation { continuation in
            let vm = makeVM(item: item, onUpdateProperty: { _, value in continuation.resume(returning: value) })
            vm.handlePropertyChange("p", .null)
            #expect(vm.draftProperties["p"] == nil)
            #expect(vm.surfaced.contains("p"))
        }
        #expect(seamValue == .null)
    }

    @Test func clearPinnedDoesNotSurface() async {
        // A promoted select → "s" is pinned → clear removes the draft but does
        // NOT surface (pinned chips live on the chip row, never the inspector).
        let type = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [PropertyDefinition(id: "s", name: "S", type: .select)],
            views: [],
            templateConfig: ItemTemplateConfig(promotedProperties: [PromotedProperty(id: "s")]),
            modifiedAt: Date()
        )
        let item = makeItem(icon: nil, description: "", properties: ["s": .select("x")])
        let seamValue: PropertyValue = await withCheckedContinuation { continuation in
            let vm = makeVM(
                item: item, type: type,
                onUpdateProperty: { _, value in continuation.resume(returning: value) }
            )
            #expect(vm.pinnedIDs.contains("s"))  // precondition
            vm.handlePropertyChange("s", .null)
            #expect(vm.draftProperties["s"] == nil)
            #expect(vm.surfaced.contains("s") == false)
        }
        #expect(seamValue == .null)
    }

    // MARK: - B3: handleTierChange
    //
    // Same fire-and-forget seam observation as B2: `handleTierChange` mutates the
    // tier draft synchronously then fires `Task { try? await onUpdateProperty }`.
    // The continuation captures BOTH the seam id and value as a tuple so we can
    // assert the tier routes to its reserved id with a `.relation` payload; the
    // synchronous draft mutation is asserted inside the continuation body.

    @Test func setTierWritesRelationAndDraft() async {
        let item = makeItem(icon: nil, description: "")
        let seam: (String, PropertyValue) = await withCheckedContinuation { continuation in
            let vm = makeVM(item: item, onUpdateProperty: { id, value in continuation.resume(returning: (id, value)) })
            vm.handleTierChange(1, ["a"])
            #expect(vm.draftTier1 == ["a"])
        }
        #expect(seam.0 == ReservedPropertyID.tier1)
        #expect(seam.1 == .relation(["a"]))
    }

    @Test func clearTierWritesEmptyRelationNotNull() async {
        let item = makeItem(icon: nil, description: "", tier1: ["a"])
        let seam: (String, PropertyValue) = await withCheckedContinuation { continuation in
            let vm = makeVM(item: item, onUpdateProperty: { id, value in continuation.resume(returning: (id, value)) })
            vm.handleTierChange(1, [])
            #expect(vm.draftTier1 == [])
        }
        #expect(seam.0 == ReservedPropertyID.tier1)
        #expect(seam.1 == .relation([]))  // empty relation clears the tier — explicitly NOT .null
        #expect(seam.1 != .null)
    }
}
