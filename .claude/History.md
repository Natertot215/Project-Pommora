### Pommora — History

Changelog — what changed and when, newest first. Brief by design. Current state lives in the feature docs + `PommoraPRD.md`; the roadmap and phases live in `Framework.md`.

#### Relations Redesign — relations + tiers unified (2026-05-29)

**Relations property layer rebuilt per the Relations Redesign plan** (`Planning/Relations-Redesign-Plan.md`). One linking system replaces two: tier tagging and relation properties now share a single pipeline.

- **Tiers are relations.** `tier1` / `tier2` / `tier3` (root frontmatter arrays) flow through the property pipeline via the tier value adapter and emit into the SQLite `relations` table; the `tier_links` table is retired (one reverse-lookup path, `IndexQuery.incomingRelations`).
- **Always-multi.** The `allows_multiple` toggle is dropped; a relation value is always an array of `{"$rel": "<ULID>"}` (single = one-element array). `RelationScope` → `RelationTarget`: user-creatable kinds are Page Type / Item Type / Agenda Tasks / Agenda Events; `context_tier` is internal-only.
- **One editor, one rendering.** A single-pane relation editor (create + edit, home side + reverse name + reverse icon) replaces the retired multi-step wizard. Relation values render as the target's icon + title in styled colored text via the single `RelationChip` primitive — a dedicated chip visual is deferred.
- **Context-delete cascades source-side** — deleting a Space / Topic / Project removes its tier reference from every Page, Item, and Agenda entry, orchestrated at the sidebar delete call sites.
- **Adoption + migration (Lean).** Per-Type sidecar `schemaVersion` 1 → 2 triggers a one-time normalizing re-save (array shape, `relation_target` key, Collection targets rewritten to their parent Type) applied silently; the one lossy change — dropping a relation property targeting a context tier — is gated behind an explicit acknowledgment in the adoption preview. Index DB `currentSchemaVersion` 2 → 3 forces a one-time rebuild that backfills tiers into `relations`.
- **Deferred** (logged in `Prospects.md`): relation chip visual design; source-side editing of an existing relation's reverse name/icon; the real Context-side `LinkedFromDropdown` surface; hierarchical value pickers.

Registry decisions #8–#12 added in `Guidelines/Paradigm-Decisions.md`. Landed green across the session (only the known `debounceCoalescesRapidEdits` editor-timing flake fails).

#### View Settings editor redesign + Design.md consolidation (2026-05-27)

Rebuilt the View Settings per-property editor to Nathan's Figma. The popover-family UIX lessons that fell out of the rebuild (PaneDivider rail standard, pinned destructive footers, Subheadline / Callout type scale, chip dimensions, back-label pane affordance, idempotent inline-`TextField` commit on Enter / blur / disappear, plain `Menu` over `Picker(.menu)` for inline selectors) folded into `Guidelines/Design.md`; the standalone `UIX-Baseline.md` file was removed (one fact, one home). Build-clean (two `xcodebuild` passes); not yet smoke-tested.

**Locked decisions:**

