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
    private func makeVM(item: Item) -> ItemWindowViewModel {
        let type = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [], modifiedAt: Date()
        )
        return ItemWindowViewModel(
            item: item,
            itemType: type,
            collection: nil,
            onUpdateProperty: { _, _ in },
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
}
