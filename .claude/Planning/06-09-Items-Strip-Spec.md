## Items Strip — Implementation Spec

Strip the Items subsystem from Pommora entirely. Everything operational becomes a **Page**. "Item-ness" (a windowed surface + pinned properties) is reframed as per-vault settings on Pages. Grounded by a 8-agent mapping fleet against `graphify-out` + live sources; this spec is the authority for the implementation plan that follows. Decision record: `// Planning//06-09-Items-Pages-Collapse-Evaluation.md`.

### Goal

Delete all `Item*` code, mirrored machinery, item index tables, and item rendering coupling; collapse every `item|page` shared seam to page-only. Pages are left as-is (working code is not rewritten). The plan ends with a clean, green, Items-free codebase plus a new `PagePreview` window (Figma design received 2026-06-09; captured in the plan's P5) and a vault-level Compact/Window open-in toggle. Pinned properties are explicitly out — recorded as a Prospect.

**Guiding principle — no trace.** The end state must read as though Items never existed and Pages were always the only operational entity: no item-named code, no dormant item-named frameworks, no `item` enum cases, no stale `item` comments. Where a capability is retained (e.g. the `{{` chip), it is **renamed to an item-free, page-native form** — kept, not parked under its old item identity. This is stricter than "delete Items"; it governs every classification below.

### Locked decisions

- **Survivor:** the **Page**. `PageType` / `PageCollection` / Page kept as-is. `Item` / `ItemType` / `ItemCollection` / "Type" / "Set" deleted. ("Set" parked as a *future* sub-collection folder name — not built.)
- **Clean slate:** no data migration. Existing item-type folders simply stop loading; any stale `Class:` on disk sits inert (foreign frontmatter, preserved by value).
- **`Class` stamp:** dropped entirely. `PageFrontmatter` stops writing it; `KindStamp` + the `NexusAdopter` `Class`-stamp self-heal pass delete. Folder sidecar is sole kind authority.
- **`[[` wikilinks:** kept, **declassed** — one resolution path, page-only (the package never branched on kind; the `kind: .item` resolver is removed app-side).
- **`{{` chip syntax + `ItemChip`:** the *capability* is retained but **re-homed under item-free naming** (no-trace) — the second link type, its service slot, styler, and chip renderer rename from `item*` to a generic page-native chip-link form, gated OFF by default (links-only). **MarkdownPM IS edited:** the parallel page-vs-item link framework is item-named tech debt and must not survive as-is.
- **`PagePreview`:** the new surface — a `WindowGroup` + `.inspector` reusing the existing page render + `FrontmatterInspector` **verbatim**, built **and wired** to the **Figma design (received 2026-06-09):** 475×475 Liquid-Glass panel, inline-editable `.title3` title/icon, lock-gated editing, "Open Page"/"Lock-Unlock" via right-click context menu. **`PreviewWindow` is eliminated** (its only consumer was the Item Window).
- **Open-in (`OpenInMode` = `.compact` | `.window`):** **vault-level only** (on `PageType`), never overridden per-collection. `.window` = today's main detail-pane behavior; `.compact` = opens `PagePreview`. This is the **only** new per-vault setting.
- **Lock + open model:** `PagePreview` opens **locked (read-only)**; the bottom-right **Lock** toggles editability (unlock → fully editable + live-saving). **"Open Page"** (route to the main detail pane) and **"Lock / Unlock"** are **right-click context-menu** commands on the body + title areas — no open toolbar button. The inspector toggle is independent of the lock.
- **No pinned-property / Page-Layout config.** There is no `PageLayoutConfig`, no pinned-property schema, no per-collection layout override. A default-open inspector gives the same effect. The pinned-property idea is recorded in `// Features//Prospects.md` and is not built or inherited.
- **QuickCapture:** retargeted to create a Page (spec-only today — no code exists).
- **Band 3:** persisted user-creatable sidebar sections ("Add Section"). Lowest priority, built last.

### Scope

- **In:** the full strip; `[[` declass; `{{`/`ItemChip` park; QuickCapture spec retarget; the vault-level open-in (`Compact`/`Window`) setting + toggle UI; `PagePreview` built + wired to the Figma design (lock-gated edit, context-menu open); eliminate `PreviewWindow`; band-3 sidebar sections; closeout (tests, cleanup, doc-sweep).
- **Removed (not built, not inherited):** pinned-property schema, its editor, and the in-`PagePreview` zone — recorded as a Prospect (`// Features//Prospects.md`). A default-open inspector covers the use case.
- **Figma design received (2026-06-09):** `PagePreview`'s chrome is specified (475×475 Liquid-Glass, inline title/icon, inset header separator with end-affordance, footnote/secondary breadcrumb, `.quaternaryLabel` 3-context menufield + properties menufield, window-dismiss control) and captured in the plan's P5. No longer gated.

### The strip surface (by domain)

The plan enumerates exact files/symbols/LOC from the agent maps; this is the domain-level shape. ACTIONS: **DELETE / SEAM-EDIT** (remove the item arm) / **PARK** (keep, decouple, gate off) / **DECLASS** / **RELOCATE** / **BUILD**.

#### Core types + shared seams

- DELETE: `Items/` (all), `Content/Item.swift` / `ItemFrontmatter.swift` / `ItemRef.swift`, item validators, `Detail/ItemTypeDetailView` / `ItemCollectionDetailView`, `Sidebar/ItemTypeRow` / `ItemCollectionRow`, `ViewSettings/ItemTemplatePane`, `Nexus/ItemFormatMigration`, `Connections/ItemLinkOpener`, `Content/KindStamp`.
- SEAM-EDIT (lose item arm): `EntityKind` (`.item/.itemType/.itemCollection`), `Detail/ContentItem` (collapses to a `.page` wrapper → fold to `PageMeta`), `SidebarSelection` / `SelectionTag`, `Pages/AppGlobals` (item bridge + `presentItemAction`), `Nexus/NexusEnvironment` (item managers — **quirk #15:** every `@Environment(ItemTypeManager/ItemContentManager)` declarer must drop in the same commit or views SIGTRAP), `ViewSettings/*` panes (the **five** duplicate `SideKind` enums are **deleted**, not collapsed — single-case after the strip), `NavDropdown/*`, `Ordering/OrderPersister`, `AtomicIO/NexusPaths`, `Nexus/NexusAdopter` (sidecar kinds + `Class` pass), `Settings/SettingsLabels` (drop `itemType`/`itemCollection`/`items` with `decodeIfPresent` tolerance).
- **The compiler is the discovery gate:** remove the `EntityKind`/`SidebarSelection`/`SelectionTag` cases last — every non-exhaustive `switch` then flags a missed seam.

#### NexusIndex / SQLite

- DROP tables `item_types` / `item_collections` / `items` + their 4 indexes; delete 6 `IndexUpdater` item methods + `IndexBuilder` item snapshot/insert paths; collapse `IndexQuery` `kind == .page ? "pages" : "items"` ternaries to `"pages"`. No FK points *at* item tables, so nothing structurally breaks.
- Bump `PommoraIndex.currentSchemaVersion` 10→11 (delete-and-rebuild on launch; no migration). Orphan item folders are simply not walked — no SQLite error.
- `PageTypeManager.loadAll` is independent of the item path (**quirk #14** stays satisfied).

#### MarkdownPM + connections

- **MarkdownPM IS edited (no-trace).** It functions without `Item` types, but it carries a *parallel page-vs-item link framework* whose names are item tech debt: `.itemLink` token + `.itemLinkTitle`/`.itemChipIcon` attrs, `itemLinkRegex`, `styleItemLinks`, `ItemChipMetrics`, `drawItemChips`/`itemChipRects`, the `services.itemLinks` slot, `onItemLinkClick` plumbing, `InlineSelectionKind.itemLink`. Under no-trace these **rename to a generic page-native chip-link form** (capability kept, gated off) — or are removed where redundant. The PagesV2 review determines the cleanest collapse.
- `[[` declass: drop the app-side `kind: .item` resolver; resolve pages directly (the package never branched on kind).
- App-side deletions: `Connections/ItemLinkOpener`, `PageEditorView.onItemLinkClick`, `AppGlobals.presentItemAction`, the `item` resolver construction.
- Connections SEAM-EDIT: `ConnectionScanner`/`ConnectionSyntax`/`ConnectionCascade`/`ConnectionFileLocator`/`AutoCompleteWiring` → page-only. Dangling `{{` targets degrade gracefully (lenient resolver → inert text).
- `PagePreview` reuses the existing page render path (`MarkdownPMEditor` + `MarkdownEditorConfig.pommora(verticalInset: 0)`, `isEditable: !isLocked` — opens locked, body via `PageFile.loadLenient`).

#### Sidebar

- Remove the whole `ItemsSection` (a self-contained sibling `Section`) + its rows. **Crash-safe** because it doesn't create a flat/disclosure mix in surviving sections (**quirk #8**); `VaultsSection` is untouched. Verify via `xcodebuild test` actually bootstrapping (**quirk #16**), not just compiling.

#### Wave-2 / overlooked (the thoroughness catches — do NOT delete by folder)

- **Transitive-dead, not item-named:** `Properties/TypeSettingsSheet.swift` (sole caller is deleted `ItemTypeRow`), `Validation/NexusContext.lookupItemType` (already zero fan-in), `DesignSystem/PUI.ItemWindow` size constants, the `NexusAdopter` `Class`-stamp pass.
- **RELOCATE, do not delete** (used by kept page code): `OpenInMode` (cases renamed `compact`/`window`), `PropertyDisplay`, `DisplayTreatment` move to a Pages file before `Items/LayoutArchetype.swift` deletes. `LayoutArchetype` / `PromotedProperty` / `PropertyLayoutMode` / `TemplateResolver` **delete**; `PageTemplateConfig` **deletes** — its only live field (`open_in`) moves to a direct `PageType.open_in`.
- **Test-folder landmine:** `PommoraTests/Items/CollectionTemplateConfigTests.swift` carries live PageCollection coverage — must NOT be removed with a blanket `Items/` delete. Honor **quirk #1** (filter matches the `@Suite`/type name, not the filename; verify non-zero executed counts).

### The build

#### Open-in setting (the only new per-vault setting)

- Add `open_in: OpenInMode?` (`.compact` / `.window`) **directly to `PageType`** (vault-level; no collection override). `OpenInMode` relocates out of the doomed `Items/LayoutArchetype.swift` (cases renamed `compact`/`window`). **Delete `PageTemplateConfig`** — it held only `open_in` + the unused `layout`; no new config object is introduced.
- Repurpose the surviving settings-leaf location (delete `ItemTemplatePane`; retarget the route) to host a **Compact / Window** toggle writing `PageType.open_in`.

#### `PagePreview` surface (plain stub, built + wired)

- A `WindowGroup` + `.inspector` hosting the existing page render path: `MarkdownPMEditor` with `MarkdownEditorConfig.pommora(verticalInset: 0)` (the `itemResolver` param is dropped; `services.chipLinks` stays NoOp), `isEditable: !isLocked` (opens locked), body via the same `PageFile.loadLenient` path; inspector = `FrontmatterInspector` reused verbatim (already the complete page-native property editor — `PropertyEditorRow` + `MultiSelectChips` move to `Properties/` so the `ItemWindow/` delete doesn't break it).
- Wire the open path: branch in `Detail/SidebarDetailView` on the resolved vault's `open_in` — `.window` → existing detail pane, `.compact` → `PagePreview`. Covers connection-driven and selection-driven opens (single DRY seam).
- **Lock + open:** opens locked (read-only); the bottom-right Lock toggles editability. **Right-click** the body/title → **"Lock / Unlock"** + **"Open Page"**; "Open Page" routes to the main detail pane via the injected `MainWindowRouter.requestOpen(to: .page)` instance and dismisses the preview.
- Eliminate `Window/PreviewWindow.swift` (independent of MarkdownPM; safe to remove).

#### Band 3: user sidebar sections (last)

- Persisted user sections via a `SavedConfig`-pattern store (`.nexus/sidebar-sections.json` + a manager registered on `NexusEnvironment`). Render each as a sibling `Section` of `PageTypeRow`s (homogeneous → crash-safe). Right-click "Add Section" on the Vaults header; "Move to Section" on `PageTypeRow`. Empty sections render nothing (never a leaf placeholder mixed with disclosure rows).

### Data / migration

Clean slate — no file migration. Stop writing `Class`; existing keys sit inert. Index rebuilds from the v11 schema on launch.

### Closeout

- **Tests:** delete item-only suites; seam-edit mixed suites to keep page coverage; delete shared item-only support (`Support/TempNexus+Items.swift`) after porting its one page consumer; keep `Support/TempNexus.swift` (115 consumers).
- **Cleanup:** the `code-simplifier`/`simplify` pass on the changed surface (the `SideKind`/`ContentItem`/ternary collapses are natural DRY wins).
- **Doc-sweep:** the agent produced a full per-file inventory. `Features/Items.md` deletes; `Domain-Model.md` / `PommoraPRD.md` / `Architecture.md` / `CLAUDE.md` (the 2-layer model, symmetric-code rule, quirk #8 mirror clause) get rewritten to a one-entity model; the ItemsV2 plans were already deleted in HEAD `caa236b` (git history preserves them — no `Superseded/` relocation); `History.md` gains a collapse entry.

### Landmines & invariants

Quirks (from `// CLAUDE.md`) that gate this work: **#8** sidebar Section shape (crash-prone) · **#14** `loadAll` index sync · **#15** `NexusEnvironment` injection (SIGTRAP on declared-but-uninjected `@Environment`) · **#16** XCTest launch-modal guard · **#1** test-filter matches suite/type name · **#7** green per commit · **#10** parallel-session tree not guaranteed clean. The parallel session migrating the Item Window (`NSPanel → WindowGroup`) is unaware of this strip — coordinate at the open-path call site; do not bundle its `ItemWindow/` churn.

### Phase structure (green-commit order)

Reference order; the plan details tasks. Each ships green.

1. **Relocate** `OpenInMode` (rename cases `compact`/`window`) + `PropertyDisplay` / `DisplayTreatment` to Pages; **delete `PageTemplateConfig`** (add `open_in` directly to `PageType`); delete `LayoutArchetype` / `PromotedProperty` / `PropertyLayoutMode` / `TemplateResolver`. (Decouples kept code from the doomed file.)
2. **Connections + MarkdownPM cleanup:** rename the item-link framework to a generic page-native chip-link form (no-trace), gate it off; `[[` declass; page-only connection scanner/cascade/locator; delete the app-side `item` resolver / `onItemLinkClick` / `ItemLinkOpener`. (Severs the editor's last `Item` dependency *and* erases the item naming.)
3. **Strip leaf consumers:** Detail/ViewSettings/NavDropdown/IconPicker item arms; `SideKind` collapse.
4. **Strip the enum spine:** `EntityKind` / `SidebarSelection` / `SelectionTag` item cases (compiler gate flags any missed seam) + sidebar `ItemsSection` removal.
5. **Strip globals + scene + injection:** `AppGlobals` item bridge, `PommoraApp` item scene, `ContentView` debug scaffold, `NexusEnvironment` item managers.
6. **Strip adopter / paths / `Class`:** `NexusAdopter` stamp pass + sidecar kinds, `NexusPaths` item helpers, `PageFrontmatter` `Class` removal, `KindStamp` delete.
7. **Index:** drop item tables/indexes/writers/queries; bump schema version.
8. **Delete item files + tests.**
9. **Build:** `PageType.open_in` field + Compact/Window toggle in the settings leaf; `PagePreview` + open-path wiring + inspector unlock→open affordance; eliminate `PreviewWindow`; QuickCapture spec retarget.
10. **Band 3** sidebar sections.
11. **Closeout:** tests green, simplify pass, doc-sweep, archive ItemsV2 plans.

### STOP/WAIT gate

The plan terminates after closeout. The `PagePreview` Figma chrome **is now in-plan** (design received 2026-06-09, captured in P5) — the prior STOP/WAIT on it is lifted. **Pinned properties are not planned** — they're a Prospect; a default-open inspector covers the use case.