- **Section headers = Subheadline / emphasized vibrant secondary; chip text = Callout / emphasized** (Nathan's Figma type ramp).
- **Inline selectors = plain `Menu` with no chevron glyph, checkmark on current** — supersedes the earlier Design.md "Menu label = Text + chevron-down" note.
- **Pane back affordance names the previous pane**, not the current one; entity-identity panes (EditPropertyPane) carry no duplicate title.

#### Folders (third Pages-side tier) — tried and reverted (2026-05-27)

Built a full `PageType → PageCollection → Folder → Page` third tier (model, `_folder.json` sidecar, SQLite table, CRUD, sidebar + detail UI) then reverted it the same cycle. The tier duplicated Collections' rigid-grouping role while conflicting with the planned view-organization system (Board / group-by / saved views, v0.6.0): you can't "group by property" and display a fixed container hierarchy in the same view, and that primitive doesn't exist yet to prove folders were even needed. Removed before more features piled onto the third tier. **Kept** from the effort: F.0's system-wide stub-and-inline-rename CRUD (`CreateWithInlineEdit` + `DefaultTitleResolver`, `68caf96`), the sidebar context-menu tweaks (no "New Vault" in the row menu — "+" header is the sole vault-creation path; plain "New X" labels), and `NexusAdopter.autoTagMissingSidecars` for Types + Collections (drag a folder structure into a Nexus via Finder and it's recognized). Full removal plan: `.claude/Planning/2026-05-27-folders-removal-plan.md`.

#### v0.3.1 Properties end-to-end (2026-05-26 — shipped on main as 21 commits, baseline `627e972` → tip `0d5aa16`)

Single-session execution of the approved `.claude/Planning/View-Settings-edit-properties-plan.md` (25 tasks, 9 phases). Tasks 1-20 shipped + Task 21 (in-window item property editing — wiring the Item Window inspector's `PropertyEditorRow` stubs to real per-type editors) deferred to v0.3.1.x. **The deferral is deliberate, not technical:** the Item Window is still a placeholder UI slated for a rebuild, so the in-window property-editor work shouldn't be invested in a surface that's about to change — it waits for the real Item Window. Task 23 (`git push` + Nexus mirror) paused for Nathan's auth.

**Phase ship map:**
- **Phase A — Data layer foundations.** `DisplayVariant` enum (`.box`/`.select`/`.chip`, Status-only render variant) + `DateFormat` enum (6 cases) + `PropertyDefinition.displayAs` + `.dateFormat` (additive Codable) + `ItemType.singular` (Capacities-style label) + `SavedView` Codable upgrade (real fields + reserved sort/filter/group stubs) + `views: [SavedView]` on PageCollection + ItemCollection + default-view migration on PageTypeManager.loadAll + ItemTypeManager.loadAll (quirk #15 pattern) + PropertyChipColor cleanup (12 cases — drop `.cyan`/`.mint`/`.gray`, add `.orange`/`.accent`; retire tier system; new OptionColorPicker 5x2 grid).
- **Phase B — ViewSettingsScope + popover scaffold.** `ViewSettingsScope` gains associated values on the 4 storage cases (PageType/PageCollection/ItemType/ItemCollection) so popover content can render schema-aware bodies. NavigationStack popover scaffold + StorageMenuRoot (Notion-style menu with active Edit Properties + Property Visibility + muted Layout/Sort/Filter/Group rows).
- **Phase C — Schema editor extraction.** SelectOptionsEditor + StatusGroupsEditor + NumberFormatPicker + FileAcceptEditor extracted from VaultSettingsSheet + TypeSettingsSheet into shared `Pommora/Properties/Editor/` module. Type-prefixed copies removed; both sheets reference shared definitions.
- **Phase D — Edit Properties pane.** PropertiesListPane (searchable + reserved-property lock badges + chevron-push) → PropertyTypePickerPane (type-aware routing: Select/Status/MultiSelect auto-push to EditPropertyPane after commit; simple types pop back; Relation defers to RelationPropertyWizard) → EditPropertyPane (Notion-format: header + Type row + per-type middle section + Duplicate + Delete footer; live-save via new `updateProperty(id:in:transform:)` per manager) → EditOptionPane (per-option editor pushed via `.editOption` route; chevron-push wiring from SelectOptionsEditor deferred to v0.3.1.x).
- **Phase E — Property Visibility pane.** Click-to-toggle + strikethrough-on-hidden + locked `_modified_at` (always visible per locked decision). Writes via new `updateView(viewID:in:transform:)` per manager (resolves containerID as PageType / PageCollection / ItemType / ItemCollection automatically).
- **Phase F — Single-property value writes.** `updatePageProperty` + `updateItemProperty` atomic single-property writes on PageContentManager + ItemContentManager. Read-modify-write via existing atomic save infrastructure; modifiedAt bumped on every write; SQLite index upsert best-effort. Dual-relation reverse-mirror via DualRelationCoordinator deferred to v0.3.1.x.
- **Phase G — Dynamic Table columns.** PropertyColumnBuilder descriptor + 3 new chip primitives (RelationChip / FileChip / LinkChip) + PropertyCellDisplay dispatcher rendering all 11 property types (chip-family for Status/Select/Multi/Relation; pure text for Number/Date/URL/LastEdit; native control for Checkbox; File via FileChip overflow counter). Wired into all 4 storage detail views via `TableColumnForEach` (macOS 14+ — the plan's "no dynamic columns" note was outdated).
- **Phase H — Click-to-edit cell popovers.** PropertyCellEditor wraps PropertyCellDisplay with a `.popover(arrowEdge: .bottom)` anchor; per-type editor dispatch inside the popover (number/date/datetime/select/multiSelect/status/url use built-ins or existing pickers; checkbox flips inline without popover; lastEditedTime stays read-only; relation + file show "v0.3.1.x" placeholder until IndexQuery + AttachmentManager flow-through ships). Detail views compute commit closures that route to updatePageProperty/updateItemProperty with the right parent collection (helpers `collectionContaining(pageID:)` + `setContaining(itemID:)` scan cache for membership).

**Locked decisions ratified this session:**

- **PropertyChipColor flat palette (12 cases).** `.default` (nil/grey fallback) / `.red` / `.orange` / `.yellow` / `.green` / `.blue` / `.accent` (Nexus accent) / `.teal` / `.indigo` / `.purple` / `.pink` / `.brown`. `.cyan`/`.mint`/`.gray` retired. Green + Teal use `.opacity(0.7)` Apple system colors. Yellow + Pink keep Pommora custom hex. `selectablePalette` returns the 10 user-pickable cases (excludes `.default` + `.accent`) for OptionColorPicker's 5x2 grid.

- **DisplayVariant is Status-only.** `.box` / `.select` / `.chip`. Other property types ignore `displayAs`. The `.chip` variant uses hardcoded `"square.dashed"` placeholder icon at v0.3.1.x; per-group / per-option Status icons + Settings config land in pre-v1 cleanup (Prospects.md).

- **DateFormat is Date/DateTime-only.** 6 cases including ISO 8601. Default `.monthDayYearLong`. Custom strftime-token formats deferred (Prospects.md).

- **Chip rendering scope (cell display side).** Chips render ONLY for Status / Select / MultiSelect (via PropertyChip pill) + Relation (via RelationChip — RoundedRectangle cornerRadius 4) + File (via FileChip — quaternary fill, link icon). Dates / Links / Numbers / Checkboxes / LastEditedTime render as pure text or native controls without chip chrome.

- **Each Collection's `views[]` is independent of the parent Type's.** SavedView lives on both PageType + PageCollection (and ItemType + ItemCollection) separately. Default-view migration in `loadAll` mints a fresh Table view per container that has empty views.

- **Schema lives on the Type; Collections inherit.** Edit Properties pane shown for Collection scope writes to the parent Type's schema via `c.typeID` lookup. Property Visibility pane writes to the Collection's own views[0].

- **TableColumnForEach works on macOS 26.** Plan note about "no dynamic columns on macOS" was outdated. Detail views use TableColumnForEach for the user-property column band between Title and Modified.

- **`updateProperty(id:in:transform:)` on each Type manager.** Generic transform-based per-config edit. Replaces a hypothetical `updateOption(...)` method — EditOptionPane reuses the same `updateProperty(transform:)` flow with closure-based option lookup. Same pattern for `updateView(viewID:in:transform:)`.

**Sub-tasks intentionally deferred to v0.3.1.x:**
- Task 21 (PropertyEditorRow relation/status/file stub patches in Item Window inspector) — cell editor bypasses entirely; sheet path stays current behavior.
- Cell-editor inline Relation editor (needs IndexQuery flow-through to cell editors).
- Cell-editor inline File editor (needs AttachmentManager flow-through to cell editors).
- SelectOptionsEditor + StatusGroupsEditor chevron-push refactor (would light up EditOptionPane in normal UX; today EditOptionPane is route-addressable but unreachable through the editors).
- Dual-relation reverse-mirror inside updatePageProperty + updateItemProperty.
- Per-option Status icons + Settings config (pre-v1 cleanup).
- Tests for `updatePageProperty` + `updateItemProperty` value-write paths (defer to a test-coverage patch; cell-editor smoke testing relies on visual verification at this slice).

**Working tree merge note:** Nathan's parallel session on Vault/Collection adoption (file-explorer add path) will conflict with my Phase A Task 5 default-view migration in PageTypeManager.loadAll + ItemTypeManager.loadAll. Quirk #11 anticipated this; rebase / merge resolution happens when his work lands.

#### v0.3.x View Settings chrome slice (2026-05-25 evening — first patch of v0.3.1.x Storage View Redesign)

Same-day continuation of the PM sweep. One focused commit on `v0.3.0-properties`; merged to `main` and pushed alongside. Ships the chrome of the consolidated View Settings popover — empty Liquid Glass shell behind a `slider.horizontal.3` toolbar button — while locking the architectural pattern every follow-up panes patch will reuse.

**Ship list:**

| Component | File | Outcome |
|---|---|---|
| Scope enum | `Pommora/Pommora/ViewSettings/ViewSettingsScope.swift` | 10-case enum (one per `SidebarSelection` variant; `.savedKey("calendar")` collapses to `.calendar`, other saved keys collapse to `.none`). Case-only at this slice; associated values added in v0.3.1 when first real pane needs entity refs |
| Empty popover shell | `Pommora/Pommora/ViewSettings/ViewSettingsPopover.swift` | `Color.clear.frame(width: 300, height: 360)`. Liquid Glass auto-inherits from toolbar anchor (WWDC25 #323). Outside-click + ESC are the only dismiss paths — no in-popover close affordance |
| Toolbar button | `Pommora/Pommora/ViewSettings/ViewSettingsButton.swift` | `Button { } label: { Image("slider.horizontal.3") ... }` + `.popover(arrowEdge: .top)`. 22x16 icon frame matches Inspector toggle next to it for capsule uniformity |
| Test coverage | `Pommora/PommoraTests/ViewSettings/ViewSettingsScopeMappingTests.swift` | 13 tests covering every `SidebarSelection` case + the 4 `.savedKey` variants (`"calendar"` / `"homepage"` / `"recents"` / unknown). All green |
| ContentView wiring | `Pommora/Pommora/ContentView.swift` | `static func viewSettingsScope(for:)` pure mapper + `private var currentViewSettingsScope` reactive computed property. Button inserted as FIRST child of the existing primary-action HStack — shares the existing `.glassEffect()` capsule with NavDropdown + Inspector toggle. Order: `[ViewSettings] [NavDropdown] [InspectorToggle]` |

**Architecture locked (locked decision #12):** static button position at ContentView level + adaptive popover content via `ViewSettingsScope` derived reactively from `sidebarSelection`. Detail views never declare their own `.toolbar { ... }` for this surface. SwiftUI re-evaluates the scope parameter when selection changes; the popover body (when open) re-renders against the new scope; the button itself never moves. Forward-compat: in v0.3.1 the enum gains associated values carrying concrete entities; the wiring shape doesn't change, only the body content.

**Bug found + fixed mid-session via systematic-debugging:** initial popover header used `Button(role: .close) { dismiss() }` — the role-only init that infers an X label from the role. Apple only documents this inside `.toolbar { ... }` context where SwiftUI synthesizes the X. Inside a popover body (non-toolbar context) it asserted at first popover-content render — crash on button click (popover content is lazy-evaluated, so render fires on tap, not at app launch). Root-cause located via Phase 2 pattern analysis: my usage was the only `Button(role: .close)` in the entire codebase; every other `Button(role:)` paired the role with explicit `label:` content. Surgical fix: replaced with `Button { dismiss() } label: { Image("xmark.circle.fill") ... }.buttonStyle(.plain)`. Then user requested empty placeholder per the chrome-only slice scope; close button removed entirely. Locked as new quirk #17.

**Locked decisions this slice:**

1. **View Settings button = single static instance at ContentView level inside the existing primary-action `.glassEffect()` HStack.** Order: `[ViewSettings] [NavDropdown] [InspectorToggle]`. NEVER per-detail-view. Popover content adapts via `scope: ViewSettingsScope` parameter derived from `sidebarSelection`. Recorded as locked decision #12 in Handoff.

**Plan record:** `.claude/Planning/View-Settings-button-chrome-plan.md`. Tasks 1-4 (button + popover + scope wiring + ContentView insertion) shipped this commit; Task 5 (visual approval on all 9 surfaces) is the remaining open item. Plan stays in active Planning until Task 5 closes; then retires to Superseded.

---

#### v0.3.x follow-up sweep (2026-05-25 PM — 17 commits on `v0.3.0-properties`)

Same-day post-merge: design-system foundations + UX correctness sweep + one architectural fix. Branch tip `88c9367` on `origin/v0.3.0-properties`.

**Ship list (chronological):**

| Cluster | Tip commit | Outcome |
|---|---|---|
| Items-Detail-Views plan Tasks 1-11 | `55bf8c3` | All 4 storage detail views (PageType / PageCollection / ItemType / ItemCollection) shipped with footer (`+ New …` buttons) + session-local drag-reorder via `DetailRowDragPayload` + `SessionRowOrdering`. Real `NewItemSheet` replaces stub. PageCollectionDetailView strips duplicate sort UI. Kind column removed from Items-side views (homogeneous content) |
| Sidebar disclosure restore | `dd441f1` | Reverses earlier flatten-to-leaf. Item Types fold like Vaults; Sets render as flat leaves WITHOUT chevrons. `ItemTypeManager.parentItemType(for:)` helper. New `SidebarConfirmation.deleteItemCollection` case. Mitigates structural-asymmetry crash risk per quirk #9 (mixed flat-leaf + disclosure children in same Section crashed `OutlineListCoordinator.recursivelyDiffRows`) |
| Items section label | `675e378` | Sidebar default `"Types"` → `"Items"` (`SettingsLabels.SidebarSectionLabels.defaults`). `Settings.currentDefaultsVersion` 1→2 with migration step that only rewrites users still on the old default. `"Delete Type"` → `"Delete \(typeLabel)"` via newly-injected `@Environment(SettingsManager.self)` on top-level SidebarView |
| Real stub-replacement sheets | `9a6aac0` | `NewItemTypeSheet` + `NewItemCollectionSheet` get real Name + Icon forms (was 23-24 line "UI ships in follow-up" stubs). Mirror `NewPageTypeSheet` / `NewPageCollectionSheet` shape |
| Chip primitives + PommoraUIX | `cedb75b` | NEW `Pommora/Properties/Chips/` folder: `PropertyChip` (pill + chip variants, 13-color `PropertyChipColor` palette in 2 tiers — `.pink = #E89EB8` / `.yellow = #FFDE21` are Pommora-custom hex overrides), `PropertyCheckbox` (custom icon + color), `ChipDropdown` (Liquid Glass, content-driven width). NEW `Pommora/ComponentLibrary/` folder: `ComponentLibraryView` Cmd+Shift+D debug window with gallery-style flat per-category leaves (Chips / Sidebar / Detail Views / Sheets / Page Editor / NavDropdown / Windows + Foundations). `PropertiesPulldown` removed from `PageEditorView` (obstructed titlebar; properties for Pages will live in Claude chat inspector slot v0.3.x). NEW spec at `.claude/Features/PommoraUIX.md` |
| Env-injection crash fix | `c8b3cbc` | `ItemTypeDetailView` + `ItemCollectionDetailView` declare `@Environment(ItemTypeManager.self)` + `@Environment(SettingsManager.self)` but `ContentView.detail` only injected `spaceMgr / vaultMgr / contentMgr / itemContentMgr`. SwiftUI `_TaskValueModifier.Child.value.getter` asserted in `EnvironmentValues.subscript.getter` (`EXC_BREAKPOINT` SIGTRAP) when computing the `.task` closure for the detail view. Added the missing two env values to the optional-unwrap chain + `.environment(...)` chain |
| Icon pipeline | `09e7a27` | `ItemContentManager.createItem(name:in:type:)` + `createItem(name:inTypeRoot:)` gain `icon: String? = nil`. Same for `PageContentManager.createPage(name:in:vault:)` + `createPage(name:inVaultRoot:)`. Both managers persist the icon into entity's icon field (was hardcoded `nil`, silently discarding the IconPickerField selection). `NewItemSheet` passes through. `NewPageSheet` gains `IconPickerField` (was missing entirely) + frame expanded 380x220 → 400x260 |
| Label sweep | `a8bd20b` | `TableColumn("Name")` → `TableColumn("Title")` in all 4 detail views. `TextField("Name", text:)` → `TextField("Title", text:)` in 8 sheet form files + 4 detail-view rename alerts. `"Tier 1 (Spaces)" / "Tier 2 (Topics)" / "Tier 3 (Sub-topics)"` → `"Spaces" / "Topics" / "Projects"` in `ItemWindow.relationsSection` + `RelationPropertyWizard` tier picker (drops `"Tier #"` prefix per locked 2026-05-25 directive) |
| **SQLite FK fix** | `88c9367` | `PageTypeManager.loadAll` + `ItemTypeManager.loadAll` defensively upsert types + collections to the SQLite index after disk-load. Eliminates recurring `SQLite error 19: FOREIGN KEY constraint failed - INSERT OR REPLACE INTO pages...` toast that fired when CRUD ran against entities loaded from disk that the index DB had no record of (adoption / external Finder folders / post-adoption state). Establishes new invariant locked as quirk #15: "after loadAll, every in-memory parent is mirrored to DB." `INSERT OR REPLACE` keeps it idempotent; `try?` swallows failures since index is regeneratable. 4 regression tests in new `LoadAllIndexSyncTests.swift` lock the invariant against future regressions |

**Locked decisions this sweep:**

1. **Items + Pages are NOT renameable concepts.** Only their containers (Vault / Collection / Type / Set) get `LabelPair` entries in `SettingsLabels`. `"New Item"` and `"New Page"` literals are correct; no `settings.labels.item` / `.page` exists.
2. **Sidebar Items section default = `"Items"`** (not the container plural `"Types"`). Users browsing this section think of it as "browsing my Items," not "browsing my Types." Renameable per Nexus.
3. **Item Types are sidebar disclosure-toggles** mirroring Vaults; their Sets render as flat leaves WITHOUT chevrons (no further sidebar children to disclose). Items themselves never appear as sidebar rows — they live in the detail-pane Table.
4. **Tables: NO vertical column borders.** Notion-flat aesthetic. Only horizontal bottom-of-header underline. Forward-applies to all 4 storage detail views + v0.5.0 view-type renderers. SwiftUI Table needs NSViewRepresentable + cleared `gridStyleMask` to enforce — implementation TBD with the v0.3.1.x Storage View Redesign spec.
5. **Tier labels in property panels = `"Spaces" / "Topics" / "Projects"`** (no `"Tier #"` prefix). Matches the 2026-05-25 sidebar-section directive. Hardcoded for v0.3.x; will thread `SettingsManager` when v0.6.0 Settings UI ships.
6. **`"Title"` everywhere, not `"Name"`.** Column headers, form placeholders, rename dialogs. Aligns with the `title` field name on every entity.
7. **`loadAll` syncs parents to index** (quirk #15). Forward-binding architectural invariant.
8. **Every detail-view `@Environment` must be injected at `ContentView.detail`** (quirk #16). Forward-binding architectural invariant.

**v0.3.1.x Storage View Redesign — locked decisions:** toolbar `slider.horizontal.3` popover with `NavigationStack` submenus mirroring Notion's view-settings menu structure; per-view config storage in `views[]` array per sidecar (one entry today, multi at v0.5.0); Property Visibility row = strikethrough toggle (no eye icon); delivery via Approach B patch-series drip v0.3.1 → v0.3.1.4.

---

#### v0.3.0 Properties — FEATURE-COMPLETE; merged to main (2026-05-25)

71 commits on `v0.3.0-properties` merged into `main` as `3d1bc19`. All 11 phases A–K shipped end-to-end. Smoke test on Nathan's real nexus is the only remaining gate before release tagging.

**What shipped (by phase):**

- **A — Foundation types.** 11-case `PropertyType`; `PropertyValue` + `FileRef`; `ReservedPropertyID` + `mintUserPropertyID`; 5-case `RelationScope` tagged-object; `PropertyDefinition` stored ULID `id` + config fields + nested `StatusGroup`/`StatusOption`/`StatusGroupID` + `DualPropertyConfig`.
- **B — `SchemaTransaction`** atomic multi-file commit primitive.
- **C — Migration suite.** `PageFrontmatter.modifiedAt` + `schema_version: 1` on every sidecar + `PropertyIDMigration` two-phase scan/apply runs every nexus open + `AdoptionPreviewView` surfaces per-Type migration counts before commit.
- **D — Schema CRUD on all 4 schema-bearing managers** (`addProperty`/`renameProperty`/`changeType`/`deleteProperty`/`reorderProperty`); `PropertyDefinitionValidator` 8 rules; `schemaByID` rewire + drop `duplicateTitle`; `default_sort` on every sidecar; `SchemaConflictDialog` EC4 drift defense.
- **E — SQLite index live end-to-end.** GRDB.swift SPM dep; `PommoraIndex.open(at:)` lifecycle with schema-version recovery; 12-table schema; `IndexBuilder` two-phase populate; `IndexUpdater` wired into all 6 managers; `IndexQuery` Notion-style filter+sort+broken-links; `NexusManager` opens/rebuilds; `ContentView.constructManagers` plumbs `IndexUpdater` so mid-session mutations propagate.
- **F — `AttachmentManager`** copy-on-attach into `<nexus>/.nexus/attachments/<entity-id>/` with MIME accept-list (wildcard support), 50 MB warn / 500 MB hard cap, collision-safe filename suffixing; cascade-delete to trash on entity delete across all 4 entity managers.
- **G — Agenda Status + paired relations.** AgendaTask + AgendaEvent schema defaults inject `_status` Status property; load-path backfill for pre-existing schemas via SchemaTransaction; `DualRelationCoordinator` manages paired-relation lifecycle (create/value-mirror/rename/delete); wired into `PageTypeManager` + `ItemTypeManager.addProperty`/`deleteProperty`.
- **H — Move-strip.** `movePageAcrossTypes` / `movePageBetweenCollections` on `PageContentManager+CRUD`; parallel `moveItem*` on `ItemContentManager+CRUD`. Name-based strip (property IDs are globally unique so ID-match is structurally impossible). Paired-relation back-ref cascade-clear. SchemaTransaction atomic across move + strip + back-refs.
- **I — Settings migration.** `Settings.defaultsVersion` field + `Settings.migrate(_:)` step-function scaffold; `SettingsManager.loadOrSeed` calls `migrate` after decode + re-persists only when changed (mtime stays stable on no-op launches). `SidebarSectionLabels.spaces` + `.topics` fields; sidebar section headers + sheet titles thread from `SettingsManager.labels` instead of hardcoded literals.
- **J — Placeholder UI suite.** PropertyEditorRow dispatches all 11 types; `ItemCollection.pinned_properties`; `StatusPicker` 3-section popover; `RelationPicker` scope-aware (GRDB `String` overload pollution workaround via private struct sub-views); `FileAttachmentEditor` with size-warning flow; `RelationPropertyWizard` 5-step (`DualRelationCoordinating` protocol for mockable tests); `PropertyTypePicker` 10-case (excludes `.lastEditedTime`); `VaultSettingsSheet` + `TypeSettingsSheet` schema editors; `MoveStripConfirmationDialog`; `PropertyPanel` host-agnostic eager panel; Item Window inspector toggle + pinned chips; `PropertiesPulldown` lazy mounted in `PageEditorView`; `FrontmatterInspector` live editors; column-header click-to-sort on `PageCollectionDetailView`.
- **K — CalendarDetailView.** Tasks list above, Events list below; sorted by due/start ascending; nil-date last. Right-click Calendar pin → "New Task" / "New Event" quick-create.

**Locked decisions this branch:**

1. **Status value on-disk encoding = `{"$status": value}` tagged-object form.** Matches `{"$rel": id}` relation pattern. Pure shape-sniff at the Codable layer can't disambiguate `.status` from `.select`; tagged form is round-trip-stable AND agent-legible.
2. **Move-strip matches by NAME, not ID.** Property IDs are globally unique per `property_definitions.id PRIMARY KEY`; ID-based cross-type matching is structurally impossible. `IndexQuery.moveStripCount` filters by name; Pages keep values where dest has a same-named property.
3. **Reserved property IDs:** `_id`, `_created_at`, `_modified_at`, `_status`, `_type`, `_tier1`, `_tier2`, `_tier3`, `_wikilinks` (`_type` added Phase D.4). User-defined properties mint `prop_<ulid>`.
4. **`schema_version: 1` on every sidecar.** Legacy decode → 0 = needs migration. Index DB carries its own `schema_version` in `meta` table; mismatch triggers delete + rebuild.
5. **`PropertyIDMigration` runs on EVERY nexus open** (not only when adoption is also needed). Idempotent. Preview sheet shows per-Type counts before commit.
6. **tier1/2/3 are root-level frontmatter fields**, not nested under `properties:`. Reserved IDs `_tier1`/`_tier2`/`_tier3` block user collisions.
7. **AgendaTask + AgendaEvent default seed = single `_status` Status property.** Legacy `type` Select removed. Load-path migration injects on existing schemas via `SchemaTransaction`.
8. **`DualRelationCoordinator` is the lifecycle owner of paired relations.** Manager `addProperty`/`deleteProperty` route paired-relation work through it; container-scoped relations get atomic dual creation, value mirroring on set/clear, atomic delete-with-value-cascade.
9. **`AttachmentManager` is the only path for file values.** Copy-on-attach into `<nexus>/.nexus/attachments/<entity-id>/`; 50 MB warn / 500 MB hard cap; cascade-delete to trash on entity delete.
10. **Settings carries `defaultsVersion: Int`** for forward-compatible stale-default migration. `Settings.migrate(_:)` is the step-function scaffold; bump the constant + add a migration step when defaults change.


---

#### v0.3.0 Properties — Phases A–G shipped on `v0.3.0-properties` (2026-05-24 EOD)

44-commit interim milestone: Phases A–G complete on the branch (off `main`). Build green; full suite passing with two known pre-existing failures (`NexusAdopterTests/applyNathansActualShape` from a parallel-session working-tree change + `PageEditorViewModelTests/debounceCoalescesRapidEdits` full-suite flake). Phase/commit detail and the branch's locked decisions are folded into the FEATURE-COMPLETE A–K entry above (2026-05-25). Parallel-session: sidebar drag-reorder `.onMove` rebuild + `RenameableRow` extraction merged as `c98ecd6` during C.5.

---

#### v0.3.0 Properties scope redirection + editor patches (2026-05-23 EOD)

Three shipped threads + a Properties scope brainstorm.

**Editor patches (parallel session):**

1. **Foldable headings toggle — fixed.** Heading chevron-on-hover + collapse mechanism now works correctly; frontmatter persistence via `folded_headings` round-trips. Resolves the long-running toggle bug in `External/MarkdownEngine/`.
2. **Em-dash / en-dash auto-syntax.** Trivial editor add: `--` → en-dash (`–`), `---` → em-dash (`—`). Ships with the heading-fold work.

**Properties scope redirection (brainstorm session — supersedes prior implementation plan):**

3. **v0.3.0 scope narrowed: data layer + minimum-viable placeholder UI only.** Real Properties Pulldown + Property Panel UI redirected to v0.3.1 (Figma-driven fast-follow). Broader inspector architecture (Claude chat as main-window inspector, PreviewWindow primitive, Item Window redesign with pinned chips) ships as separate v0.3.x patches with TBD timing. Effort estimate dropped from ~7.5 sessions to ~5.5 sessions. Items dropped from v0.3.0: `panel_hidden_properties` data field, `_itemcollection.json` `pinned_properties` field, seven-section Type Settings sheet (collapses to Edit Properties + Sort only), SchemaEditorRouter, concurrent-open guard, MultiSelectChips color refactor, all detail-pane property-column work, all right-click cross-surface routing.

4. **Surface architecture locked.** Properties live in three context-specific surfaces:
   - **Pages in main window** → NavDropdown-style pulldown at top of content (v0.3.1)
   - **Page Preview** → property panel in window's own inspector (toggle, default closed); ships with PreviewWindow primitive
   - **Item Window** → property panel in popover's own inspector + pinned-property chips above title (saved at Item Collection level); ships with Item Window redesign
   - **Main window inspector** → Claude chat (CLI subprocess bridge; ships independently); properties NEVER live here

5. **Six conceptual decisions locked** (added as decisions #21-#26 in spec):
   - Lazy properties: "+ Add property" picker only lists EXISTING schema properties not yet populated on this entity. Brand-new schema entries go through Type Settings.
   - Per-Type property order: drag-reorder in any surface writes to the parent Type's per-kind sidecar declaration order (affects every entity of that Type). No per-entity override at v0.3.0.
   - Empty surface state: "No properties" message + "+ Add property" affordance. Surface stays visible.
   - Pinning: right-click property row → "Pin Property" / right-click chip → "Unpin Property". Per-Item-Collection scope (shared across all Items in Collection).
   - Status universal: addable to PageType / ItemType / AgendaEvent manually. EventKit relevance is silent on non-Agenda Types — agent-readable as informational data shape.
   - Live red-border validation: invalid values render red as user types; failed saves silently revert.

6. **AgendaTaskSchema `defaultSeed()` rewritten in plan** — drops the placeholder `type` Select (`[Task, To-Do, Phase]`); Status becomes the sole built-in (per spec § Status property type). A.7.5 plan task documents load-path migration for existing nexuses (idempotent removal of legacy `type` if `builtin: true`; injection of Status if missing).

7. **`SchemaTransaction` shape extended to compound mode** (`schemaWrites: [SchemaWrite]`) — dual-relation create/delete rides one transaction; no `try? src.rollback()` orchestration needed. Resolved the rollback API inconsistency from the earlier audit.

8. **Properties.md + spec + plan + PRD + Framework + Pages.md + Items.md + PageTypes.md + Prospects.md doc sweep.** Properties.md gains canonical "Where Properties Live" section. Pages.md gains "Properties Pulldown — to-be-implemented" section. Items.md gains "Inspector Panel + Pinned Chips — to-be-implemented" section. Prospects.md retires "Property panel placement options" + promotes "Claude chat in inspector" out of Prospects (now in roadmap). PRD's three-pane shell description rewritten to reflect Claude-as-inspector direction. AgendaTask + AgendaEvent kind descriptions in PRD lose stale `type` Select reference.

**Sidebar bugfixes + UX tightening:**

9. **Sidebar disclosure-click bug — fixed (introduced drag regression).** Vault / Topic / PageCollection rows weren't expanding to show their children. Root cause: `.draggable` (inside `.reorderable(...)`) was applied to the entire DisclosureGroup, swallowing chevron clicks as drag-init gestures. Fix: moved `.reorderable(...)` from outer modifier into the DisclosureGroup's `label:` closure on PageTypeRow / PageCollectionRow / TopicRow — drag source stays the label area only, chevron tap area free for expand/collapse. **Side effect:** drag-to-reorder hit zones shrunk to label area only, and `rowHeight` measurement broke (label height ≠ full row height → above/below drop position calc is off). Drag feels non-functional. **Queued for follow-up:** split drag source from drop destination — `.draggable` on label only, `.dropDestination` on full row. See Handoff "Sidebar drag-to-reorder REGRESSION."

10. **Sidebar header label "Pages" → "Vaults"** — Nathan's `.nexus/settings.json` carried stale `sidebar_sections.pages = "Pages"` from before `SidebarSectionLabels.defaults()` was updated to `"Vaults"` / `"Types"` (`da744ab` 2026-05-23 morning). Direct file edit on Nathan's nexus. SidebarView code comment updated to reflect new defaults. **Settings migration shim queued** as Open Question #9 in Handoff (for future users with same stale state).

11. **PageType context menu cleanup** — verbose action labels stripped: "New Vault" / "New Collection" / "New Page". Direct-page-to-vault path was already wired via `NewPageSheet(parent: .vaultRoot(v))`; just relabeled cleanly.

#### Post-flatlayout hardening cluster (2026-05-23)

Five follow-up commits on `main` after the `flatlayout` tag (`049df19`), addressing issues Nathan found running the app post-ship on his real nexus.

1. **`2d42d63` fix(adopter): adoption preview fires only on structural migration.** `AdoptionPlan.hasAnythingToAdopt` no longer triggers on `freshSidecars` — only `inPlaceRenames` (legacy v0.2 migration), `unwrapSteps` (paradigmV2 wrapper unwrap), and `warnings` (explicit issues). Non-Pommora folders at root (Obsidian organization, etc.) stay invisible to discovery instead of spamming the adoption preview every launch. Per-folder opt-in adoption UI is a future Prospect. New test: `adoptionNoOpOnUnPommoraFoldersAtRoot`.

2. **`9cd8cd1` feat(sidebar): drag-to-reorder Phase 2 UX (v0.2.8).** Wired `.reorderable(...)` modifier (built in Phase 1 but never used in production) onto PageType / Topic / Space / Page / PageCollection / Project rows. Removed residual no-op `.onMove { ... }` modifiers (iOS/iPad pattern; doesn't fire on macOS without EditMode). Phase 1 persistence (`5a264f0`) was already correct — only the UX was missing. Out of scope: Items-side rows (ParadigmV2 stubs), NavDropdown Pinned reorder, cross-container drag, detail-pane Table reorder (Phase 4).

3. **`9c3820c` fix(detail): folder-name fallback + diagnostic info for "Collection parent vault not found".** `SidebarDetailView.lookupVault` gains a folder-name-match fallback when typeID-match fails — rescues users whose stored typeID drifted from the live PageType id (data-state caused by re-init / migration anomalies). Error UI surfaces diagnostics (collection title + typeID + parent folder name + full list of known vault IDs) so users can paste into bug reports if the fallback also fails.

4. **`5234f78` fix(adopter): cleanup co-located per-kind sidecar orphans; suppress noisy warning.** `cleanupLegacyOrphans` extended via new `cleanupOrphansAt` helper. Deletes orphan sidecars co-located with the authoritative per-kind sidecar — both other per-kind sidecars (e.g. `_pagecollection.json` next to `_pagetype.json` at vault-root) AND legacy `_vault.json` / `_collection.json` / `_schema.json`. Multi-sidecar warning suppressed at scan time (fires routinely for nexuses migrated through early flatlayout-4.2 versions; cleanup at apply handles silently). **Rule encoded:** at any folder level, only ONE per-kind sidecar is authoritative. The authoritative one wins via `recognizedSidecarsAt`'s order (pageType > itemType > taskConfig > eventConfig > pageCollection > itemCollection) — matches the natural-parent-inference rule (a root folder with both `_pagetype.json` + `_pagecollection.json` is a Type, not a Collection, because Collections must nest inside a Type). Triggered by Nathan's nexus having `Materials/_pagecollection.json` (May 22) next to `Materials/_pagetype.json` (May 23) — orphan from an early flatlayout-4.2 wrong-sidecar bug; subsequent corrected runs wrote the right one but never cleaned up the orphan. New tests: `scan silently classifies dual-sidecar folders as flat (cleanup at apply)`, `apply deletes co-located per-kind sidecar orphan`.

5. **`5f0e11d` chore(adopter): silence 'var unchanged never mutated' warning.** One-line `var` → `let` cleanup. Cosmetic.

**Data-state confirmation:** Nathan's real nexus migrated successfully — `/Users/nathantaichman/The Nexus/` is flat with all 8 vaults (`Archives` / `Assets` / `Claude` / `Databases` / `Knowledge` / `Materials` / `Pommora` / `Systems`) at root, plus `Tasks/` + `Events/` singletons carrying their sidecars. Flat layout verified end-to-end on production data. Two inert collision-suffixed artifacts (`Tasks.20260523-224558-760F/`, `Events.20260523-224558-46F1/`) sit alongside the authoritative singletons — left for Nathan to delete manually if confirmed empty.

#### Flat-Layout refactor (2026-05-23; tag `flatlayout`)

V0.3.0 refinement on top of ParadigmV2. Drops the `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/` wrapper folders — Page Types / Item Types / Tasks singleton / Events singleton now live at the nexus root, classified by sidecar filename. Ships between `paradigmV2` and v0.3.0; lands before v0.3.0 Properties because Properties' schema-editing operates on these sidecar files. Plan: `// Planning//v0.3.0-Flat-Layout-Plan.md`.

**13 locked decisions:**

1. Wrapper folders disappear — no `<nexus>/Pages/`, no `<nexus>/Items/`, no `<nexus>/Agenda/`; Types live at root.
2. Six per-kind sidecar filenames replace the unified `_schema.json`.
3. Asymmetric `config` suffix on Agenda is intentional — `.task.json` / `.event.json` entity extensions would clash with bare `_task.json`.
4. Swift struct names unchanged from ParadigmV2 — `PageType` / `PageCollection` / `ItemType` / `ItemCollection` / `AgendaTask` / `AgendaEvent` stay.
5. Agenda stays singleton via sidecar-driven discovery — folder rename via Finder Just Works.
6. Sidebar grouping reads sidecar filename, not folder location.
7. Adopter handles FOUR input shapes (fresh / legacy v0.2 / paradigmV2-wrapper / already-flat); mixed states tolerated per-folder.
8. Pathological case policy: best-effort + log warnings; first-found wins on duplicate sidecars; timestamp-discriminator suffix on collision.
9. Tasks/Events folders eagerly created on launch (current behavior preserved).
10. Agenda collapse is EventKit-aligned, not just structural — `EKEvent` and `EKReminder` are peer types.
11. Adopter atomicity: best-effort + idempotent; no two-phase transaction; re-launch picks up where it left off.
12. Documentation ships FIRST (Phase 1, before code) so Phase 2–6 subagents read the target spec cleanly.
13. Phase 1 → Phase 2 gated on Nathan's explicit "proceed" signal (remote-review pattern).

**Six per-kind sidecar filenames:** `_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`.

**Wrapper folders dropped:** `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/`. All operational containers now at nexus root.

**Adopter:** handles four input shapes — fresh (content-sniff), legacy v0.2 (`_vault.json` / `_collection.json` in-place rename), paradigmV2 wrapper (unwrap + sidecar rename), already-flat (no-op). Legacy `_vault.json` / `_collection.json` orphans co-located with new sidecars are cleaned up. `.DS_Store`-tolerant empty-wrapper detection — wrappers containing only macOS system-noise files (`.DS_Store`, `Icon\r`, `.localized`) count as empty for deletion. Mixed input shapes coexist; per-folder failures don't block the rest.

**Per-side sidebar section defaults:** "Vaults" (Pages-side) / "Types" (Items-side) — locked UI-divergence rule. Pages get the distinctive "Vault" + generic "Collection"; Items get the generic "Type" + distinctive "Set". All renameable via Settings.

**Agenda discovery:** sidecar-driven — Tasks/Events folders renameable via Finder; discovery walks root for any folder carrying `_taskconfig.json` or `_eventconfig.json`. Multi-folder pathological case: first-found wins with warning logged.

**Outstanding manual step:** Nathan's nexus migration (backup + adopt + verify on real Nexus at `/Users/nathantaichman/The Nexus/`). Engineering ships in flatlayout Phase 4; user-side adoption is one click on next launch — preview describes the migration, apply executes it, idempotent if interrupted.

#### ParadigmV2 — Operational-layer domain model refactor (2026-05-22 plan; SHIPPED 2026-05-23, tag `paradigmV2`)

Vault becomes Pages-only as Page Type; Item Type introduced as parallel Items-side container; Page Collection (Pages) + Item Collection (Items) as parallel organizational sub-folders. AgendaItem split into AgendaTask + AgendaEvent (matching EKReminder + EKEvent). Sub-topics renamed to Projects. Schema sidecars unified to `_schema.json` across all typed containers. On-disk wrapper folders introduced: `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/`. UI label divergence locked: Pages-side defaults to "Vault" + "Collection"; Items-side defaults to "Type" + "Set"; renameable via Settings. Settings scaffold (`.nexus/settings.json` + `SettingsManager` + label wiring across UI) lays groundwork for v0.6.0 Settings UI. New paradigm rule: "Pommora" prohibited in on-disk schemas + Swift namespace qualifications. Retires `Pommora.Collection` quirk #6. Plan: `// Planning//ParadigmV2.md`.

**Locked phase sequence (11 phases):** 1) Doc rewrites → 2) PageType + PageCollection renames + `_schema.json` sidecar → 3) Subtopic → Project rename → 4) AgendaItem split → 5) New ItemType + ItemCollection subsystem → 6) Pages/Items/Agenda wrapper folders + NexusAdopter → 7) Settings scaffold → 8) Sidebar / Detail / Sheet UI restructure → 9) Tests consolidation + v0.3.0 Properties spec reconciliation → 10) Nathan's user-data migration (one-shot script) → 11) Cleanup + Framework reconciliation + ship (tag `paradigmV2`).

**Execution status (2026-05-23):** **SHIPPED.** Tag `paradigmV2` pushed to origin at `36d48c8`. All 11 phases complete. **Fix-forward at `2b8ade8` pulls Phase 10's data-migration scope into NexusAdopter** — legacy root-level Vault folders are classified by content sniff (`.md` → Pages-side; user `.json` → Items-side; empty → default Pages-side) and moved into the appropriate wrapper at `apply()`, with collision handling + fresh-sidecar generation for bare folders. Phase 10 simplified to "backup + run adoption + verify" — engineering shipped, Nathan's manual step (adopt his real nexus) remains open.

**UI tint-cascade regression caught during Phase 7.5 ship.** `.tint(currentAccent)` applied to `ContentView`'s `NavigationSplitView` cascaded the accent color into the `.borderless` "New Collection" button in `PageTypeDetailView`'s footer. Fixed with `.foregroundStyle(.primary)` after `.buttonStyle(.borderless)` — keeps the borderless style but opts out of tint inheritance. Same pattern applies to any other inline button that should NOT inherit the accent.

#### Session 15B (parallel) — 2026-05-21 (Blockquote chrome — v0.2.7.5; visual TBD)

Concurrent with Session 15's drag-reorder work; engine-only scope. Blockquote rendering rewritten from flat `.backgroundColor` + 20pt indent to a renderer-drawn rounded card + continuous vertical accent bar, using the always-show overlay pattern (same as v0.2.7.4 bullet glyph + task checkbox; no caret-aware service).

**Hidden `>` syntax + activation gate.** `> ` (marker + space/tab) is the activation trigger; bare `>` doesn't fire either the renderer chrome or the marker collapse (matches list UX where `-` alone doesn't activate until `- `). `applyMarkerCollapse(in:)` on the supplemental styler walks each line in the blockquote NSRange and applies `font: 0.1pt + foregroundColor: .clear` to `>` + trailing whitespace only when the gate matches — mirrors `visitTable`'s pipe-collapse pattern.

