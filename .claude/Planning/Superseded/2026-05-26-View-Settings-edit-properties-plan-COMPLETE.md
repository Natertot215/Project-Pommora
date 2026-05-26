# v0.3.1 — Properties End-to-End: Schema CRUD + Dynamic Table Columns + Cell Editors (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land properties end-to-end on Pommora's 4 storage detail surfaces — schema CRUD via the View Settings popover (add/edit/remove properties + per-type config) AND dynamic property-value columns in each detail view's Table with click-to-edit popovers wired through every one of the 11 property types. By the end of this slice, users can fully configure their schema and edit their data without leaving the detail view.

**Architecture:** Inside the existing 300×360pt popover at ContentView level, the NavigationStack root mirrors Notion's view-settings menu — Group Level (Edit Properties) + View Level (Property Visibility active; Layout/Filter/Sort/Group muted placeholders). Schema-editor sub-views currently duplicated across `VaultSettingsSheet` + `TypeSettingsSheet` are extracted into a shared `PropertyEditor` module; popover + both sheets render the same components. Detail-view Tables compute their column set from each container's `views[0]` config + the parent Type's schema; cells render type-specific display views and open type-specific editor popovers anchored to the cell on click. Single-property atomic writes flow through new `updatePageProperty(_:in:propertyID:newValue:)` / `updateItemProperty(_:in:propertyID:newValue:)` manager methods; existing `PropertyEditorRow` editors (and the existing-but-currently-unwired `RelationPicker`) get reused as popover content.

