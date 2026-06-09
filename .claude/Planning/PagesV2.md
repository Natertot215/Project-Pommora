## PagesV2 — Items-Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement task-by-task. Steps use checkbox (`- [ ]`) syntax. **Green per commit** (paradigm decision #4). Each phase ends with a builder-subagent verification (quirk #13: background Agent, `-only-testing:PommoraTests`, no UI tests, no window-focus grab) — confirm a **non-zero executed count** (quirk #1), not just `** TEST SUCCEEDED **`.

**Goal:** Strip the Items subsystem from Pommora so the codebase reads as though Pages were always the only operational entity — no item-named code, no dormant item frameworks — while landing a plain `PagePreview` window, a vault-level Compact/Window open-in toggle, and user-creatable sidebar sections.

**Architecture:** Page is the sole survivor; `Item*` code/index-tables/tests are deleted and every `item|page` shared seam collapses to page-only. The `EntityKind`/`SidebarSelection` enum-case removals are the compiler's exhaustiveness gate (P2). MarkdownPM's `{{ }}` capability is **renamed** to an item-free page-native chip-link (kept, gated off), not parked under its old identity. `Class` is dropped; the index rebuilds at schema v11 (no data migration).

**Tech Stack:** SwiftUI, Swift 6 strict concurrency + ExistentialAny, GRDB/SQLite, Yams, in-tree `MarkdownPM` (TextKit 2 + `swift-markdown`), Swift Testing (`@Suite`).

**Source of truth:** spec `// Planning//06-09-Items-Strip-Spec.md`; decision record `// Planning//06-09-Items-Pages-Collapse-Evaluation.md`. This plan was authored from an 8-cluster + adversarial-critic whole-codebase review (workflow `pagesv2-codebase-review`).

---

### Decisions (resolved 2026-06-09)

All seven open decisions are ratified — reflected in the tasks below.

