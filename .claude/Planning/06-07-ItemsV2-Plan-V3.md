# ItemsV2 — Interactive Default Window Implementation Plan (V3)

> **Status: RATIFIED — review-certified (round-1 fixes folded; re-verify round clean).** A 3-agent plan-review round found **4 blockers + ~6 precision fixes**, all folded below: (1) live-index source was ungrounded → new **Task A9** adds `NexusEnvironment.nexusManager` + injection; (2) `validate` has **4** call sites (not 6) and `isBodyEdit` lives on the private `validate` wrapper, set via `updateItem` → A3 corrected; (3) C1's reorder-suite is type-name form; (4) the VM holds `pinnedIDs` so a pinned-clear doesn't surface → B1/B2. Plus: shared `isFilled(_:)` predicate (B1/B8/D5), shared `pinnedTypes` slice (D4), `pinnedTypes` unit test (A5), `ContextValueEditor.ids` is `@Binding`, flush-on-replace accepted-edge note (D1). A focused re-verify round then confirmed **every fix sound + grounded against real source, no new contradictions** (its one "still-broken" flag was source-not-yet-applied = Task A9, which is correctly specified + buildable — `NexusManager` is `@Observable`, `NexusEnvironment.init` already receives it). Per `Guidelines/Review-Discipline.md`, confidence is **earned**: 6 review rounds total across spec + plan (≈20 agents).
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.
>
> **Supersedes Plan-V1/V2.** Written against **`// Planning // 06-07-ItemsV2-Spec-V5.md`** (5-review-round spec). V3 deltas vs V2: surface KEPT (no re-host); `ItemWindowMode` enum DELETED (`editing: Bool` removed); `commitItemEdits` DELETED (not redesigned); footer REUSES `DetailFooterBar` (no `NSPathControl`); the cap is a **pooled conditional-cap engine**; the `.null` gate moves into the shared manager; index is threaded **live** (not a stored snapshot); the Templates pane is a grouped-by-type checkbox list.

**Goal:** Replace the read-only Item Window stub with a fully interactive Default card — assign property values, add existing schema properties, set the 3 Contexts, edit title/icon/body, delete — live, with a pooled-capped select/multi chip-row pinned per the Type/Set template, inside the existing floating window.

**Architecture:** One `ItemWindowRenderer` primitive (always live; no mode enum) composing fixed zones (Header / Property Field / Body / Inspector / Footer). A new `@Observable @MainActor ItemWindowViewModel` holds drafts + a session-surfaced set and routes each field to verified manager seams, live-saving with a body debounce + flush-on-close. Pinning caps are a pooled engine (`ItemWindowZoneConfig`: combined-total + per-type rules; V1 enables select+multi). On-disk change is additive (`property_layout`). Surface unchanged (`WindowGroup`+`.plain`+`PreviewWindow`).

**Tech Stack:** SwiftUI (macOS 26.4), Swift 6 strict concurrency + ExistentialAny, Swift Testing, GRDB, Yams, MarkdownPM.

---

## Conventions (every task)