**Renderer-drawn card.** `drawBlockquoteCard(at:in:)` in `MarkdownTextLayoutFragment` draws a rounded `CGPath` fill at `NSColor.tertiarySystemFill` (system-native intensity). The styler no longer emits `.backgroundColor` — moving the fill to the renderer is what makes corner rounding possible (attribute-emitted backgrounds are flat rects with no shape control). New `BlockquotePosition` enum (`.only` / `.first` / `.middle` / `.last`) drives selective corner rounding so multi-paragraph quotes butt-joint into one visually-contiguous block. Position computed via neighbor-line peeks for `> ` start.

**Continuous vertical bar.** 4pt wide pill at `NSColor.secondaryLabelColor`. Bar Y-extent matches card exactly (both inflated by `cornerRadius = 6pt` on rounded ends so the bar extends slightly above/below the body text). `paragraphSpacing = 0` + `paragraphSpacingBefore = 0` between consecutive quote paragraphs so per-fragment bar segments butt-joint flat across multi-line quotes without seams.

**Line-height floor.** `paragraph.minimumLineHeight = ceil(baseFont.ascender - baseFont.descender + baseFont.leading)` forces body line height — without it, a `> ` line with no content yet has only font-0.1 marker chars on it → natural line collapse to ~1pt. The floor keeps the line tall enough to type into AND lets the chrome have proper vertical extent before content arrives.

