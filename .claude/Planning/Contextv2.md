# Drop Relations → Contexts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Checkbox (`- [ ]`) steps. Swift/macOS — run every `xcodebuild test` via a **background builder subagent** (quirk #13). **Run the whole `-only-testing:PommoraTests` target each time** (not a per-suite filter) and confirm a **non-zero executed count** (quirk #1) — this sidesteps suite-name/filename divergence. `swift format` is a subcommand (quirk #11). Anchors were verified live and hardened through **two adversarial review rounds**; still **grep-confirm before deleting**. **The test target is part of "green"** — every deletion task carries a *Test fallout* bullet because the compiler fails the whole build if a surviving test references a deleted symbol.

**Goal:** Remove user-creatable Relations so the **three context tiers (Spaces/Topics/Projects) are the only relation-type connections**, then **rename the surviving machinery `Relation*` → `Context*`** (including the index table `relations` → `context_links`). Wikilinks/graph are a **separate v0.4.0 effort** — one deferred doc line only.

**Architecture:** Retire, don't break the substrate. Drop the user-relation create/edit/dual-pair machinery + the now-dead legacy relation migration; filter stored user-relation defs out at decode (DRY helper, the `.date`-retirement pattern) **while exempting reserved tier IDs** so tier customizations survive, and **decode legacy relation targets tolerantly** so old sidecars stay loadable. **KEEP the substrate** (`$rel` token, `PropertyValue.relation` codec, `RelationTarget.contextTier`, `TierRelationCarrying`, `RelationTargetKind`, `PropertyType.relation` enum case). Then a mechanical `Relation→Context` rename of every context-only symbol. Orphaned `$rel` member values are cleared opportunistically inside the migration's existing member-walk (no new file/launch-hook).

**Tech Stack:** SwiftUI · Swift 6 · swift-testing · GRDB (SQLite) · Yams · Xcode 26 `swift format`.

**Standard commands:** full suite `xcodebuild test -scheme Pommora -destination 'platform=macOS,arch=arm64' -only-testing:PommoraTests 2>&1 | tail -40` → `** TEST SUCCEEDED **`, non-zero count. Format: `swift format format --in-place <paths>` then `swift format lint --strict <paths>`. Commit per task; callers deleted before callees so every commit is green.

> **Two decisions locked by Nathan (2026-06-04):** (1) **Orphan-clear is folded into the migration member-walk**, not a standalone task — leftover `$rel` values are functionally inert (schema-driven render skips them — `PropertyPanel.swift:101` iterates the schema, not the member dict — Task 6 stops indexing them, and they decode + round-trip harmlessly). (2) **The legacy relation migration is deleted wholesale** — Task 1's decode filter strips every user `.relation` def *before* the migration scan runs, so both passes of `applyRelationTransforms` are dead. Keep only the ID-mint + version-bump.

---

## PHASE A — Remove user-creatable relations (Tasks 0–6)