1. **`PageCollection.template_config` — dropped entirely.** No per-collection layout schema; `open_in` is vault-level on `PageType`. The 2 `CollectionTemplateConfigTests` page tests are deleted (P8).
2. **Open-in toggle — a segmented control at the bottom of the main settings pane.** A simple `Layout: Compact | Window` segmented `Picker` at the bottom of `StorageMenuRoot` (the settings dropdown), separated by a `Divider` above it, using Design.md padding discipline. Vault-scoped. No new `ViewSettingsRoute` case; no duplicate toggle in `PageTypeDetailView`.
3. **`{{ }}` collapses at the connection layer.** Connections use `[[` **only** — drop the `{{` regex from `ConnectionScanner`, collapse `ConnectionSyntax` to page-only, drop the chip arm from `AutoCompleteWiring`, no `{{` index rows. The chip-link **render design is retained, dormant, in MarkdownPM** (renamed page-native, gated off, NoOp resolver) so it can be re-enabled later — but the app wires no `{{` trigger.
4. **`{{ }}` click — moot** (collapsed). No `onChipLinkClick` wired; the dormant chip render reuses later if turned on.
5. **`Paradigm-Decisions.md` — append a superseding entry + mark #14/#15 superseded inline** (registry is append-only; chronology preserved).
6. **Band-3 sections — single-membership + inline-rename.** A vault sits in at most one user section; ungrouped vaults stay in the default Vaults section.
7. **Resolver — reuse `pageConnectionResolver`, rename `ConnectionResolver`.** Drop the separate `itemConnectionResolver` env key/@Entry; the renamed page resolver serves `[[` (fewer injection slots; quirk #15).

---

### Phase order & dependencies

`P0` (MarkdownPM rename, independent) · `P1` (collapse leaf item arms) → `P2` (remove enum spine = compiler gate) → `P4` (relocate survivors + `PageType.open_in`) → `P3` (delete item type bodies/managers/migration; `NexusEnvironment` keystone) → `P7` (schema v11) ; then `P5` (re-home chip-link app-side + build `PagePreview`) needs P0+P3+P4 ; `P6` (settings/labels) alongside P5 ; `P8` (test surgery) after P3/P7 ; `P9` (band-3, last build) after P5 ; `P10` (doc-sweep + archival) after P5/P8.

> Verification idiom (every phase): dispatch a **background builder Agent**: `xcodebuild build` then `xcodebuild test -only-testing:PommoraTests` on the Pommora scheme; report green/red + the executed test count. Never run xcodebuild in the foreground (quirk #13). Before each commit, revert incidental Yams/GRDB pbxproj package-reorder diffs (quirk #6).

---

### Phase P0 — MarkdownPM chip-link rename (item-free, capability kept)

**Goal:** rename the entire `item*` link framework in the package to a generic `chipLink` family + add the off-by-default gate, so the chip-link **render design survives as a dormant, reusable capability with zero item tokens**. Package builds + package tests green before app-side seams depend on the new names. (Per decision #3, the *app* wires no `{{` trigger — this pipeline stays in the package, gated off + NoOp-resolved, for later reuse; only the connection layer collapses to `[[`.)

**Files (all under `Pommora/Pommora/External/MarkdownPM/Sources/MarkdownPM/`):** `Parser/MarkdownToken.swift`, `Parser/MarkdownTokenizer.swift`, `Parser/MarkdownDetection.swift`, `Renderer/ItemChipMetrics.swift` (→ rename file `ChipLinkMetrics.swift`), `Renderer/MarkdownTextLayoutFragment.swift`, `Styling/MarkdownPMStyler+Links.swift`, `Styling/MarkdownPMStyler.swift`, `Styling/MarkdownPMStyler+TextStyling.swift`, `Services/MarkdownPMServices.swift`, `TextView/NativeTextViewWrapper.swift`, `TextView/Coordinator/NativeTextViewCoordinator.swift` (+`+Restyling`/`+TextDelegate`/`+Services`), `TextView/NativeTextViewSelectionTypes.swift`; tests under `External/MarkdownPM/Tests/MarkdownPMTests/`.

- [ ] **Step 1 — Token + attr keys.** `MarkdownToken.swift`: `case .itemLink → .chipLink` (L26); attr keys `itemLinkTitle → chipLinkTitle` (raw `"ChipLinkTitle"`), `itemChipIcon → chipLinkIcon` (raw `"ChipLinkIcon"`) (L15–16). `MarkdownTextLayoutFragment.swift`: `itemChipBounds → chipLinkBounds` (raw `"ChipLinkBounds"`) (L21).
- [ ] **Step 2 — Tokenizer + detection.** `MarkdownTokenizer.swift`: `itemLinkRegex → chipLinkRegex` (L21), emission `.itemLink → .chipLink` (L121–128). `MarkdownDetection.swift`: `itemDepth → chipDepth` (L510/516–520), `.itemLink → .chipLink` (L416). Scrub item comments. **LEAVE** genuine bullet/heading list-item comments (L84–95/268).
- [ ] **Step 3 — Metrics file rename.** Rename `Renderer/ItemChipMetrics.swift → ChipLinkMetrics.swift`; `enum ItemChipMetrics → ChipLinkMetrics`; header-comment scrub. (Synchronized file group auto-includes — quirk #2; confirm no explicit pbxproj reference.)
- [ ] **Step 4 — Fragment draw.** `MarkdownTextLayoutFragment.swift`: `drawItemChips → drawChipLinks`, `itemChipRects → chipLinkRects`, `itemChipFont → chipLinkFont`, `itemChipRect(forSize:) → chipLinkRect(forSize:)` (L758/796/1131–1225); attribute reads use `chipLink*` keys; `ItemChipMetrics.* → ChipLinkMetrics.*` (L1191–1204). **LEAVE** L296 `-` list-item comment.
- [ ] **Step 5 — Styler + gate.** `MarkdownPMStyler+Links.swift`: `styleItemLinks → styleChipLinks` (L105), `.itemLink → .chipLink` (L107), `ctx.services.itemLinks → chipLinks` (L114), `ItemChipMetrics.size → ChipLinkMetrics.size` (L123), attr stamps → `chipLink*` (L130–132/168). **Add gate:** `MarkdownPMLinkConfig.renderChipLinksAsChips: Bool = false` read via `ctx.configuration`; when `false`, skip the kern-trick chip-draw branch (L120–160) and fall through to the plain-link branch (L162–174 → `.link` + `.chipLinkTitle`). `MarkdownPMStyler.swift`: call site `styleItemLinks → styleChipLinks` (L256, KEEP the call), `.itemLink` filters → `.chipLink` (L457/498). `MarkdownPMStyler+TextStyling.swift`: `.itemLink → .chipLink` (L65).
- [ ] **Step 6 — Services + coordinator + selection.** `MarkdownPMServices.swift`: `services.itemLinks → chipLinks` (L249), init param + assignment (L257/264). `NativeTextViewWrapper.swift`: `onItemLinkClick → onChipLinkClick` (L72/102/119/421). Coordinator chain (`+Restyling`/`+TextDelegate`/`+Services`): `onItemLinkClick → onChipLinkClick`, `itemLinkTokens → chipLinkTokens`, `InlineTokenContext.itemLink → .chipLink`, `isItemLinkActive → isChipLinkActive`, `.itemLinkTitle` reads → `.chipLinkTitle`, local `itemTitle → chipTitle`. **LEAVE** `NSMenuItem item.tag` locals (`+Services` L121–122). `NativeTextViewSelectionTypes.swift`: `InlineSelectionKind.itemLink → .chipLink` (L38).
- [ ] **Step 7 — Package tests.** Rename `ItemLinkTokenizerTests.swift → ChipLinkTokenizerTests.swift` (`@Suite` + struct + `.itemLink → .chipLink`). `ConnectionStylerResolutionTests`: `itemLinks: → chipLinks:`, chip attr asserts → `chipLink*`; **keep a chip-on variant** flipping `renderChipLinksAsChips = true` so chip-bounds coverage survives. `InlineSelectionDetectorTests`: `.itemLink → .chipLink` + func renames. `InputTransformCorpusTests`: `itemLinkAutoPair → chipLinkAutoPair`.
- [ ] **Step 8 — Verify + commit.** Builder Agent: `swift build` of MarkdownPM + `swift test` (renamed suites). Confirm non-zero executed count (quirk #1). The app target is NOT expected green yet (it still uses old slot names until P5) — verify the *package* only. Commit: `refactor(markdownpm): rename item-link framework to page-native chip-link + gate off`.

**Green gate:** MarkdownPM package builds + its renamed suites pass (non-zero count).

---

### Phase P1 — Collapse leaf item arms (no type deletions yet)

**Goal:** drop every item arm from kept files + delete pure-item leaf VIEW files, so P2's enum-spine removal hits a clean exhaustiveness gate. Item types/managers + enum cases still exist.

**Files & actions:**

- [ ] **Detail leaf deletes:** delete `Detail/ItemTypeDetailView.swift`, `Detail/ItemCollectionDetailView.swift`.
- [ ] **Sidebar strip (quirk #8):** delete `Sidebar/ItemTypeRow.swift`, `Sidebar/ItemCollectionRow.swift`; remove `struct ItemsSection` from `SidebarView.swift` (L510–573) + its List-body call (L45–51); drop `confirmationTitle/Message/Buttons` item arms (L115–140/218–235); drop `cascadeUnlinkTier` `itemContentManager.unlinkTier` (L246); L134 `"All Pages and Items inside" → "All Pages inside"`. The List now holds only homogeneous Sections (Saved/Spaces/Topics/Vaults) — do NOT introduce a flat-leaf/disclosure mix.
- [ ] **Detail seam-edits (collapse to `.page`/`.collection`):** `PageTypeDetailView.swift` + `PageCollectionDetailView.swift` (rows/contentKind/handleDoubleTap/handleDrop/menuItems/parent/propertyValue/commitRename item arms + the `presentItemAction` call + Phase-6 stub comments); `PropertyCellEditor.swift` (L7–8 doc + L374 `"Use the Item Window inspector…"` string → page-native); `DetailRowDragPayload.swift` L5 comment.
- [ ] **ViewSettings seam-edits (managers still exist → safe):** collapse the four duplicate `private enum SideKind { pages, items }` to page-only in `StorageMenuRoot`, `PropertiesListPane`, `PropertyVisibilityPane`, `PropertyTypePickerPane`, `EditPropertyPane`; drop their `@Environment(ItemTypeManager)` declarers; `ViewSettingsButton` drop the `itemTypeManager` stored param + fix the `ContentView` call site; `PropertyEditorErrorMessage` drop the `ItemTypeManagerError` branch (L22–24) + overload (L58–69) — **must land in the same green window as the `ItemTypeManager` delete (P3)** (removing the branch early is safe; leaving a cast against a deleted type breaks compile).
- [ ] **Properties:** delete `SchemaConflictDetector`/`SchemaConflictDialog` (dead — verify zero instantiations), delete `TypeSettingsSheet` (dead once `ItemTypeRow` gone); `ContextDisplayResolver` L45 drop `.item/.itemType/.itemCollection` icon arm; `PerTypeSchemaService`/`ContextValueEditor`/`ContextPicker`/`ContextChip`/`PropertyChip` doc-scrub; `MoveStripConfirmationDialog` — verify fan-in, delete if dead.
- [ ] **Index seam-edits (tables stay until P7):** `IndexUpdater` 6 item methods + `reconcile/activate/reactivate` ternaries → page-only; `IndexBuilder` item snapshot structs + `collect/insert` item funcs + `clearAllTables`/`insertTierContextLinks`/`insertConnections` item blocks.
- [ ] **Connections seam-edits (collapse `{{` to `[[`-only — decision #3):** `ConnectionScanner` **delete the `itemRegex` + its `.item` dict slot entirely** (no `{{` scanning); `ConnectionCascade` delete `.item` rewrite arm (`Item.load`); `ConnectionFileLocator` delete `.item` `locate`/`idMatches` arms; `AutoCompleteWiring` **delete the chip/`itemLink` arm** + `queryKind` collapse to `.page`; `AutoCompleteWindow` comment scrub. (The MarkdownPM chipLink render pipeline stays dormant per P0; it just gets no connection-layer trigger.)
- [ ] **NavDropdown seam-edits:** `NavDropdownButton` drop `openItemWindow` helper + `.item` arm; `BackForwardButtons` drop `case .item` + `lookupItem` helper + `presentItemAction` call; `EntityRow` drop `.item/.itemType/.set` icon+label arms; `RecentsManager` drop `.itemType/.set`; `NexusState` drop `itemTypeOrder` + `item_type_order` key.
- [ ] **CRITIC-ADDED — `Nexus/AdoptionPreviewView.swift` (production view, was missed):** drop `summaryStat itemTypeMigrationCount` + `labels.itemType.singular` (L107–108); the `itemTypeMigrations` ForEach (L281); `itemTypeMigrationCount` computed incl. `wrapperKind == .items` (L431–434); `.itemType/.itemCollection` icon arm (L457) + label arms (L467–468); L167 `"Pages/Items/Agenda" → "Pages/Agenda"`; L13 doc. It consumes `PropertyIDMigration.itemTypeMigrations` (P3) + `SettingsLabels.itemType` (P6) + `AdoptedSidecarKind.itemType` (P3) — **must drop in lockstep** or it compile-breaks.
- [ ] **Verify + commit.** Builder Agent green with item enum cases + types still defined. If the compiler couples P1↔P2 (an enum case can't survive with all arms gone), fold P1+P2 into one green checkpoint. Commit: `refactor(pages): drop item arms from shared call sites (pre-enum-gate)`.

**Green gate:** build green with item enums/types still defined.

---

### Phase P2 — Remove the enum spine (compiler exhaustiveness gate)

**Goal:** delete the item enum cases — the keystone that forces any missed seam to surface as a build error.

**Files & actions:**

- [ ] `IndexQuery.swift`: `EntityKind` (L658–661) drop `item/itemType/itemCollection`; `TargetRef` (L711–719) drop `itemType/itemCollection`; `resolveEntities` items SELECT block (L65–67); `entityContainer .item` case (L182–211); **drop the `kind` param entirely** from `resolveUniqueEntity`/`resolveUniqueTitle`/`resolvePageByIDOrTitle`/`titleExists`/`titleCandidates` (page-native simplification, L301/316/332/346/359); `kindTableMap` item keys (L97–108/390–406); `FilterBuilder.targetSQL`/`targetEntityKind` (L496–509); `entityKindToOwningTypeKind`/`entityKindFromString` (L611–632).
- [ ] `ConnectionTitle.swift`: **collapse `ConnectionSyntax` to page-only** — drop the second (`item`) case entirely (decision #3); if the enum becomes single-case, simplify call sites accordingly. `targetKind` returns `"page"`.
- [ ] `SidebarSelection.swift`: drop `case itemType/itemCollection` (L14–15) + `resolvedIcon` arms; `SidebarLookupBundle.itemType` field (L53) + every constructor arg; delete `resolveItemType`/`resolveItemCollection` (L115–128); `init?(stateRef:)` item arms (L144–146); `init?(tag:)` item arms (L169–170); `SelectionTag.itemType/.itemCollection` (L187–188) + `matches`/`init?` arms (L212–213).
- [ ] `SidebarConfirmation.swift`: drop `deleteItemType/deleteItemCollection` + id arms. `SidebarSheet.swift`: `IconTarget` drop `.itemType/.itemCollection/.item` + id arms. `IconPickerSheet.swift`: drop `.itemType/.itemCollection/.item` arms (currentIcon/save) + `@Environment(ItemTypeManager/ItemContentManager)` declarers.
- [ ] `DetailRow.swift`: `Kind` drop `.item/.itemCollection`; update `kindLabel` + `stateRef`. `DetailReorderPlanner.swift`: drop `.item/.itemCollection` from `Kind` + init arms.
- [ ] `SidebarDetailView.swift`: drop `.itemType/.itemCollection` switch arms; drop `@Environment(ItemTypeManager/ItemContentManager)`; delete the `.onAppear AppGlobals.presentItemAction` builder block (L130–152: `ItemLocationResolver`/`ItemRef`/`openWindow id:item-window`); KEEP `@Environment(\.openWindow)` (reused for page-preview in P5). **Quirk #10:** this single open-path call site is the coordination point with the parallel NSPanel session.
- [ ] `EntityStateRef.swift`: drop `Kind .item/.itemType/.set` + `init?(sidebarSelection:)` item arms (L56–57). Old `state.json` item kinds decode as `typedKind == nil` and skip (clean-slate safe).
- [ ] `ViewSettingsScope.swift`: drop `itemType/itemCollection` cases. `ViewSettingsRoute.swift`: drop `itemTemplate` case + `paneTitle` arm. `ViewSettingsPopover.swift`: drop item `rootContent` + `itemTemplate` destination arms. Delete `ViewSettings/ItemTemplatePane.swift` (now orphaned).
- [ ] `Validation/NexusContext.swift`: drop `lookupItemType` slot (L18) + `ItemType.find` resolver (L56) — KEEP the `@MainActor @escaping () -> NexusContext` snapshot-closure pattern for Pages (quirk #5). `NameCollisionValidator`: drop item branch. (Both resolve once `ItemType` is gone in P3 — same green window.)
- [ ] `Detail/ContentItem.swift`: **DELETE** (single-case dead weight; detail views already map page→page).
- [ ] **Verify + commit.** Builder Agent: first hard compiler gate. `xcodebuild test` must confirm the host app bootstraps (quirk #16) and the sidebar outline diffs without crashing (quirk #8). Commit: `refactor(pages): remove item enum spine (compiler gate green)`.

**Green gate:** build green with item enum cases gone; host app bootstraps; outline stable.

---

### Phase P4 — Relocate survivors + add `PageType.open_in`

**Goal:** move the three page-used types out of the doomed `Items/LayoutArchetype.swift` and add `open_in` to `PageType`, so the symbols exist when `Items/` is deleted in P3. (P4 lands inside the P3 window, before the `LayoutArchetype.swift` delete.)

**Files:** Create `Pommora/Pommora/Vaults/PageDisplay.swift`; modify `Pommora/Pommora/Vaults/PageType.swift`; delete `Pommora/Pommora/Vaults/PageTemplateConfig.swift`; verify `Pommora/Pommora/Detail/Columns/PropertyCellDisplay.swift`; modify `Pommora/Pommora/DesignSystem/PUI.swift`.

- [ ] **Step 1 — Create `Vaults/PageDisplay.swift`** with the relocated types (internal; doc-strings page-native):

```swift
// Page-native display config relocated from the deleted Items/LayoutArchetype.swift.
enum OpenInMode: String, Codable, Sendable, CaseIterable {
    case compact   // opens the page in the PagePreview window
    case window    // opens the page in the main detail pane (was .fullPage)
}

enum PropertyDisplay: String, Codable, Sendable { /* …relocated verbatim… */ }
enum DisplayTreatment: Sendable { /* …relocated verbatim… */ }

extension PropertyDisplay {
    func treatment(for /* …existing signature… */) -> DisplayTreatment { /* …relocated verbatim… */ }
}
```

  (Copy the real `PropertyDisplay`/`DisplayTreatment`/`treatment(for:)` bodies from `Items/LayoutArchetype.swift`; rename `OpenInMode` cases `.preview → .compact` (raw `"compact"`), `.fullPage`(raw `full_page`)`→ .window` (raw `"window"`).)
- [ ] **Step 2 — `PageType.swift`:** remove `templateConfig` prop (L34) + CodingKey `template_config` (L43) + its init/decode/encode; add:

```swift
var openIn: OpenInMode?
// in CodingKeys: case openIn = "open_in"
// decode:  openIn = try c.decodeIfPresent(OpenInMode.self, forKey: .openIn)
// encode:  try c.encodeIfPresent(openIn, forKey: .openIn)
```

  Fix the `ItemType`-parity doc-strings (L5/25/32) and `find(id:)` doc (L109–111, drop the `ItemTypeManager` ref).
- [ ] **Step 3 — Delete `Vaults/PageTemplateConfig.swift`** (held only `layout`/`defaultBody`/`openIn`; `open_in` now on `PageType`, the rest dropped — open-decision #1).
- [ ] **Step 4 — Delete from `Items/LayoutArchetype.swift`** (the file is deleted in P3, but confirm these have no other consumer now): `LayoutArchetype`, `PropertyLayoutMode`, `PromotedProperty`.
- [ ] **Step 5 — `DesignSystem/PUI.swift`:** delete `enum ItemWindow { width/height }` (L86–95) + its MARK header (dead once the scene goes in P5; `PagePreview` is resizable — do not revive under a renamed enum).
- [ ] **Step 6 — Verify + commit.** Builder Agent green: `PageType` decodes `open_in`; `PropertyCellDisplay` resolves `PropertyDisplay`/`DisplayTreatment` from `PageDisplay.swift`. Commit: `refactor(vaults): relocate page display types + add PageType.open_in`.

**Green gate:** build green; no `LayoutArchetype`/`PromotedProperty`/`PropertyLayoutMode` symbol survives outside the about-to-delete file.

---

### Phase P3 — Delete item type bodies, managers, migration, `NexusEnvironment` keystone

**Goal:** with no references left, delete the item types/managers/validators/migration and strip the `NexusEnvironment` keystone (quirk #15 lockstep).

**Files & actions:**

- [ ] **Delete `Items/`** entirely: `ItemType`, `ItemTypeManager`, `ItemContentManager`, `ItemContentManager+CRUD` (`ItemCRUDError`), `ItemCollection`, `ItemParent`, `TemplateResolver`, and `LayoutArchetype.swift` (after P4 relocated its survivors).
- [ ] **Delete `ItemWindow/`** (13 files): `FloatingItemPanel`, `ItemInspector`, `ItemWindowHost`, `ItemWindowLayouts`, `ItemWindowPanelManager`, `ItemWindowPresenter`, `ItemWindowRenderer`, `ItemWindowSceneRoot`, `ItemWindowViewModel`, `ItemWindowZoneConfig`, `MultiSelectChips`, `PropertyEditorRow`, `PropertyFieldBar`.
- [ ] **Delete `Content/`:** `Item.swift`, `ItemFrontmatter.swift`, `ItemRef.swift` (+ `ItemLocationResolver`), `KindStamp.swift`. **Seam-edit** `TierRelationCarrying.swift` (drop `ItemFrontmatter` conformance, keep Page). **Seam-edit** `PageFrontmatter.swift`: drop `KindStamp.decodeKind` + **stop writing `Class`** (foreign frontmatter still preserves any external `Class` by value).
- [ ] **Delete `Validation/`:** `ItemValidator`, `ItemTypeValidator`, `ItemCollectionValidator`. **Delete** `Connections/ItemLinkOpener.swift`.
- [ ] **`NexusEnvironment.swift` KEYSTONE STRIP (quirk #15):** remove stored props `itemTypeManager`/`itemContentManager`/`itemWindowPanelManager`/`itemConnectionResolver`; their construction/wiring/snapshot blocks; `AppGlobals.publish` item params; the `itemTypeMgr.loadAll` Task; the `.environment(...)` injects. Per open-decision #7, **reuse `pageConnectionResolver`** (drop the separate `itemConnectionResolver` slot). **Quirk #10:** `itemWindowPanelManager` served the floating window — coordinate removal with the parallel session; don't bundle its churn.
- [ ] **`ConnectionResolver.swift` (decision #7):** drop the `@Entry itemConnectionResolver` env key entirely; reuse `pageConnectionResolver` for `[[`. `PommoraConnectionResolver` is `kind: .page`-only (drop the `kind` param). **Rename** the resolver type/symbols to a page-native name (no `item`/`kind` framing) per no-trace.
- [ ] **Nexus migration deletes:** delete `ItemFormatMigration.swift`; `NexusManager.runFormatMigration` + `migratedItems` OR-fold + item-migration prose. `PropertyIDMigration.swift`: drop `itemTypeMigrations`/`scanItemType`/`applyItemType`/`enumerateItemMembers`/`.itemType` `TypeMigration` case/`itemTypesScanned` → PageType-only.
- [ ] **`NexusAdopter.swift` (heavy):** drop `AdoptedSidecarKind .itemType/.itemCollection`; `WrapperKind .items` + the `"Items"` name classification; delete `stampClassPass`/`stampOneFile`/`classifyClassStamp`/`ClassStampRead` + the autoTag call (Class dropped); delete `sweepStrayJSONItems`/`isStrayItemJSONCandidate` + its call; item sidecar writers; contentSniff doc simplify. Folder sidecar = sole kind authority.
- [ ] **`AtomicIO`:** `AtomicYAMLMarkdown` delete both `setStampKey` overloads + the `Yams.Node("Class")` write; `frontmatterScalar(at:forKey:)` — **re-grep**: delete if Class-classify was its only non-test caller, else keep generic (open item (b)). `NexusPaths` delete `itemTypeSidecarFilename`/`itemCollectionSidecarFilename` + the 5 item path helpers + L205 Class comment. `Filesystem.swift`/`Nexus.swift` doc-scrub.
- [ ] **`Ordering/OrderPersister.swift`:** delete `setItemTypeOrder`/`setItemCollectionOrder`/`setItemOrder`(×2)/`mutateItemType`/`mutateItemCollection`.
- [ ] **Verify + commit.** Builder Agent: `grep` confirms NO surviving `@Environment(ItemTypeManager/ItemContentManager)` declarer AND env props gone (first selection must not SIGTRAP — quirk #15); host app bootstraps (quirk #16). Commit: `refactor(pages): delete item types/managers/migration; strip NexusEnvironment keystone`.

**Green gate:** build + test green; no item managers, no `Class` write, no SIGTRAP on first selection.

---

### Phase P7 — SQLite schema v11 (delete-and-rebuild, no migration)

**Goal:** drop the item DDL so the index is page-only; bump the version so existing DBs delete-and-rebuild on open.

**Files:** `Index/IndexSchema.swift`, `Index/PommoraIndex.swift`.

- [ ] `IndexSchema.swift`: delete `itemTypesDDL`/`itemCollectionsDDL`/`itemsDDL` constants + their `apply()` calls; delete item index lines (`idx_items_*`, `idx_item_collections_*`); fix connections DDL comments (`'page'|'item'` → page-only; `surface → 'page_body'`).
- [ ] `PommoraIndex.swift`: bump `currentSchemaVersion 10 → 11` (L85) with a doc note (item tables dropped; connections/context_links item rows orphaned; existing DBs delete+recreate page-only). No logic change to `open(at:)`.
- [ ] Connections table keeps its columns but page-only (`source_kind`/`target_kind` always `"page"`, `surface "page_body"`).
- [ ] **Verify + commit.** Builder Agent: fresh DB builds page-only; an existing v10 DB deletes+rebuilds on open. Commit: `refactor(index): schema v11 — drop item tables (delete-and-rebuild)`.

**Green gate:** build + test green; index test target compiles (item-table asserts removed in P8 — if P8 hasn't run, expect test-target breaks here and sequence P7 immediately before/with P8).

---

### Phase P5 — Re-home chip-link app-side + build `PagePreview`

**Goal:** point the app's `{{ }}` path at the renamed MarkdownPM slots, delete the Item Window scene + `AppGlobals` bridge + auto-open scaffold, and build the new `PagePreview` surface + open-routing + the open-in toggle.

**Depends on:** P0 (renamed slots), P3 (item types gone), P4 (`OpenInMode` relocated).

**Files:** `Pages/MarkdownEditorConfig.swift`, `Pages/PageEditorView.swift`, `Pages/AppGlobals.swift`, `ContentView.swift`, `PommoraApp.swift`, create `Window/PagePreviewScene.swift`, delete `Window/PreviewWindow.swift`, `Vaults/PageType.swift` (+`PageTypeManager`), `Detail/PageTypeDetailView.swift`, `ViewSettings/StorageMenuRoot.swift`, `Sidebar/` page-row tap site, `ComponentLibrary/ComponentLibraryView.swift`.

- [ ] **Step 1 — Editor config + view re-home.** `MarkdownEditorConfig.swift`: **drop the `itemResolver` param** (L33) — `config.services.chipLinks` stays at its NoOp default, so `{{` renders inert (decision #3, no app trigger). `PageEditorView.swift`: delete the `onItemLinkClick:` closure (L277–288, `ItemLinkOpener`/`presentItemAction`); drop `@Environment(\.itemConnectionResolver)` (L45) — reuse the renamed page resolver (decision #7); drop the L462 resolver arg. KEEP the `[[ ]]` `onLinkClick` path (L263–276) as the sole page link path. No `onChipLinkClick` wired (decision #4).
- [ ] **Step 2 — `AppGlobals.swift`:** delete `itemContentManager`/`itemTypeManager` statics (L23/25); the Item Window bridge block (L63–77: `itemWindow`, `presentItemAction`); `publish(...)` item params (L43–55). Coordinate the `publish` signature with `NexusEnvironment.init` in one commit.
- [ ] **Step 3 — `ContentView.swift`:** delete the `#if DEBUG -autoOpenItemWindow` `.task` block (L223–255); the `env.itemTypeManager/itemContentManager` reads in `primaryActionCapsule` (L94/100/108) + the inspector toolbar `SidebarLookupBundle` (L179).
- [ ] **Step 4 — `PommoraApp.swift`:** delete `UtilityWindow("Item", id: "item-window")` (L61–74). Add the page-preview scene (quirk #10: single owner; if the parallel session already converted the scene, replace whatever form exists):

```swift
WindowGroup(id: "page-preview", for: PageRef.self) { $ref in
    PagePreviewScene(ref: ref).environment(nexusManager)
}
.defaultSize(width: 480, height: 640)
.windowResizability(.contentMinSize)
```

- [ ] **Step 5 — Create `Window/PagePreviewScene.swift`** (from build_specs):

```swift
struct PagePreviewScene: View {
    let ref: PageRef?
    @Environment(PageTypeManager.self) private var vaultManager
    @Environment(PageContentManager.self) private var contentManager
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var page: PageMeta?
    @State private var vault: PageType?
    @State private var body: String = ""

    var body: some View {
        Group {
            if let page, let vault {
                MarkdownPMEditor(
                    text: .constant(body),
                    configuration: .pommora(verticalInset: 0),
                    fontName: "SF Pro Text", fontSize: 15,
                    documentId: page.id, isEditable: false
                )
                .inspector(isPresented: .constant(true)) {
                    FrontmatterInspector(page: page, vault: vault,
                        index: contentManager.indexUpdater?.index,
                        relationDisplay: /* ContextDisplayResolver from env */,
                        onSave: nil)
                }
                .toolbar {
                    Button { MainWindowRouter.requestOpen(to: .page(page)); dismissWindow() }
                        label: { Label("Open", systemImage: "lock.open") }
                }
            } else { ProgressView() }
        }
        .task(id: ref) {
            guard let ref else { return }
            let r = ref.resolve(vaultManager: vaultManager, contentManager: contentManager)
            page = r?.page; vault = r?.vault
            if let page { body = (try? PageFile.loadLenient(from: page.url, nexusRoot: contentManager.nexus.rootURL))?.body ?? "" }
        }
    }
}
```

  (`isEditable: false` is a real `NativeTextViewWrapper` param; `FrontmatterInspector` tolerates `onSave: nil`. Apply the quirk-#16 XCTest guard if any launch-time restoration touches permissions.)
- [ ] **Step 6 — Delete `Window/PreviewWindow.swift`** (zero live consumers; `PagePreview` does not reuse it).
- [ ] **Step 7 — `PageType.open_in` persistence + toggle.** Add to `PageTypeManager`:

```swift
func setOpenIn(_ mode: OpenInMode, forVault typeID: String) async throws {
    guard let i = types.firstIndex(where: { $0.id == typeID }) else { return }
    var updated = types[i]
    updated.openIn = mode
    updated.modifiedAt = Date()
    try updated.save(to: NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus))
    types[i] = updated
    // no SQLite upsert — open_in is not indexed
}
```

  In `StorageMenuRoot.swift` (decision #2): collapse `SideKind` to page-only + strip remaining item arms, then add — **at the bottom of the main settings pane, above a `Divider`** (Design.md padding discipline) — a `Layout:` segmented control:

```swift
Divider()
Picker("Layout", selection: Binding(
    get: { liveVault.openIn ?? .window },
    set: { mode in Task { try? await pageTypeManager.setOpenIn(mode, forVault: liveVault.id) } }
)) {
    Text("Compact").tag(OpenInMode.compact)
    Text("Window").tag(OpenInMode.window)
}
.pickerStyle(.segmented)
// padding per Design.md
```

  Vault-scoped (shown for a vault's settings). Labels `"Compact"`/`"Window"` are structural, NOT user-renameable. **No duplicate toggle in `PageTypeDetailView`** (decision #2 — single location).
- [ ] **Step 8 — Open-routing branch** at the sidebar page-row tap (where `selection = .page(p)` is set):

```swift
switch vault.openIn ?? .window {
case .window:  selection = .page(p)                                   // in-pane (existing render)
case .compact: openWindow(id: "page-preview", value: PageRef(/* page:in:vault: */))
}
```

  `SidebarDetailView`'s `.page` case stays the `.window` render.
- [ ] **Step 9 — `ComponentLibraryView.swift`:** delete `ItemChipShowcase` + the "Item Chip" gallery section (re-add under the page-native chip name or drop); delete the "Item Window" `WindowLaunchRow` + `WindowStubSheet` + `showingItemWindow`; rewrite the "Page Preview" row prose + rewire to `openWindow(id: "page-preview")`. (Also rename `Properties/Chips/ItemChip.swift` View to match the MarkdownPM chip-link family name — open item (e).)
- [ ] **Step 10 — Verify + commit.** Builder Agent green. Manual smoke (note for executor): a `.compact` vault page-tap opens `PagePreview`; the "Open" button routes to the detail pane + dismisses; a `.window` vault renders in-pane. `grep` confirms no `"item-window"` literal survives. Commit: `feat(pages): PagePreview window + vault open-in toggle; remove Item Window scene`.

**Green gate:** build + test green; open-in routing works both ways; no `item-window` scene id.

---

### Phase P6 — Strip item vocabulary from Settings + peripheral docs (alongside P5)

**Files:** `Settings/SettingsLabels.swift`, `Settings/Settings.swift`, `Agenda/AgendaTaskManager.swift` + `AgendaEventManager.swift`, `Properties/Chips/*`, `Properties/PinnedManager.swift`.

- [ ] `SettingsLabels.swift`: remove `itemType`/`itemCollection` `LabelPair` (L7–8) + CodingKeys `item_type`/`item_collection` (L17–18) + default seeds (L29–30). `SidebarSectionLabels`: remove `var items` (L48) + CodingKey + init param/assignment + the custom `init(from:)` `items` decode (L83) + default `items: "Items"` (L60); keep `pages` required.
- [ ] `Settings.swift`: delete the v1→v2 migrate block rewriting `sidebarSections.items "Types"→"Items"` (L131–139); keep the version scaffold + later steps.
- [ ] Agenda doc-comments (DRY across both manager files): `ItemCRUDError.duplicateTitle → PageCRUDError`; `"Pages, Items, and Agenda" → "Pages and Agenda"`; drop the `"Items) there is no container"` parenthetical.
- [ ] `ContextChip`/`PropertyChip` doc-scrub (Item Window → `FrontmatterInspector`/`PagePreview`); `PinnedManager` doc `'"page"/"item"' → '"page"'`.
- [ ] **Verify + commit.** Builder Agent green; add the `SettingsLabels` decode-tolerance test in P8 (a legacy `settings.json` with `item_type`/`item_collection` keys still loads). Commit: `refactor(settings): drop item labels + migration (decode-tolerant)`.

---

### Phase P8 — Test surgery (after P3/P7)

**Goal:** delete pure-item suites, relocate the two mis-filed page tests, seam-edit the ~25 mixed suites the critic flagged, and add new coverage. Honor quirk #1 (run by real `@Suite`/type token; verify non-zero counts).

- [ ] **Delete pure-item suites in `PommoraTests/Items/`** (real type tokens; note suite-string≠type for `ItemCollectionFile`/`ItemTypeFile`/`ParentItemTypeLookup`): `ClearTemplateConfigTests`, `ItemCollectionPinningTests`, `ItemCollectionTests`, `ItemContentManagerTests`, `ItemMarkdownTransitionTests`, `ItemReorderPersistenceTests`, `ItemTemplateConfigTests`, `ItemTypeManagerSchemaCRUDTests`, `ItemTypeManagerTests`, `ItemTypeSingularCodableTests`, `ItemTypeTests`, `ItemValidatorCapTests`, `ItemWindow{Layouts,Partition,Reorder,ViewModel,ZoneConfig}Tests`, `LayoutArchetypeTests`, `MoveItemTests`, `ParentItemTypeLookupTests`, `PromotedEntriesTests`, `PromotedForFieldTests`, `PromotedPropertyTests`, `RenameItemReturnTests`, `TemplateResolverTests`, `UpdateTemplateConfigTests`.
- [ ] **Relocate out of `Items/`:** `PropertyEditorRowTests.swift → PommoraTests/Properties/` (no item dep — mis-filed). Seam-edit + relocate `CollectionTemplateConfigTests.swift → Vaults/` (strip the 4 item tests; reconcile the 2 page tests against post-strip `PageCollection`/`PageType` — gated by open-decision #1; if `PageCollection.template_config` is dropped, delete those 2).
- [ ] **Delete pure-item suites outside `Items/`:** `Content/ItemFileTests`, `Content/ItemRefTests`, `Content/KindStampTests`, `Detail/ItemTypeDetailViewTests`, `Detail/ItemCollectionDetailViewTests`, `Validation/ItemValidatorTests`, `Connections/ItemLinkNavigationTests`, `Nexus/ClassStampPassTests`, `Nexus/ItemFormatMigrationTests`, `Sidebar/Sheets/NewItemSheetTests`, `ViewSettings/ItemTemplateRouteTests`, `ViewSettings/ArchetypePickerTests`, `ViewSettings/TemplateEditorTests`, `Properties/TypeSettingsSheetTests`, `Vaults/PageTemplateConfigTests`.
- [ ] **Seam-edit the critic-flagged mixed suites** (drop item arms, keep page coverage): `Index/{IndexUpdaterTests,IndexBuilderTests,IndexQueryTests,ConnectionQueryTests,TierRelationsEmitTests,IndexParentUpsertCascadeTests,CollectionIconSetterTests,CollectionIconTests,PommoraIndexTests}`; `Connections/{ConnectionCascadeTests,ConnectionLiveRefreshTests,ConnectionScannerTests(.item→.chip),ConnectionConfigWiringTests,ConnectionResolverTests,AutoCompleteWiringTests}`; `Nexus/{AutoTagOrphanCleanupTests,DefaultViewMigrationTests,LoadAllIndexSyncTests(keep page-side quirk #14, drop item-side),PropertyIDMigrationTests,NexusAdopterAutoTagTests,NexusManagerLaunchIntegrationTests,IndexUpdaterWiringTests,NexusManagerIndexTests,NexusAdopterTests,ContentSniffTests}`; `AtomicIO/NexusPathsTests` (drop `itemTypeSidecarFilename` asserts L42–43/266); `Vaults/{CollectionTypeIDReconcileTests,ResolvedPropertiesTests,SidecarVersionTests,PageCollectionViewsTests,ManagerErrorMessageTests(drop ItemTypeManagerError),MemberFileStripResilienceTests}`; `Content/{NexusWideUniquenessTests,RelationCommitRoutingTests,UnlinkTierTests(drop item MARK),PageItemIconSetterTests(drop 2 item tests + RENAME file/suite/struct → PageIconSetterTests)}`; `Properties/{ReorderPropertyParityTests,DefaultSortConfigTests}`; `CRUD/ManagerCreateReturnContractTests`; `Detail/DetailReorderPlannerTests`; `Validation/NameCollisionTests` (drop item arm if present); `NavDropdown/RecentsManagerTests` (rewrite `.item/.itemType` records → `.page/.pageType`); `Settings/{SettingsTests,SettingsManagerTests,UILabelThreadingTests}`; `ViewSettings/ViewSettingsScopeMappingTests` (drop 2 item-scope tests).
- [ ] **Support:** delete `Support/TempNexus+Items.swift` after porting `UnlinkTierTests` off `itemTypeRoot`; KEEP `Support/TempNexus.swift` (115 consumers). Remove the now-empty `PommoraTests/Items/` folder.
- [ ] **VERIFY-SAFE (do not touch — only generic `removeItem`/cosmetic tokens):** `AppStateTests`, `DisplayAsDefaultTests`, `FilesystemTrashTests`, `DetailRowDragPayloadTests`, `AttachmentCascadeTests` (confirm only `FileManager.*Item`).
- [ ] **Add new coverage** (TDD — write failing first):
  - `PommoraTests/Vaults/PageOpenInTests.swift` — `PageType.open_in` round-trips through Codable + defaults to `nil` (treated as `.window`).
  - `PommoraTests/Settings/SettingsLabelsDecodeToleranceTests.swift` — a `settings.json` carrying legacy `item_type`/`item_collection`/`items` keys still decodes.
  - `PommoraTests/ViewSettings/OpenInToggleTests.swift` — the Compact/Window leaf writes `setOpenIn` (replaces `ItemTemplateRouteTests`).
  - `PommoraTests/Pages/PagePreviewRoutingTests.swift` — vault `open_in == .compact` routes to the page-preview window value; `== .window` sets `.page` selection.
- [ ] **Verify + commit.** Builder Agent: `xcodebuild test` green; `PommoraTests` compiles with zero item-domain references; each renamed suite run by its real token shows a non-zero executed count (quirk #1). Commit: `test(pages): strip item suites, seam-edit mixed, add open-in/PagePreview coverage`.

**Green gate:** full test target green; zero item references; new suites execute non-zero.

---

### Phase P9 — Band 3: user sidebar sections (last build)

**Goal:** persisted user-creatable sidebar sections grouping Vaults — navigation-only, no on-disk vault move. Reuse the `SavedConfig` manager pattern verbatim.

**Files:** create `Configuration/SidebarSectionsConfig.swift` + `Configuration/SidebarSectionsManager.swift`; modify `AtomicIO/NexusPaths.swift`, `Nexus/NexusEnvironment.swift`, `Sidebar/SidebarView.swift`, `Sidebar/PageTypeRow.swift` context menu.

- [ ] **Step 1 — Config + manager** (mirror `SavedConfig`/`SavedConfigManager` verbatim):

```swift
struct SidebarSectionsConfig: Codable, Sendable {
    struct Section: Codable, Sendable, Identifiable { let id: String; var label: String; var vaultIDs: [String] }
    var sections: [Section] = []
}
```

  `SidebarSectionsManager` mirroring `SavedConfigManager.swift` — `init(nexus:)`, `load()` via `AtomicJSON.decode` with `defaultSeed` + first-write, `save()` via `AtomicJSON.write`, `@Observable pendingError`. Add `NexusPaths.sidebarSectionsURL(in:) -> .nexus/sidebar-sections.json`. (Quirk #16: guard `load()` if it touches permissions at launch.)
- [ ] **Step 2 — Register on `NexusEnvironment`** (quirk #15): one stored property + one `.environment(...)` line in `.injectNexusEnvironment(_:)`.
- [ ] **Step 3 — Render** (quirk #8 — homogeneous rows only): each user section a sibling `Section(isExpanded:) { ForEach(vaultIDs → PageType) { PageTypeRow(...) } } header: { SectionHeader(...) }` — identical shape to `VaultsSection`, reusing `PageTypeRow(pageType:selection:editingID:justCreatedID:presentedSheet:confirmingDelete:nexus:index:)`. **Empty sections render NOTHING** (never a leaf placeholder mixed with disclosure rows).
- [ ] **Step 4 — Affordances:** "Add Section" `Button` in the Vaults `SectionHeader .contextMenu`; "Move to Section" `Button` in `PageTypeRow .contextMenu` writing the `vaultID` into the chosen section (single-membership — open-decision #6); inline-rename via the existing `CreateWithInlineEdit.run` + `DefaultTitleResolver`.
- [ ] **Step 5 — Verify + commit.** Builder Agent: `xcodebuild test` confirms the outline bootstraps (quirk #8) with a user section present + an empty one. Commit: `feat(sidebar): user-creatable sections grouping vaults`.

**Green gate:** build + test green; outline stable with populated + empty user sections.

---

### Phase P10 — No-trace doc sweep + plan archival

**Goal:** docs read as if Pages were always the only operational entity beside Agenda; ItemsV2 plans archived; the active-branch quirks updated.

- [ ] **Delete `.claude/Features/Items.md`;** repoint or remove every `[[Items]]` wikilink (Domain-Model, Connections, Prospects, Architecture, Properties, History) → `[[Pages]]` or drop.
- [ ] **Heavy one-entity rewrites:** `Domain-Model.md`, `Architecture.md` (table count 11→8; schema v11 delete-and-rebuild; drop Class stamp + `_itemtype`/`_itemcollection` + `ItemTypeManager`/`ItemContentManager` rows), `PommoraPRD.md` (drop item DDL + recount; one operational entity; drop Item Window/Class/`{{` item product vocab), `Connections.md` (`[[` sole page-link path; `{{` re-homed page-native chip-link gated off; drop Item Chip/Item Window), `Properties.md` (drop Item Type Settings + `_itemtype` schema-carrier; pinned_properties → Prospect), `Sidebar.md` (drop Items section; recast shape; band-3 note; rewrite the quirk-#8 mirror clause), `NavDropdown.md`.
- [ ] **Seam-edit docs:** `Prospects.md` (delete Item Templates + legacy-Item-JSON-migration; reframe Item↔Page promotion; keep the pinned-property prospect item-free), `QuickCapture.md` (retarget capture to Page), `PageTypes.md` (document `open_in`; drop ItemType symmetry + `PageTemplateConfig`), `Pages.md` (document the open-in model + `PagePreview`), `Agenda.md`.
- [ ] **Guidelines:** `Symbols.md`, `CRUD-Patterns.md` (rewrite the PreviewWindow rule → `PagePreview`; drop the `ItemContentManager` arm), `Markdown.md`, `Paradigm-Decisions.md` (**append** a superseding entry + mark #14/#15 superseded inline — open-decision #5; do not falsify chronology).
- [ ] **`History.md`:** add a top collapse entry (survivor=Page; Item* deleted; Class dropped; `[[` declassed; `{{` re-homed gated-off; `PageType.open_in`; `PagePreview` built / `PreviewWindow` eliminated; schema v10→v11; no migration); cross-note prior ItemsV2 entries as superseded.
- [ ] **`Framework.md`:** drop Items-side roadmap rows; replace the "Item UIX — Item Window" slot with `PagePreview` + open-in + band-3 work.
- [ ] **`CLAUDE.md` (heavy):** one-entity rewrite (drop the Items operational layer, the symmetric-code paragraph, the Vault/Collection vs Type/Set divergence, the Class-stamp clause, the Item Window bullet → detail-pane vs `PagePreview`). Quirks: #8 → post-strip homogeneous-sections rule; #14 drop `ItemTypeManager.loadAll`; #15 drop the `ItemTypeManager/ItemContentManager` example; #5 drop `ItemContentManager`. Update the Document Map (Items.md deleted).
- [ ] **Archival:** create `.claude/Planning/Superseded/`; relocate `06-07-ItemsV2-Plan-V3.md`, `06-07-ItemsV2-Spec-V5.md`, `06-03-ItemsV2-Implemented.md` into it (quirk #10: `06-07-ItemsV2-Plan-V3.md` shows modified in the working tree — surface, coordinate, don't bundle). `Planning/README.md`: move ItemsV2 entries to a Superseded subsection; fix the false "MarkdownPM untouched" line.
- [ ] **Low-severity residue** (kept page code): scrub stale `ItemType`/`_itemtype` doc-comments in `Vaults/PageCollection.swift` L4, `PropertyDefinition.swift` L3–4/128/166, `SavedView.swift` L4–5, `BuiltInContextLinkProperties.swift` L33.
- [ ] **Verify + commit.** Repo-wide `grep -rniE '\bitem'` across `.claude/` returns only legitimate append-only history entries (marked superseded) + generic `item`. Commit: `docs: no-trace sweep — one-entity model; archive ItemsV2 plans`.

**Green gate (no-trace, final):** the grep verification in `no_trace_verification` passes — production source, on-disk schema, MarkdownPM, tests, and docs all item-free except the enumerated generic survivors (`FileManager.*Item`, `NSMenuItem`, `GridItem`, `SavedConfig.Item`, loop vars) and append-only history.

---

### Self-review notes

- **Spec coverage:** every spec section maps to a phase — strip (P1–P3, P7, P8), `[[` declass + `{{` rename (P0, P2, P5), `Class` drop (P3), `PagePreview` + open-in + unlock→open (P4, P5), band-3 (P9), QuickCapture (spec-only, P10 doc), closeout (P8 tests, P10 docs). No pinned-property tasks (correctly absent — Prospect).
- **Critic gaps folded in:** `AdoptionPreviewView` (P1) + the ~25 under-mapped test files (P8 seam-edit list).
- **Type consistency:** `OpenInMode { .compact, .window }`, `chipLink*` family names, `setOpenIn(_:forVault:)`, `PagePreviewScene`, `SidebarSectionsConfig` used consistently across P0/P4/P5/P8/P9.
- **Open decisions** (7) carry recommendations; the write→stress-test→revise loop ratifies them.