**Enter/Shift+Enter semantics match list convention.** Plain Enter on a `> foo` line inserts `\n<prefix>` (continues the quote, preserving leading indent — new `blockquoteMarkerRegex` powers detection); Shift+Enter inserts plain `\n` (exits the quote). Mirrors how plain Enter continues lists and Shift+Enter exits.

**v0.2.7.5 caveat:** the horizontal positioning of the card highlight relative to the bar still has a visual mismatch — the card appears to start at the body text rather than extending into the hidden `>` syntax area. Suspected to be either a bar-pill-radius (2pt) vs card-corner-radius (6pt) mismatch causing a visible 2pt gap at the rounded corners, OR a card-fill alpha visibility issue. Shipped as-is, follow-up next session.

**Files (this session — engine package only):**
- `External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift` — `visitBlockQuote` rewrite + `applyMarkerCollapse(in:)`.
- `External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift` — `import Markdown`, `hasBlockquoteMarker`, `BlockquotePosition` + `blockquotePosition`, `drawBlockquoteCard(at:in:)`, `makeSelectiveRoundedRect(_:radius:roundTop:roundBottom:)`, `renderingSurfaceBounds` extension.
- `External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift` — `blockquoteMarkerRegex`, plain-Enter blockquote-continue branch.
- `External/MarkdownEngine/NOTICE.md` — v0.2.7.5 entries.

**Decisions locked (this session):**

10. **Blockquote uses always-show overlay, NOT dynamic-syntax.** Per Nathan: "the always-show is how it currently works; we have no intent on changing that." Per L14 (`// Guidelines//Markdown.md`): always-show beats caret-aware reveal for non-interactive markers. Locked at `// Guidelines//Markdown.md` §9.10.
11. **Plain Enter continues quotes; Shift+Enter exits.** Mirrors list convention. Both behaviors live in `MarkdownListHandler.handleInsertion`'s `\n` branch.

#### Session 14 (parallel) — 2026-05-21 (Editor polish bundled into v0.2.7.4)

A parallel session shipped four small editor wins folded into the v0.2.7.4 ship.

**Bullet glyph substitution shipped.** Closes the Session 13 deferred item. Lines starting with `- ` render `•` via `MarkdownTextLayoutFragment.drawDashBulletGlyph` overlay (always-on, no caret-reveal — same UX guarantee as task checkboxes). The source dash stays in storage as portable CommonMark `- item` for cross-tool readability; the styler hides only its color (`NSColor.clear` while preserving natural width). Only `-` triggers — `*` / `+` / `•` literal markers render as-is. Pixel-aligned draw via `backingScaleFactor` so the bullet doesn't vanish on fractional Y positions (the Session 13 failure mode).

**Task-list shorthand `-[]` / `-[x]`.** Both forms now match alongside the GFM `- [ ]` / `- [x]` form. Regex updated in two places (`MarkdownStyler.taskListRegex` + `MarkdownLists.listRegex` + `bulletListPattern`): spacer group is zero-or-more (was one-or-more), inner-bracket content is `[ xX]?` (was `[ xX]`). Marker collapse: the leading `-` plus any whitespace before the `[` shrinks to font 0.1pt + clear color so the drawn checkbox glyph is the only visible marker prefix (the `[...]` brackets themselves stay at body font — the checkbox draw reads `font.pointSize` from the `[` to compute its size, so collapsing the brackets would make the box render near-zero).

**Bracket auto-pair guard.** Typing `[` only fires the `[` → `[|]` auto-pair when the preceding char is whitespace (space / tab / newline) or the cursor is at line start. Lets the Pommora `-[]` flow without the auto-pair inserting a `]` between `-` and `[`. Prose-link case (`text [link](url)`) still auto-pairs. Implementation in [`MarkdownLists.handleListInsertion`](../External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift) — `shouldAutoPair = (insertionLocation == 0) || prevChar in {" ", "\t", "\n"}`.

**Arrow auto-format extended.** Closes the Session 13 known bug ("typed `<-` and `<->` don't fire on input — only on paste"). Two new cases added to the `>` keypress handler: (A) chained `<-` → `←` then `>` extends `←` → `↔`; (B) pasted `<-` still-literal in buffer, `>` does a combined two-char replace `<-` → `↔`. The existing `->` → `→` case unchanged.

**Code colors.** `MarkdownStyler` now applies `.foregroundColor: NSColor.systemRed.withAlphaComponent(0.85)` to both `.codeBlock` and `.inlineCode` token attributes. `PlainTextSyntaxHighlighter.backgroundColor()` returns `NSColor.quaternaryLabelColor` — semantic system fill, adapts light↔dark, has built-in subtle alpha. Replaces the previous `textBackgroundColor.withAlphaComponent(0)` (effectively invisible).

**Files (parallel session):** `MarkdownStyler.swift`, `MarkdownListHandler.swift`, `MarkdownDetection.swift` (added `isDashBulletLine` mirroring `isThematicBreakLine`'s three-stage pattern, with regex-only Stage 2 since CommonMark's space-after-marker requirement is encoded in the bullet regex), `MarkdownTextLayoutFragment.swift` (added `hasDashBulletMarker` + `dashBulletMarkerDocumentLocation` + `drawDashBulletGlyph` + `renderingSurfaceBounds` extension for invalidation), `MarkdownEditorServices.swift` (`PlainTextSyntaxHighlighter.backgroundColor()`).

**Decisions locked:**

7. **Portable-source-with-overlay is the locked pattern for dash bullets** — same as HR. Source on disk is portable CommonMark; the visual glyph is drawn by the layout fragment at render time. No source mutation.
8. **`-` is the only dash-bullet trigger.** `*`, `+`, and legacy `•` markers render literally. Single-trigger keeps the styler-vs-renderer agreement contract simple.
9. **Bracket auto-pair requires a word boundary on the left.** Auto-pair fires only after whitespace or at line start. Lets compact task syntax (`-[]`) coexist with prose-link auto-pair.