**Tech Stack:** SwiftUI macOS 26 (NavigationStack + `.popover` + `.glassEffect` inheritance + dynamic `Table` columns via state-driven re-render), Swift 6 strict concurrency, GRDB SQLite (index updates via existing IndexUpdater), Swift Testing (`@Suite`/`@Test`), `builder` subagent for xcodebuild verification (quirk #13).

---

## Context

The View Settings chrome slice (shipped 2026-05-25 PM, merged to main as `48316be`) wired the `slider.horizontal.3` toolbar button + an empty 300×360pt Liquid Glass popover into the existing primary-action HStack at ContentView level. The popover currently renders `Color.clear` — chrome-only validation slice.

Now: ship the full properties experience. From any storage detail view (Vault, Page Collection, Item Type, Set):

1. Click the View Settings button → see the Notion-mirrored menu with Edit Properties + Property Visibility both active
2. Tap Edit Properties → see all schema properties → add, edit (rename, change options/config, set Display as for Status), or remove any user-defined property
3. Toggle Property Visibility → drag-reorder + show/hide columns
4. See user-defined property columns render dynamically in the Table per the active view's `visibleProperties` order
5. Click any cell → type-appropriate editor popover opens anchored to the cell → set/change the value → commit on outside-click

All 11 property types (number, checkbox, date, datetime, select, multi-select, status, url, relation, last-edited-time, file) are editable in cells via reused existing editor views (PropertyEditorRow dispatcher) or — for relation — by wiring the existing RelationPicker that previously sat unused. last-edited-time stays read-only by design.

The sidebar right-click `VaultSettingsSheet` and `TypeSettingsSheet` continue to work; both they and the popover render identical schema-editor sub-views via a shared `PropertyEditor` module.

---

## Data Layer Constraints (must be addressed before UI work begins)

Six additive Codable changes. None require on-disk migration of existing user files — all fields optional with safe defaults; missing keys decode as nil / empty / struct-default via `decodeIfPresent`.

### 1. `DisplayVariant` enum + `PropertyDefinition.displayAs: DisplayVariant?` (NEW — optional per-property display)

```swift
enum DisplayVariant: String, Codable, Equatable, Sendable {
    case box      // colored dot/circle + label (default for Status type)
    case select   // colored chip with label (same shape as Select-property render)
    case chip     // icon-only chip — uses existing PropertyChip.chip(icon:) variant
                  //   with hardcoded "square.dashed" placeholder icon at v0.3.1.x.
                  //   Final per-group/per-option icons + Settings.statusGroupIcons
                  //   config land in a pre-v1 cleanup phase (Prospects.md).
}
```

Added to `PropertyDefinition` as optional `displayAs: DisplayVariant?`. Persisted as `display_as` snake_case. nil = type default (`.box` for Status); **only Status reads it** — explicitly NOT a generic field. Other types ignore the field entirely.

### 2. `ItemType.singular: String?` (NEW — Capacities-style singular form)

```swift
var singular: String?
```

nil falls back to `title`. Drives "+ Add <singular>" labels everywhere Item Types render an add affordance (wiring per call site lands when each call site needs it; this plan just adds the field). Item Types only. Persisted as `singular` in `_itemtype.json`.

### 3. `SavedView` Codable upgrade — real fields

Currently empty stub. Replaced with:

```swift
struct SavedView: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String                              // "view_<ULID>"
    var name: String                            // "Table" default
    var icon: String?                           // SF Symbol; default "tablecells"
    var type: ViewType                          // .table at v0.3.1; others muted
    var visibleProperties: [String]             // ordered property IDs that show as columns
    var hiddenProperties: [String]              // muted-strikethrough in Property Visibility pane

    // Fields reserved for follow-up patches; NOT consumed at v0.3.1:
    var sort: [SortCriterion]?                  // v0.3.1.2
    var filter: FilterGroup?                    // v0.3.1.3
    var group: GroupConfig?                     // v0.3.1.4
}

enum ViewType: String, Codable, Sendable {
    case table
    case board, list, cards, gallery            // placeholder cases — render muted in Layout pane
}

// Reserved stubs to keep Codable forward-compatible without breaking decodes:
struct SortCriterion: Codable, Equatable, Hashable, Sendable {
    var propertyID: String
    var direction: SortDirection
}
enum SortDirection: String, Codable, Sendable { case ascending, descending }

struct FilterGroup: Codable, Equatable, Hashable, Sendable {
    var match: MatchMode
    var rules: [FilterRule]
}
struct FilterRule: Codable, Equatable, Hashable, Sendable {
    var propertyID: String
    var op: String                              // serialized operator name — full enum in v0.3.1.3
    var value: String?                          // serialized payload — full union in v0.3.1.3
}
enum MatchMode: String, Codable, Sendable { case all, any }

struct GroupConfig: Codable, Equatable, Hashable, Sendable {
    var propertyID: String
    var order: [String]?
}
```

- `visibleProperties` / `hiddenProperties` together describe the column set + order at v0.3.1. Active Property Visibility pane writes both.
- Reserved fields (`sort` / `filter` / `group`) are optional + Codable today so v0.3.1 sidecars don't accidentally break v0.3.1.x follow-up decodes.

### 4. `PageCollection.views: [SavedView]` + `ItemCollection.views: [SavedView]` (NEW)

```swift
// PageCollection.swift + ItemCollection.swift
var views: [SavedView] = []
```

`PageType` + `ItemType` already have this field; Collections previously lacked it. Each Collection is INDEPENDENT (locked decision) — its own `views[0]` config separate from the parent Type's.

Codable round-trip via decodeIfPresent → empty array on missing key (pre-v0.3.1 sidecars).

### 5. `PropertyDefinition.dateFormat: DateFormat?` (NEW — Date display format)

```swift
enum DateFormat: String, Codable, Equatable, Sendable {
    case monthDayLong       // "March 4"
    case monthDayYearLong   // "March 4, 2026"
    case numericShort       // "03-04"
    case numericMedium      // "03-04-26"
    case numericLong        // "03-04-2026"
    case iso                // "2026-03-04" (matches on-disk storage)
}
```

Added to `PropertyDefinition` as optional. Persisted as `date_format`. nil = `.monthDayYearLong` default. Only Date / Date & Time read it. Edit Property pane's Display as row (Date types only) writes it. Custom strftime-token format flagged for future via Prospects.md ("post-v1 Date Display as custom format").

### 6. Default-view migration on `loadAll` (4 manager call sites)

Mirrors quirk #15's defensive-on-load pattern. In each of `PageTypeManager.loadAll` + `ItemTypeManager.loadAll`, after disk load, walk every container (Type AND its Collections) and ensure each has at least one `SavedView`:

```swift
private func ensureDefaultView(visiblePropertyIDs: [String]) -> SavedView {
    SavedView(
        id: "view_\(ULID.generate())",
        name: "Table",
        icon: "tablecells",
        type: .table,
        visibleProperties: visiblePropertyIDs,
        hiddenProperties: []
    )
}

// in PageTypeManager.loadAll (after types are loaded):
for i in 0..<types.count {
    if types[i].views.isEmpty {
        types[i].views = [ensureDefaultView(visiblePropertyIDs: types[i].properties.map(\.id))]
        try? saveType(types[i])
    }
    for j in 0..<pageCollectionsByType[types[i].id, default: []].count {
        var c = pageCollectionsByType[types[i].id]![j]
        if c.views.isEmpty {
            // Collections inherit parent's visibility ordering as default
            c.views = [ensureDefaultView(visiblePropertyIDs: types[i].properties.map(\.id))]
            try? saveCollection(c)
            pageCollectionsByType[types[i].id]![j] = c
        }
    }
}
```

Same pattern in ItemTypeManager.loadAll. Idempotent — `views.isEmpty` is the only mutation gate.

### What is NOT changing in this plan's data layer

- `StatusGroup` schema model unchanged. No new Settings config for status group icons. `DisplayVariant.chip` rendering hardcodes `"square.dashed"` as the placeholder icon at the call site. Per-group AND per-option icon selection + Settings config all deferred together to a pre-v1 cleanup phase (logged in Prospects.md).
- `PropertyChip` API unchanged — the existing `.chip(icon:)` variant IS the rendering target for `DisplayVariant.chip`.
- No on-disk file rewrites for existing user nexuses beyond the default-view migration (which is per-container, idempotent, and only fires when `views.isEmpty`).
- No Settings migration — `currentDefaultsVersion` stays at 2.

---

## Scope decisions (locked)

| Q | Decision | Rationale |
|---|---|---|
| Plan shape | One big plan covering schema editing + dynamic columns + cell editors + Property Visibility | User explicitly chose "one big plan" |
| Cell editor location | **Popover anchored to the cell** (Notion-style) | User-locked |
| Surfaces in scope | **All 4 storage detail views simultaneously** | User-locked; shared helper rendering logic prevents drift |
| Property Visibility pane | **Active in v0.3.1 alongside dynamic columns** | User-locked |
| Empty cells | Blank cell, full-area clickable; click opens editor; outside-click commits | Recommended default (Notion-style) |
| Header drag-reorder | Deferred to v0.3.1.x follow-up — drag-reorder lives in Property Visibility pane only at v0.3.1 | Smaller scope; one source of truth |
| Relation editor | Wire the existing-but-unused `RelationPicker` (J.15-shipped) into `PropertyEditorRow.relationEditor` (currently a stub `Text("Relation editor coming v0.3.0")`) | Picker is built; just need to swap out the stub |
| New property defaults on existing entities | Stay empty until edited per locked Properties.md rule ("add property = schema-only write") | No member file rewrites; matches existing model |
| Reserved properties in Properties pane | Show with lock badge; chevron disabled; tooltip "Built-in property — not editable" | Notion-style "show everything" with disabled affordances |
| `_modified_at` (Last Edited Time) in cells | Always-visible read-only column (cannot be hidden via Property Visibility) | Standard sort criterion; toggling it off causes UX confusion |
| Deleted properties row | Skip — Pommora is hard-delete with cascade | No soft-delete history surface in the model |
| + New property UX | **Mixed by type:** push to PropertyTypePicker → on selection: if Select/Status/Multi-Select, push to fresh Edit Property pane so options get set; if Link/File/Date/Checkbox/Number/URL/Relation, create immediately + pop back to Properties list | User-locked; option-requiring types are useless without options, so flow forces config; simple types skip the extra hop |
| Edit Property pane format for Select/Status/Multi-Select | Notion screenshot format: combined icon+title row at top + Type row (push) + Sort row (Manual/Alphabetical/Reverse) + Options section with `+` add button + per-option draggable rows showing colored chip + chevron (push to EditOptionPane) + footer Duplicate property + Delete property | User-provided screenshot reference; SelectOptionsEditor/StatusGroupsEditor restructure from inline editors to chevron-push list patterns |
| Edit Option pane (NEW) | Per-option editing — push from any option chevron; renders name TextField + color picker + (Status-only) group selector + Delete option button | Matches Notion's drill depth in the user's screenshot |
| Option ordering (Select/Multi/Status) | **Drag-only** — user reorders options by dragging the drag-handle on option rows. NO Sort picker / NO alphabetical-sort affordance. Schema option order is the single source of truth | User-locked override of Notion's Sort row |
| "Display as" Edit Property row | Type-aware: Status → `.box`/`.select`/`.chip` (DisplayVariant — Status-only); Date/DateTime → 5 user-listed formats + ISO 8601 (DateFormat enum); other types → no Display as row | User-locked. DisplayVariant is exclusively Status's concern |
| Chip-rendering scope (cell display side) | Chips render for: Status / Select / Multi-Select (via `PropertyChip` — vivid color palette) + Relation (via `RelationChip` — default-grey, less corner-rounded) + File (via `FileChip` — quaternary fill, link icon). Dates, Links (URL), Numbers, Checkboxes, LastEditedTime render as pure text or native controls without chip chrome | User-locked across multiple messages |
| Link (URL) cell display | Pure accent-blue inline text. Strip `https://` / `http://` prefix from displayed string (stored value retains the scheme). Truncate at 15 chars with `…`. Click reveals full URL for editing | User-locked |
| Date / DateTime cell display | Pure text per `dateFormat`, primary color, no chip, no fill | User-locked |
| File cell display | `FileChip` primitive: quaternary fill, `link` SF Symbol, filename truncated at 13 chars with `…`. Multiple files render multiple chips | User-locked |
| Relation cell display | Default-grey chip-style with **less corner rounding** than existing PropertyChip + the linked entity's icon + target title. New rendering primitive: `RelationChip` view (RoundedRectangle cornerRadius 4 vs PropertyChip's Capsule). One default look at v0.3.1; per-property override deferred | User-locked: "This will be the default look for now" |
| AI Autofill row from screenshot | Skip — Pommora has no AI integration | Not in Pommora's product surface |
| "Wrap content" footer | Skip | Notion-specific text-wrap concept |
| File / Link (URL) Edit Property pane | NO per-type config — just icon+name row, Duplicate, Delete. No Type-change push, no options, no Display as | User direction: "File & Link properties don't need an 'edit' beyond a rename of the property titles" |
| Duplicate property action | New `duplicateProperty(id:in:)` manager method that mints a new ULID, copies the PropertyDefinition (incl. all per-type config), appends `(copy)` to name, persists via SchemaTransaction. Member files unaffected (per locked schema-only rule) | Notion-style; small addition |
| PropertyChipColor enum | **12 cases locked**: `.default` (= nil / grey fallback) / `.red` / `.orange` / `.yellow` / `.green` / `.blue` / `.accent` (nexus accent) / `.teal` / `.indigo` / `.purple` / `.pink` / `.brown`. `.cyan` and `.mint` retired (overlap Teal). Green + Teal use Apple's secondary Color variants (less bright). Yellow + Pink keep custom hex (#FFDE21 / #E89EB8). No more tier system — flat palette | User-locked: "no secondary tiers" |
| Color SELECTION UI (color picker for options) | **5×2 grid of 10 swatches** — excludes `.default` (= nil, no-color state) and `.accent` (can't render consistently as a pickable swatch). 10 pickable colors: Red / Orange / Yellow / Green / Blue / Teal / Indigo / Purple / Pink / Brown. Selecting "no color" is a separate affordance (e.g. an X icon next to the grid) that writes `nil` to the option's color | User-locked: "5x2 without [Default and Accent]" |
| Option sort | **Drag-only** in Edit Property pane at v0.3.1 (no Sort row). Sort as a per-VIEW configuration ships separately in v0.3.1.2's Sort pane (different surface — view-level, not property-level) | User-locked: "sorting is for the future view setting" |
| PropertyEditor extraction | YES — deduplicate Vault/Type sheets into shared `Pommora/Properties/Editor/` module | Eliminates 4-way duplication |
| Sheet alignment | Backport extracted PropertyEditor into both sidebar sheets at the end of this plan | Sheets continue working unchanged from user perspective |
| Mirror | `/Users/nathantaichman/The Nexus/Pommora/Planning/View-Settings-edit-properties-plan.md` (Obsidian-visible — NOT under `.claude/`) | Obsidian doesn't index hidden folders |

---

## Architectural principle (carried from chrome slice)

Static button position, adaptive popover content (locked decision #12). The button never moves. Popover content adapts via `ViewSettingsScope` derived reactively from `sidebarSelection`. Detail views never declare their own `.toolbar` for this button.

In this plan, the scope enum gains entity associated values (source-compatible additive change). Popover body switches on scope to render storage-scope content (full menu with Edit Properties + Property Visibility both active) vs placeholder-scope content (empty body, retained from chrome slice).

---

## File structure

**Files to CREATE:**

| Path | Responsibility |
|---|---|
| `Pommora/Pommora/ViewSettings/DisplayVariant.swift` | Enum: `.status` / `.select` / `.chip` |
| `Pommora/Pommora/Vaults/SavedView+Codable.swift` (or replace existing `SavedView.swift` if empty stub) | Real `SavedView` + `ViewType` + reserved Sort/Filter/Group stubs |
| `Pommora/Pommora/ViewSettings/ViewSettingsRoute.swift` | Hashable NavigationStack destinations: `.editProperties` / `.propertyTypePicker` / `.editProperty(id:)` / `.newProperty(type:)` / `.propertyVisibility` |
| `Pommora/Pommora/ViewSettings/StorageMenuRoot.swift` | Root storage-scope menu rendering |
| `Pommora/Pommora/ViewSettings/PropertiesListPane.swift` | Notion screenshot 2 |
| `Pommora/Pommora/ViewSettings/PropertyTypePickerPane.swift` | Wraps existing PropertyTypePicker as a pushed pane |
| `Pommora/Pommora/ViewSettings/EditPropertyPane.swift` | Notion-format Edit Property pane: combined icon+title row, Type row, Sort row, Options section with `+` add button + chevron-push option rows, Duplicate + Delete footer. Type-aware: simple types render compact form; Select/Status/Multi render full options structure; Date renders Display-as format picker |
| `Pommora/Pommora/ViewSettings/EditOptionPane.swift` | NEW — per-option editing pushed from any option chevron. Name TextField + color picker + (Status-only) group selector + Delete option button |
| `Pommora/Pommora/ViewSettings/DateFormatPicker.swift` | Display-as picker for Date / Date & Time properties; 6 cases (5 user-listed + ISO 8601) |
| `Pommora/Pommora/ViewSettings/PropertyVisibilityPane.swift` | Click-to-toggle + strikethrough + drag-reorder property list |
| `Pommora/Pommora/Properties/Editor/SelectOptionsEditor.swift` | Extracted from Vault/TypeSettingsSheet |
| `Pommora/Pommora/Properties/Editor/StatusGroupsEditor.swift` | Extracted |
| `Pommora/Pommora/Properties/Editor/NumberFormatPicker.swift` | Extracted |
| `Pommora/Pommora/Properties/Editor/FileAcceptEditor.swift` | Extracted |
| `Pommora/Pommora/Properties/Editor/PerTypeConfigEditor.swift` | Type-switching @ViewBuilder for popover + sheets |
| `Pommora/Pommora/Detail/Columns/PropertyColumnBuilder.swift` | Computes TableColumn array from `views[0].visibleProperties` + schema |
| `Pommora/Pommora/Detail/Columns/PropertyCellDisplay.swift` | Per-type read-side cell renderer. **Chip family ONLY for** Status (`PropertyChip` variant per `displayAs` — `.box` / `.select` / `.chip`) + Select / Multi-Select (`PropertyChip` pill variants in option colors) + Relation (new `RelationChip` — default-grey, less corner-rounded rectangle, linked entity icon + title). All other types use non-chip displays: Text formatters for date/number/url/lastEdit; native `Toggle`-style image for checkbox; thumbnail count + name for file |
| `Pommora/Pommora/Properties/Chips/PropertyChipColor.swift` | MODIFY — palette cleanup: drop `.cyan` + `.mint` cases (overlap Teal). 12 enum cases: Default / Red / Orange / Yellow / Green / Blue / Accent / Teal / Indigo / Purple / Pink / Brown. Drop tier system. Green + Teal use Apple secondary Color variants; Yellow + Pink keep custom hex (already coded). Add `selectablePalette: [PropertyChipColor]` returning the 10 pickable cases (excludes Default + Accent) |
| `Pommora/Pommora/Properties/Chips/OptionColorPicker.swift` | NEW — 5×2 grid of 10 selectable colors (from `PropertyChipColor.selectablePalette`) + separate "No color" affordance writing `nil`. Used by EditOptionPane for per-option color picking |
| `Pommora/Pommora/Properties/Chips/RelationChip.swift` | New rendering primitive for Relation values. RoundedRectangle (cornerRadius ~4) shape — distinct from `PropertyChip`'s Capsule. Default grey fill. Takes `icon: String` (target entity's icon) + `title: String` (target entity's current title). v0.3.1 = single default look; future per-property override deferred |
| `Pommora/Pommora/Properties/Chips/FileChip.swift` | New rendering primitive for File property values. **Quaternary fill** + `link` SF Symbol (chain-link icon) + filename truncated at 13 chars with `…`. Distinct from PropertyChip + RelationChip — separate primitive for the file-attachment visual language |
| `Pommora/Pommora/Properties/Chips/LinkChip.swift` | New rendering primitive for URL ("Link") property values. **Pure text** (no fill, no chip chrome) in accent-blue. Strips `https://` / `http://` prefix from display (stored value retains full URL). Truncates at 15 chars with `…`. Tap reveals the full URL for editing. Lives in the Chips folder for naming consistency with FileChip / RelationChip / PropertyChip — even though it renders as styled text not a capsule |
| `Pommora/Pommora/Detail/Columns/PropertyCellEditor.swift` | Cell wrapper that owns popover state + dispatches type-specific editor on click |
| `Pommora/PommoraTests/ViewSettings/EditPropertiesPopoverTests.swift` | Integration: dispatch popover with PageType scope, assert root menu state |
| `Pommora/PommoraTests/Properties/DisplayVariantCodableTests.swift` | DisplayVariant + PropertyDefinition.displayAs round-trip |
| `Pommora/PommoraTests/Items/ItemTypeSingularCodableTests.swift` | ItemType.singular round-trip |
| `Pommora/PommoraTests/Vaults/SavedViewCodableTests.swift` | SavedView round-trip + ViewType cases + reserved stub fields decode-as-nil |
| `Pommora/PommoraTests/Vaults/PageCollectionViewsTests.swift` | views[] round-trip on PageCollection + ItemCollection |
| `Pommora/PommoraTests/Nexus/DefaultViewMigrationTests.swift` | loadAll mints default view; idempotent; respects existing views |
| `Pommora/PommoraTests/Content/PageContentManagerUpdatePropertyTests.swift` | updatePageProperty single-property atomic write tests |
| `Pommora/PommoraTests/Items/ItemContentManagerUpdatePropertyTests.swift` | updateItemProperty single-property atomic write tests |

**Files to MODIFY:**

| Path | Change |
|---|---|
| `Pommora/Pommora/Items/ItemType.swift` | Add `var singular: String?` field |
| `Pommora/Pommora/Vaults/PropertyDefinition.swift` | Add `var displayAs: DisplayVariant?` + `var dateFormat: DateFormat?` fields |
| `Pommora/Pommora/Vaults/SavedView.swift` | Replace empty stub with real fields (or move to `SavedView+Codable.swift`) |
| `Pommora/Pommora/Vaults/PageCollection.swift` | Add `views: [SavedView] = []` field |
| `Pommora/Pommora/Items/ItemCollection.swift` | Add `views: [SavedView] = []` field |
| `Pommora/Pommora/Vaults/PageTypeManager.swift` | Default-view migration in `loadAll` for both Types and their PageCollections + new `duplicateProperty(id:in:)` method |
| `Pommora/Pommora/Items/ItemTypeManager.swift` | Same for ItemTypes + ItemCollections + new `duplicateProperty(id:in:)` method |
| `Pommora/Pommora/ViewSettings/ViewSettingsScope.swift` | Add associated values: `.pageType(PageType)` / `.pageCollection(PageCollection)` / `.itemType(ItemType)` / `.itemCollection(ItemCollection)`; others stay case-only |
| `Pommora/Pommora/ViewSettings/ViewSettingsPopover.swift` | Replace `Color.clear` with NavigationStack + scope-switch root content |
| `Pommora/Pommora/ViewSettings/ViewSettingsButton.swift` | Take manager params + inline-inject in `.popover` content closure |
| `Pommora/Pommora/ContentView.swift` | Update scope mapping to populate associated values; pass managers into ViewSettingsButton |
| `Pommora/Pommora/Properties/VaultSettingsSheet.swift` | Replace inlined editors with shared imports from `Properties/Editor/` |
| `Pommora/Pommora/Properties/TypeSettingsSheet.swift` | Same for `Type*` prefixed copies |
| `Pommora/Pommora/Content/PageContentManager+CRUD.swift` | Add `updatePageProperty(_:in:propertyID:newValue:)` atomic single-property write |
| `Pommora/Pommora/Items/ItemContentManager+CRUD.swift` | Add `updateItemProperty(_:in:propertyID:newValue:)` atomic single-property write |
| `Pommora/Pommora/ItemWindow/PropertyEditorRow.swift` | Replace `relationEditor`'s `Text("Relation editor coming v0.3.0")` stub with the real `RelationPicker` (J.15-shipped); ditto `statusEditor` (currently Text-only) and `fileEditor` (currently count-only) — wire to actual editor views |
| `Pommora/Pommora/Detail/PageTypeDetailView.swift` | Replace static columns with `PropertyColumnBuilder` output; rows display via `PropertyCellDisplay`, edits via `PropertyCellEditor` |
| `Pommora/Pommora/Detail/PageCollectionDetailView.swift` | Same |
| `Pommora/Pommora/Detail/ItemTypeDetailView.swift` | Same |
| `Pommora/Pommora/Detail/ItemCollectionDetailView.swift` | Same |
| `Pommora/PommoraTests/ViewSettings/ViewSettingsScopeMappingTests.swift` | Extend tests to assert associated-value round-trip |
| `.claude/Features/Properties.md` | Document `displayAs` + `views[]` on Collections + extraction note + cell-edit popovers |
| `.claude/Features/Items.md` | Document new `singular` field |
| `.claude/Features/PommoraUIX.md` | Add EditProperties pane + Property Visibility pane + PropertyCellEditor showcases |
| `.claude/Features/Prospects.md` | Add deferred "Status group + per-option icons + Settings config" entry; deferred "header drag-reorder" entry |
| `.claude/Handoff.md` | Update current state + new resume prompt |
| `.claude/History.md` | Append v0.3.1 ship entry |
| `.claude/Framework.md` | Update v0.3.1 entry |
| `.claude/Planning/README.md` | Register new plan; retire chrome plan to Superseded |

---

## Task list (25 tasks across 9 phases — each phase ships green standalone per quirk #8)

> Each task structure: Files touched → TDD steps (write failing test → verify fails → implement → verify passes) → commit. For pure-UI tasks where unit tests don't apply, the visual smoke is the gate.

### Phase A — Data layer foundations

#### Task 1: `DisplayVariant` enum + `PropertyDefinition.displayAs`

Add `DisplayVariant.swift` with the three-case enum. Add `displayAs: DisplayVariant?` to `PropertyDefinition` Codable. Tests cover round-trip + decode-from-missing-key.

#### Task 2: `ItemType.singular: String?`

Add the field + CodingKey. Tests cover round-trip + missing-key decode.

#### Task 3: `SavedView` Codable upgrade

Replace empty stub with real fields (id, name, icon, type, visibleProperties, hiddenProperties + reserved stub fields for sort/filter/group). Tests cover round-trip + reserved-field-missing decode.

#### Task 4: `views: [SavedView]` on PageCollection + ItemCollection

Add field + CodingKey + decodeIfPresent fallback to empty array. Tests cover round-trip + missing-key decode (pre-v0.3.1 sidecars).

#### Task 5: Default-view migration on `loadAll`

`PageTypeManager.loadAll` + `ItemTypeManager.loadAll` each mint a default Table view for any container (Type or Collection) where `views.isEmpty`. Idempotent. Tests mirror `LoadAllIndexSyncTests` pattern.

#### Task 5b: PropertyChipColor palette cleanup (12 enum cases, 5×2 selection grid of 10)

`Pommora/Pommora/Properties/Chips/PropertyChipColor.swift`:
- Remove `.cyan` and `.mint` cases entirely
- Final 12 enum cases: `default` (= nil / grey fallback) / `red` / `orange` / `yellow` / `green` / `blue` / `accent` (nexus accent) / `teal` / `indigo` / `purple` / `pink` / `brown`
- Green and Teal: switch `swiftUIColor` getter to use Apple's secondary Color variants (e.g. `Color(.systemGreen).opacity(0.7)` or `Color(.secondaryGreen)` if exposed — exact pattern verified during execution; goal is less-bright fill matching user's "secondary" reference)
- Yellow and Pink: keep existing custom hex values (`#FFDE21` / `#E89EB8`)
- Drop tier system entirely — no Primary / Secondary tier grouping (was 2-tier in shipped version); all 12 cases live in one flat palette
- Add a static `selectablePalette: [PropertyChipColor]` property returning the 10 pickable cases (excludes `.default` and `.accent`) for the color picker UI

`Pommora/Pommora/Properties/Chips/OptionColorPicker.swift` (NEW — extracted from inline option editor work):
- Renders `PropertyChipColor.selectablePalette` in a compact **5×2 grid** (5 columns × 2 rows = 10 swatches)
- Each cell: a small filled swatch in that color; tap selects + writes the color to the bound option
- Separate "No color" affordance (X icon or "None" pill) that writes `nil` to the binding — corresponds to the `.default` state
- Used by EditOptionPane (Task 11b) for per-option color picking

`Pommora/Pommora/ComponentLibrary/ComponentLibraryView.swift` — Chips gallery section:
- Update palette showcase to the 5×2 grid of 10 selectable colors
- Add separate showcase showing the `.default` (no-color) + `.accent` (nexus-accent) states as informational examples (not pickable)

Any place in the code that references `.cyan` or `.mint` on PropertyChipColor must migrate. Run `grep -rn "PropertyChipColor.cyan\|PropertyChipColor.mint" Pommora/` to surface call sites; expected to be just the component-library showcase.

Commit on completion. Yellow + Pink custom hex already shipped in commit `cedb75b` (2026-05-25); this task strips Cyan + Mint, retires the tier system, and adds the OptionColorPicker primitive.

### Phase B — Scope upgrade + popover scaffold

#### Task 6: `ViewSettingsScope` gains associated values + ContentView mapping helper

Same as in original chrome-slice expansion plan. Extends existing scope tests to assert associated-value round-trip through `ContentView.viewSettingsScope(for:)`.

#### Task 7: Popover NavigationStack scaffold + storage-scope root menu

Replace `Color.clear` body with `NavigationStack(path:)` + scope-switched root rendering. Storage scopes render `StorageMenuRoot` (header + active Edit Properties + active Property Visibility + muted Layout/Filter/Sort/Group rows). Placeholder scopes retain empty 300×360 shell. Managers (PageTypeManager, ItemTypeManager, PageContentManager, ItemContentManager, SettingsManager) inline-injected at popover content level.

### Phase C — Schema editor extraction (shared module)

#### Task 8: Extract shared PropertyEditor sub-views; backport into both sheets

Move `SelectOptionsEditor` / `StatusGroupsEditor` / `NumberFormatPicker` / `FileAcceptEditor` from VaultSettingsSheet + TypeSettingsSheet into `Pommora/Pommora/Properties/Editor/` (single canonical copies, no `Type` prefix). Add `PerTypeConfigEditor` switching @ViewBuilder. Backport: both sheets now reference shared sub-views. Visual smoke confirms sheets behave identically.

### Phase D — Edit Properties pane

#### Task 9: Properties list pane (Notion screenshot 2)

`PropertiesListPane` with searchable list + "+ New property" footer. Reserved properties render with lock badge + disabled chevron + tooltip. User-defined push to `EditPropertyPane` via NavigationLink.

#### Task 10: + New property flow → PropertyTypePickerPane (type-aware routing)

`PropertyTypePickerPane` wraps existing `PropertyTypePicker` for pushed-pane mode. On type pick:
- If type ∈ {Select, MultiSelect, Status}: commit the new property to the manager AND push `.editProperty(id:)` for the just-minted property so user lands in the option editor immediately (matches user direction "Adding a new property such as select, status, or multi-select that requires variables should immediately direct to the 'edit property' view of that property")
- Else (Number, Checkbox, Date, DateTime, URL, Relation, File): commit the new property AND pop back to Properties list (simple types are usable without further config). Note: Relation creation routes through the existing `RelationPropertyWizard` for scope picking before commit; on wizard complete, pops back to Properties list

#### Task 11: EditPropertyPane (Notion screenshot format)

Single pane, type-aware body. Structure mirrors user-provided Notion screenshot exactly:

**For every property type:**
- Header row: combined `IconPickerField` + `TextField(name)` — like Notion's "Area" row with icon button + inline name field
- Type row: `Image(icon) + "Type" + Spacer + currentTypeName + chevron` — pushes to a Type-picker sub-pane (only available for newly-created properties at v0.3.1; existing-property type-change flagged for v0.3.1.5)
- Footer: "Duplicate property" + "Delete property" rows (Delete gated on non-reserved + non-required)

**Type-dependent middle sections:**

| Type | Middle section |
|---|---|
| Select / Multi-Select | "Options" section with `+` header button + per-option draggable rows (drag handle + colored chip + chevron pushing to `EditOptionPane`). **Drag-only reordering** — no Sort picker |
| Status | Display as row (`.box` / `.select` / `.chip` via `DisplayVariant` Picker) + 3-group section (Upcoming / In Progress / Done) — each group's options follow the same draggable-chip-with-chevron pattern. Group labels editable inline. **Drag-only reordering** within each group |
| Date / Date & Time | Display as row (`DateFormatPicker` — 6 format cases) |
| URL ("Link") / File | NO middle section — just header + Type + footer. User direction: "File & Link properties don't need an 'edit' beyond a rename of the property titles" |
| Number | `NumberFormatPicker` row (integer / decimal / percent / currency) |
| Relation | Scope summary (read-only at v0.3.1; full reconfiguration uses existing `RelationPropertyWizard` triggered from a "Change scope…" action — deferred to v0.3.1.5 if scope balloons) |
| Checkbox | No middle section |
| LastEditedTime | Reserved; would normally be lock-badged in Properties list and not reach this pane |

Add-property commit calls `addProperty` on the right manager (PageTypeManager or ItemTypeManager); existing-property commit calls `renameProperty` for name changes + per-config-field updates flow through a new `updateProperty(id:in:transform:)` manager method added in Phase F alongside the single-property value writers. Display as / Sort / Format changes commit via the same path.

#### Task 11b: EditOptionPane + duplicateProperty manager method

`EditOptionPane` — pushed from any option chevron in EditPropertyPane (Select/Multi/Status). Contents:
- Name TextField (option label)
- Color picker (PropertyChipColor palette — 13 colors in 2 tiers; reuses existing color-render primitives)
- For Status options only: Group selector (Upcoming / In Progress / Done — moves the option between structural groups, triggers confirmation per Properties.md "Move an option between groups" mutation)
- "Delete option" button with cascade confirmation listing affected entity count

Commits via new `updateOption(_:in propertyID:in typeID:newValue:)` manager method (or via the existing `updateProperty(transform:)` Phase F adds) — writes the full PropertyDefinition atomically through SchemaTransaction.

Plus `duplicateProperty(id:in:)` on both `PageTypeManager` and `ItemTypeManager`: mints new ULID, deep-copies the PropertyDefinition (including all per-type config), appends `(copy)` to the name, persists via SchemaTransaction. Member files unaffected.

### Phase E — Property Visibility pane

#### Task 12: PropertyVisibilityPane (click-to-toggle + drag-reorder)

List of all properties on the active Type's schema. Each row: icon + name + drag handle. Click row → toggle hidden state (visible = solid; hidden = strikethrough + tertiary color). Drag handle → reorder. Saves via new `updateView(_:in:newValue:)` manager method that writes the full `views[0]` SavedView atomically.

Reserved `_modified_at` (Last Edited Time) is always visible and not draggable — locked decision.

### Phase F — Single-property atomic writes (manager methods)

#### Task 13: `PageContentManager.updatePageProperty(_:in:propertyID:newValue:)`

Atomic single-property write on a Page's frontmatter. Validates the value against the property's type/schema before commit. Updates SQLite index via `IndexUpdater.upsertPage`. For relation property values, calls `DualRelationCoordinator.handleValueChange(...)` to mirror the reverse side. Test coverage: each of the 11 types' write paths + relation reverse-mirror.

#### Task 14: `ItemContentManager.updateItemProperty(_:in:propertyID:newValue:)`

Parallel to Task 13 for Items. Same test pattern.

### Phase G — Dynamic Table columns (display side)

#### Task 15: `PropertyColumnBuilder` helper

Given a container's `views[0]` SavedView + the parent Type's `properties: [PropertyDefinition]`, produces an ordered array of `TableColumn` descriptors. Reserved Title column always leads; reserved Last Edited Time column always trails. User properties appear in between per `visibleProperties` order. Hidden properties excluded.

Output is a struct array (not actual SwiftUI TableColumn) — call sites translate the struct into TableColumn declarations via switch-based static column constructions (workaround for SwiftUI Table's lack of dynamic column count on macOS).

#### Task 16: `PropertyCellDisplay` + new `RelationChip` primitive

For each of the 11 types, a SwiftUI view that takes a `PropertyValue?` and renders the display form. Empty values render as blank cells (full-area clickable to open editor per Phase H Task 19).

**Chip-family renders (4 types):**
- **Select / Multi-Select**: `PropertyChip(.pill(label:))` in the option's `color` from schema. Multi renders multiple chips in a `FlowLayout`.
- **Status**: switches on `definition.displayAs` (defaulting to `.box`) — `.box` renders colored dot + label; `.select` renders as a `PropertyChip` pill; `.chip` renders as `PropertyChip.chip(icon:)` with hardcoded `"square.dashed"` placeholder.
- **Relation**: new `RelationChip(icon: target.icon, title: target.title)` — default-grey, RoundedRectangle (cornerRadius 4 — less rounded than PropertyChip's Capsule). Lookup of target entity via IndexQuery; missing target renders italic "(missing)" placeholder.

**Non-chip renders (7 types):**
- **Number**: `Text(NumberFormatter)` per `numberFormat`. Pure text, primary color, no fill.
- **Checkbox**: `Image(systemName: value ? "checkmark.circle.fill" : "circle")` in secondary color.
- **Date / Date & Time**: `Text(DateFormatter)` per `dateFormat` (default `.monthDayYearLong`). **Pure text, no color** — primary text color, no fill, no chip.
- **URL ("Link")**: **Pure accent-blue inline text**. Strip the `https://` (or `http://`) scheme prefix from display only — stored value retains full URL. Truncate display at 15 chars with `…`. Click reveals the full URL inline for editing (popover from Phase H opens the URL editor). No chip, no fill.
- **File**: Chip primitive with **quaternary fill** + `link` SF Symbol (chain-link icon — user-specified "link icon" for file attachments) + filename truncated at 13 chars with `…`. Distinct from `PropertyChip` (vivid colors, full-name) and `RelationChip` (default-grey, rectangular). Implemented as a new `FileChip` primitive under `Pommora/Pommora/Properties/Chips/`. Multi-file values render multiple chips side-by-side (or with a `+N` counter chip if overflowing).
- **LastEditedTime**: relative-date `Text` (e.g. "2h ago", "Apr 12"). Pure text, secondary color.

**New chip-family primitives this task adds (3):**
- `RelationChip.swift` — default-grey, RoundedRectangle cornerRadius 4, takes `icon: String` + `title: String`
- `FileChip.swift` — quaternary fill, `link` SF Symbol + shortened filename (max 13 chars)
- `LinkChip.swift` — pure accent-blue text, strips `https://` prefix, truncates at 15 chars

All three live under `Pommora/Pommora/Properties/Chips/` alongside `PropertyChip` + `PropertyCheckbox`. PommoraUIX gallery (Chips category) gains entries showing each new variant.

#### Task 17: Wire ColumnBuilder + PropertyCellDisplay into PageTypeDetailView + PageCollectionDetailView

Replace static Table column declarations with the new pattern. Schema from parent Vault; view config from `container.views[0]`. Verifies a Vault with a Select property surfaces a Select column with chip-rendered values across all its Pages.

#### Task 18: Wire same into ItemTypeDetailView + ItemCollectionDetailView

Mirror Task 17 for Items side. Item Type — properties from `itemType.properties`; Set — properties from `parentType.properties` (Collections share parent's schema per locked decision).

### Phase H — Click-to-edit cell popovers

#### Task 19: `PropertyCellEditor` wrapper view

Wraps `PropertyCellDisplay` with a popover anchor. Owns `@State isPresented: Bool` per cell. Tap cell → opens popover with type-appropriate editor. Closing the popover (outside-click / ESC) commits the draft value via the manager method from Tasks 13/14.

Last Edited Time cells are non-interactive (no tap gesture; no editor popover).

#### Task 20: 11 per-type editor popovers — reuse + wire existing editors

For each of the 11 types, mount the appropriate editor view as popover content:
- number → existing TextField from PropertyEditorRow
- checkbox → existing Toggle from PropertyEditorRow
- date / datetime → existing DatePicker from PropertyEditorRow
- select → existing inline Picker from PropertyEditorRow
- multiSelect → existing `MultiSelectChips` view
- status → existing `StatusPicker` (wire properly — currently `PropertyEditorRow.statusEditor` returns Text only)
- url → existing TextField from PropertyEditorRow
- relation → wire existing `RelationPicker` (J.15-shipped; currently unused — `PropertyEditorRow.relationEditor` stubs as Text)
- file → existing `FileAttachmentEditor` (currently `PropertyEditorRow.fileEditor` shows count only — wire properly)
- lastEditedTime → no editor (cell non-interactive)

Each popover commits its draft via `PropertyCellEditor` on dismiss.

#### Task 21: Patch `PropertyEditorRow` stubs (relation / status / file) — wire to real editors

These three currently return placeholder Text in the dispatcher. Replace with their respective full editors so PropertyEditorRow itself stays consistent across surfaces (PropertyPanel / FrontmatterInspector / PropertiesPulldown / popover cells all use the same dispatcher output).

### Phase I — Documentation + finalization

#### Task 22: Documentation sweep + plan moves

Update Properties.md, Items.md, PommoraUIX.md, Prospects.md (add deferred "Status icons Settings config" + deferred "Table-header drag-reorder"), Handoff.md, History.md, Framework.md, Planning/README.md. Move plan from `~/.claude/plans/quizzical-mapping-boot.md` to `.claude/Planning/View-Settings-edit-properties-plan.md`. Retire chrome plan to Superseded.

#### Task 23: Commit + push branch + merge to main + push main + Nexus mirror

Mirror all `.claude/` edits to `/Users/nathantaichman/The Nexus/Pommora/` equivalents (Obsidian-visible paths — `.claude/` content gets mirrored to root-level paths for visibility). Push v0.3.0-properties; merge to main; push main. Both branches synced at the same SHA.

---

## Reusable existing infrastructure (no new build required)

| Component | File | Reuse plan |
|---|---|---|
| `PropertyTypePicker` | `Pommora/Properties/PropertyTypePicker.swift` | Mounted as pushed pane via `PropertyTypePickerPane` (Task 10) |
| `IconPickerField` | `Pommora/Sidebar/Sheets/IconPickerField.swift` | Edit Property pane header icon picker (Task 11) |
| `PropertyChip` / `ChipDropdown` / `PropertyCheckbox` | `Pommora/Properties/Chips/` | PropertyCellDisplay select/multiSelect/status/checkbox rendering (Task 16) |
| `StatusPicker` | `Pommora/Properties/StatusPicker.swift` | Status cell editor popover content (Task 20) |
| `RelationPicker` | `Pommora/Properties/RelationPicker.swift` | Relation cell editor popover content — wire into PropertyEditorRow (Tasks 20-21) |
| `FileAttachmentEditor` | `Pommora/Properties/FileAttachmentEditor.swift` | File cell editor popover content + wire into PropertyEditorRow (Tasks 20-21) |
| `MultiSelectChips` | `Pommora/ItemWindow/MultiSelectChips.swift` | Multi-select cell editor popover content (Task 20) |
| `SchemaTransaction` | `Pommora/AtomicIO/SchemaTransaction.swift` | All manager CRUD already uses this — no direct popover usage |
| `PropertyDefinitionValidator` | `Pommora/Validation/PropertyDefinitionValidator.swift` | Called pre-commit on every schema mutation |
| `DualRelationCoordinator` | `Pommora/Properties/DualRelationCoordinator.swift` | Called via managers' addProperty/deleteProperty + new `updatePageProperty` / `updateItemProperty` for value-mirroring |
| `IndexUpdater.upsertPropertyDefinition` / `upsertPage` / `upsertItem` | `Pommora/Index/IndexUpdater.swift` | Non-fatal post-commit hook; wired into all new manager methods |
| `ReservedPropertyID.isReserved(_:)` | `Pommora/Vaults/ReservedPropertyID.swift` | PropertiesListPane lock badge + PropertyVisibilityPane "always visible" gating for `_modified_at` |
| Manager CRUD methods (addProperty / renameProperty / deleteProperty / reorderProperty) | PageTypeManager + ItemTypeManager | Called directly by Edit Property pane via @Environment-injected manager |

---

## Verification summary

| Gate | Mechanism | Passing condition |
|---|---|---|
| Data-layer tests | `xcodebuild test -only-testing:PommoraTests/DisplayVariantCodableTests,ItemTypeSingularCodableTests,SavedViewCodableTests,PageCollectionViewsTests,DefaultViewMigrationTests` | All pass |
| Scope tests | `xcodebuild test -only-testing:PommoraTests/ViewSettingsScopeMappingTests` | 13/13 pass |
| Sheet regression | `xcodebuild test -only-testing:PommoraTests` after Task 8 | No new failures vs pre-extraction baseline |
| Single-property write tests | `xcodebuild test -only-testing:PommoraTests/PageContentManagerUpdatePropertyTests,ItemContentManagerUpdatePropertyTests` | Each 11-type write path passes; relation reverse-mirror passes |
| Build | `xcodebuild build` after each task | BUILD SUCCEEDED |
| Visual smoke (each phase) | Manual Cmd+R | Per per-phase instructions |
| End-to-end smoke (Phases G+H+I) | Cmd+R → open popover → Edit Properties → add a Status property → see new column in Table → click cell → StatusPicker opens → set value → commits + cell re-renders with chip | All paths reachable across all 4 storage detail views |
| Both branches in sync | After Task 23 | `origin/main` and `origin/v0.3.0-properties` point to the same SHA |

---

## Self-review

**1. Spec coverage**

| Requirement | Task |
|---|---|
| Edit Properties end-to-end from popover (add/edit/remove) | Tasks 9 + 10 + 11 |
| Properties pane mirrors Notion screenshot 2 | Task 9 |
| Edit Property pane mirrors Notion screenshot (icon+title row, Type, Sort, Options w/ chevron-push, Duplicate+Delete footer) | Task 11 |
| Edit Option pane for per-option editing (push from option chevron) | Task 11b |
| Option ordering for Select/Multi/Status | **Drag-only** — no Sort picker in Edit Property pane. Schema option order IS the sort. Task 11 (drag-handle rows) |
| Date "Display as" picker (6 format cases incl. ISO 8601) for Date / Date & Time | Task 1 (dateFormat field) + Task 11 (Display as row) |
| File / Link (URL) Edit Property panes have NO middle section | Task 11 |
| Duplicate property action + Delete property in EditPropertyPane footer | Task 11b (manager method) + Task 11 (UI rows) |
| + New property type-aware routing: Select/Status/Multi auto-push to Edit Property pane; others pop back to list | Task 10 |
| Reserved properties show with lock badge | Task 9 |
| `displayAs` field on PropertyDefinition with Codable round-trip | Task 1 |
| Status `.chip` rendering uses existing PropertyChip.chip(icon:) with hardcoded "square.dashed" placeholder | Task 16 (cell display) + Task 20 (editor commit writes the field) |
| Per-group AND per-option Status icons + Settings config deferred to pre-v1 | Documented in Prospects.md (Task 22) |
| `singular: String?` on ItemType | Task 2 |
| PropertyEditor extraction (eliminate duplication) | Task 8 |
| Property Visibility pane active (show/hide + drag-reorder) | Task 12 |
| Dynamic property columns in Table (all 4 storage detail views) | Tasks 15 + 17 + 18 |
| Click-to-edit cell popovers (all 11 property types) | Tasks 19 + 20 + 21 |
| RelationPicker wired into PropertyEditorRow (replace stub) | Task 21 |
| Single-property atomic write managers | Tasks 13 + 14 |
| Empty cells = blank, full-area clickable | Task 16 + Task 19 (gesture binding) |
| Header drag-reorder deferred | Documented in Prospects.md (Task 22) |
| Plan moved to `.claude/Planning/` | Task 22 |
| Mirror to The Nexus (Obsidian-visible folder) | Task 23 |
| Chrome plan retires to Superseded | Task 22 |
| Both branches synced after ship | Task 23 |

**2. Placeholder scan**

Searched for "TBD" / "TODO" / "implement later" / "add appropriate" / "edge cases" in task bodies. Zero hits. One forward-binding note in Task 11 ("EditProperty update path commits rename only; change-type + per-type-config edits on existing properties land at v0.3.1.5 via a new updateProperty(id:in:transform:) manager method") — that's a stub-and-progressively-replace boundary per quirk #8, not a placeholder. v0.3.1 ships green; v0.3.1.5 lights up the gap.

**3. Type consistency**

- `ViewSettingsScope` cases used by popover routing match Task 6's enum declaration (4 storage cases with associated values + 6 case-only).
- `ViewSettingsRoute` cases used in NavigationStack push sites match Task 7's declaration.
- `PropertyDefinition.displayAs` field used in Task 11's Display as picker matches Task 1's added field.
- `SavedView.visibleProperties` / `.hiddenProperties` referenced in Property Visibility pane (Task 12) + column builder (Task 15) match Task 3's struct definition.
- `PageCollection.views` / `ItemCollection.views` referenced in default-view migration (Task 5) match Task 4's added field.
- `PropertyCellEditor` referenced in detail view wiring (Tasks 17 + 18) matches Task 19's view declaration.
- `updatePageProperty(_:in:propertyID:newValue:)` referenced in `PropertyCellEditor` commit (Task 19) matches Task 13's manager method signature; ditto `updateItemProperty` from Task 14.
- `PropertyChip.chip(icon:)` referenced for `DisplayVariant.chip` rendering is the existing variant from `Pommora/Properties/Chips/PropertyChip.swift` (shipped 2026-05-25) — no new initializer needed.

All shapes consistent.

**4. Surface-area honesty**

This plan is BIG. 23 tasks across 9 phases. Each phase ships green standalone per quirk #8 — user can pause at any phase boundary. Likely 2-3 long execution sessions if user has time; or split across several sessions hitting one phase per session. Phase A alone is 5 tasks of data-layer work; Phase H+I together are the cell-editing work that's the headline user feature.

The single biggest risk: **SwiftUI Table column dynamism on macOS**. The research confirmed there's no `TableColumnForEach` and `Group { if ... }` doesn't work inside `columns:` parameter. Task 15's `PropertyColumnBuilder` produces struct descriptors that get translated into static-column declarations via switch-based selection per detail view. If that pattern proves limiting at scale (eg. user has 20+ columns), the fallback is NSTableView via NSViewRepresentable (already noted in the locked UIX rules for no-vertical-borders enforcement). Same Representable could solve both. Flagged here so it's not a surprise.

Plan ready for approval.

---

## Cross-references

- `.claude/Planning/View-Settings-button-chrome-plan.md` — chrome slice (predecessor); retires to Superseded at Task 22
- `.claude/Planning/View-Settings-research-notes.md` — locked research; feeds remaining v0.3.1.x slices (Sort / Filter / Group / Layout / Edit Properties on existing)
- `.claude/Features/Properties.md` — property system canonical spec
- WWDC25 Session 323 — Liquid Glass toolbar popovers
- Apple SwiftUI docs (via Context7 `/websites/developer_apple_swiftui`) — `.popover`, `NavigationStack`, `@Environment(\.dismiss)`
- Notion reference screenshots (this session) — root menu / properties list / edit property panes