- **Build/test via a background builder** (quirk #13): `Agent run_in_background: true` → `xcodebuild test -only-testing:PommoraTests/<SuiteName> …`. Use the **real `@Suite` name** (quirk #1); **visually confirm a non-zero executed count**; when unsure run the whole `-only-testing:PommoraTests` target.
- Trust `xcodebuild`, not SourceKit (quirk #3). New files auto-include (quirk #2); revert incidental Yams/GRDB pbxproj reorder (quirk #6).
- Format before commit: `swift format format --in-place <files>` (quirk #11). Green commit per task (quirk #7).
- Swift 6 Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)` (quirk #5).
- **SwiftUI/macOS tasks leverage the `swiftui-expert-skill`.** Every view-building task — Phases C/D/E (renderer zones, `ItemInspectorRow`, chip-row cells, the grouped-checkbox Templates pane, the `DetailFooterBar` footer wiring, the `PreviewWindow` header change) and any `@Observable`/`@State` VM-lifecycle, `@FocusState`, `WindowGroup`/`.windowStyle(.plain)`, or `NSViewRepresentable` work — **invokes `swiftui-expert-skill` before writing the view code**, for idiomatic SwiftUI + AppKit-bridge guidance. (Phases A/B are plain-Swift logic/TDD — the skill isn't required there.)
- **Verify exact initializer labels against source before writing each test** (anchors below verified in the 5-round spec; re-confirm at edit time).

**Verified `@Suite` names for `-only-testing`** (V5 §15): string-label suites — `ItemContentManager`, `ItemMarkdownTransition`, `ClearTemplateConfig`, `ItemCollectionFile`, `ItemTypeFile`, `Move Item`, `ItemType.singular`; type-name suites — `TemplateResolverTests`, `PromotedEntriesTests`, `ItemTemplateConfigTests`, `RenameItemReturn` (new), `ItemWindowZoneConfig` (new), `PromotedForField` (new), `ItemWindowViewModel` (new), `ItemWindowReorderTests` (renamed from `ItemWindowEditModeTests`). ⚠️ `ItemWindowLayoutsTests` has **no `@Suite`** → per-suite filter runs 0 tests; rely on the full-target run (F1). `CommitItemEdits` suite is being DELETED (A7).

---

## File Structure

**Create:** `ItemWindow/ItemWindowZoneConfig.swift`, `ItemWindow/ItemWindowViewModel.swift`, `ItemWindow/ItemInspectorRow.swift`; tests `ItemWindowZoneConfigTests.swift`, `ItemWindowViewModelTests.swift`, `RenameItemReturnTests.swift`, `PromotedForFieldTests.swift`; `PommoraTests/Support/TempNexus+Items.swift`.
**Modify:** `Items/ItemType.swift` (+`property_layout`), `Items/LayoutArchetype.swift` (+`PropertyLayoutMode`), `Items/ItemContentManager+CRUD.swift` (renameItem return, `.null` gate, validate `isBodyEdit`, delete `commitItemEdits`), `Items/TemplateResolver.swift` (+`promotedForField`), `ItemWindow/ItemWindowRenderer.swift` (remove `editing`, interactive zones, delete dead display path), `ItemWindow/ItemWindowSceneRoot.swift` (VM construction + live index + flush), `ViewSettings/ItemTemplatePane.swift` (rebuild), `Properties/TypeSettingsSheet.swift` (remove placeholder), `Window/PreviewWindow.swift` (header-less), `DesignSystem/PUI.swift` (window-size constants); rename `ItemWindowEditModeTests.swift`→`ItemWindowReorderTests.swift`; docs `Features/Items.md`, `Guidelines/Paradigm-Decisions.md`, `History.md`.
**DELETE:** `Items/ItemContentManager+CRUD.swift` `commitItemEdits` func; `PommoraTests/Items/CommitItemEditsTests.swift`; archetype picker + "Layout preview" mockup + `displaySection` in `ItemTemplatePane.swift`; `TypeSettingsTemplatesPlaceholder` in `TypeSettingsSheet.swift`.
**Do NOT modify** (blast-radius): `PropertyEditorRow.swift`, `MultiSelectChips.swift`, `VaultSettingsSheet.swift` placeholder, `PageTemplateConfig.swift`, `PromotedEntriesTests.swift`.

---

## Phase A — Foundations (Figma-independent, fully TDD'd)

### Task A0: `TempNexus` Item fixtures
**Files:** Create `PommoraTests/Support/TempNexus+Items.swift`.
- [ ] **Step 1: Implement** (confirm `TempNexus.make()`, `NexusContext.empty`, `NexusPaths.itemTypeFolderURL(in:typeFolderName:)`/`itemTypeMetadataURL`, and the `ItemType`/`ItemContentManager` inits against source first):
```swift
import Foundation
@testable import Pommora
extension TempNexus {
    @MainActor static func itemTypeRoot(named name: String) async throws
      -> (nexus: Nexus, itemType: ItemType, manager: ItemContentManager) {
        let nexus = try TempNexus.make()
        let itemType = ItemType(id: ULID.generate(), title: name, icon: nil,
                                properties: [], views: [], modifiedAt: Date())
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try itemType.save(to: NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: name))
        let manager = ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
        return (nexus, itemType, manager)
    }
    @MainActor static func reopen(_ nexus: Nexus) -> ItemContentManager {
        ItemContentManager(nexus: nexus, contextProvider: { NexusContext.empty })
    }
}
```
- [ ] **Step 2: Build green** (full target). **Step 3: Commit** `test(support): TempNexus item-type-root + reopen fixtures`.

### Task A1: `renameItem` → `@discardableResult -> Item`
**Files:** Modify `ItemContentManager+CRUD.swift` (`renameItem` ~:137, ~:338); Test `RenameItemReturnTests.swift`.
- [ ] **Step 1: Failing test:**
```swift
import Testing; import Foundation; @testable import Pommora
@Suite("RenameItemReturn") @MainActor
struct RenameItemReturnTests {
    @Test func renameReturnsRenamedAndRemovesOldFile() async throws {
        let (nexus, itemType, manager) = try await TempNexus.itemTypeRoot(named: "Errands")
        let created = try await manager.createItem(name: "Buy milk", inTypeRoot: itemType)
        let oldURL = NexusPaths.itemFileURL(forTitle: "Buy milk",
            in: NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Errands"))
        let renamed: Item = try await manager.renameItem(created, to: "Buy oat milk", inTypeRoot: itemType)
        #expect(renamed.title == "Buy oat milk")
        #expect(renamed.id == created.id)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
    }
}
```
- [ ] **Step 2: Run — FAIL** ("cannot assign value of type '()'").
- [ ] **Step 3:** Change both overloads to `@discardableResult ... async throws -> Item`; `return updated` as the **last statement of the `do` block — after** the in-memory cache write + `pinnedManager`/`recentsManager` title-update lines.
- [ ] **Step 4: Run — PASS.** Regression: `ItemContentManager`, `ConnectionLiveRefreshTests`, `ConnectionCascadeTests`, `ItemMarkdownTransition` (they discard the result — `@discardableResult` keeps them valid).
- [ ] **Step 5: Commit** `refactor(items): renameItem returns renamed Item (@discardableResult)`.

### Task A2: `.null` gate in the SHARED `updateItemProperty`
**Files:** Modify `ItemContentManager+CRUD.swift:719-740`; Test add to `ItemContentManager` suite.
- [ ] **Step 1: AUDIT** (no code yet): grep every `PropertyValue.null` production site — `PropertyCellEditor.swift` (number `:215`, multiSelect `:294`, url `:333`), any others. Confirm each is a clear-intent (wants the key removed). Record the list in the commit body.
- [ ] **Step 2: Failing test** (append to `ItemContentManagerTests`):
```swift
@Test func nullValueRemovesKeyNotPersistsNull() async throws {
    let (nexus, itemType, manager) = try await TempNexus.itemTypeRoot(named: "T")
    let created = try await manager.createItem(name: "I", inTypeRoot: itemType)
    try await manager.updateItemProperty(created, propertyID: "p", newValue: .select("x"), type: itemType, collection: nil)
    try await manager.updateItemProperty(created, propertyID: "p", newValue: .null, type: itemType, collection: nil)
    let fresh = TempNexus.reopen(nexus); await fresh.loadAll(for: itemType)
    #expect(fresh.items(in: itemType).first?.properties["p"] == nil)   // key removed, NOT stored .null
}
```
- [ ] **Step 3: Run — FAIL** (`.null` persists).
- [ ] **Step 4:** At the top of `updateItemProperty`, normalize: `let newValue: PropertyValue? = { if case .null = newValue { nil } else { newValue } }()` (shadow the param before the relation?/set/removeValue branches at `:732-737`). `.relation([])` is unaffected (not `.null`).
- [ ] **Step 5: Run — PASS.** Regression: `ItemContentManager` + manually verify a detail-table cell clear still works (it now removes the key).
- [ ] **Step 6: Commit** `fix(items): .null normalizes to key-removal in updateItemProperty (fixes table-cell null-to-disk bug)`.

### Task A3: `validate(isBodyEdit:)` — icon/non-body edits don't reject on over-cap body
**Files:** Modify `ItemContentManager+CRUD.swift` (`fileprivate func validate(_:type:)` ~:66, all call sites).
- [ ] **Step 1: Failing test** (append to `ItemContentManager`): create an item whose `description` is already > 500 (write the `.md` directly over-cap, or set `description_cap` low), then `updateItemIcon(item, to: "star", …)` and `#expect` it does NOT throw + the icon persisted.
- [ ] **Step 2: Run — FAIL** (`descriptionTooLong`).
- [ ] **Step 3 (corrected by plan-review — VERIFIED 4 call sites):** `validate(_:type:)` (`:66`) has exactly **4 call sites**: `createItem`(`:106`, `:307`) + `updateItem`(`:235`, `:432`). `updateItemProperty` and `renameItem` do **NOT** call `validate`. Because `updateItemIcon` routes through `updateItem` (a non-body change) **and** the VM body path also calls `updateItem`, the flag must live on **`updateItem`**, not only `validate`: add `isBodyEdit: Bool = true` to both `updateItem` overloads (default `true` = current behavior) and thread it into the **private** `validate(_:type:isBodyEdit:)` wrapper (`:66`); gate the body-cap there — when `isBodyEdit == false` the wrapper skips the description-cap path. Keep `ItemValidator.validate`'s public signature unchanged if the wrapper can gate it (confirm the cleanest split at edit time). `updateItemIcon` calls `updateItem(..., isBodyEdit: false)`; the VM body path uses the default `true`; `createItem` keeps the `validate` default (empty body — cap irrelevant).
- [ ] **Step 4: Run — PASS.** Regression: `ItemContentManager`, `ItemValidator`-related suites.
- [ ] **Step 5: Commit** `fix(items): body-cap validation only on body edits (icon/property writes don't reject over-cap items)`.

### Task A4: `PropertyLayoutMode` + `property_layout` on `ItemTemplateConfig`
**Files:** Modify `Items/LayoutArchetype.swift`, `Items/ItemType.swift:112-137`; Test `ItemTemplateConfigTests`.
- [ ] **Step 1: Failing tests** — `propertyLayoutAbsentDecodesAsStandard`, `propertyLayoutRoundTrips` (assert on-disk key `property_layout`), `unknownPropertyLayoutTolerated`, `legacyLayoutStillDecodes`.
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Add `PropertyLayoutMode`** to `LayoutArchetype.swift` (tolerant enum + single-value `Codable`, mirroring `LayoutArchetype.unknown`):
```swift
enum PropertyLayoutMode: Codable, Equatable, Hashable, Sendable {
    case standard, compact, unknown(String)
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw { case "standard": self = .standard; case "compact": self = .compact; default: self = .unknown(raw) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .standard: try c.encode("standard"); case .compact: try c.encode("compact"); case .unknown(let r): try c.encode(r) }
    }
}
```
- [ ] **Step 4: Add field** to `ItemTemplateConfig`: `var propertyLayout: PropertyLayoutMode?` + `case propertyLayout = "property_layout"` in `CodingKeys` + the param in the memberwise `init()`. Keep `layout` decode-tolerated. Synthesized decode/encode (no custom needed).
- [ ] **Step 5: Run — PASS** (`ItemTemplateConfigTests` + regression `TemplateResolverTests`, `CollectionTemplateConfigTests`). **Step 6: Commit** `feat(items): add property_layout (PropertyLayoutMode) — additive, decode-tolerant`.

### Task A5: `ItemWindowZoneConfig` — pooled conditional-cap engine
**Files:** Create `ItemWindow/ItemWindowZoneConfig.swift`; Test `ItemWindowZoneConfigTests.swift`.
- [ ] **Step 1: Failing tests** (`@Suite("ItemWindowZoneConfig")`):
```swift
import Testing; @testable import Pommora
@Suite("ItemWindowZoneConfig")
struct ItemWindowZoneConfigTests {
    @Test func combinedTotalCapsAcrossPoolA() {
        let pinned: [PropertyType] = [.select, .select, .select, .multiSelect]  // 4 in Pool A
        #expect(ItemWindowZoneConfig.isAtCap(.select, pinnedTypes: pinned))      // pool full
    }
    @Test func perTypePoolBCapsEachIndependently() {
        let pinned: [PropertyType] = [.checkbox]
        #expect(ItemWindowZoneConfig.isAtCap(.checkbox, pinnedTypes: pinned))        // checkbox at 1
        #expect(!ItemWindowZoneConfig.isAtCap(.status, pinnedTypes: pinned))         // status still open
    }
    @Test func notInV1WinsOverCapReached() {
        let pinned: [PropertyType] = [.select, .select, .select, .multiSelect]  // pool A full
        #expect(ItemWindowZoneConfig.muteReason(.number, pinnedTypes: pinned) == .notInV1)  // not .capReached
    }
    @Test func selectAndMultiAreV1Checkable() {
        #expect(ItemWindowZoneConfig.muteReason(.select, pinnedTypes: []) == nil)
        #expect(ItemWindowZoneConfig.muteReason(.checkbox, pinnedTypes: []) == .notInV1)
    }
    @Test func pinnedTypesResolvesViaSchemaAndFiltersToV1() {  // plan-review fix
        let schema = [PropertyDefinition(id: "s", name: "S", type: .select),
                      PropertyDefinition(id: "n", name: "N", type: .number)]
        let promoted = [PromotedProperty(id: "s"), PromotedProperty(id: "n")]
        #expect(ItemWindowZoneConfig.pinnedTypes(promoted: promoted, schema: schema) == [.select])
    }
}
```
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** (caseless namespace enum):
```swift
import Foundation
enum ZoneCapRule: Equatable, Sendable { case combinedTotal(Int); case perType(Int) }
struct ItemWindowZonePool: Equatable, Sendable { let types: [PropertyType]; let rule: ZoneCapRule }
enum MuteReason: Equatable, Sendable { case notInV1; case capReached }
enum ItemWindowZoneConfig {
    static let pools: [ItemWindowZonePool] = [
        .init(types: [.select, .multiSelect, .number], rule: .combinedTotal(4)),
        .init(types: [.checkbox, .status, .date, .datetime], rule: .perType(1)),
        .init(types: [.url, .file], rule: .combinedTotal(2)),
    ]
    static let v1Checkable: Set<PropertyType> = [.select, .multiSelect]
    static func pool(for type: PropertyType) -> ItemWindowZonePool? { pools.first { $0.types.contains(type) } }
    static func isAtCap(_ candidate: PropertyType, pinnedTypes: [PropertyType]) -> Bool {
        guard let p = pool(for: candidate) else { return true }
        switch p.rule {
        case .combinedTotal(let n): return pinnedTypes.filter { p.types.contains($0) }.count >= n
        case .perType(let n):       return pinnedTypes.filter { $0 == candidate }.count >= n
        }
    }
    /// Precedence: .notInV1 ALWAYS wins (checked first; cap only matters for checkable types).
    static func muteReason(_ type: PropertyType, pinnedTypes: [PropertyType]) -> MuteReason? {
        if !v1Checkable.contains(type) { return .notInV1 }
        return isAtCap(type, pinnedTypes: pinnedTypes) ? .capReached : nil
    }
}
```
- [ ] **Step 4:** Add the resolution helper (used by the pane + chip-row so counts never diverge):
```swift
extension ItemWindowZoneConfig {
    /// Types of currently-pinned properties, resolved via schema, filtered to v1Checkable
    /// (so stale/off-V1 sidecar entries can't poison a count).
    static func pinnedTypes(promoted: [PromotedProperty], schema: [PropertyDefinition]) -> [PropertyType] {
        promoted.compactMap { p in schema.first { $0.id == p.id }?.type }
                .filter { v1Checkable.contains($0) }
    }
}
```
- [ ] **Step 5: Run — PASS.** **Step 6: Commit** `feat(items): ItemWindowZoneConfig pooled conditional-cap engine (combined-total + per-type; V1 select+multi)`.

### Task A6: `TemplateResolver.promotedForField` (paired return; additive)
**Files:** Modify `Items/TemplateResolver.swift`; Test `PromotedForFieldTests.swift`.
- [ ] **Step 1: Failing test** (`@Suite("PromotedForField")`):
```swift
@Test func promotedForFieldKeepsChipEligibleDropsRest() {
    let sel = PropertyDefinition(id: "s", name: "Stage", type: .select)
    let num = PropertyDefinition(id: "n", name: "Count", type: .number)
    let type = ItemType(id: ULID.generate(), title: "T", icon: nil, properties: [sel, num], views: [],
        templateConfig: ItemTemplateConfig(promotedProperties: [.init(id: "s"), .init(id: "n")]),
        modifiedAt: Date())
    let out = TemplateResolver.promotedForField(type: type, collection: nil)
    #expect(out.map(\.definition.id) == ["s"])   // select kept, number (not v1Checkable) dropped
}
```
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3:** Add (do NOT touch `promotedEntries`):
```swift
static func promotedForField(type: ItemType, collection: ItemCollection?)
  -> [(promotion: PromotedProperty, definition: PropertyDefinition)] {
    promotedEntries(type: type, collection: collection)
        .filter { ItemWindowZoneConfig.v1Checkable.contains($0.definition.type) }
}
```
- [ ] **Step 4: Run — PASS** (`PromotedForField` + `PromotedEntriesTests` untouched-green). **Step 5: Commit** `feat(items): TemplateResolver.promotedForField (chip-eligible paired entries; promotedEntries untouched)`.

### Task A7: delete `commitItemEdits` + its tests
**Files:** Modify `ItemContentManager+CRUD.swift` (delete `commitItemEdits` :474-495); DELETE `PommoraTests/Items/CommitItemEditsTests.swift`.
- [ ] **Step 1:** Confirm via grep there are no production callers (only `CommitItemEditsTests`). Delete the func + the test file.
- [ ] **Step 2: Build green** (full target). **Step 3: Commit** `chore(items): delete dead commitItemEdits (live VM live-saves field-by-field)`.

### Task A8: remove the Items Templates placeholder (decoupled pure deletion)
**Files:** Modify `Properties/TypeSettingsSheet.swift` (delete `:219` call + `:540-542` struct).
- [ ] **Step 1:** Delete `TypeSettingsTemplatesPlaceholder()` call + struct. **Leave `VaultSettingsSheet.swift:258`.** The live route (`StorageMenuRoot` → `.itemTemplate` → `ItemTemplatePane`) already navigates.
- [ ] **Step 2: Build green.** **Step 3: Commit** `chore(items): remove stale Items Templates placeholder (Pages untouched)`.

### Task A9: expose `NexusManager` on `NexusEnvironment` (live-index enabler — plan-review blocker fix)
**Files:** Modify `Nexus/NexusEnvironment.swift`.
- [ ] **Step 1:** The Item Window scene reaches its env via `AppGlobals.current: NexusEnvironment` and injects managers via `injectNexusEnvironment` — but **`NexusManager` is neither stored on `NexusEnvironment` nor injected**, so the tier `ContextValueEditor` has no live-index source (a stored snapshot would go stale; that was the round-5 bug). Fix: add `let nexusManager: NexusManager` as a stored property on `NexusEnvironment` (it's already the init input — capture it), and add `.environment(env.nexusManager)` to the `injectNexusEnvironment(_:)` modifier (it's `@Observable`, so `@Environment(NexusManager.self)` works without SIGTRAP — quirk #15). Confirm `NexusManager` is `@Observable` at edit time.
- [ ] **Step 2: Build green** (full target; confirm no other `injectNexusEnvironment` consumer breaks). **Step 3: Commit** `feat(nexus): expose NexusManager on NexusEnvironment (live index for the Item Window)`.

---

## Phase B — `ItemWindowViewModel` (TDD core)

### Task B1: skeleton + hydration
**Files:** Create `ItemWindow/ItemWindowViewModel.swift`; Test `ItemWindowViewModelTests.swift`.
- [ ] **Step 1: Failing test** (`@Suite("ItemWindowViewModel") @MainActor`) — a `makeVM` helper + `hydratesDraftsFromItem` (assert draftTitle/draftIcon/draftBody/draftProperties/tiers match the item). **`draftIcon` is `String?`.**
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Implement** `@Observable @MainActor final class ItemWindowViewModel` with: `var item: Item` (var — re-held after rename), `var draftTitle`, `var draftIcon: String?`, `var draftBody`, `var draftProperties: [String: PropertyValue]`, `var draftTier1/2/3: [String]`, `var surfaced: Set<String> = []`, **`let pinnedIDs: Set<String>`** (plan-review fix — computed at init: `Set(TemplateResolver.promotedForField(type: itemType, collection: collection).map { $0.promotion.id })`; needed so `handlePropertyChange` can suppress surfacing on a pinned-clear), `var inlineError: String?`, `var isOverCap = false`, `var inspectorShown = true`, `let itemType`, `let collection`, the five `let on…` closures, `private var bodyTask: Task<Void,Never>?`, `static let debounce: Duration = .milliseconds(300)`, and an `init` hydrating drafts from `item`. Also add the **shared filled-predicate** (plan-review fix, used by D5's row filter AND B8's `filled:` set): `static func isFilled(_ v: PropertyValue?) -> Bool` → `false` for `nil`, `.null`, `.multiSelect([])`, `.relation([])`, and empty-string values; `true` otherwise.
- [ ] **Step 4: PASS.** **Step 5: Commit** `feat(items): ItemWindowViewModel skeleton + hydration`.

### Task B2: property-value handler (clear → remove + surface)
- [ ] **Step 1:** tests — (a) `handlePropertyChange("p", .select("x"))` sets draft + calls `onUpdateProperty("p", .select("x"))`; (b) `handlePropertyChange("p", .null)` for a NON-pinned `"p"` `removeValue`s the draft, calls `onUpdateProperty("p", .null)` (manager gate removes the key), and **adds "p" to `surfaced`**; (c) **negative (plan-review fix):** `handlePropertyChange(pinnedID, .null)` where `pinnedID ∈ vm.pinnedIDs` does the write + removeValue but does **NOT** add it to `surfaced` (pinned chips stay visible via the chip-row; they never render in the inspector — §4.4/§11). Construct the VM in (c)'s fixture with a pinned select so `pinnedIDs` is non-empty.
- [ ] **Step 2: FAIL. Step 3:** implement: on `.null` → `draftProperties.removeValue(forKey: id)`; **`if !pinnedIDs.contains(id) { surfaced.insert(id) }`**; else `draftProperties[id] = v`; always `Task { try? await onUpdateProperty(id, v) }`. **Step 4: PASS. Step 5:** Commit `feat(items): VM property handler (clear removes + surfaces; pinned-clear does not surface)`.

### Task B3: tier handler (`.relation([])` on clear)
- [ ] **Step 1:** test `handleTierChange(1, ["a"])` → `onUpdateProperty(ReservedPropertyID.tier1, .relation(["a"]))`; `handleTierChange(1, [])` → `.relation([])` (NOT nil). **Step 2: FAIL. Step 3:** `handleTierChange(_:_:)` sets `draftTierN`; maps tier→`ReservedPropertyID.tierN`; always `.relation(newIDs)`. **Step 4: PASS. Step 5:** Commit `feat(items): VM tier handler (.relation([]) clears)`.

### Task B4: title commit (rename + re-hold + collision; Enter & focus-loss)
- [ ] **Step 1:** tests — changed title → `onRename` called, `vm.item` re-held to the returned Item (id same, title new); `onRename` throws (collision) → `inlineError` set + `draftTitle` reverts to `item.title`; unchanged → no-op. **Step 2: FAIL. Step 3:** `handleTitleCommit() async` { guard `draftTitle != item.title`; do `let renamed = try await onRename(draftTitle); self.item = renamed; inlineError = nil` catch `inlineError = …; draftTitle = item.title` }. (D2 fires this on `.onSubmit` AND FocusState false-transition.) **Step 4: PASS. Step 5:** Commit `feat(items): VM title commit + re-hold + inline collision`.

### Task B5: icon handler
- [ ] test `handleIconChange("star")` sets `draftIcon` + `onUpdateIcon("star")` → implement `Task { try? await onUpdateIcon(newIcon) }` → PASS. Commit `feat(items): VM icon handler`.

### Task B6: body debounce + cap gate + flush-on-close
- [ ] **Step 1:** tests — rapid `handleBodyChange` → single `onUpdateBody` after debounce; over-cap → `isOverCap=true` + no call; `flushBodyNow()` cancels the pending task + writes immediately (under cap). **Step 2: FAIL. Step 3:** `handleBodyChange(_)` sets draft + `scheduleBodySave()` (cancel `bodyTask`; `bodyTask = Task { try? await Task.sleep(for: Self.debounce); await flushBodyNow() }`). `flushBodyNow() async` { `let cap = ItemValidator.effectiveCap(template: TemplateResolver.effective(type: itemType, collection: collection))`; if `draftBody.count > cap { isOverCap = true; return }`; `isOverCap = false; try? await onUpdateBody(draftBody)` }. **Step 4: PASS. Step 5:** Commit `feat(items): VM body debounce + 500-cap gate + flushBodyNow`.

### Task B7: delete handler
- [ ] test `confirmDelete()` calls `onDeleteItem()` → implement `Task`-free `func confirmDelete() async { try? await onDeleteItem() }` → PASS. Commit `feat(items): VM delete handler`.

### Task B8: Add-Property + session-surfaced + `addableProperties`
- [ ] **Step 1: tests:** (a) `addProperty("p")` inserts into `surfaced`, no `onUpdateProperty` call; (b) `addableProperties(schema:filled:pinned:)` excludes filled, `ReservedPropertyID.all`, `type == .lastEditedTime`, AND pinned IDs (include a `.lastEditedTime` user def + a pinned select in the fixture to prove both exclusions); (c) **`isFilled(_:)` predicate (plan-review fix):** returns `false` for `.null`, `.multiSelect([])`, `.relation([])`, empty-string; `true` otherwise. The inspector's `filled:` set is `Set(draftProperties.filter { Self.isFilled($0.value) }.map(\.key))`, and a row shows if filled OR surfaced.
- [ ] **Step 2: FAIL. Step 3:** implement `addProperty(_:)` (`surfaced.insert(id)`) +:
```swift
static func addableProperties(schema: [PropertyDefinition], filled: Set<String>, pinned: Set<String>)
  -> [PropertyDefinition] {
    schema.filter { d in
        !filled.contains(d.id) && !pinned.contains(d.id)
            && !ReservedPropertyID.all.contains(d.id) && d.type != .lastEditedTime
    }
}
```
- [ ] **Step 4: PASS. Step 5:** Commit `feat(items): VM Add-Property + surfaced set + addableProperties (excludes pinned)`.

### Task B9: round-trip integration (UIX↔Data proof)
- [ ] **Step 1: Failing test** — `let (nexus, itemType, manager) = try await TempNexus.itemTypeRoot(named:"T")`; create an item; **wire the index** via `let (index,_) = try PommoraIndex.open(at: nexus.rootURL); manager.indexUpdater = IndexUpdater(index)` (confirm labels against `PageContentManagerTests.swift:96` pattern). Build the VM with closures bound to the real seams. `handlePropertyChange("p", .select("x"))`; await; `let fresh = TempNexus.reopen(nexus); await fresh.loadAll(for: itemType)`; `#expect` value persisted + `IndexQuery` row present. Repeat for a tier (assert `tier1` root + `IndexQuery.incomingContextLinks`) and a clear (key absent, no `.null`).
- [ ] **Step 2–4: FAIL → wire → PASS. Step 5:** Commit `test(items): VM↔manager↔disk↔index round-trip`.

---

## Phase C — Renderer restructure (atomic)

### Task C1: remove `editing: Bool` + tear down the old pane (one atomic commit)
**Files:** Modify `ItemWindow/ItemWindowRenderer.swift`, `ViewSettings/ItemTemplatePane.swift`; rename `ItemWindowEditModeTests.swift`→`ItemWindowReorderTests.swift`.
- [ ] **Step 1:** In `ItemWindowRenderer`: remove `var editing: Bool = false` (`:35`); collapse every `if editing` branch (`:185/:285/:292/:315/:385`) to the live path; **delete the dead archetype-display path** (`resolvedDisplay`/`archetypeDefaultDisplay`/`PropertyDisplay` resolution, `:153-178`). Update the file-level doc comment (drop the two-mode framing). **Keep** `reorderPromoted` + `partition()`.
- [ ] **Step 2:** In `ItemTemplatePane`: delete `archetypeSection` (`:100-111`), `mockupSection` (`:122-141`, the `editing: true` site `:131`), `displaySection`, the `ArchetypeRow` struct + archetype `label(for:)`/`select(_:)`. **Keep** `coverSection`, the scope section (`ScopeOverrideRow`/`ScopeInheritsRow`), and the legacy `pinnedProperties` collapse (`:379-396`). (The new checkbox pin UI lands in E1; between C1 and E1 the pane has no pin UI but compiles.)
- [ ] **Step 3:** Rename `ItemWindowEditModeTests.swift`→`ItemWindowReorderTests.swift`; the suite must be the **type-name form** `@Suite struct ItemWindowReorderTests` so `-only-testing:PommoraTests/ItemWindowReorderTests` matches (NOT a string label `@Suite("ItemWindowReorder")` — plan-review fix). Update the stale file comment (it tests `reorderPromoted`, which survives). Keep `ItemWindowPartitionTests`.
- [ ] **Step 4: Build + `ItemWindowReorder` + full target — GREEN.** **Step 5: Commit** `refactor(items): remove editing:Bool + retire archetype picker/mockup/display path (atomic)`.

### Task C2: `PreviewWindow` header-less
**Files:** Modify `Window/PreviewWindow.swift`.
- [ ] **Step 1:** Make the standalone header optional: add `var header: (() -> AnyView)? = nil` (or an `@ViewBuilder` generic param defaulting to `EmptyView`); render it only when supplied. Keep the card frame + `.onKeyPress(.escape)`. The Item card will supply its own header row (D2), so it passes no header here. Other consumers (future Pages) keep the default.
- [ ] **Step 2: Build green** (confirm the existing `PreviewWindow {}` call sites still compile). **Step 3: Commit** `refactor(window): PreviewWindow header is optional (item card supplies its own)`.

---

## Phase D — Interactive card zones (build-green + manual)

### Task D0: two-column scaffold + window-size constants
- [ ] Add `enum PUI { … }`'s `ItemWindow { static let totalWidth: CGFloat = 760; static let mainWidth: CGFloat = 480; static let inspectorWidth: CGFloat = 260; static let height: CGFloat = 480 }` to `DesignSystem/PUI.swift`. In `ItemWindowRenderer`, establish `HStack(alignment:.top, spacing:0){ mainColumn; if vm.inspectorShown { Divider(); inspectorColumn } }` with empty stubs framed to the constants. Build green. Commit.

### Task D1: construct the VM in the scene (+ live index + flush)
- [ ] In `ItemWindowSceneContent`, build the VM as `@State private var vm: ItemWindowViewModel?` set in the `if let resolved` block (closures → `env.itemContentManager.{updateItemProperty,updateItemIcon,updateItem,renameItem,deleteItem}`; the body closure passes `updateItem` with default `isBodyEdit: true`, the icon closure uses `updateItemIcon` which passes `isBodyEdit: false` — A3). **Live index (plan-review blocker fix):** the prior "`env.nexusManager` / `@Environment(NexusManager.self)`" guess was ungrounded — `NexusEnvironment` had no `nexusManager` and `NexusManager` wasn't injected into this scene. Task **A9** adds `NexusEnvironment.nexusManager` + injects it; here the renderer/inspector reads `@Environment(NexusManager.self)` and passes `nexusManager.currentIndex` (live, at render — NOT a stored snapshot) into each tier `ContextValueEditor`. Add `.onDisappear { Task { await vm?.flushBodyNow() } }` and `.id(ref)` so the VM re-inits per item. **Flush-on-replace caveat:** `.id(ref)` swapping items mid-session can drop a pending sub-300ms body edit (the close path is covered by `.onDisappear`; the in-window item-swap is an accepted v1 bounded-loss edge per §11). Build green. Commit.

### Task D2: Header zone (exit-left-of-icon, icon, title, toggle, drag)
- [ ] In `mainColumn`: a header `HStack` = `[✕ exit]` (plain `xmark` style copied from `PreviewWindow.swift:44-54`, calls `dismissWindow()`) · icon via `.iconPickerPopover(isPresented:$showIcon, symbol:$vm.draftIcon)` wired to `vm.handleIconChange` · `TextField("Title", text:$vm.draftTitle)` with `.onSubmit { Task { await vm.handleTitleCommit() } }` + `@FocusState` firing `handleTitleCommit` on false-transition + inline `if let e = vm.inlineError { Text(e).foregroundStyle(.red).font(.caption) }` · `Spacer()` · `[▥ inspector toggle]` (plain style; toggles `vm.inspectorShown`). Apply `.gesture(WindowDragGesture())` to the header row. **No Liquid Glass.** Build green; manually verify rename persists (Enter + click-away) + collision shows. Commit.

### Task D3: Body zone (editable MarkdownPM + counter)
- [ ] `MarkdownPMEditor(text:$vm.draftBody, isEditable:true, documentId: vm.item.id, …)` `.frame(maxWidth:.infinity, minHeight:80, maxHeight:200)`; `.onChange(of: vm.draftBody) { _, new in vm.handleBodyChange(new) }`; a counter reddening on `vm.isOverCap`. Build green; manually verify typing persists + cap blocks + closing immediately still saves (flush). Commit.

### Task D4: Property Field zone (pooled chip-row)
- [ ] Render `TemplateResolver.promotedForField(type: vm.itemType, collection: vm.collection)` (paired entries). **Per-pool slice (plan-review fix):** group entries by `ItemWindowZoneConfig.pool(for: def.type)` and defensively keep at most each pool's cap (V1: combined-total 4 across select+multi) — **not** a single global `.prefix`. Each cell: a select/multi editor using `ChipDropdown` — local `@State private var opts: [PropertyChipOption]` seeded `.onAppear` from `definition.selectOptions?.map { $0.asChipOption() }`; selected from the item's current value; `onPick` → `vm.handlePropertyChange(def.id, …)`. Honor `property_layout == .standard` (title + chips). Build green; manually verify assignment persists + the chip shows when empty. Commit.

### Task D5: Inspector zone (contexts + filled-non-pinned + Add-Property)
- [ ] Create `ItemInspectorRow` composing per type: `.select/.multiSelect/.status` → `ChipDropdown` (local opts); `.date/.datetime` → `DateTimePicker`; `.number/.url` → `TextField`; `.checkbox` → `PropertyCheckbox`/`Toggle`; `.file`/`.lastEditedTime` → `PropertyCellDisplay` (read-only). Tier rows: `ContextValueEditor(ids: $vm.draftTierN, scope: .contextTier(N), index: nexusManager.currentIndex, resolver: contextResolver)` — **`ids` is a `@Binding` (use `$`, plan-review fix)**; `nexusManager = @Environment(NexusManager.self)` (live index via A9); `contextResolver = @Environment(ContextDisplayResolver.self)`. In `inspectorColumn`: 3 tier slots at top (always; labels from `@Environment(TierConfigManager.self)`); let `promoted = TemplateResolver.promotedForField(type: vm.itemType, collection: vm.collection)`; then rows for each property where **`ItemWindowViewModel.isFilled(vm.draftProperties[id]) OR vm.surfaced.contains(id)`** AND **not pinned** (`!Set(promoted.map { $0.promotion.id }).contains(id)`); then an "Add Property" `Menu` over `ItemWindowViewModel.addableProperties(schema: vm.itemType.properties, filled: Set(vm.draftProperties.filter { ItemWindowViewModel.isFilled($0.value) }.map(\.key)), pinned: Set(promoted.map { $0.promotion.id }))` → `vm.addProperty`. Below a `Divider()`, a read-only meta section (`modified_at` via `PropertyCellDisplay`; `id`/`created_at` collapsed). Build green; manually verify contexts always show (live index, names resolve) + assign persists + Add-Property surfaces→assigns + clear keeps the row this session. Commit.

### Task D6: Footer zone (reuse `DetailFooterBar`)
- [ ] `DetailFooterBar(crumbs: <container path as [FooterCrumb]>) { /* trailing */ ⋯ options Menu + destructive Delete → .confirmationDialog }`. Add `@Environment(\.dismissWindow)`; on confirm `Task { await vm.confirmDelete(); dismissWindow() }`. Build green; manually verify path shows + delete + close. Commit.

### Task D7: inspector toggle collapse
- [ ] Confirm the `if vm.inspectorShown` two-column/single-column switch (D0) is driven by the header toggle (D2); single-column width = `mainWidth`. Build green; manually verify collapse/expand. Commit `feat(items): inspector collapse toggle`.

---

## Phase E — Templates pane (grouped checkbox list)

### Task E1: grouped-by-type checkbox pane + pooled-cap muting
- [ ] In `ItemTemplatePane`, add a new section: `Dictionary(grouping: itemType.properties, by: \.type)` rendered as section groups (header layout modeled on `StatusGroupSection`; per-property checkbox row modeled on `PropertyVisibilityPane`'s row — confirm both at edit time). Each property's checkbox = pinned (`promoted_properties` membership). **Muting:** compute `pinnedTypes` via `ItemWindowZoneConfig.pinnedTypes(promoted:schema:)`; for each unchecked row call `ItemWindowZoneConfig.muteReason(def.type, pinnedTypes:)` → disable with a **distinct** treatment: `.capReached` shows the pool's "n/N" count; `.notInV1` shows a muted/lock treatment. Checking writes `template_config.promoted_properties` via `updateTemplateConfig`; on the first pin write to a Set still carrying legacy `pinnedProperties` (`resolved.collection?.templateConfig?.promotedProperties == nil`), call the legacy collapse (`:379-396`). Keep cover + scope sections. Build green; manually verify select/multi checkable to cap then mute, others muted-as-disabled (distinct), pins reflect on the card. Commit.

### Task E2: `property_layout` control (Standard; Compact disabled)
- [ ] Add a minimal `property_layout` control bound to `liveTemplateConfig?.propertyLayout ?? .standard`, writing via `updateTemplateConfig`. The Compact option is `.disabled(true)`. Build green. Commit.

---

## Phase F — Cross-checks, docs, full green

### Task F1: full-target green + format
- [ ] Run the **entire** `-only-testing:PommoraTests` target; confirm non-zero executed count + all green (`ItemWindowLayoutsTests` runs only here). `swift format lint --strict --recursive Pommora/Pommora`; fix; commit format-only.

### Task F2: docs — Items.md + Paradigm-Decisions #15 + History
- [ ] `Features/Items.md` ~:91: Type-root items inherit the Type's template (pinning in `template_config` on Type or overriding Set), superseding "no pinning controls for Type-root items."
- [ ] `Guidelines/Paradigm-Decisions.md` #15 amend: `property_layout` added (`PropertyLayoutMode`, absent⇒standard); `layout` + `PromotedProperty.display` decode-tolerated, not honored; `template_config` is the rendering-config home (item files untouched); pooled-cap config is code-side data (`ItemWindowZoneConfig`), not on disk; the interactive window replaces the read-only stub; archetype model retired; `commitItemEdits` removed.
- [ ] `History.md`: concise entry. Commit `docs(items): ItemsV2 interactive window — Items.md + #15 amend + History`.

---

## Self-Review

- **Spec coverage:** §2 (no mode enum)→C1; §3 scope→D/E; §4 anatomy/sizing→D0; §4.1 header→D2; §4.2 chip-row+pooled cap→A5/A6/D4; §4.3 body+flush→B6/D3; §4.4 inspector (contexts/filled/surfaced/Add-Property/meta)→B8/D5; §4.5 footer (DetailFooterBar)→D6; §5 editors→D4/D5; §6 save model (.null at manager/debounce/tier-clear/title)→A2/B2/B3/B4/B6; §7 pane→E1/E2; §8 schema→A4; §9 reuse→file structure+C/D; §10 must-fixes→A1(rename)/A2(.null)/A3(icon-cap)/A4(property_layout)/A5(engine)/A6(promotedForField)/C1(editing+display)/E1(pane)/A8(placeholder)/D1(live index)/D6(footer)/F2(docs); §11 states→B2/B4/B6/B8/D5/D7/(VM lifecycle D1); §14 decisions→all; §15 blast radius→A1/A2/A7/C1/E1; §16 round-5 fixes→A2(audit)/A3/A5(pinnedTypes)/A6(paired)/C1(display path)/D1(live index)/D6(footer)/B-VM(concurrency).
- **Placeholder scan:** Phase D/E are composition + build-green + manual (SwiftUI bodies aren't unit-tested); all logic TDD'd in A/B. No `TBD`.
- **Type consistency:** `ItemWindowZoneConfig.{pools,isAtCap,muteReason,pinnedTypes,v1Checkable}` (A5) ← A6/D4/D5/E1; `promotedForField` paired return (A6) ← D4/D5/E1; VM methods (A/B) ← D; `PropertyLayoutMode` (A4) ← E2/D4; `draftIcon: String?` consistent B1↔D2; `PUI.ItemWindow.*` (D0) ← renderer; footer = `DetailFooterBar` (no new type) ← D6.
- **Verify-before-write:** confirm exact labels for `Item`/`ItemType`/`PropertyDefinition` inits, `NexusPaths.*`, `ItemValidator.effectiveCap(template:)`, `PommoraIndex.open(at:)`/`IndexUpdater`, `ChipDropdown`/`asChipOption`, `ContextValueEditor`, `.iconPickerPopover`, `MarkdownPMEditor`, `DetailFooterBar`/`FooterCrumb`, `StatusGroupSection`/`PropertyVisibilityPane` row, the live index source in the scene — at edit time.

---

## Execution handoff (after the plan review returns clean)

Two options: **(1) Subagent-Driven** (fresh subagent per task, two-stage review between — recommended; `superpowers:subagent-driven-development`) or **(2) Inline** (batch with checkpoints; `superpowers:executing-plans`). Builder verification always via background `Agent` (quirk #13). Nathan picks at handoff.