#### Session 14 (continued) — 2026-05-21 (HR jitter on large files — root-cause + two-phase fix)

Editor exhibited two distinct jitter symptoms on large documents: (a) general jitter during cursor placement and selection drag, and (b) a vertical "auto-adjust" of the line when the caret entered or left an HR paragraph. Systematic debugging located two independent root causes, both in the Session 12 HR dynamic-syntax pattern. Same UX preserved.

**Phase 4a — selection-scope.** `NativeTextViewCoordinator.syncHRVisibility` walked the **entire document** on every `textViewDidChangeSelection`, calling `NSString.lineRange(for:)` + `substring(with:)` + an attribute read on every paragraph and Stage-1 + Stage-2 `Markdown.Document(parsing:)` AST parse on any HR-shaped paragraph. The comment claimed "microseconds for typical docs" — true for small files, but on a 1000-paragraph file the cost is ~1ms per caret tick and mouse-drag selection fires this 60+ times per second.

The HR state of paragraphs N..end can only change when the caret crosses into or out of a specific paragraph — every other paragraph's hidden/revealed state is already correct from the last full walk (initial load + each edit cycle). Added a scoped overload `syncHRVisibility(in:textView:scopedTo:)` that walks only a supplied list of paragraph ranges; `textViewDidChangeSelection` now passes `{currentCaretParagraph, priorCaretParagraph}`. Restyle paths (`restyleTextView`, `rebuildTextStorageAndStyle`) keep the full walk because edits can introduce or remove HRs anywhere. Shared `applyHRSync` + `makeHRStylingContext` extracted so the two variants cannot drift. The `priorCaretLocation` must be captured BEFORE `previousCaretLocation` is overwritten at the bottom of `textViewDidChangeSelection`; a local variable at the top of the function handles this. O(N) per-caret-tick walk replaced with O(1).

**Phase 4b — layout-constancy.** Caret entering an HR paragraph caused a visible vertical jump because the locked design swapped the dashes from `NSFont.systemFont(ofSize: 0.1)` (line height ~0.1pt) to `bodyFont` (~21pt) AND swapped the paragraph style from `hrParaStyle` (paragraphSpacingBefore = paragraphSpacing = 16) to `baseParagraphStyle` (zero spacing). Net paragraph height collapsed by ~11pt on enter and reflowed on leave.

Unified the two states: dashes always render at `bodyFont`, only the foreground color toggles (body text color when caret is in, `NSColor.clear` when out). Same paragraph style in both states, computed once per sync pass from the base style with `paragraphSpacingBefore = paragraphSpacing = max(0, 16 - bodyLineHeight / 2)` — preserves Session 12's perceived 16pt visual margin around the drawn rule line at any font size while keeping total paragraph height constant. Replaced separate `applyHRHiding` / `revealHRDashes` with a single `applyHRDashAttributes(in:paragraphRange:bodyFont:foregroundColor:)`. The drawn rule (in `MarkdownTextLayoutFragment.drawThematicBreak`) sits at the line's typographic midY, which is now identical in both states — so the rule's geometric position relative to the dashes is unchanged whether they're visible or invisible.

**Files:** [`External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift`](../External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift) (scoped overload + unified hidden/revealed paths + computed paragraph spacing); [`NativeTextViewCoordinator+TextDelegate.swift`](../External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift) (capture `priorCaretLocation` before overwrite; switch caret-only path to scoped sync; skip when `tokensChanged` since `restyleTextView` already did a full walk).

**Decisions locked:**

5. **HR caret-aware reveal/hide must not cause vertical layout change.** Both states share line metrics + paragraph spacing; only dash color differs. Computed spacing `max(0, 16 - bodyLineHeight / 2)` keeps the ~16pt visual margin invariant at any font size.
6. **Dynamic-syntax services must scope per-caret-move work.** `syncHRVisibility` on `textViewDidChangeSelection` is the canonical example — only the prior + current caret paragraphs need touching. Full walks stay on `restyleTextView` and `rebuildTextStorageAndStyle` for events that can add/remove the construct anywhere.

#### Session 14 — 2026-05-21 (v0.2.7.4 Nexus folder adoption SHIPPED)

Obsidian-parity "open folder as Nexus." Both Nexus-open paths (`openPicked` from menu, `openExisting` from saved bookmark) now run `NexusAdopter.scan` after identity is established and present a preview-and-confirm sheet listing top-level folders → Vaults and direct sub-folders → Collections. Excludes only `.`/`_`-prefixed, `node_modules`, `.trash`, `Agenda`. Idempotent — fully-adopted Nexuses produce an empty plan and skip the sheet silently. Re-runs on every open catch newly-added folders (the indexer is the source of truth, not first-launch state).

`PageFile.loadLenient(from:nexusRoot:)` accepts `.md` files without Pommora frontmatter — synthesizes a stable `id` from `"adopted-" + sha256(relativePath).prefix(16)`, defaults tier/properties to empty, uses file `creationDate` for `created_at`. Critical invariant: does NOT write back. Files stay byte-identical until the user actually edits and saves. Used by both `ContentManager.loadAll(for:)` and the editor host (`PageEditorHost.swift:74`) — anything that surfaces in the sidebar also opens. `Filesystem.descendantFiles` makes Content discovery recursive; depth-≥2 folders aren't Collections but their files roll up to the nearest Collection ancestor.

`NexusManager.isIndexing` + `IndexingHUD` overlay in the sidebar give visible feedback during the scan. `pendingAdoption: AdoptionPlan?` + `withCheckedContinuation` route the sheet's user decision back into the async open flow; sheet auto-dismiss (Esc / click-outside) handled via `.sheet(item:onDismiss:)` calling idempotent `resolveAdoption(false)`.

**Architecture cross-check via Context7.** Pommora's Vault + `.nexus/` structure verified identical to Obsidian's Vault + `.obsidian/` shape. The one principled divergence: Vaults need `_vault.json` and Collections need `_collection.json` because Pommora has a per-Vault property schema concept Obsidian lacks. The indexer creates those sidecars on existing folders so the user doesn't have to.

**Cleanup pass post-implementation:** auto-dismiss continuation hang fixed; redundant `String.StringInterpolation` extension removed; manual `Equatable` on `AdoptionError` replaced with auto-synth; duplicate `childFolders` enumeration in `scan` merged; `apply`'s vault-id cache populated inline as we write instead of via a separate reload pass.

**Decisions locked:**

1. **Adoption runs on every open**, not just first-time init. Re-runs are idempotent and catch newly-added top-level folders (Obsidian-parity).
2. **Existing `.md` files stay byte-identical** until the user edits — lenient load synthesizes the id in memory only. Adopting a folder that's also an Obsidian vault doesn't mutate any notes.
3. **2-level structural depth** (Vault > Collection) preserved from the locked domain model; deeper sub-folders aren't Collections but their Markdown files roll up to the nearest Collection. No flattening of the model.
4. **Agenda stays as a sibling of Vaults** at `<nexus>/Agenda/`, not inside `.nexus/`. Files-are-canonical principle: user data lives at the user-visible root.

#### Session 13 — 2026-05-20 (v0.2.7.2 Lists shipped)

Lists rewrite: space styles immediately (styler-driven, no source mutation), Enter continues with the next marker, Shift+Enter exits with a plain `\n`, bare `-` / `1.` + Enter initializes. Source on disk is portable CommonMark (`- item` / `* item` / `+ item` / `1. item`) — pre-v0.2.7.2 `\t• ` engine-only syntax dropped (legacy files render via back-compat regex). Visual indent via styler paragraphStyle without source `\t`. Bullet glyph substitution (`-` → `•` visually) attempted + reverted (overlay produced invisible bullets); deferred as non-blocking cosmetic.

Pivots: Case 2 (empty-item exit) + Case 3 (mid-line continuation indent) dropped — Enter always creates a new list item; Shift+Enter is the only exit. Shift+Enter detection moved from `doCommandBy` (only fires on Ctrl+\) to a modifier-flag check at the top of `shouldChangeText`'s `\n` branch.

Bug noted: typed `<-` / `<->` don't transform to `←` / `↔` though typed `->` → `→` works (pasted versions render correctly).

Architecture + 4 new lessons in `Features/PageEditor.md → Dynamic-syntax pattern`. Deferred: bullet glyph, blockquote rendering, code & quote `Enter}` auto-completion, code-block red-text bug, arrow auto-format gap.

#### Session 12 — 2026-05-20 (v0.2.7.2 HR / divider SHIPPED via Obsidian-style dynamic syntax; Blockquote + Tables deferred)

**HR shipped** via a different architecture than the locked spec. Original plan attempted the locked design (custom `.pommoraThematicBreak` attribute + always-hidden dashes + cursor-out push + smart-backspace handlers); after four cascading bugs across two execution rounds, reverted to v0.2.7.1 baseline and replanned. Replanned design uses **Obsidian/Typora-style dynamic syntax** — caret on line shows `---`, caret off line hides dashes and draws the horizontal line. Establishes architecture for paragraph-level dynamic-syntax constructs. Full architecture + 8 lessons in `Features/PageEditor.md → Dynamic-syntax pattern`.

**Three engine files changed + one new file:** `MarkdownTextLayoutFragment.swift` — added `import Markdown`, AST-backed `hasThematicBreak` (Stage 0 code-block guard + Stage 1 prefilter + Stage 2 AST parse), `caretIsInFragment` (paragraph-start identity), rewrote `drawThematicBreak` with raw `separatorColor` + container-minus-padding width + stable `textLineFragments.first.typographicBounds.midY` Y anchor, wired into `draw(at:in:)`, extended `renderingSurfaceBounds` tightly (±3.5pt). `AppleASTSupplementalStyler.swift` — `visitThematicBreak` reduced to no-op (service is sole writer of HR attributes). `NativeTextViewCoordinator.swift` — added `isSyncingHRVisibility` reentry flag. `NativeTextViewCoordinator+HRVisibility.swift` (NEW) — caret-awareness service: walks document on every selection-change + post-restyle, applies `font 0.1 + clear color + paragraphSpacing 16/16` when caret is OUT of HR paragraph, restores body styling when caret is IN. Wired into `textViewDidChangeSelection` + `restyleTextView` + `rebuildTextStorageAndStyle`. `MarkdownInputHandler.swift` — preserved Nathan's `()` auto-pair (no HR-related additions; auto-transform DROPPED). `MarkdownListHandler.swift` — legacy HR expansion (`---` → 100-dash string on Enter) removed; incompatible with overlay approach.

**Pivots from locked plan:** 6-change plan reduced to 3 (`caretIsInFragment` + dynamic-syntax eliminated cursor-out push, smart-backspace handler, and caret-policy workaround in `NativeTextView+CaretWorkarounds`); auto-transform on 3rd dash + 4th-dash swallow DROPPED (per Nathan: Enter is natural trigger via dynamic syntax + CommonMark parsing of `---\n`); paragraphSpacing 16/16 (vs plan's 24/24) per Nathan; setext-underline guard added then removed — contradicted CLAUDE.md's "Pommora removed Setext H2 support" (`B\n---` must always render as HR per Obsidian/Typora); `.pommoraThematicBreak` attribute key kept as dead code (optional cleanup).

**Four hotfixes during execution:** (1) removed legacy `MarkdownListHandler` HR expansion (lines 245-267); (2) fixed renderer/service detection disagreement — moved setext + code-block guards into shared three-stage service check; (3) dropped setext guards from BOTH detectors per Nathan's clarification; (4) attempted `.rounded()` pixel-snap for first-HR-dimness; did NOT resolve; reverted (lesson #8: revert speculative fixes; don't pile on).

**Known caveat:** First HR renders slightly dimmer than subsequent HRs — likely sub-pixel anti-aliasing from first paragraph's fractional Y position. `.rounded()` pixel-snap didn't resolve. Documented in PageEditor.md; next investigation should test `NSScreen.backingScaleFactor`-aware half-pixel snap or explicit anti-aliasing disable.