### Task 0: Baseline
- [ ] Run the full suite; record actual pass/fail (don't trust inferred "RED" claims for `CollectionTypeIDReconcileTests`/`RelationDeleteToleranceTests` — confirm their real state). Note the executed count to compare against post-refactor.

### Task 1: Decode-time filter (DRY helper, tier-safe) + regression tests
**Files:** create `PommoraTests/Content/UserRelationDecodeFilterTests.swift`; edit `Vaults/PropertyDefinition.swift`, and **all four `[PropertyDefinition]` decode sites**: `Items/ItemType.swift:80`, `Vaults/PageType.swift:73`, `Agenda/AgendaTaskSchema.swift:66`, `Agenda/AgendaEventSchema.swift:66`.
- [ ] **Failing tests** — create `UserRelationDecodeFilterTests.swift`:
```swift
import Testing
import Foundation
@testable import Pommora

@Suite("UserRelationDecodeFilter")
struct UserRelationDecodeFilterTests {
    private func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    @Test func itemTypeDropsUserRelationDefOnDecode() throws {
        let json = """
        {"id":"01ITEMTYPE","modified_at":"2026-06-04T00:00:00Z","schema_version":2,
         "properties":[{"id":"prop_rel","name":"Author","type":"relation","relation_target":{"kind":"item_type","item_type_id":"01OTHER"}},
                       {"id":"prop_num","name":"Pages","type":"number"}]}
        """
        let t = try decoder().decode(ItemType.self, from: Data(json.utf8))
        #expect(t.properties.contains { $0.id == "prop_num" })
        #expect(!t.properties.contains { $0.type == .relation })
    }
    @Test func pageTypeDropsUserRelationDefOnDecode() throws {
        let json = """
        {"id":"01PAGETYPE","modified_at":"2026-06-04T00:00:00Z","schema_version":2,
         "properties":[{"id":"prop_rel","name":"Cited","type":"relation","relation_target":{"kind":"page_type","page_type_id":"01OTHER"}}]}
        """
        #expect(try decoder().decode(PageType.self, from: Data(json.utf8)).properties.isEmpty)
    }
    // CRITICAL: a stored tier override (reserved id, type .relation) MUST survive — these carry custom reverse-name/icon.
    @Test func itemTypeKeepsStoredTierOverrideOnDecode() throws {
        let json = """
        {"id":"01ITEMTYPE","modified_at":"2026-06-04T00:00:00Z","schema_version":2,
         "properties":[{"id":"_tier1","name":"My Spaces","type":"relation","relation_target":{"kind":"context_tier","tier":1},"reverse_name":"Members"}]}
        """
        let t = try decoder().decode(ItemType.self, from: Data(json.utf8))
        let tier = try #require(t.properties.first { $0.id == "_tier1" })
        #expect(tier.reverseName == "Members")
    }
}
```
- [ ] Run → fixtures 1 & 2 go **RED** in baseline; fixture 3 is a **green-both-ways regression guard** against a *naive* helper that drops reserved tier defs (it must stay green after the fix, not fail before it). Then add the **DRY helper** at the end of `PropertyDefinition.swift` (confirm the snake-case key for `reverse_name` matches the real CodingKeys before trusting the fixture):
```swift
extension Array where Element == PropertyDefinition {
    /// User relations retired; tiers are synthesized at runtime. Drop stored `.relation` defs on decode,
    /// EXCEPT reserved tier ids (`_tier1/2/3`) — those persist a user's reverse-name/icon override.
    func droppingUserRelations() -> [PropertyDefinition] {
        filter { $0.type != .relation || ReservedPropertyID.isReserved($0.id) }
    }
}
```
- [ ] Call it at **all four decode sites** → `self.properties = (<decoded properties>).droppingUserRelations()`: `ItemType.swift:80`, `PageType.swift:73`, and BOTH Agenda schemas. ⚠️ `AgendaTaskSchema`/`AgendaEventSchema` `init(from:)` decode `properties` in **two branches** — a legacy `if let legacyProps = try? c.decode([LegacyProperty].self…)` map (`:56-64`, can yield `type: .relation`) and the new-shape `else` (`:66`). Apply `.droppingUserRelations()` to the **final assigned `self.properties`** (wrap the whole if/else result), not just `:66`, so the legacy path isn't a back-door.
- [ ] **Test fallout (keep target green) — these break the instant the filter lands (the migration scan + `decodeStaged` both re-run `init(from:)`), so they must be handled HERE, not deferred to Task 7:**
  - **`git rm Pommora/PommoraTests/Nexus/PropertyIDMigrationTests.swift` relation cases** — git-rm (or fully stub) the six migration-transform tests that decode a user `.relation` def and `#require` it survives: `rewritesPageCollectionTargetToParentPageType` (:563), `rewritesItemCollectionTargetToParentItemType` (:596), the contextTier-drop test, and the multi-type `plan.allEvents` test. They validate the migration deleted in Task 7. Drop the "amend" framing — remove them.
  - **`RelationDeleteToleranceTests.swift`** — only **2 of 4** tests build retired targets (`.pageCollection` :38, `.itemCollection` :95 + `DualPropertyConfig`). The other 2 (`pageTypeManagerErrorRendersFriendly` :148, `itemTypeManagerErrorRendersFriendly` :153) are live `LocalizedError` assertions on `PageTypeManagerError`/`ItemTypeManagerError.propertyNotFound`. **Before `git rm` the file, relocate those 2 friendly-error assertions** into a surviving manager-error test (e.g. `ManagerErrorMessageTests`) so that behavior stays covered.
  - Catch stragglers: `grep -rln 'relationTarget: .pageType\|relationTarget: .itemType\|relationTarget: .pageCollection\|relationTarget: .itemCollection' Pommora/PommoraTests`. **Do not** touch tier-override tests.
- [ ] New tests PASS → full suite green → format + commit `feat(relations): retire user-relation defs via tier-safe decode filter`.

### Task 2: Remove `.relation` from the catalog
**Files:** `Properties/PropertyTypePicker.swift:18`; `PommoraTests/.../PropertyTypePickerTests.swift`.
- [ ] **grep-guard:** `grep -n 'userCreatable' PropertyTypePickerTests.swift` — confirm `userCreatableCountIs9` + any `expectedCasesPresent` set.
- [ ] Update the test: count 9→8 + remove `.relation` from the expected set. Run → FAIL.
- [ ] Delete `.relation,` (`:18`) from `userCreatable`. **Keep** the `pickerIcon`/`displayName` `.relation` arms (`:33,:50`) — `PropertyType.relation` is KEEP-substrate, the switches must stay exhaustive.
- [ ] PASS + suite green → commit `feat(relations): drop Relation from the user-creatable catalog`.

### Task 3: Delete the editor UI, routing, target-pickers, and dead create-branches
**git rm:** `Properties/RelationTargetMenu.swift`, `RelationTargetCatalog.swift`, `RelationDraftBuilder.swift`, `PommoraTests/.../RelationTargetCatalogTests.swift`. (`EditPropertyPaneRelationTests.swift` was already removed in Task 1 — it broke on the decode filter; skip it here.)
- [ ] **`EditPropertyPane.swift`** — delete the user-relation create path AND the paired-relation mirror path (all below are paired/create-only; the *tier* path uses `bindingForReverseName`/`reverseIconBinding`/`reverseIconPickerOpen` and survives):
  - Create path: `createRelationBody` (`:156-182`), `createRelationIconTitleRow` (`:188-218`), `createRelationFooter` (`:223-245`), `commitRelationDraft` (`:1046-1078`), `RelationDraftTargetSection` (`:1086-1103`), `RelationDraftMirrorSection` (`:1107-1146`), `canSaveRelationDraft` (`:247-252`), `@State relationDraft` (`:81`), `relationReverseName` (`:82`).
  - **Mode plumbing** (BLOCKER if half-done): delete the `Mode` enum (`:55-58`); **replace `let mode: Mode` (`:61`) with `let propertyID: String`** init param; delete the `propertyID` computed accessor (`:86-89`); update the construction site **`ViewSettingsPopover.swift:70`** `EditPropertyPane(scope: scope, mode: .edit(propertyID: id), path: $path)` → `EditPropertyPane(scope: scope, propertyID: id, path: $path)`. The `body` then reduces to `editBody` (no switch).
  - **Paired-mirror methods** (BLOCKER — these call `updatePairedRelation`, deleted in Task 5): delete `commitMirrorName` (`:963`), `commitMirrorIcon` (`:986`), `mirrorIconBinding` (`:629`), `@FocusState mirrorNameFocused` (`:78`), `@State mirrorNameDraft` (`:76`) + its `onAppear` seed (`:145`), and the `.onChange/.onDisappear/.focused` wiring inside `relationPairedReverseRow` (`:556-576`). ⚠️ `mirrorNameDraft` is paired-only; the genuinely tier-used `@State` is `reverseIconPickerOpen` (`:71`), which stays.
  - **`catalog` (`:254-260`)** — deleting it breaks `resolvedTargetDisplay` (`:593-611`), reached on the *surviving* tier path (`relationEditSection:453`→`relationTargetReadonlyRow:467`→`resolvedTargetDisplay:468`). **`resolvedTargetDisplay` switches over `RelationTarget?` (`:596`), whose user cases still exist until Task 7 — so DO NOT remove the `.some(let concrete)` arm (the switch would go non-exhaustive and break THIS commit).** Instead replace that arm's body (the `catalog.resolve` call, `:603-607`) with a neutral fallback: `return ("arrow.triangle.branch", "Unknown target")`. The arm collapses naturally in Task 7 when the cases go.
  - **`relationPairedReverseRow`** call in `relationEditSection`'s else branch (`:457`) + the method (`:536`): delete; make `relationEditSection` call `relationTierReverseRows` (`:455`) unconditionally.
- [ ] **`PropertyTypePickerPane.swift`** — delete the `.relation`→`.newRelation` routing block (`:66-72`). **Do NOT** delete the `.relation` arm in `makeDefaultDefinition` (`:175-179`) — it's an exhaustive `switch` over `PropertyType`, which **keeps** `.relation` (KEEP-substrate); removing the arm makes the switch non-exhaustive. Leave it as harmless documented dead code.
- [ ] **`ViewSettingsRoute.swift`** — delete `case newRelation` (`:28`) + its `paneTitle` arm (`:41`). **`ViewSettingsPopover.swift`** — delete `case .newRelation` (`:71-72`).
- [ ] **`TypeSettingsSheet.swift:326` + `VaultSettingsSheet.swift:366`** — delete the now-unreachable `if type == .relation { … resetNewPropertyState() … }` silently-cancel branches (`:330`/`:370`) + their stale comments (the `onSelect` closure collapses to dismissing the picker).
- [ ] **Test fallout:** `ViewSettings/ViewSettingsScopeMappingTests.swift` (the `.newRelation` route case) — `git rm` or drop that case.
- [ ] Suite green → commit `feat(relations): delete the user-relation editor, routing, target pickers, and dead create-branches`.

### Task 4: Delete the cross-type-move back-ref clearing (runs BEFORE dualProperty deletion)
> Ordering fix: both production move-strip blocks read `def.dualProperty`, so they must go in or before the commit that deletes `dualProperty` (Task 5). They run first here.
- [ ] Delete the `moveAcrossTypesClearsPairedRelationBackRefs` tests: `Items/MoveItemTests.swift:120` and `Content/MovePageTests.swift:150` (note the real dirs — there is no `PommoraTests/CRUD/`).
- [ ] **`ItemContentManager+CRUD.swift`** `moveItemAcrossTypes` — delete the `for def in strippedDefs where def.type == .relation { … guard let dual = def.dualProperty … stageBackRefClear … }` block (`:526-540`) + `stageBackRefClear` (`:610-680`), `extractRelationIDs` (`:599-605`), `removeID`. **Keep** the name-based strip (`:481-490`).
- [ ] **`PageContentManager+CRUD.swift`** `movePageAcrossTypes` — mirror (block `:493-510` reading `def.dualProperty` at `:494` + helpers).
- [ ] Suite green → commit `refactor(relations): drop paired back-ref clearing from cross-type moves`.

### Task 5: Delete `DualRelationCoordinator`, paired wiring, and `dualProperty`
**git rm:** `Vaults/DualRelationCoordinator.swift`. (All the paired/dual TEST files — `DualRelationCoordinatorTests`, `DualRelationCoordinatorAgendaTests`, `DualRelationWiringTests`, `PairedRelationUpdateTests`, `PairedRelationManagerUpdateTests`, `PairedRelationTargetsTests` — were already removed in Task 1 because they round-trip a `.relation` def through disk reload past the new filter; confirm none remain via `git ls-files '*DualRelation*' '*PairedRelation*'` and delete any stragglers, but expect only the production `DualRelationCoordinator.swift` here.)
- [ ] **`PerTypeSchemaService.swift`** — delete the paired block in `addProperty` (`:182-231`) and in `deleteProperty` (`:328-364` — the whole `if prop.type == .relation, let dualConfig = prop.dualProperty, let scope = prop.relationTarget {…}` block **including the `:361-363` unresolvable-reverse fallback referencing `dualConfig.syncedPropertyID`** and its closing brace). Keep the owner-only paths. Remove the 5 `PerTypeSchemaAdapter` requirements: `typeKind` (`:67`), `reverseRelationTarget` (`:72`), `resolveDualTargetKind` (`:79-82`), `reloadType` (`:88`), `nexusForCoordinator` (`:92`).
- [ ] **`PageTypeManager.swift` + `ItemTypeManager.swift`** — delete `updatePairedRelation`, `resolveDualTargetKind`, the `reloadTypeByID` stored property, the adapter conformance impls for the 5 methods, and the `duplicated.dualProperty = nil` line in `duplicateProperty`.
- [ ] **`NexusEnvironment.swift`** — delete the `reloadTypeAcrossManagers` closure (`:165-173`) and its two assignments (`:174-175`).
- [ ] **`PropertyDefinition.swift`** — delete `dualProperty` (`:35`, init param `:53`, assignment `:70`, decode `:308`, encode `:329`), `DualPropertyConfig` (`:163-171`), its CodingKey (`:275`). **Keep** `reverseName`/`reverseIcon`.
- [ ] **Test fallout:** `grep -rln 'dualProperty\|DualPropertyConfig\|resolveDualTargetKind' Pommora/PommoraTests`. Known: `Vaults/MemberFileStripResilienceTests.swift`, `Vaults/PropertyDefinitionTests.swift` (`dualPropertyConfigSnakeCase`/`RoundTrip` ~:124-139), `Items/MoveItemTests.swift`/`Content/MovePageTests.swift` (any residual `DualPropertyConfig` constructs). Disposition: `git rm` purely-dual tests; for mixed files, delete only the dual assertions.
- [ ] Suite green → commit `refactor(relations): delete DualRelationCoordinator, paired wiring, and dualProperty`.

### Task 6: Index builder + reconcile — drop user rows, keep tiers
- [ ] **Failing guard test** in `Index/TierRelationsEmitTests`: a `.relation([id])` `properties` value emits **no** `relations` row while tier rows DO. Run → FAIL.
- [ ] **`IndexBuilder.swift`** — delete the **entire `insertRelations` function** (`:665-712`, which makes **6** `insertRelationRows` calls at `:671,:677,:687,:693,:701,:708`) **and its single invocation at `:163`**; delete `insertRelationRows` (`:714-741`). **Keep** `insertTierRelations` (`:743`) + its call (`:164`) and `insertTierRelationRows` (`:793`).
- [ ] **`IndexUpdater.swift`** `reconcileRelations` — delete the user loop (`:447-471`, body + the loop's closing brace; includes the `INSERT INTO relations` at `:460`) + the `relationTarget(forPropertyID:)` helper (`:516-536`); **keep** the leading per-source DELETE (`:443-446`), the tier loop (`:472-496`, includes the tier `INSERT INTO relations` at `:485`), `RelationTargetKind.string()`.
- [ ] PASS + suite green → commit `refactor(relations): stop indexing user-relation values; keep tier rows`.

---

## PHASE B — Delete the dead migration, remove `RelationTarget` user cases, rename `Relation→Context`

### Task 7: Delete the legacy migration + tolerant-decode + remove `RelationTarget` user cases + fix the exhaustive switches
> Decision (2): the decode filter (Task 1) strips all user `.relation` defs *before* the migration scan runs, so both passes of `applyRelationTransforms` are dead. Delete it; keep ID-mint + version-bump.
- [ ] **`PropertyIDMigration.swift`** — delete `applyRelationTransforms` entirely (`:349-390`, both passes) and its calls in `scanPageType` (`:282`) / `scanItemType` (`:312`). **Then remove the now-dangling event plumbing it fed:** the `var events: [MigrationEvent] = []` local (`:172`) and the `events: events` argument at both `TypeMigration(...)` initializers (`:299`, `:329`). Delete `CollectionParentMap` (`:54-66`, `:396-448`) + its `scan` call (`:213-216`), and **remove the now-unused `parentMap: CollectionParentMap` parameter** from `scanPageType` (`:271`), `scanItemType` (`:304`), dropping the args at the call sites (`:224`,`:229`). **Delete the consent accessors + flattener that key on `.contextTierDropped`:** the standalone `allEvents` flattener (`:105-107`, its only remaining consumers are the two accessors below + deleted tests), `requiresAcknowledgment` (`:114-119`), `contextTierDropCountsByTier` (`:123-129`). **Keep** the ID-mint, the `schemaVersion` bump, and the member-walk (`applyPageType`/`applyItemType` — extended in Task 10). **grep-guard:** `grep -n 'CollectionParentMap\|applyRelationTransforms\|parentMap\|contextTierDropped\|requiresAcknowledgment\|allEvents' PropertyIDMigration.swift` returns zero after.
- [ ] **`MigrationEvent.swift`** — delete `pageCollectionRewritten`/`itemCollectionRewritten` (`:10-13`) **and `contextTierDropped`**. **Keep** `relationShapeWrapped` (`:7`), `allowsMultipleStripped` (`:9`), `agendaSchemaUnified` (`:17`).
- [ ] **Consent UI surface (BLOCKER — concrete consumers, not "the preview UI"):**
  - **`NexusManager.swift:344`** — reduce `let needsPreview = plan.hasAnythingToAdopt || migrationPlan.requiresAcknowledgment` to `plan.hasAnythingToAdopt` (`:343-344`).
  - **`AdoptionPreviewView.swift`** — delete `contextTierDropsSection` (`:323-360`, `@ViewBuilder` attr at `:323`), `contextTierName` helper (`:365-372`), `@State contextTierDropsAcknowledged` (`:34`), the section's body render (`:64`), and drop the `requiresAcknowledgment` term from the adopt-disabled accessor (`:479-483`, which reads `requiresAcknowledgment` at `:482`). (`contextTierDropCountsByTier` is read at `:326` *inside* `contextTierDropsSection` — it goes with that deletion.)
- [ ] **`PropertyDefinition.swift` — tolerant decode FIRST, then collapse the enum:**
  - **Make the target decode tolerant** so legacy sidecars stay loadable (the `RelationTarget` decoder's `default:` throws — `decodeIfPresent` propagates it, failing the whole sidecar). Wrap both decode attempts (`:301-305`) in `try?`:
    ```swift
    self.relationTarget = ((try? c.decodeIfPresent(RelationTarget.self, forKey: .relationTarget)) ?? nil)
        ?? ((try? c.decodeIfPresent(RelationTarget.self, forKey: .legacyRelationScope)) ?? nil)
    ```
    A retired user-relation value now degrades to `nil`; the def (still `type: .relation`) is dropped by Task 1's filter.
  - **Collapse `RelationTarget` to `.contextTier`-only:** delete the user cases (`.pageType :185-186`, `.itemType :187-188`, `.pageCollection :189-190`, `.itemCollection :191-192`, `.agendaTasks :195-196`, `.agendaEvents :197-198`) — **KEEP `.contextTier` (:193-194)**. Delete CodingKeys `:202-205` (**keep `:206 tier`**). Delete decode arms `:213-220` **and** `:223-226` (**keep `:221-222 context_tier` + the `default: throw` at `:227-232`** — now a tolerance boundary caught by the `try?` above). Delete encode arms `:238-249` **and** `:253-256` (**keep `:250-252 .contextTier`**).
  - **Add a regression test:** a sidecar JSON carrying `relation_target:{kind:"page_type", page_type_id:"X"}` decodes successfully (sidecar loads; the def is dropped).
- [ ] **`Index/IndexQuery.swift` (corrected — only TWO switch over `RelationTarget`):**
  - `entitiesByTarget` (`:14-58/60`, fully exhaustive, no default) — collapse to `.contextTier`-only.
  - `entitiesByTargetGrouped` (`:68-123`) — **already has a `default:` (`:120`)**; only delete the `.pageType`/`.itemType` case bodies (`:70,:95`), the `default` then covers `.contextTier`.
  - **DO NOT TOUCH** `targetSQL` (`:500-514`) / `targetEntityKind` (`:516-517`) — they switch over the separate enum **`TargetRef`** (`:721-729`), not `RelationTarget`; nor `entityKindToOwningTypeKind` (`:618`) / `entityKindFromString` (`:634`) — they switch over **`EntityKind`** (which has no `.contextTier`). None are affected by the `RelationTarget` case deletion.
  - (`TargetRef`'s parallel user cases may now be unreachable dead code — flag for a *follow-up* grep audit of its sort/filter callers `:321,:332,:465,:484`; out of scope here, leave intact since it compiles.)
- [ ] **`Validation/PropertyDefinitionValidator.swift`** — delete the entire `if def.type == .relation { … switch target … }` block (`:37-63`) + the now-unused error cases `relationMissingTarget`/`relationTargetNotResolvable` (`:11-15`). **`ViewSettings/PropertyEditorErrorMessage.swift:38-41`** — delete the `.relationMissingTarget`/`.relationTargetNotResolvable` arms (inside the `string(for:)` switch at `:28`).
- [ ] **`Index/RelationTargetKind.swift` (BLOCKER — MANDATORY in this same commit, NOT conditional):** `string(from:)` (`:18-33`) is a **third exhaustive switch over `RelationTarget` with NO `default:`** — so deleting the enum's user cases breaks it. **Delete the `.pageType/.pageCollection` (`:21`), `.itemType/.itemCollection` (`:22`), `.agendaTasks` (`:30`), `.agendaEvents` (`:31`) arms**, collapsing to `.contextTier`-only (keep `:23-29` — the tier→space/topic/project/context map; keep the `nil` guard). It is always referenced (`IndexUpdater.swift:455,:480`), so the "only if grep-unreferenced" framing was wrong — this is compile-time exhaustiveness on deleted cases.
- [ ] **Tolerance docstrings** on `PropertyType.relation`, the kept `RelationTarget.contextTier`/`RelationTargetKind` arms, and the `PropertyValue.relation` case declaration (`PropertyValue.swift:42` — NOT the `:92-95` decode arm): "tier-only tolerance; retired from user creation."
- [ ] **Test fallout (largest):** `grep -rln '\.pageType(\|\.itemType(\|\.pageCollection(\|\.itemCollection(\|\.agendaTasks\|\.agendaEvents\|contextTierDropped\|pageCollectionRewritten\|itemCollectionRewritten\|requiresAcknowledgment' Pommora/PommoraTests`. Known — `git rm` if purely legacy-relation, else reduce to `.contextTier`-only: `Vaults/RelationTargetTests.swift`, `Index/RelationTargetKindTests.swift`, `Validation/PropertyDefinitionValidatorTests.swift`, `Vaults/PropertyDefinitionTests.swift` (user-target assertions), `Index/IndexQueryTests.swift`, `Index/EntitiesByTargetGroupedTests.swift`, **`Index/CollectionIconTests.swift` (`git rm` — its whole purpose is the `.pageType`-grouped Collection-icon path being deleted; the `entitiesByTargetGrouped(.pageType(...))` arg at `:83,:122` won't compile, so it cannot be "reduced")**, `Nexus/PropertyIDMigrationTests.swift` (remaining Collection→Type + contextTier-drop + `plan.allEvents.count` cases not already removed in Task 1), `Nexus/MigrationEventTests.swift`, `Nexus/MigrationConsentTests.swift`, `Nexus/NexusManagerLaunchIntegrationTests.swift` (the consent-gate launch assertions), `Detail/PropertyCellEditorRelationTests.swift`, `Vaults/ReservedTypeIDTests.swift`, **`Properties/RelationPickerTests.swift`** (the `[RelationTarget]` "all kinds" array at `:117-123` + `makePicker(scope: .pageType(…))` at `:45` — reduce to `.contextTier`-only HERE; it breaks at *this* commit, not at the Task 8 rename), **`Vaults/BuiltInRelationPropertiesTests.swift`** (`mergeIgnoresStructurallyLockedRelationTargetInSidecar` at `:62` builds `relationTarget: .pageType("tampered")` at `:67` — swap for a surviving construct so the "merge ignores tampered target" intent survives the case deletion). Both then get *renamed* in Task 8 as tier-only survivors.
- [ ] Suite green → commit `refactor(relations): delete the dead relation migration + remove RelationTarget user cases`.

### Task 8: Rename `Relation→Context` — render/value/schema/DB layer
> Mechanical rename; the build catches *symbol* misses (NOT SQL string literals — see below). Do NOT touch the KEEP-substrate (`RelationTargetKind`, `TierRelationCarrying`/`relationIDs`/`setRelationIDs`, `PropertyValue.relation`, `$rel`, `RelationTarget.contextTier`).
- [ ] **SQL table (BLOCKER — the compiler does NOT catch raw SQL strings)** — rename `relations`→`context_links` everywhere it appears as a literal, in this commit:
  - `IndexSchema.swift`: DDL (`:122-131`), the `relationsDDL` constant + apply ref (`:15`), indexes `idx_relations_*`→`idx_context_links_*` (`:156-158`).
  - Surviving runtime statements (post-Task-6): `IndexBuilder.swift:481` (`DELETE FROM relations`), `:816` (tier `INSERT`); `IndexUpdater.swift:159,262,298,334` (per-source `DELETE`), `:444` (leading per-source `DELETE` in reconcile), `:485` (tier `INSERT`); `IndexQuery.swift:215,418,430` (`FROM relations`).
  - **grep-guard:** `grep -rn 'relations' --include='*.swift' Pommora/Pommora/Index | grep -iE 'FROM relations|INTO relations|TABLE relations|DELETE FROM relations|idx_relations'` returns **zero**.
  - Test SQL literals: `Index/TierRelationsEmitTests.swift`, **`Content/UnlinkTierTests.swift`** (confirmed path — NOT `Index/`), `Index/IndexBuilderTests.swift`, `Index/IndexQueryTests.swift`.
  - Bump `PommoraIndex.swift:58` schema version (force-rebuild).
- [ ] **Chips** — `RelationChip`→`ContextChip` (file + struct + ~9 consumer files — **grep-confirm**; named consumers incl. `ComponentLibraryView.swift` (rename `RelationChipShowcase`→`ContextChipShowcase` + its instantiations + the "Relation Chip" showcase copy), `NexusAdopter.swift`, `Detail/Columns/PropertyCellDisplay.swift`, `Properties/PropertyPanel.swift`, `Properties/RelationValueEditor.swift`); `RelationChipRow`→`ContextChipRow`.
- [ ] **Value/edit** — `RelationValueEditor`→`ContextValueEditor` (file + sites: `PropertyCellEditor`, `PropertyEditorRow`, `EditPropertyPane`, **`FrontmatterInspector.swift`**); `RelationPicker`→`ContextPicker` (+ private `RelationCollectionRow`/`RelationLeafRow`→`Context*`; rename `RelationPickerTests`→`ContextPickerTests`).
- [ ] **Display resolver (an `@Observable` injected per-Nexus manager — quirk #15; `relationResolver` is an OVERLOADED name, so be surgical):**
  - **Rename the TYPE `RelationDisplayResolver`→`ContextDisplayResolver` at EVERY grep hit** — `grep -rn 'RelationDisplayResolver' Pommora/Pommora`. A missed `@Environment(RelationDisplayResolver.self)` SIGTRAPs at runtime (quirk #15), not a clean error. Sites incl.: `NexusEnvironment.swift:63` (typed stored prop), `:148` (constructor), `:192` (assignment), `:258` (`.environment(…)` injection — quirk #15); `ItemWindow/ItemWindowRenderer.swift:42` (`@Environment`); `ItemWindow/PropertyEditorRow.swift:10` (`var … RelationDisplayResolver?`); `PropertyPanel`; the 4 detail views; `FrontmatterInspector.swift`; `ContentView.swift:289`.
  - **Rename the OWNER property** `NexusEnvironment.relationResolver`→`contextResolver` (`:63,:148,:192,:258`) + its read at `ContentView.swift:289`. The detail views also hold a SECOND env var `relationDisplay` (`@Environment(RelationDisplayResolver.self) private var relationDisplay` — `PageTypeDetailView:21`, `PageCollectionDetailView:20`, Item* mirrors) with `.warm(…)`/`.resolve(…)` chains (e.g. `PageTypeDetailView:198,:151,:169`) — rename that var too for consistency (build-safe, not forced).
  - **DO NOT touch** the unrelated `relationResolver:` CLOSURE param label (`(String)->(icon:,title:)?`) on `PropertyCellDisplay`/`PropertyCellEditor`/`ItemWindowRenderer`/the detail render-config — it is a different symbol; renaming it is out of scope and risks churn.
  - Rename `RelationDisplayResolverTests`→`ContextDisplayResolverTests`.
- [ ] **ProjectLink (separate from the user-Relation removal — per Nathan's rename decision)** — the Project property `linkedRelations` (on-disk key `linked_relations`) is Context-to-Context linking, NOT user-relation machinery. Rename it to **`projectLinks`** (on-disk `project_links`) in `Contexts/Project.swift` + every reader/writer (`TopicManager.swift` etc.). **Data-safe:** decode tolerantly — accept BOTH the new `project_links` and the legacy `linked_relations` key on read (mirror the existing `relation_target`/`relation_scope` dual-key pattern at `PropertyDefinition.swift:299-305`), always write `project_links`. Update its tests. (Nathan reports existing Project files may carry `linked_relations`, so the legacy-key fallback is required, not optional.)
- [ ] **Schema** — `BuiltInRelationProperties`→`BuiltInContextLinkProperties`. **Correct site list:** decl `Vaults/BuiltInRelationProperties.swift`, `Vaults/PageType.swift:130,134`, `Items/ItemType.swift:168,172`, **`Agenda/AgendaTaskSchema.swift:122,126`**, **`Agenda/AgendaEventSchema.swift:122,126`**, + rename `BuiltInRelationPropertiesTests`→`BuiltInContextLinkPropertiesTests`. (NexusEnvironment/PageTypeManager/ItemTypeManager have **zero** refs.)
- [ ] Suite green → commit `refactor(contexts): rename Relation→Context (render/value/schema/DB)`.

### Task 9: Rename `Relation→Context` — query/index/detail layer
- [ ] **`IndexQuery.swift`** — `incomingRelations`→`incomingContextLinks`. **All call sites** (enumerate, don't trust a count): `PageContentManager+CRUD.swift:854`, `ItemContentManager+CRUD.swift:808`, **`Agenda/AgendaTaskManager.swift:267`**, **`Agenda/AgendaEventManager.swift:272`** (+ their docstrings) — confirm via `grep -rn 'incomingRelations' Pommora/Pommora`. Also `entitiesByTarget`→`entitiesByContextTarget` (`:14`, now `.contextTier`-only after Task 7); `entitiesByTargetGrouped`→`entitiesByContextTargetGrouped` (`:68`, internal call `:121`).
- [ ] **`IndexUpdater.swift`** — `reconcileRelations`→`reconcileContextLinks` (`:434` + 4 call sites `:123,228,283,319`).
- [ ] **`IndexBuilder.swift`** — `insertTierRelationRows`→`insertTierContextLinkRows` (`:793` + sites); `insertTierRelations`→`insertTierContextLinks`.
- [ ] **Detail/UI** — `PropertyCellDisplay.relationCell`→`contextLinkCell` (`:241` + switch arm `:71`); `ItemWindowRenderer.relationsRegion`→`contextLinksRegion` (`:484` + call `:189`); `visibleRelationIDs`→`visibleContextLinkIDs` in the 4 detail views (`PageTypeDetailView:116`, `PageCollectionDetailView:90`, `ItemTypeDetailView:151`, `ItemCollectionDetailView:105`) + their `.task(id:)`/`warm(...)` refs.
- [ ] **Test fallout (rename) — these survive Tasks 1–7 (tier-path only) and first break HERE at the symbol rename:** `IconBackfillTests.swift:65` (calls `incomingRelations`), **`Index/RebuildResilienceTests.swift:130,133`** and **`Index/IndexPopulationReproTests.swift:127,130,303`** (both call `entitiesByTarget(.contextTier(N))` → `entitiesByContextTarget`), `Index/IndexQueryTests.swift`, `Index/TierRelationsEmitTests.swift`, `Content/UnlinkTierTests.swift` — update to the renamed symbols/SQL.
- [ ] Suite green → commit `refactor(contexts): rename Relation→Context (query/index/detail)`.

---

## PHASE C — Fold orphan `$rel` member-value clear into the migration walk (Task 10)

### Task 10: Clear orphaned `$rel` values during the migration member-walk
> Decision (1): no standalone file/launch-hook. The migration's `apply` already enumerates every member, rekeys its `properties` block, and stages each rewrite into one `SchemaTransaction` (`applyPageType:452-487`, `applyItemType:489-525`). Piggyback the clear there. Scope is honest: this clears orphans only for Types the migration already rewrites (a nexus already at schema v2 with minted IDs produces `Plan.empty` → the clear never runs); a Type needing no migration keeps its (inert) orphans — acceptable, since leftover `$rel` values are schema-invisible (`PropertyPanel.swift:101` iterates the schema), unindexed, and round-trip-stable. **Nathan reports zero configured user-relations on the current nexus, so this is a defensive no-op there — kept for completeness (e.g. restoring older data).**
**Files:** edit `Nexus/PropertyIDMigration.swift` (`applyPageType`, `applyItemType`); extend `Nexus/PropertyIDMigrationTests.swift` (or a focused suite) + `Index/TierRelationsEmitTests`.
- [ ] **grep-guards:** confirm the member load/re-encode helper (`~:534`, re-encodes in the member's own on-disk format); confirm `static let modeledKeys` in `Content/ItemFrontmatter.swift` / `Content/PageFrontmatter.swift` (so `properties` is the modeled dict being rewritten).
- [ ] **Failing test** — a fixture member under a migrating Type with an orphaned `$rel` value (property-id absent from `updatedSchemaJSON`'s properties) **and** a tier value (`tier1` root array); assert post-apply the orphan key is gone, while the tier root array + foreign frontmatter survive.
- [ ] **Implement** inside the existing member loop (both apply paths, via one shared DRY helper): the member is currently staged only when `rekey(properties:&…)` returns true (`applyPageType:460`, `applyItemType:502`). **Change the stage condition to an OR:** `let didRekey = rekey(…); let didClear = clearOrphanRelationValues(&props, validIDs:); if didRekey || didClear { txn.stage(…) }` — else a member needing only orphan-clearing (no id-rekey) is never written. The clear computes the valid property-id set from `migration.updatedSchemaJSON` (post-filter, includes reserved `_tierN`) and **drops any `properties` entry whose key ∉ that set AND whose value is a `.relation`/legacy `{$rel}` shape**. **Never** touch root `tier1/2/3`.
- [ ] **Extend `TierRelationsEmitTests`**: after a migration run, assert tier rows present and no orphan user-relation rows.
- [ ] Tests green + full suite green → commit `feat(contexts): clear orphaned user-relation values during the migration member-walk`.

---

## PHASE D — Complete documentation review (Task 11)

### Task 11: Full documentation review — rewrite EVERY doc against the shipped code
> The final task. Not a targeted patch — a **complete sweep of all project documentation**, rewriting every stale/false claim to match what Tasks 0–10 actually shipped. Use `docs-audit-skill`. Per CLAUDE.md: cross-check each doc claim against the code before treating it as factual — the code is the source of truth, the docs follow.
- [ ] **Build the retired/renamed vocabulary set** and grep it across all docs: `grep -rniE 'relation|linked_relations|dualProperty|RelationChip|RelationValueEditor|RelationDisplayResolver|RelationPicker|BuiltInRelationProperties|incomingRelations|reconcileRelations|entitiesByTarget|pageCollection|itemCollection|paired|context_?tier ?drop' .claude` → bucket every hit: **(a) rewrite** (false/stale factual claim), **(b) rename** (symbol/table/key changed), **(c) keep-historical** (an intentional past-tense `History.md`/changelog entry), **(d) intentional** (e.g. the surviving `context_links` / tier-relation / `RelationTargetKind` substrate, or the v0.4.0 wikilink roadmap). The doc set is "done" only when every (a)/(b) hit is resolved.
- [ ] **Affected-doc list** (prose-scoped 2026-06-04 — every `.claude` doc was read, not grepped; folders are literally `Features/`/`Guidelines/`, no leading space). For each, rewrite the named stale claim against what *actually shipped* — **the exact new wording is decided here, post-code, not prescribed in advance.** `verify` = a judgment call (reframe vs. leave-as-history vs. confirm-still-true) to confirm with Nathan during the pass.

  **Features**
  - `Properties.md` — **heaviest.** The whole user-Relation apparatus: catalog row + `dual_property`, "Relation values bind to entities", "Relation target" (4 kinds + paired table), "Dual relations" + editor, "Agenda as relation targets", validation rules 5–6; `RelationChip`/`incomingRelations`/`BuiltInRelationProperties` renames; "Per-tier relations"/Status/sort/Group-By survive but rename.
  - `Contexts.md` — `linked_relations` (L60/70/72)→`project_links` (ProjectLink); "Cross-layer relations"/"Linked-from" cite the `relations` table + `incomingRelations` + `BuiltInRelationProperties`; "User-defined relations target a Page Type…" (L86) now false.
  - `Architecture.md` — `incomingRelations`→`incomingContextLinks`; `relations`→`context_links`; "user-defined Relation-property values", "paired-relation create touches two sidecars", "Collection targets rewritten to their parent Type" all stale. *(verify — confirm exact sections.)*
  - `PageTypes.md` — the `_pagetype.json` example embeds a user `relation` property + full `dual_property` block (L88-138); Settings-sheet relation-target/dual language; the `EditPropertyPane .newRelation` route (L161) is gone.
  - `Agenda.md` — "Agenda Tasks and Events as relation targets" (L18-23) removed; `RelationTarget.agendaTasks/.agendaEvents`, `entitiesByTarget`, `incomingRelations`, `relations` table drop/rename; catalog mention L8.
  - `Domain-Model.md` — `linked_relations` (L37/L138)→`project_links`; "Cross-layer relations" + L173 "…mandatory dual… Cross-side relations supported" now false; `BuiltInRelationProperties`/`incomingRelations` rename.
  - `Items.md` — L3 "Items carry typed relations to any other entity" + L51 "relation values are tagged arrays" frame user-Relations as an Item capability (gone); tier `BuiltInRelationProperties` mention L97.
  - `Homepage.md` — `incomingRelations` (L42) rename; L48 "relation property values (including the tier relations)" assumes user relations alongside tiers.
  - `Pages.md` — "Wikilinks vs relations" (L104-111) + "Properties surface" contrast wikilinks against the user-Relation type. *(verify — reread "relation" as Context-links.)*
  - `PageEditor.md` — L66 cross-ref to Pages.md "Wikilinks vs relations" inherits the stale framing; one-line fix.
  - `QuickCapture.md` — L58 "Relation fields / relation pickers" deferral assumes user-Relation pickers. *(verify — may reread as Context pickers.)*
  - `Prospects.md` — "Relations Redesign — post-v1 deferrals" (L85-90) + Item↔Page/Cloud-sync incidental relations/tiers mentions. *(verify.)*
  - `Wiki-Link.md` — repeatedly analogizes wikilinks to user "relations" ("This mirrors how relations work" L15, "kept separate from relations" L84, the L106-112 table). *(verify — v0.4.0 doc making present-tense claims about the relations system; reframe vs. leave.)*

  **Guidelines**
  - `Paradigm-Decisions.md` — entries #1/#8/#9/#10/#12 are user-Relation decisions now superseded (#10 "tiers emit into `relations`"→`context_links`); **keep** #1's `$rel` statement. (Plus the new entry below.)
  - `CRUD-Patterns.md` — "Inline property editing + picker hosting" (L271-279) names `RelationValueEditor`/`RelationPicker`/`RelationDisplayResolver`/`RelationChip`→`Context*`; tier path survives renamed.
  - `Design.md` — L65 cites `RelationPicker` as the popover exemplar→`ContextPicker`. *(verify it's still the live exemplar.)*

  **Root**
  - `PommoraPRD.md` — DDL `relations` table (L276-284)→`context_links`, `idx_relations_*` (L304-306)→`idx_context_links_*`; "Property Model" L336/L339 "Cross-side relations supported"/"Relations paired by default… four container scopes" now false; the "Eleven data tables" count.
  - `Framework.md` — v0.3.4 + Relations-Redesign roadmap (L71-78) describe the now-removed system as shipped; v0.7.0 "relation-property sort + filter" + `incomingRelations`; log the Contextv2 drop. *(verify how shipped-then-removed history is handled.)*
  - `History.md` — "Make Relations Real" + "Relations Redesign" (L63-82) accurate-but-superseded; add a "Drop Relations → Contexts" entry. *(verify — append-only history → add, don't edit.)*
  - `CLAUDE.md` — Core-Principles "Relations stored by ID… Tiers are relations… merged via `BuiltInRelationProperties`" rename+reframe; quirk #12 cites `RelationPicker.swift`→`ContextPicker.swift`.
  - `Handoff.md` — self-correcting; Fix Log #5 closes; handled by the standard `/handoff` pass, not a manual edit.

  **Confirmed clean (verified, no change):** `Resources.md`, `Features/Collections.md`, `Features/Spaces.md`, `Features/NavDropdown.md`, `Features/PommoraUIX.md`, `Features/Sidebar.md`, `Guidelines/Markdown.md`, `Guidelines/Symbols.md`, `Guidelines/README.md`, `Planning/2026-05-31-vault-table-displayonly-interim.md`, `ReactInfo/Contingency.md`.
- [ ] **`Guidelines/Paradigm-Decisions.md` — add one decision entry:** user relations removed; tiers = sole relation type; `Relation→Context` rename + table→`context_links`; tolerant legacy-target decode; `Project.linked_relations`→`project_links` (ProjectLink, dual-key decode); orphaned `$rel` values schema-invisible/unindexed/round-trip-safe, cleared opportunistically in the migration walk; legacy migration deleted as dead-after-filter. **Plus one line** for the v0.4.0 connection-model roadmap (separate per-shape tables, weight-at-query, contexts-as-cores — not built now).
- [ ] **Completeness gate:** re-run the vocabulary grep; every remaining hit must be a deliberate (c)/(d) — zero stale factual claims. Commit `docs: align all documentation with the Relation→Context refactor`.

## Self-Review
- **Scope = your three points:** drop relations (A) → tiers are the only relation type (substrate kept; `RelationTarget` collapses to `.contextTier` in B) → rename Relation→Context (B). Orphan-clear (C) folded per your decision. **Wikilinks excluded** (one deferred doc line).
- **Green commits:** decode filter first (tier-safe + legacy-tolerant); move-strip (Task 4) before `dualProperty` deletion (Task 5); callers (Task 3) before callees (Task 5); migration + case-deletion + every dependent exhaustive switch + consent UI land together (Task 7); rename (Tasks 8–9) operates only on survivors; orphan-clear last (Task 10).
- **Substrate intact:** `$rel`/`PropertyValue.relation`/`RelationTarget.contextTier`/`TierRelationCarrying`/`RelationTargetKind`/`PropertyType.relation` keep names + behavior; reserved tier defs survive the decode filter; legacy sidecars stay loadable via tolerant decode.
- **Not over-reached:** `TargetRef`/`EntityKind` switches in IndexQuery are left alone (different enums); the unrelated `relationResolver:` closure labels are left alone (overloaded name). But `RelationTargetKind.string()` user arms ARE deleted in Task 7 (mandatory — it's a no-default switch over the collapsed enum).

## Verification
1. Per task: background builder green, **non-zero executed count** (quirk #1 — verify the suite actually ran); whole `-only-testing:PommoraTests` target each time.
2. **Tier round-trip:** set `tier1` on an Item → `context_links` row (`TierRelationsEmitTests`) → `incomingContextLinks` returns it → renders/edits via `ContextValueEditor`. A customized tier reverse-name survives a decode round-trip (Task 1 regression test).
3. **Decode + orphan-clear:** a legacy sidecar with a user `.relation` def + a member `$rel` value → sidecar loads (tolerant decode), def filtered, member orphan cleared during the migration walk, tiers + foreign keys unaffected.
4. **SQL grep-guard** (Task 8) returns zero `relations`-table literals; whole-target green; `swift format lint --strict` clean on touched files.

## Effort & execution
~12 tasks across 4 phases ≈ **3–4 Claude sessions** (Task 7 is heaviest — migration deletion + tolerant decode + 2 switch collapses + consent-UI + the broad test fallout; Tasks 8–9 rename largest by ref-count but mechanical; Task 11 is the full docs sweep). **Execution:** subagent-driven (recommended) — fresh subagent per task, review between; re-read the plan against reality after each green task.
