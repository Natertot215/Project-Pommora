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
        onUpdateProperty: @escaping (String, PropertyValue) async throws -> Void = { _, _ in },
        onUpdateIcon: ((String?) async throws -> Void)? = nil,
        onUpdateBody: ((String) async throws -> Void)? = nil,
        onRename: ((String) async throws -> Item)? = nil,
        onDeleteItem: (() async throws -> Void)? = nil
    ) -> ItemWindowViewModel {
        ItemWindowViewModel(
            item: item,
            itemType: type,
            collection: nil,
            onUpdateProperty: onUpdateProperty,
            onUpdateIcon: onUpdateIcon ?? { _ in },
            onUpdateBody: onUpdateBody ?? { _ in },
            onRename: onRename ?? { _ in item },
            onDeleteItem: onDeleteItem ?? {}
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

    /// Polls `condition` on the MainActor (up to ~3s, every 10ms), returning as soon
    /// as it holds. Robust against main-actor contention under the full parallel test
    /// target, where a fixed `debounce + margin` sleep can lose the race for a
    /// main-actor slot and read the value before the debounced timer fires.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
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

    // MARK: - B4: handleTitleCommit
    //
    // The method is `async` and awaits the rename seam directly (unlike B2/B3's
    // fire-and-forget Task), so tests simply `await vm.handleTitleCommit()` — no
    // continuation. A `RenameSpy` reference type records each rename call so we
    // can assert call count without mutable-capture concerns.

    @Test func renameRehydratesItemOnSuccess() async {
        let original = makeItem(icon: nil, description: "")
        let renamed = Item(
            id: original.id, title: "Renamed", icon: original.icon,
            description: original.description, tier1: original.tier1, tier2: original.tier2,
            tier3: original.tier3, properties: original.properties,
            createdAt: original.createdAt, modifiedAt: original.modifiedAt
        )
        let spy = RenameSpy()
        let vm = makeVM(
            item: original,
            onRename: { name in
                spy.calls.append(name)
                return renamed
            })

        vm.draftTitle = "Renamed"
        await vm.handleTitleCommit()

        #expect(spy.calls == ["Renamed"])
        #expect(vm.item.id == original.id)
        #expect(vm.item.title == "Renamed")
        #expect(vm.inlineError == nil)
    }

    @Test func renameCollisionSetsErrorAndReverts() async {
        let original = makeItem(icon: nil, description: "")
        let vm = makeVM(item: original, onRename: { _ in throw TitleTaken() })

        vm.draftTitle = "Taken"
        await vm.handleTitleCommit()

        #expect(vm.inlineError != nil)
        #expect(vm.draftTitle == original.title)  // reverted to "Sample"
        #expect(vm.item.title == original.title)  // item unchanged
    }

    @Test func unchangedTitleIsNoOp() async {
        let original = makeItem(icon: nil, description: "")
        let spy = RenameSpy()
        let vm = makeVM(
            item: original,
            onRename: { name in
                spy.calls.append(name)
                return original
            })

        vm.draftTitle = original.title + "   "  // trailing whitespace only
        await vm.handleTitleCommit()

        #expect(spy.calls.isEmpty)  // guard short-circuited via trimming
        #expect(vm.inlineError == nil)
    }

    // MARK: - B5

    @Test func iconChangeSetsDraftAndCallsSeam() async {
        let item = makeItem(icon: nil, description: "")
        let seamValue: String? = await withCheckedContinuation { continuation in
            let vm = makeVM(item: item, onUpdateIcon: { icon in continuation.resume(returning: icon) })
            vm.handleIconChange("star")
            #expect(vm.draftIcon == "star")
        }
        #expect(seamValue == "star")
    }

    // MARK: - B6: body debounce + cap gate + flush
    //
    // Unlike the one-shot handlers, the body save is debounced via `bodyTask`
    // (`[weak self]`), so each test holds the VM in a `let vm` for its whole
    // duration — a dropped reference would deallocate the in-flight timer. Waits
    // derive from the real `ItemWindowViewModel.debounce` plus a margin so they
    // track the constant rather than hardcoding 300ms. `BodyRecorder` (reference
    // type) collects every body the seam receives without mutable-capture concerns.

    @Test func bodyDebounceCoalescesRapidEdits() async {
        // No templateConfig → cap defaults high, so none of these edits is over-cap.
        let item = makeItem(icon: nil, description: "")
        let recorder = BodyRecorder()
        let vm = makeVM(item: item, onUpdateBody: { body in recorder.bodies.append(body) })

        vm.handleBodyChange("a")
        vm.handleBodyChange("ab")
        vm.handleBodyChange("abc")
        // Each new edit cancels the prior debounce task synchronously, so only the
        // final timer fires. Poll for that single write (robust under main-actor load).
        await waitUntil { !recorder.bodies.isEmpty }

        #expect(recorder.bodies == ["abc"])  // rapid edits coalesced into one write
    }

    @Test func bodyOverCapSetsFlagAndSkipsSave() async {
        let type = ItemType(
            id: ULID.generate(), title: "T", icon: nil,
            properties: [], views: [],
            templateConfig: ItemTemplateConfig(descriptionCap: 5),
            modifiedAt: Date()
        )
        let item = makeItem(icon: nil, description: "")
        let recorder = BodyRecorder()
        let vm = makeVM(item: item, type: type, onUpdateBody: { body in recorder.bodies.append(body) })

        vm.handleBodyChange("123456")  // 6 chars > cap of 5
        // Flush deterministically — same cap gate the debounce path runs, no timer race.
        await vm.flushBodyNow()

        #expect(vm.isOverCap == true)
        #expect(recorder.bodies.isEmpty)  // over-cap skips the write
    }

    @Test func flushBodyNowWritesImmediatelyAndCancelsPending() async {
        let item = makeItem(icon: nil, description: "")
        let recorder = BodyRecorder()
        let vm = makeVM(item: item, onUpdateBody: { body in recorder.bodies.append(body) })

        vm.handleBodyChange("hello")
        await vm.flushBodyNow()
        #expect(recorder.bodies == ["hello"])  // written immediately, not after the debounce

        // The debounce timer armed by handleBodyChange was cancelled by flushBodyNow.
        try? await Task.sleep(for: ItemWindowViewModel.debounce + .milliseconds(200))
        #expect(recorder.bodies == ["hello"])  // no double-write from the cancelled timer
    }

    // MARK: - B7

    @Test func confirmDeleteCallsSeam() async {
        let item = makeItem(icon: nil, description: "")
        let spy = DeleteSpy()
        let vm = makeVM(item: item, onDeleteItem: { spy.count += 1 })
        await vm.confirmDelete()
        #expect(spy.count == 1)
    }

    // MARK: - B8

    @Test func addPropertySurfacesWithoutSeamCall() {
        let item = makeItem(icon: nil, description: "")
        let vm = makeVM(
            item: item,
            onUpdateProperty: { _, _ in Issue.record("addProperty must not call the property seam") }
        )
        vm.addProperty("newProp")
        #expect(vm.surfaced.contains("newProp"))
    }

    @Test func addablePropertiesExcludesFilledPinnedReservedAndLastEdited() {
        let schema = [
            PropertyDefinition(id: "a", name: "A", type: .select),  // survivor
            PropertyDefinition(id: "b", name: "B", type: .number),  // filled → excluded
            PropertyDefinition(id: "p", name: "P", type: .select),  // pinned → excluded
            PropertyDefinition(id: ReservedPropertyID.tier1, name: "T1", type: .select),  // reserved id → excluded
            PropertyDefinition(id: "le", name: "LE", type: .lastEditedTime),  // virtual → excluded
        ]
        let out = ItemWindowViewModel.addableProperties(
            schema: schema, filled: ["b"], pinned: ["p"]
        )
        #expect(out.map(\.id) == ["a"])
    }

    // MARK: - B9: VM↔manager↔disk↔index round-trip
    //
    // The UIX↔Data proof: driving the REAL VM handlers persists THROUGH the real
    // `ItemContentManager` to disk AND mirrors tier links into the index — going
    // *through* the VM seam, not around it. The VM's save Task holds `self`
    // strongly, so the local `vm` survives until the seam runs; `boundVM`'s seam
    // resumes the continuation after the manager write, so each fire-and-forget
    // save can be awaited without sleeps. `created`'s title stays "I", so
    // `updateItemProperty` (which reloads by title) round-trips it across ops.

    @Test func roundTripVMToManagerToDiskToIndex() async throws {
        let (nexus, itemType, manager) = try await TempNexus.itemTypeRoot(named: "T")
        let created = try await manager.createItem(name: "I", inTypeRoot: itemType)

        // Wire the live index so tier writes mirror into context_links. Seed the
        // parent Type row first: a fresh index is empty, and item upserts FK to
        // `item_types` — in the real app `loadAll` has already synced the Type
        // (quirk #14), so the window's edits index fine; a test index must seed it
        // (else upsertItem skips on the FK and context_links never populates).
        let (index, _) = try PommoraIndex.open(at: nexus.rootURL)
        manager.indexUpdater = IndexUpdater(index)
        try manager.indexUpdater?.upsertItemType(itemType)

        // A VM bound to the REAL manager seam; `resume` lets the fire-and-forget
        // save be awaited via a continuation.
        func boundVM(resume: @escaping () -> Void) -> ItemWindowViewModel {
            ItemWindowViewModel(
                item: created, itemType: itemType, collection: nil,
                onUpdateProperty: { id, value in
                    try? await manager.updateItemProperty(
                        created, propertyID: id, newValue: value, type: itemType, collection: nil)
                    resume()
                },
                onUpdateIcon: { _ in }, onUpdateBody: { _ in },
                onRename: { _ in created }, onDeleteItem: {})
        }

        // 1) Property set → reopen + assert disk.
        await withCheckedContinuation { cont in
            let vm = boundVM(resume: { cont.resume() })
            vm.handlePropertyChange("p", .select("x"))
        }
        let m1 = TempNexus.reopen(nexus)
        await m1.loadAll(for: itemType)
        #expect(m1.items(in: itemType).first?.properties["p"] == .select("x"))

        // 2) Tier set → assert disk AND index (upsertItem mirrors tier1 → context_links).
        let contextID = ULID.generate()
        await withCheckedContinuation { cont in
            let vm = boundVM(resume: { cont.resume() })
            vm.handleTierChange(1, [contextID])
        }
        let m2 = TempNexus.reopen(nexus)
        await m2.loadAll(for: itemType)
        #expect(m2.items(in: itemType).first?.tier1 == [contextID])
        let incoming = try await IndexQuery(index).incomingContextLinks(targetID: contextID)
        #expect(incoming.contains { $0.id == created.id })

        // 3) Clear → reopen + assert the key is ABSENT (not stored as `.null`).
        await withCheckedContinuation { cont in
            let vm = boundVM(resume: { cont.resume() })
            vm.handlePropertyChange("p", .null)
        }
        let m3 = TempNexus.reopen(nexus)
        await m3.loadAll(for: itemType)
        #expect(m3.items(in: itemType).first?.properties["p"] == nil)
    }
}

/// Records delete-seam calls for the B7 tests (reference type — no mutable-capture concerns).
private final class DeleteSpy {
    var count = 0
}

/// Records rename-seam calls for the B4 tests without mutable-capture concerns.
private final class RenameSpy {
    var calls: [String] = []
}

/// Records each body the save seam receives in the B6 tests (reference type —
/// no mutable-capture concerns).
private final class BodyRecorder {
    var bodies: [String] = []
}

/// Stand-in collision error thrown by the rename seam in the B4 failure test.
private struct TitleTaken: Error {}