**Deferred:** Blockquote (Phase 1) → next session, reuses dynamic-syntax architecture (Apple-Calendar-event-card target preserved); Tables (Phase 3) → "ASAP but not immediate" per Nathan (estimate revised to 10-15h after divider's 4h actual vs planned 45min); right-click "Insert HR" → future patch.

**Open follow-ups Nathan flagged:** (1) Lists improvements — Enter on bare `-`/`*`/`1.` should commit as list item (currently only space triggers); Shift+Space inserts new list item below at same nesting. (2) Blockquote — see above; reuses dynamic-syntax pattern.

#### Session 11 — 2026-05-20 (v0.2.7.2 page editor fixes plan LOCKED)

**No code commits.** Planning session sharpened across two rounds.

1. **NSTextTable rejected.** Exists since OS X 10.3 but never promoted to TextKit 2; Apple's TextEdit silently downgrades to TextKit 1 on table insertion (Krzyzanowski "TextKit 2: The Promised Land," Aug 2025). Adopting it forfeits Writing Tools, Look Up / Translate, spell-check, IME, dynamic system colors. **Core Graphics overlay drawn in `MarkdownTextLayoutFragment.draw` IS the 2026 Apple-native pattern.**

2. **HR cursor-atom behavior.** `---` source line stays in storage (needed for swift-markdown's ThematicBreak parse) but caret must never plant inside. `textViewDidChangeSelection` push-out (direction-aware, mirrors NSTextAttachment caret-skip); arrow keys skip past; smart-backspace from line below deletes `---\n` in one keystroke. Both interceptors guard against `isProgrammaticEdit == true`. Apple Notes parity.

3. **Structural context menu added** (Nathan: "add column / add row should be on the context menu and shouldn't open the popup"). Right-click in `.pommoraTable` range surfaces row/column add → in-place AST splice via `TableStructureRewriter` (Apple `MarkupRewriter`) + `Markup.format()` GFM emission. Matches Apple Numbers/Pages/Notes (no popover).

4. **Popover cell styling spec** for the Grid-hosted cell editors: `.textFieldStyle(.plain) + .focusEffectDisabled()` (`.plain` strips bg + border but NOT the focus ring); `.padding` (inner) → `.frame` (outer); `.contentShape(Rectangle())` (SwiftUI hit-tests intrinsic content, not explicit frame); `.onTapGesture` on the wrapper routes focus to the embedded TextField; `TextField(axis: .vertical)` with `.onKeyPress(.return)` (`.onSubmit` doesn't fire for vertical axis). Beyond: per-column `.multilineTextAlignment` from GFM `table.columnAlignments`; 1pt accent `.overlay` focus border; `NSCursor.iBeam` push/pop on hover.

5. **Blockquote target locked** as Apple Calendar event-card chrome (per Nathan's reference screenshot): grey rounded-rect card + accent bar inside at small leading inset. Multi-line blockquotes use per-fragment corner-rounding (`.only` / `.first` / `.middle` / `.last`) to render as one visually contiguous card. `BlockquoteMetadata { let sourceRange: NSRange }` attribute payload lets each fragment determine position without re-scanning storage.

6. **Version sequence locked:** v0.2.7.0 engine swap → v0.2.7.1 NavDropdown → v0.2.7.2 page editor fixes. Tables custom grid (was v0.2.7.3) absorbs into v0.2.7.2 Phase 3.

---

#### Session 10 (continued) — 2026-05-19 (v0.2.7.1 NavDropdown SHIPPED — simplified + cleaned)

Session 10 second half. Nathan: "this session produced lots of data layers, and code with lots of back-and-forth touch-ups that I'm still unhappy with." The v0.2.7.2 NavDropdown shipped earlier was functional but bloated — 22 commits of UIX iteration on standalone-window chrome + hover-heart favorites that didn't land where Nathan wanted.

**Scope cuts Nathan called for:** (1) remove standalone preview-window machinery entirely — feature-specific window plumbing rots; the real PreviewWindow is a cross-feature primitive (build once, light up per kind); (2) replace hover-heart favorites with right-click "Pin" context menu — rename Favorites → Pinned across class, file, JSON key, UI; (3) mid-session add: detail-view context menus on Page + Item rows inside Vault/Collection views don't work — fix in same patch.

**Ship summary:** standalone-window machinery stripped (deleted `EntityRef.swift`, `EntityWindowHost.swift`, `EntityRefTests.swift`, `WindowGroup(for: EntityRef.self)` scene; replaced `init?(entityRef:)` with `init?(stateRef:)`). Favorites → Pinned rename across `PinnedManager` + JSON key (`pinned`, with `favorites` backward-compat decode) + `EntityRow` (hover-heart removed; right-click "Pin" / "Unpin" instead). Click model: single-click selects in List, double-click opens via `.simultaneousGesture(TapGesture(count: 2))` (plain `.onTapGesture(count: 2)` gets intercepted by NSTableView's selection handler). Detail-view rows (`VaultDetailView`, `CollectionDetailView`) gained `.contextMenu` with Rename / Pin / Delete. Bypassed `AppGlobals.mainWindowRouter`'s `@Observable` hop for the dropdown (didn't propagate reliably from popover view host) — `NavDropdownButton` takes an `onOpen` closure that writes the parent's `@State sidebarSelection` directly. GitHub CI removed (`.github/workflows/ci.yml`).

**Version note:** committed/tagged `v0.2.7.1` despite chronologically following `v0.2.7.2`. `v0.2.7.2` stays in git history as "first NavDropdown attempt (functional but UIX-deferred)"; v0.2.7.1 is canonical shipped NavDropdown.

**New architectural rule:** `Guidelines/CRUD-Patterns.md → Preview-window prerequisite` — the PreviewWindow primitive ships per kind before any "open in preview" UI for that kind. CRUD lands independently (deleted EntityWindowHost is the cautionary tale).

---

#### RC Session — 2026-05-19 (v0.3.0 Properties brainstorm + spec)

**No code commits.** Docs + planning session that locked the v0.3.0 Properties shape before implementation.

**Locked decisions** (carried forward into the shipped v0.3.0 work): 10-type property catalog (number / checkbox / date / datetime / select / multi-select / URL / relation / **status** / **last edited time**); Status type with 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done — group labels renamable, slots structural); relation scope: Vault / Collection / Context-tier (no `.anywhere`), mandatory dual for Vault/Collection; no inline option creation — schema editor only; property icons (SF Symbol per property); Vault Settings sheet as central edit surface; Vault templates rejected in favor of post-v1 content templates; move-strip pulled v0.4.0 → v0.3.0 (tightly coupled to schema); AgendaSchema migration shim for built-in Status injection on legacy schemas; SchemaEditorRouter `@Observable` for shortcut routing.

---

#### Session 9 — 2026-05-18 (v0.2.7.0 SHIPPED — native TextKit 2 editor)

Native TextKit-2 Page editor shipped on `origin/main` at `9a0b383`, tagged `v0.2.7.0`. After Phase A-G of the Pallepadehat WKWebView fork failed Nathan's visual baseline, demo of `nodes-app/swift-markdown-engine` sealed the pivot. Session stripped the fork, vendored the engine, wired Pommora's editable title + body-binding chain, added UX polish driven by Nathan's first-look feedback.

**Ship summary:**
- Pallepadehat fork stripped (pbxproj entries + Package.resolved pin + `network.client` entitlement + External/PageEditorMD/ clone removed).
- `swift-markdown-engine` vendored at `External/MarkdownEngine/` (Apache 2.0, local Swift Package). Apple swift-markdown 0.8.0 added as SPM dep. Minimal Swift-6 patches to engine sources (`@MainActor` on Input/Styling struct types + `nonisolated` overrides with `MainActor.assumeIsolated` bodies on `MarkdownTextLayoutFragment`).
- PageEditorView body swapped to `NativeTextViewWrapper`; editable title TextField preserved exactly.
- Character-pair auto-pair (`**`/`__`/`[[`/`` ` ``) added to engine's `MarkdownInputHandler`; auto-unpair on backspace (`*|*` / `**|**` / `[[|]]` / `` `|` `` backspace deletes both halves as single undo step).
- **Apple-AST supplemental styler**: walks `Document(parsing:)` AST for BlockQuote/Strikethrough/Table/ThematicBreak (the GFM block types the engine's regex tokenizer doesn't cover). Composes additively on top of primary `MarkdownStyler`.
- **Expanded right-click menu**: Format (Bold/Italic/Strikethrough/Inline Code/Link) + Heading (H1-H4) + Lists (Bullet/Numbered) + Block submenu (Blockquote/Code Block/Table/Horizontal Rule). H5/H6 removed (render smaller than body text).
- **HR-as-real-line**: `---` renders as 1pt full-width horizontal line via custom `MarkdownTextLayoutFragment.drawThematicBreak` (dashes hidden via font-0.1 + clear foreground; range tagged with `.pommoraThematicBreak`). **Table source markup hidden**: pipes + separator row invisible (cell content styled). **Enter on title → body focus**: `focusBodyEditor()` walks `NSApp.keyWindow.contentView` for first NSTextView and makes it first responder.
- Title focus via `@FocusState` (`titleFocused = false` on submit before `focusBodyEditor()` so TextField cleanly relinquishes focus).

**Plan deviations:** engine vendored at `External/MarkdownEngine/` as a local Swift Package (plan said `Pommora/Pommora/PageEditor/Engine/` raw) — package boundary isolates the engine's Swift 5.9 concurrency contract from Pommora's Swift 6 strict-concurrency + ExistentialAny. AST tokenizer/styler rewrite (Phase 3) deferred to v0.2.7.1; engine ships with its existing regex-based tokenizer.

**Carried to v0.2.7.1:** AST tokenizer/styler rewrite; selection-wrap auto-pair + auto-exit; split Pages.md editor-UX content into `Features/PageEditor.md`; `PommoraWikiLinkResolver` conformance to engine's `WikiLinkResolver`.

#### Session 7 — 2026-05-18 — v0.2.7 Phase A-G ship + Milkdown pivot (later superseded)

SPM dep on Pallepadehat fork → full domain layer + 10 tests → editor wires end-to-end → polish iterations post-smoke → Phase G fork-side polish (drop active-line, custom fold chevron, `markdown-autopair.ts`, Apple typography overhaul SF Pro Text/Display/Mono 28/22/17/15/13/13pt, triple-clear transparent-bg `!important`). Nathan smoke-tested Phase G; visual baseline still didn't ship Notion-like polish — decision to swap to Milkdown + Crepe (Crepe `frame` theme as default; vendor wrapper as source inside Pommora's tree, not SPM dep). Session 8 reconsidered both and pivoted again to native TextKit-2 — see Session 9.

**Survives swap (verified preserved across both pivots):** PageRef, PageFile, PageMeta, ContentManager.updatePage, PageEditorViewModel, PageEditorHost, AppGlobals, AppState.pageInspectorOpen, Pommora.entitlements, title-banner VStack + `.inspector` pattern.

**Quirk added (#13 in `CLAUDE.md`):** branch-pinned SPM forks don't bump via gentle `xcodebuild -resolvePackageDependencies` — need full nuke of `Package.resolved` + `DerivedData/.../SourcePackages` + `~/Library/Caches/org.swift.swiftpm/repositories/<DepName>-*`.

#### Founding decisions (2026-05-16…18) — superseded

The original by-area founding-decisions block (Stack / Architecture / Domain Model / Storage / Property Model / Editor / Sidebar + Shell / Views / Scope / Design System) is removed. It described an earlier model and is no longer current truth — the live state lives in `// Features//Domain-Model.md`, `// Features//Properties.md`, and `// Features//Architecture.md`; the SwiftUI stack lock and editor direction in `PommoraPRD.md` + `// Features//PageEditor.md`. Two facts from that era are recorded as dated entries below: the SwiftUI stack lock and the 2-layer domain model (revised 2026-05-16, replacing the earlier 3-entity model).

#### Features Implemented

**v0.0 — Shell opens.** Two-column `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)`. Sidebar (240 default, drag-resizable) + main pane (`EmptyPane` — `windowBackgroundColor` fill) + pop-out inspector (280 default, hidden by default). Inspector toggle: `sidebar.trailing` SF Symbol at `.primaryAction` inside the `.inspector { … }` closure, wrapped in `withAnimation(.smooth(duration: 0.30))`. Sidebar collapse via system `≡` (`NSSplitView` native animation). View menu's "Show Inspector" via `InspectorCommands()`. Window 1440×810 default, 960×560 min. Title suppressed via `.windowToolbarStyle(.unified(showsTitle: false))`. `NSSearchField` via `NSViewRepresentable`, anchored to `.safeAreaInset(.top, spacing: 8)` — preserved into v0.1a. The placeholder sidebar Sections shipped in v0.0 were replaced by real folder content in v0.1a.

**v0.1a — Nexus Foundation.** Sandboxed picker, security-scoped bookmark persistence, hidden `.nexus/` folder init, sidebar mirroring user-picked nexus folder.

- **Sandbox** via `ENABLE_APP_SANDBOX = YES` + `ENABLE_USER_SELECTED_FILES = readwrite` (Xcode 15+ auto-generates entitlements plist; no separate `.entitlements` file). Verified via `codesign -d --entitlements -`.
- **Code structure:** single app target; `Nexus/` and `Sidebar/` auto-included by Xcode 16's `PBXFileSystemSynchronizedRootGroup`. Files: [`Nexus`](Pommora/Pommora/Nexus/Nexus.swift), [`NexusManager`](Pommora/Pommora/Nexus/NexusManager.swift) (@Observable @MainActor), [`NexusBookmark`](Pommora/Pommora/Nexus/NexusBookmark.swift), [`NexusStore`](Pommora/Pommora/Nexus/NexusStore.swift), [`NexusIdentity`](Pommora/Pommora/Nexus/NexusIdentity.swift) (Codable `nexus.json`), [`AppState`](Pommora/Pommora/Nexus/AppState.swift) (Codable `state.json`), [`ULID`](Pommora/Pommora/Nexus/ULID.swift) (inline spec-compliant generator), [`FolderTree`](Pommora/Pommora/Nexus/FolderTree.swift), plus [`SidebarNode`](Pommora/Pommora/Sidebar/SidebarNode.swift), [`SidebarRow`](Pommora/Pommora/Sidebar/SidebarRow.swift), [`SidebarView`](Pommora/Pommora/Sidebar/SidebarView.swift) (`List` with recursive `OutlineGroup`).
- **Init flow:** existing `.nexus/` → load `nexus.json`. Empty folder → silent init. Non-empty → confirm dialog. `NSOpenPanel` defaults to `~/PommoraNexus/` if exists, else `~/`.
- **State separation:** machine-specific bookmark at `~/Library/Application Support/com.nathantaichman.Pommora/state.json`; vault-portable identity at `<nexus>/.nexus/nexus.json`; nexus-portable user state at `<nexus>/.nexus/state.json` (deferred to v0.2+).
- **Per-nexus DB path** reserved at `App Support/.../nexuses/<nexus-id>/nexus.db`; marked `isExcludedFromBackupKey = true`. DB created by GRDB in v0.2.
- **Menu commands:** File → Open Nexus… (⌘O); Debug → Reset Nexus Bookmark (DEBUG-only).
- **Tests:** 25 unit tests across `ULIDTests`, `AppStateTests`, `NexusIdentityTests`, `NexusStoreTests`, `FolderTreeTests`.
- **Stylistic UI copy intentionally absent** per direction — no welcome screens, error alerts, empty-state descriptions, NSOpenPanel customizations. Design pass adds these.

Design + 4 implementation Findings preserved at [.claude/Planning/v0.1-nexus-foundation-design.md](.claude/Planning/v0.1-nexus-foundation-design.md).

**Post-v0.1a sidebar visual scaffolding pass.** Sidebar UI swapped from FolderTree-driven to hardcoded placeholder Sections (3 loose Items + Spaces section × 3 entries + Collections section with 3 collection-folders × 3 placeholders each) to iterate on selection language without real-data noise. New private `SelectableRow` view consolidates icon + text + tap selection + selection chrome. `FolderTree` / `SidebarNode` / `SidebarRow` remain in the target but dormant — re-wire when de-scaffolding. `EmptyPane` removed from `ContentView`; detail closure is bare `Color.clear`. Inspector toggle stays in `.inspector { ... }.toolbar { }` per the v0.0 UIX-Guide direction (the toolbar-move experiment from commit 807057d was reverted in-session). Pommora-specific selection language documented at `// Features//Sidebar.md`.

**Paradigm scaffolding — branch `paradigm-scaffolding`, session 1 (2026-05-16).** Tasks 1-44 of 65 from `// Planning//Paradigm-Scaffolding-Tasks.md` shipped on a feature branch, plus 4 cleanup commits — 48 total. Data layer is feature-complete for v0.2: every entity in the locked paradigm (Space / Topic / Sub-topic / Vault / Collection / Item / Page / AgendaItem / AgendaSchema / Recurrence / Homepage / TierConfig / SavedConfig) has Codable, validator, and `@MainActor @Observable` manager. Swift 6 strict concurrency + ExistentialAny upcoming feature both enabled (flipped Task 1). Yams 5.4.0 added via SPM (Task 2). All custom Codable signatures use `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)` and all manager `pendingError` fields use `(any Error)?` per cleanup sweeps. UI tier (sidebar replacement + sheets + detail pane + Item Window + ContentView wiring) is Tasks 45-65, deferred to session 2.

Paradigm-solidifying decisions confirmed during session 1 (registry at `// Guidelines//Paradigm-Decisions.md`):
- **`PropertyValue.relation` encodes as tagged JSON object `{"$rel": "<ULID>"}`** — not bare string. Makes relation edges legible to external agents + graph-view indexer without consulting Vault schema; satisfies load-bearing constraint #3.
- **Collections persist a minimal `_collection.json` sidecar** with `{id, vault_id, modified_at}` — Collection is now Codable (no longer pure folder); parent-Vault relation is explicit on-disk property. Supersedes the original spec's "no metadata file" design.
- **SF Symbol picker = `xnth97/SymbolPicker` SPM dep, wrapped behind Pommora's `IconPickerSheet`** — wrapper isolates third-party API; swapping libraries is a single-file rewrite.

A new operating protocol installed in `// Guidelines//Paradigm-Decisions.md`: future paradigm-solidifying choices (on-disk schemas, wire encodings, defaults that lock once data exists, file-layout choices, cross-entity contracts, error semantics, identifier conventions) MUST surface via confirmation BEFORE the code lands, not after-the-fact.

**Paradigm scaffolding — branch `paradigm-scaffolding`, session 2 (2026-05-17).** Tasks 45-65 shipped (21 commits, **69 total ahead of `main`**). UI tier end-to-end: SidebarSheet + SidebarConfirmation enums; SidebarView four-section layout (Saved / Spaces / Topics / Vaults) with SelectionTag; 5 row views (SpaceRow / TopicRow / SubtopicRow / VaultRow / CollectionRow + ParentSpaceTags); 10 sheets (NewSpace / NewTopic / NewSubtopic / NewVault / NewCollection / NewPage / NewItem / EditTopicParents / SpaceColorPicker + ColorPickerSheet / IconPickerSheet wrapping SymbolPicker); detail-pane tier (ContentItem + DetailRow + ContextDetailPlaceholder / VaultDetailView + CollectionDetailView with native `Table(_:children:)` / SidebarDetailView dispatcher); ItemWindow tier (MultiSelectChips + FlowLayout / PropertyEditorRow / ItemWindow popover with title + icon + description + property editors + tier1/2/3 read-only); ContentView 8-manager wiring with real `contextProvider` closures via in-body snapshot-capture. **177 tests, 0 failures, 0 warnings, entitlements verified.** SymbolPicker 1.6.2 via SPM.

Four-commit cleanup plan queued for session 3: dead-code purge (`SheetStubView` + v0.1a FolderTree trio); sidebar UX restructure per right-click-context-menu direction + row commit() draft-loss fix; Pages-under-Vaults/Collections sidebar disclosure; atomicity + error-surfacing (6 rename sites, pendingError-on-CRUD, AgendaManager orphan fix, PageFrontmatter required-id, validators trim consistency, ContentView initial-construction race, AtomicYAMLMarkdown force-unwrap, VaultDetailView modifiedAt, ItemWindow applyDraft helper).

Paradigm-solidifying decisions session 2 (appended to `// Guidelines//Paradigm-Decisions.md`):
- **Stub-and-progressively-replace execution strategy.** For branch-spanning plans with forward-dependencies, write each task with throwaway in-file stubs for not-yet-shipped types; later tasks replace stubs in-place. Every commit ships green standalone, independently verifiable. Supersedes spec's batch-commit-at-end (uncommitted 12-task blobs where any single break contaminates the batch).
- **Sidebar UX direction.** All "+ New" removed from sidebar; replaced by **right-click context menus location-scoped to the cursor** (right-click Vault row → "New Collection / New Page" bind to THAT Vault; right-click Collection row → "New Page" binds to THAT Collection). Saved Section keeps wrapper for future pinned items but loses literal "Saved" header — renders as heading-less group at top. **Pages appear in sidebar** under parent Vault (root) or Collection with `doc.text` icon (click no-op until v0.3 editor). **Items, Agenda items, Events do NOT appear in sidebar** — only detail-pane Tables. Hover-icon "+" on section headings skipped; quick-capture (Cmd+Shift+N / menu-bar) absorbs most CRUD entry before v1.

The React+Electron-locked v0.0 spec is preserved at `// ReactInfo// v0.0.md` for contingency.

**Paradigm scaffolding — branch `paradigm-scaffolding`, session 3 (2026-05-17/18) — cleanup + UX polish + Commit 4.** All 4 planned cleanup commits shipped + a longer-than-planned sidebar polish iteration sequence.

Commits shipped:

1. **`1343e50`** — Dead code purge: `SheetStubView` + v0.1a folder-tree trio (`FolderTree` / `SidebarNode` / `SidebarRow` / `FolderTreeTests`).
2. **`c8dbac6`** — Sidebar UX restructure: right-click context menus replace 5 "+ New" buttons; preserve rename drafts on error; new `SidebarSheet.newPageInVault(vault:)` case; section-area `Color.clear` hit-test rows (later replaced).
3. **`02da8ff`** — Pages-in-Vault-root + show Pages in sidebar under Vaults/Collections: `ContentManager` gained `pagesByVaultRoot` / `itemsByVaultRoot` storage + `pages(in vault:)` / `items(in vault:)` accessors + 4 `(inVaultRoot vault:)` CRUD overloads; new `PageRow` (non-selectable leaf, `doc.text` icon); new `PageParent` enum.
4. **`1a84a5f`** — Sidebar regressions fix: restore full-row click via `Spacer(minLength: 0)` + `.frame(maxWidth: .infinity)` + `.listRowInsets`; restore section disclosure chevrons via `Section(isExpanded:) { } header: { SectionHeader(...) }`; replace empty `Color.clear` hit-test rows with custom `SectionHeader` containing `+` button + context menu.
5. **`64e6cd8`** — Sidebar polish: hover-only `+` button via `.opacity(hovered ? 1 : 0).animation(.easeInOut(duration: 0.12))`; selection chrome on DisclosureGroup-wrapped rows via in-content `.background` (later reverted); `SelectableRow` becomes generic `SelectableRow<Trailing: View>` with trailing slot for TopicRow's `ParentSpaceTags`.
6. **`9971a35`** — Sidebar fixes batch: SF Symbol picker via new `IconPickerField` (wraps `SymbolPicker` directly, bypassing `IconPickerSheet`'s manager-routing) wired into all 4 Create sheets; `SpaceColor.accent` case added; renamingRow in all 6 row files keeps icon visible (only text editable); `.onChange(of: renameFocused)` with `isCommitting` guard auto-cancels rename on click-off without blocking Enter-commit.
7. **`2d707a0`** — Atomicity rollback + pendingError-based error surfacing + 8 small fixes + 4 Commit-3 reviewer carryovers: new `RenameAtomicityError`; rollback at 8 rename sites; all 8 managers wrap CRUD in `do/catch` setting `pendingError`; new `SidebarToast` view observes 5 managers' `pendingError`, renders dismissable banner above List; replaced silent `try?` calls in SidebarView delete handlers + IconPickerSheet + ColorPickerSheet + PageRow delete; `PageFrontmatter.id` required-decode; `AgendaManager.updateItem` refuses title changes (extracted `renameAgendaItem`); `VaultDetailView` uses `coll.modifiedAt`; `ContentView.onChange(initial: true)`; 8 validators trim consistency; `AtomicYAMLMarkdown` UTF-8 throws; `ItemWindow.applyDraft` helper; `ContentManager` split into `ContentManager.swift` + `ContentManager+CRUD.swift` (storage + load in main; 13 CRUD methods in extension); `existingInCollection:` → `existingSiblings:` rename; `@discardableResult` symmetry on Collection-scoped create methods; PageRow's `confirmingDelete` binding dropped; +5 new tests (`RenameAtomicityTests` + AgendaManager rename tests).
8. **`3657cad`** — Launch crash fix: `ContentView`'s sidebar branch missing `.environment(contentMgr)` injection. Commit 3 added `@Environment(ContentManager.self)` reads to VaultRow/CollectionRow/PageRow but parent never injected — Commit 2b's section restructuring shifted diff traversal timing enough to surface as `EXC_BREAKPOINT in EnvironmentValues.subscript.getter` via `OutlineListCoordinator.recursivelyDiffRows`. Bisected via parallel test runs at 3 SHAs. One-line fix.
9. **`838b063`** — Accent swatch polish: rainbow `AngularGradient` for `SpaceColor.accent` (matches macOS Finder Multicolor tag) + 5x2 fixed-column grid for the now-10 options.
10. **`8fe91d7`** — Detail-pane fixes: `SidebarDetailView` gained `.sheet(item: $presentedSheet)` so detail-pane "+ New Collection / New Page / New Item" buttons actually present sheets (Nathan's ContentView edit passed binding but no `.sheet` wired); `VaultDetailView` rows now include vault-root Pages + Items as top-level rows; `VaultDetailView.task` loads vault-root content; `SavedSection` dropped `header: { EmptyView() }` (was reserving height, creating top gap under search bar).
11. **`ae8280d`** — Restored `.listRowBackground` for sidebar selection chrome: removed `SelectableRow`'s in-content `.background`; added `SelectionChrome` view rendering `RoundedRectangle.fill(...).padding(EdgeInsets(top: 2, leading: 11, bottom: 2, trailing: 11))`; each row applies `.listRowBackground(SelectionChrome(isSelected: ...))` at body root. Attempted asymmetric `.disclosure` style (leading 0 to cover chevron); reverted to symmetric `.flat` (both 11pt).
12. **`576d933`** — Sidebar geometry consistency: HStack spacing 10 → 8 in SelectableRow + 6 renamingRow blocks; Image `.font(.system(size: 14, weight: .regular))`; `.frame(width: 16, height: 16, alignment: .center)` centers glyphs in fixed box so text always starts at same X; renamingRow geometry mirrors SelectableRow.
13. **`8cc492b`** — Symmetric chrome for disclosure rows: TopicRow / VaultRow / CollectionRow `SelectionChrome` switched from `.disclosure` (leading 0, trailing 11) to default `.flat` (11pt symmetric) so corners have matching radius. Trade-off: chevron may sit outside chrome's left edge in some widths; revisit via hand-rolled chevron if visually wrong.
14. **`0bc4c8d`** — Selection polish: Nathan-tweaked chrome opacity (0.11 → 0.10) and text brightness (0.12 → 0.10) for subtler selection.

Plus a parallel SpaceColorPicker tweak (made `color` binding optional + tap-toggle-deselect) shipped via Nathan's separate session — captured in the working-tree handoff state.

**Paradigm-solidifying decisions added during session 3** (appended to `// Guidelines//Paradigm-Decisions.md`):

- **Sidebar selection chrome via `.listRowBackground` at row file level.** Locked after the long polish iteration. `Color.gray.opacity(0.10)` fill, 6pt continuous corner radius, symmetric 11pt horizontal + 2pt vertical inset, text brightness 0.10, icon no brightness, HStack content spacing 8pt, icon column 16x16 centered at 14pt glyph size, row content padding 4pt leading / 0 trailing / 6pt vertical. Chrome applied at each row file's body root (DisclosureGroup itself for wrapped rows; row body for flat rows + Saved items per iteration) so it covers the chevron gutter. SelectableRow keeps no chrome — purely content. `SectionHeader` (private struct in SidebarView) renders a secondary-styled title + hover-only `+` button via `.opacity(hovered ? 1 : 0).allowsHitTesting(hovered).animation(.easeInOut(duration: 0.12))` (opacity not conditional rendering to avoid layout shift); right-click context menu surfaces "New X" regardless of hover.

- **Pages editor stack: Tiptap (ProseMirror) in WKWebView, MarkEdit-pattern native shell, vanilla TypeScript bundle.** Closes the long-running Option 1 (native NSTextView) vs Option 2 (WKWebView + JS editor) question. WYSIWYG editing locked over Live Preview at Nathan's direction — typing `**bold**` becomes **bold** instantly, no markers visible. Markdown round-trip via `@tiptap/markdown` (per-node serializers; near-perfect not byte-perfect). `:::callout` and `:::columns` / `@Columns` directives via custom Tiptap `Node.create`. Roadmap reordered: Pages moves from v0.6/0.7/0.8 to v0.3 (internal phases a/b/c); Tabs become v0.4; Properties v0.5; infrastructure cycles shift to v0.6+. Pages open in detail pane (single Page at a time) in v0.3; tabs ship at v0.4. Standalone-window-via-context-menu / `⌥⌘O` path works in v0.3a via `WindowGroup(for: PageRef.self)`. Full implementation spec at `// Planning//Page-Editor-Plan.md`.

**Merge strategy locked: full history** (non-fast-forward merge commit preserving all 82 commits). Bisect-value-preserving — already paid off twice this session (locating the launch crash, finding SidebarToast issue).

**Known UX gap flagged at session end (2026-05-17):** Item creation affordance is buried — only `CollectionDetailView`'s footer offers "+ New Item"; not in VaultDetailView footer, not in any sidebar context menu. Fix is small (~3 button additions across detail views + row context menus); deferred to pre-v0.3 polish or rolled into v0.3a prep. Sidebar.md table to be updated to reflect the new affordance once added.

**Nathan-sketched "New Item" window design (v0.5 design intent)** captured at `// Features//Items.md` "Item window — design evolution" section. Modal window with 2-column layout (description body LEFT, property dropdowns stacked RIGHT), Delete (red, edit-only) + Save (blue primary) footer, title bar with icon-picker + view-toggle affordances top-right. Supersedes current v0.2 Spartan ItemWindow popover; lands with v0.5 Properties.


---

#### Session 4 — 2026-05-17 end (audit + semver + v0.2.1 / v0.2.2 / v0.2.3 to main)

Long session covering Framework audit + semver conversion + Pages/Tabs reorder + three patches landed on main.

**v0.2.0 merged to main (e3daedb):** the paradigm-scaffolding 83-commit branch merged via `git merge --no-ff` preserving full history. Pushed to `origin/main`.

**Framework audit + reorders (locked end-of-session):**

1. **Pages + Tabs ship as v0.2.x patches, NOT v0.3.0/v0.4.0 minors.** Restructured: v0.2.7 = Pages editor (prose + standard Markdown), v0.2.8 = Tabs, v0.2.9 = directives + heading fold + slash menu, v0.2.10 = wikilinks + rename cascade. Order between v0.2.7 and v0.2.8 is interchangeable. v0.3.0 becomes Properties — the next substantial capability after Pommora is writable + multi-instance.
2. **Editor library NOT solidified.** Tiptap was previously locked in `// Planning//Page-Editor-Plan.md`; demoted to "leading candidate" end-of-session. Final pick reopens at v0.2.7 implementation start. Architecture (WKWebView + 7-message bridge + MarkEdit pattern) stays stack-agnostic.
3. **Agenda UI ships hand-in-hand with EventKit at v0.6.0** — not split. Earlier in the session an Agenda-UI-at-v0.5-split was considered; reverted end-of-session.
4. **SQLite + Watcher at v0.4.0** (was v0.8.0); **Vault views at v0.5.0** (was v0.10.0); **v0.6.0 consolidates** EventKit + Agenda UI + accessibility + performance + onboarding + Settings + accent customization. v0.11/v0.12 dissolved.
5. **`.trash//` data layer at v0.2.5**, in-app Trash UI window at v0.4.0.
6. **Semver format locked:** `major.minor.patch`. Minor = completed feature; patch = touch-up or addition; major reserved for v1.0.0. Internal phases like `v0.3a/b/c` retired.

**Three patches shipped to main (in order):**

1. **`3bcf328` — v0.2.1: Parallel-session sidebar UX tweaks + page selection wiring.** 16 Swift files (Detail / Sidebar / Sheet polish from the parallel Claude session) including `case page(PageMeta)` selection wired + a `PageDetailView`-style placeholder in `SidebarDetailView` ("Page editor coming v0.6" — stale version string, fix in v0.2.6 spec catch-up).
2. **`2e140ed` — v0.2.2: CodeRabbit tightening.** `ItemWindow.swift` refetch-after-rename recovery (`await contentManager.loadAll(for: coll)` + `dismiss()` on still-missing-after-reload) + 2 `ContentManagerTests` filesystem assertions (`renameItem` verifies old URL gone + new URL exists; `deletes` verifies files gone from disk).
3. **`56efd68` — v0.2.3: CI baseline.** `.github/workflows/ci.yml` running `xcodebuild build` + `xcodebuild test -only-testing:PommoraTests` on `runs-on: macos-26`, triggered by push to ANY branch + PRs targeting `main`. Cherry-picked from `v0.2.3-ci` branch (snapshot ref `b746481`). First push will smoke-test runner availability; fallback is `macos-latest` + explicit Xcode 26 path.

**Quirk #4 corrected:** `.claude/*` IS included in commits. The prior "don't stage .claude/* unless explicitly asked" rule prevents unilateral doc bundling into Swift commits, but explicit doc commits are expected so branch switches preserve doc visibility (caught when Claude stashed accumulated docs before a branch switch and Nathan saw the docs revert).

**Item Window v0.5 redesign now targets v0.3.0:** was slotted with Properties at v0.5.0; Properties moved to v0.3.0, redesign comes along.

---

#### Session 5 — 2026-05-18 (v0.2.4 → v0.2.6 shipped)

Three patches landed on `main`:

1. **`60e2ef6` — v0.2.4: swift-format baseline.** `.swift-format` config at repo root (lineLength 120 / 4-space indent / `respectsExistingLineBreaks: true` / `OrderedImports: true` / `NeverForceUnwrap: false` to honor `try!`). One-time formatter pass over 97 Swift files. CI `swift format lint --strict --recursive` step. Fixed two pre-existing `OneCasePerLine` violations in `Recurrence.swift` since the formatter can't auto-fix that rule.

2. **`9f56fbe` — v0.2.5: `.trash//` data foundation.** New `NexusPaths.trashDir(in:)`, `Filesystem.moveToTrash(_:in:)` (@discardableResult, preserves deleted entity's relative path under nexus root, creates intermediate `.trash` dirs, resolves collisions via timestamp + 4-char hex discriminator suffix → `Notes.20260518-093215-A3F2.md`), `FilesystemError.sourceNotInNexus` case. Swapped 10 manager delete call-sites to route through trash. `.trash//` lives inside the nexus (syncs with iCloud/Dropbox as user data), unlike the regeneratable SQLite index.

3. **`7b17d1d` — v0.2.6: Spec catch-up.** Aligned 5 in-app `Text(...)` version strings to the Framework reorder (e.g., "Property-panel relation editor coming v0.5" → "Property panel coming v0.3.0"). Doc passes on `Pages.md` (Tiptap softened to "leading candidate") + `Sidebar.md` (hover-icon `+` complement instead of quick-capture-only).

**Project quirk added (#12):** `swift format` invoked as subcommand (`swift format format`, `swift format lint`) via Xcode 26's bundled toolchain. Direct `swift-format` binary not on `$PATH`. CI uses same form. Locked at v0.2.4.

---

#### Session 6 — 2026-05-18 (editor library re-evaluation, no code)

Research session reopening the editor library decision. Nathan confirmed Live Preview (Obsidian/Bear marker-fade-by-proximity) AND pure WYSIWYG both acceptable — "as long as Markdown syntax isn't always visible and the page looks like a page rather than a file." Removes the constraint that drove Tiptap-over-CodeMirror earlier.

**Native framework gaps surfaced:**
- TextKit 2 has no native `NSTextTable` support; an `NSTextTable` in attributed string triggers fallback to TextKit 1 (disabling `NSTextAttachmentViewProvider`). Workaround: render tables via `NSTextAttachment` / `NSTextAttachmentViewProvider`, never `NSTextTable` — fallback isn't triggered by "document contains table syntax," only by NSTextTable instances in storage.
- No multi-column inline layout API in TextKit 2 — `@Columns` requires custom rendering.
- `swift-markdown` lacks first-class custom-directive parsing (post-parse traversal handles `:::callout` / `@Columns`); DOES provide source-range tracking critical for decoration efficiency.

**Three options listed in `Page-Editor-Plan.md`:** Native Swift (TextKit 2 + `swift-markdown`, optionally wrapping `nodes-app/swift-markdown-engine`); JS editor + WKWebView shell (Tiptap / Milkdown / BlockNote); fork `Pallepadehat/MarkdownEditor` (CodeMirror 6 + WKWebView). `.md` is the firewall — user data portable across all transitions.

Decision #7 (Tiptap leading direction) superseded by the three-option inventory.

---

#### Session 7 — 2026-05-18 (continued — Phase A-G of v0.2.7 + Milkdown decision)

Nathan picked Option 3 (fork Pallepadehat); shipped Phase A through Phase G of v0.2.7 across 11 commits on `main` + 3 commits on the fork at `Natertot215/PageEditorMD`. End-of-session smoke test failed Nathan's visual baseline despite extensive Apple typography overhaul; decision to swap to Milkdown + Crepe (later superseded by Session 8).

**Code shipped (11 commits, `1df93a6` → `1989fac`):**

- **Phase A** — SPM dep on Pallepadehat fork.
- **Phase B** — Domain layer: `PageRef` (Codable+Hashable ID-based for `WindowGroup(for:)`), `ContentManager.updatePage(_:body:in:vault:)` + vault-root variant (body-only writes, frontmatter preserved verbatim via `PageFile(...).save(to:)` → `AtomicYAMLMarkdown.write` → atomic temp+rename), `PageEditorViewModel` (300ms debounce, `flushNow`/`close`/`explicitSave`/`clearError`, `PageSaver` protocol + `ContentManagerPageSaver`), 10 new tests + Nathan's icon migration.
- **Phase C1-C5.2** — Inspector wiring + sandbox entitlements (4 keys including `network.client` for WKWebView), `AppGlobals` (NSHashTable<PageEditorViewModel> registry + willResignActive + willTerminate observers), `AppState.pageInspectorOpen` per-Page persistence (v1→v2 backward-compat decoder), `FrontmatterInspector` (read-only Form), `PageEditorView` + `PageEditorHost` (`.task(id:)` page-switch flush + `.id()` re-keying), editable title `TextField` (28pt bold, plain, commit → `ContentManager.renamePage`), inspector at NavigationSplitView level with toolbar `ToolbarItem(placement: .primaryAction)` INSIDE `.inspector(...)` closure (fixes left-side placement), sidebar page-switching fix (`@State var viewModel` → `@Bindable` + `.id(vm.page.id)`).
- **Phase G** — Fork polish: drop active-line, custom fold chevron, `markdown-autopair.ts` for `**`/`__`/`[[`/`` ` ``, Apple typography (SF Pro Text body + SF Pro Display headings + SF Mono code; 28/22/17/15/13/13pt), triple-clear transparent-bg (`drawsBackground=false` KVC + `underPageBackgroundColor=.clear` + NSView layer bg + CSS `!important`), Pommora-side `.background(Color.clear)` defensive layer.

**Smoke test verdict (Nathan):** Phase G's overhaul still didn't produce Notion-like polish. Decision to swap editor library to Milkdown + Crepe.

**Project quirk added (#13 in `CLAUDE.md`):** SPM branch-pinned forks need full cache nuke to bump (gentle `xcodebuild -resolvePackageDependencies` respects pins). Nuke `Package.resolved` + `DerivedData/.../SourcePackages` + `~/Library/Caches/org.swift.swiftpm/repositories/<DepName>-*`.

---

#### Session 8 — 2026-05-18 (architecture pivot to native TextKit 2 + swift-markdown-engine, plan-only)

Plan-only session. Nathan reconsidered the Milkdown direction after demoing `nodes-app/swift-markdown-engine` (Apache 2.0, native TextKit 2). The native-Mac feel made the call.

**Architecture locked** (shipped at v0.2.7.0 in Session 9):
- **Parser:** Apple `swift-markdown` (full GFM AST + `BlockDirective` + source-range tracking).
- **Renderer:** Apple `NSAttributedString` + `NSTextView` + `NSTextLayoutManager`. Writing Tools (15.1+), Look Up / Translate / spell-check, IME, dynamic system colors, drag-select all free.
- **Live-preview chassis:** `swift-markdown-engine` vendored. Two load-bearing engine contributions: **dynamic syntax** (markers shrink when caret leaves AST node — Bear/Notion pattern) + **Markdown-aware typing helpers** (list continuation, block auto-wrap, character-pair auto-pair `**`/`__`/`[[`/`` ` ``).
- **Domain wiring** preserved from Phase A-G: PageRef, PageFile, ContentManager.updatePage, PageEditorViewModel, PageEditorHost, AppGlobals, AppState.pageInspectorOpen, inspector + sidebar wiring, atomic-write contract, frontmatter preservation, editable title TextField.

**Critical scoping discovery:** engine's `MarkdownToken` type is load-bearing — 11 non-styling files reach through it. Plan preserves the type-API of `MarkdownToken` / `MarkdownTokenizer.parseTokens(in:)` / `MarkdownDetection.isInside…` and rewrites internals to back onto Apple AST.
