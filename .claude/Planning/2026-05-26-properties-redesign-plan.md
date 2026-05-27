### View Settings Overhaul + Sidebar Selection Hotfix

#### Context

Six critical issues block usable Properties UX on the v0.3.1 ship:

1. **Sidebar selection regression** — entities created at runtime (PageTypes, ItemTypes, Collections, Pages, Items) render in the sidebar but tapping them does nothing. Only seed entities loaded at app launch respond. Root cause (confirmed via read-only Explore): `SidebarSelection(tag:)` resolves entity IDs via `AppGlobals.itemTypeManager.types.first(where:)` and `AppGlobals.pageTypeManager.types.first(where:)`, but `AppGlobals` snapshots once at app launch and never updates as live managers append new entities. Live `@Environment` managers see the new entities; `AppGlobals` doesn't.
2. **Popover pane chrome is inconsistent.** `PropertiesListPane` got an inline header last session; `PropertyVisibilityPane` / `PropertyTypePickerPane` / `EditPropertyPane` / `EditOptionPane` still use `.navigationTitle(...)` which on macOS renders a dark NavigationStack title band that cuts through the popover top (visible as the chopped "perty Visibility" / "+ New Property" titles in Nathan's screenshots).
3. **Property creation is broken for simple types.** Picking Number / Checkbox / Date / DateTime / URL / File commits a default-named property and pops back to the schema list with no editor visit. User can't name or customize. Only Select / MultiSelect / Status push into the editor. Nathan's spec is universal: every type lands in the editor (`Edit Properties → List of Types → Selection → Edit Icon + Title + Options`).
4. **Inline-edit TextFields lock the user in.** Clicking the Vault/Collection title or any property name opens a TextField with no click-outside commit. Only Enter or Tab commits — feels broken.
5. **ContentView toolbar back/forward buttons don't work** — clicking them does nothing. **Confirmed same root cause as #1.** `BackForwardButtons.applyStep()` (line 89) calls `SidebarSelection(stateRef:)`, which goes through the same `AppGlobals.contentManager` / `AppGlobals.pageTypeManager` / `AppGlobals.itemTypeManager` lookups (SidebarSelection.swift lines 27, 42, 47, 52, 57, 66). When AppGlobals points to stale manager instances (initial app-launch snapshot, never refreshed after Nexus switch or runtime-created entities), the lookup silently returns nil and the function exits early. (The Explore agent surfaced the bug from a NavDropdown angle; the actual button lives in ContentView's toolbar — the underlying broken call path is the same regardless.) **One fix covers both bugs.**
6. **Vault delete/rename broken on disk + in UI** — sidebar items for Vaults (PageTypes) cannot be deleted or renamed properly. Filesystem-layer issue. Root-cause investigation in flight via read-only Explore agent; full diagnosis folded into Phase 1 once the agent returns. Likely lives in `PageTypeManager.swift` rename/delete methods + their sync to SQLite index + their `types` array mutation.

Nathan's mockup (root + property-editor wireframe) is the structural answer to #2 and #3; the click-outside fix and sidebar hotfix address #1 and #4.

#### Phase 1 — Hotfix Triplet (Ships First, 3 Commits)

Three independent bug fixes that block visual testing of the redesign downstream. Each ships its own commit since they touch different subsystems.

##### Phase 1A — Selection Plumbing (1 commit)

Fixes both bugs #1 (sidebar selection regression) and #5 (toolbar back/forward buttons) — same root cause: `SidebarSelection` reading stale `AppGlobals` references.

**Files:**
- Modify: `Pommora/Pommora/Sidebar/SidebarSelection.swift` — remove every `AppGlobals.contentManager` / `AppGlobals.pageTypeManager` / `AppGlobals.itemTypeManager` lookup (lines 27, 42, 47, 52, 57, 66, 110, 140). Replace with parameter-injected manager instances. New init signatures: `SidebarSelection(tag:contentManager:pageTypeManager:itemTypeManager:)` and `SidebarSelection(stateRef:contentManager:pageTypeManager:itemTypeManager:)`.
- Modify: `Pommora/Pommora/Sidebar/SidebarView.swift` — read live managers via existing `@Environment(...)` declarations + pass them into the `.onChange(of: selectedTag)` closure when constructing `SidebarSelection(tag:...)`.
- Modify: `Pommora/Pommora/Navigation/BackForwardButtons.swift` (or wherever the toolbar back/forward live — grep to confirm exact path) — read live managers via `@Environment` + pass them into `SidebarSelection(stateRef:...)` calls in `applyStep()`.
- Modify: `Pommora/Pommora/ContentView.swift` — if the toolbar back/forward buttons are constructed inline (not via a separate view), env-injection happens here.
- Search + update any other callers of `SidebarSelection(tag:)` / `SidebarSelection(stateRef:)` — likely SidebarView + BackForwardButtons only; grep to confirm.

**Verification:**
1. Launch app → create new ItemType via sidebar "+" → click it → detail view routes.
2. Create new Set inside the Type → click → routes.
3. Same flow for new Page Type, new Page Collection, new Page, new Item.
4. Seed entities (Ideas + Notes) still work.
5. Navigate between several entities → click toolbar back button → previous loads. Click forward → returns. Repeat with newly-created entities.
6. `xcodebuild build` clean.

##### Phase 1B — Vault Delete/Rename Fix (1 commit)

Fixes bug #6 — sidebar items for Vaults cannot be deleted or renamed properly.

**Diagnosis (per Explore agent — partial confidence):** `PageTypeRow.swift:25` captures `let pageType: PageType` at row construction. After rename, the manager's `types` array updates correctly (`PageTypeManager.swift:216,234-238`), but the row continues rendering with the stale captured value at `PageTypeRow.swift:123` (`SelectableRow(title: pageType.title, ...)`). Same pattern exists on `ItemTypeRow` per the agent but doesn't reproduce there — suggesting the true root cause may be environmental (timing of rename completion vs ForEach diff) or PageType-specific (something the agent didn't pinpoint).

**Execution approach:** Re-diagnose at commit time to confirm root cause before committing the fix. Two candidate fixes:

1. **Stable-ID row refactor (cleaner):** Change `PageTypeRow` from `let pageType: PageType` to `let pageTypeID: String` + computed `pageType` lookup from `@Environment(PageTypeManager.self)`. Row always reads current state from the live manager. Mirror change to `ItemTypeRow` defensively (even though it doesn't reproduce there) — same architecture, same fix.
2. **Force re-render via reset (surgical):** Trigger `PageTypeRow` re-instantiation after rename by toggling a dependency or clearing selection. Less invasive but more brittle.

Default: option 1 (stable-ID refactor). If timing/env diagnosis reveals a different cause, plan adjusts.

**Delete path:** Verify confirmation dialog completes + `confirmingDelete = nil` + active sidebar selection is cleared if it pointed to the deleted PageType (else selection holds a stale tag that breaks subsequent navigation).

**Files:**
- Modify: `Pommora/Pommora/Sidebar/PageTypeRow.swift` — refactor to ID-based lookup.
- Modify: `Pommora/Pommora/Sidebar/ItemTypeRow.swift` — same refactor (defensive symmetry).
- Modify: `Pommora/Pommora/Vaults/PageTypeManager.swift` (if delete-path side-effects are missing) — clear selection on delete OR signal a row-refresh.
- Verify: `Pommora/Pommora/Items/ItemTypeManager.swift` for symmetric delete-path coverage.

**Verification:**
1. Create new Vault → rename via sidebar context menu → sidebar row immediately reflects new name.
2. Rename existing Vault → same.
3. Delete a Vault → row disappears immediately; folder moves to `.trash` per architecture; SQLite index updates.
4. Same flow for Page Collection / ItemType / Item Collection (defensive symmetry test).

##### Phase 1 Summary

Total Phase 1 commits: 2 (selection plumbing + vault delete/rename).

#### Phase 2 — View Settings Popover Redesign

##### 2A. New Root (Replaces `StorageMenuRoot`)

```
┌─────────────────────────────────────┐
│ [📁] [Vault/Collection Title]       │  inline-edit (chevron deferred)
│ [📊] [View Title]                   │  inline-edit (chevron deferred)
│  ─────                              │
│ 📑 Edit Properties               >  │  ACTIVE → PropertiesListPane
│ 📑 Visibility                    >  │  ACTIVE → PropertyVisibilityPane
│ 📑 Templates                        │  MUTED  (no chevron, no destination)
│ 📑 Filter                           │  MUTED
│ 📑 Group                            │  MUTED
│ 📑 Sort                             │  MUTED
└─────────────────────────────────────┘
```

**Locked from Nathan's spec:**
- **Row order (top to bottom):** Vault/Collection title → View title → Edit Properties → Visibility → **Templates** → Filter → Group → Sort. Templates sits right after Visibility per directive. Bottom triplet: Filter → Group → Sort (Filter before Group per latest directive).
- **Row 1 and Row 2 chevrons are dropped at v0.3.1.0.1.** Color picker (Row 1) and Layout pane (Row 2) are both deferred; per Nathan's earlier offer ("we could remove the chevron on the title areas; I'm fine with that") and his "DO NOT say 'coming in version X.X' just keep it muted" directive, dropping the chevrons until their destinations are wired is cleaner than rendering disabled/no-op chevrons or stub destinations with version annotations.
- **Muted rows have NO version annotation** ("Coming v0.X.X" text removed). Plain tertiary-foreground icon + label, no right-side text, no chevron, not tappable. Same visual treatment as the old `StorageMenuRoot.mutedRow` but with the version note stripped.
- **Two active rows at first ship** — Edit Properties + Visibility. The four muted rows below (Templates, Group, Filter, Sort) get their chevrons + push destinations as their respective features ship.
- **No stub destination panes** — no `SortPane.swift` / `GroupPane.swift` / `LayoutPane.swift` / `ColorPickerPane.swift` files needed at this ship. The muted rows have no destination, period.

**Files:**
- Modify: `Pommora/Pommora/ViewSettings/StorageMenuRoot.swift` — full rewrite to the new 8-row layout. Two active rows + four muted rows + two inline-edit rows. Keep the muted-row helper concept but drop the version-note parameter.
- Modify: `Pommora/Pommora/ViewSettings/ViewSettingsRoute.swift` — no new routes needed for this ship (muted rows have no destination). New routes (`.color`, `.layout`, `.sort`, `.filter`, `.group`, `.templates`) get added later as their features land.
- `ViewSettingsPopover.swift` — no changes needed (no new destinations).

##### 2B. Unified Pane Chrome via `PaneHeader`

New shared component renders the back chevron + title inside popover content (not via `.navigationTitle`), killing the dark NavigationStack band uniformly across every pane.

```swift
struct PaneHeader: View {
    @Binding var path: [ViewSettingsRoute]
    let title: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { if !path.isEmpty { path.removeLast() } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back")
                Text(title).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 8)
            Divider()
        }
    }
}
```

**Files:**
- Create: `Pommora/Pommora/ViewSettings/PaneHeader.swift`
- Modify each pane to use `PaneHeader` + drop `.navigationTitle(...)`:
  - `PropertiesListPane.swift` — replace existing inline `inlineHeader` ViewBuilder
  - `PropertyVisibilityPane.swift`
  - `PropertyTypePickerPane.swift`
  - `EditPropertyPane.swift`
  - `EditOptionPane.swift`

##### 2C. Universal Property Creation Flow — Split Surface by Type Richness

Every type still lands in an editor after creation (Bug #2 fix), but the editor SURFACE varies by how much config the type needs:

- **Inline popup (anchored to the row, no navigation push):** Number, URL, Checkbox, File. These types need only icon + title + (optional) one picker + Duplicate/Delete. A small anchored popover fits the entire editor without leaving the schema list.
- **Pushed pane (full NavigationStack push):** Select, MultiSelect, Status, Date & Time, Relation. These types need nested chevron-rows (options → EditOptionPane; status groups → EditOptionPane; Display Date / Display Time sub-pickers; target picker + mirror toggle + limit) and don't fit in a popup. Stays as `.editProperty(propertyID:)` route push.

**Decision matrix:**

| Type | Surface | Inline contents |
|------|---------|-----------------|
| Number | popup | icon + title + Format picker + Duplicate/Delete |
| URL | popup | icon + title + Duplicate/Delete |
| Checkbox | popup | icon + title + Duplicate/Delete |
| File | popup | icon + title + Duplicate/Delete |
| Date & Time | **push** | (see 2D-DateTime — Display Date + Display Time chevron-rows) |
| Select | push | (see 2D middle-sections — Options + "+" + chevron-rows to EditOptionPane) |
| MultiSelect | push | same as Select |
| Status | push | (see 2D middle-sections — 3 group sections + Display As + chevron-rows) |
| Relation | push | (see 2D-Relation — target picker + mirror toggle + limit) |

**New files:**
- Create: `Pommora/Pommora/ViewSettings/PropertyEditorPopover.swift` — the inline popup view that renders the simple-types editor. Anchored via `.popover(isPresented:arrowEdge:)` on the schema-list row. Same `@FocusState` click-outside-commits pattern as the pushed panes.

**Modifications:**
- Modify: `Pommora/Pommora/ViewSettings/PropertiesListPane.swift` — schema-list rows for simple types open `PropertyEditorPopover` via popover instead of pushing `.editProperty`. Rich-type rows still push.
- Modify: `Pommora/Pommora/ViewSettings/PropertyTypePickerPane.swift` — `commit(_:)` branches:
  - Simple type → create property + pop back to schema list + auto-open the inline popup on the new row (so the user lands in the editor immediately, same as Notion's "click new property → editor opens" UX, just popup-style).
  - Rich type → create property + push `.editProperty(propertyID:)` as before.
  - Drop the `requiresOptionConfig` branch + the simple-type early-pop-without-editor logic.

**Why this matters:** Notion's pattern is "simple types get small inline editors; rich types get full sub-pages." Pommora's previous all-push design felt heavy for things like renaming a Checkbox. The popup keeps the user oriented in the schema list while still letting them edit.

##### 2D. `EditPropertyPane` Refresh (Per Wireframe)

```
┌─────────────────────────────────────┐
│ < Edit Property                     │  PaneHeader
│ ─────                               │
│ [📁]  [Title TextField]             │  icon + inline-edit title
│                                     │
│ Awaiting                       +    │  Status group header w/ "+"
│ ─ ● Awaiting option           >    │  draggable + chevron-push
│ In Progress                    +    │
│ ─ ● In Progress option        >    │
│ Complete                       +    │
│ ─ ● Complete option           >    │
│                                     │
│ Display As             [Type] ▾    │  Status-only (chip/label/box)
│ ─────                               │
│ ⎘  Duplicate property               │  footer
│ 🗑  Delete property                  │
└─────────────────────────────────────┘
```

**Universal pane shape** (every type, no exceptions):

```
< Edit Property                  ← PaneHeader
─────
[icon] [Title TextField]         ← ALWAYS present, every type
─────
[type-specific middle section]   ← per table below — may be empty for some
─────
⎘  Duplicate property            ← ALWAYS present, every type
🗑  Delete property
```

Icon + title row and Duplicate/Delete footer are universal across **every** property type (Number, Checkbox, Date, DateTime, Select, MultiSelect, Status, URL, File, Relation). The only thing that varies per type is the **middle section**.

**Per-type middle sections:**

| Type | Middle section |
|------|---------------|
| **Number** | "Display as" Format picker chevron-row (existing `NumberFormatPicker` — Decimal / Percent / Currency / etc.) |
| **Date & Time** | Two chevron-row sub-pickers: **Display Date** (date format options) + **Display Time** (time format options including "None" to hide time entirely). See "Date & Time consolidation" below. |
| **Select / MultiSelect** | "Options" section header with "+" + draggable rows + chevron-push to `EditOptionPane` |
| **Status** | Three group sections (defaults: Awaiting / In Progress / Complete — Pommora's current labels; renameable per existing code), each header with its own "+" + draggable rows (drag within and across groups) + chevron-push + bottom "Display as" picker (Chip / Label / Box) |
| **Checkbox** | _empty_ (just icon + title + Duplicate/Delete) |
| **URL** | _empty_ (just icon + title + Duplicate/Delete) |
| **File** | _empty_ (just icon + title + Duplicate/Delete) |
| **Relation** | **NEW for v0.3.1.0.1** — verified against Notion's actual UX. See 2D-Relation below. |

Every type — including Checkbox, URL, File — pushes to `EditPropertyPane` (Bug #2 universal flow). The pane shows icon + title + Delete/Duplicate even when the middle is empty.

`EditOptionPane` finally becomes reachable via chevron-push (it shipped last session but no caller pushed the route in normal UX).

##### 2D-Relation. Relation Editor (Verified Against Notion's Actual UX)

Notion's actual flow (per `notion.com/help/relations-and-rollups`):
1. User names the property
2. Selects `Relation` type
3. **Searchable picker** for target database
4. TOGGLE: `Show on [target name]` — default OFF (one-way); ON reveals an inline TextField to name the mirror property
5. (Optional) Limit picker — `1 page` or `No limit`
6. Preview text shows directional relationship
7. Click `Add relation` button to finalize both directions simultaneously

Pommora's v0.3.1.0.1 Relation editor mirrors this:

```
< Edit Relation                          ← PaneHeader
─────
[📁] [Title TextField]                   ← this-side icon + inline-edit title
─────
Related to                  [searchable ↧]   ← searchable picker for target Type/Collection
─────
[ ] Show on [Target Name]                ← TOGGLE (default OFF — one-way relation)
    │
    └ [Mirror Title TextField]           ← appears only when toggle is ON
─────
Limit          [ 1 page | No limit ▾ ]   ← picker, default No limit
─────
⎘  Duplicate property
🗑  Delete property
```

**Implementation:**
- New private subview inside `EditPropertyPane.swift`: `RelationEditor(def:onUpdate:)` — wraps the target picker + mirror toggle + limit picker.
- **Searchable target picker** — searches across PageTypes + ItemTypes + PageCollections + ItemCollections in the active Nexus. Reads from `PageTypeManager.types` + `ItemTypeManager.types`. Drives `PropertyDefinition.relationScope` enum (`.pageType(id)` / `.itemType(id)` / `.pageCollection(id)` / `.itemCollection(id)` / `.contextTier(tier)`).
- **Mirror toggle** — `Show on [target name]` Toggle. Default OFF. When ON, reveals an inline TextField for mirror property name. Mirror creation uses `DualRelationCoordinator` per locked decision #8.
- **Limit picker** — Picker over `[.single, .unlimited]`. Adds new `relationLimit: RelationLimit?` field to `PropertyDefinition`. Default `.unlimited`. Schema migration: existing relations default to `.unlimited`.
- Visual arrow notation — column-header rendering uses `↗` per Notion convention (deferred to a chip-render polish patch; not in v0.3.1.0.1 editor scope).

**Defer to v0.3.1.5:** multi-step Relation wizard (preview affected entities, confirmation dialogs, scope-reconfiguration of existing relations with cascading effects). The v0.3.1.0.1 editor is enough for creating + naming a new Relation pair from scratch + toggling mirror + setting limit; advanced reconfiguration ships later.

##### 2D-DateTime. Date & Time Consolidation

**Schema change:** Drop `PropertyType.date` entirely. Keep only `PropertyType.dateTime` (UI label "Date & Time"). The flexibility previously provided by `.date` (date without time) is now achieved by setting Display Time to "None" within the consolidated `.dateTime` type.

**Migration:** Existing `.date` properties in user data auto-migrate to `.dateTime` with Display Time = `.none` (preserves existing display behavior). Migration runs in `PropertyIDMigration` or a sibling migration step on Nexus open. Schema sidecar `schema_version` bumps to 2.

**Editor middle section for Date & Time:**

```
Display Date              [Full date ▾]   ← chevron-row picker (renames + reuses DateFormat enum)
Display Time              [12-hour ▾  ]   ← chevron-row picker — includes "None" option
```

**`DateFormat` enum changes:**
- Existing 6 date-format cases stay.
- New `TimeFormat` enum: `.none`, `.twelveHour`, `.twentyFourHour` (3 cases). Default `.none` (matches old `.date` behavior).
- `PropertyDefinition` gets new `timeFormat: TimeFormat?` field.

**Property type picker (`PropertyTypePicker`):** Drop the "Date" row entirely; keep only "Date & Time" (relabel from the old "Date & Time" entry; effectively dropping one row from the 10-type picker → 9 user-creatable types now).

**Files:**
- Modify: `Pommora/Pommora/Vaults/PropertyDefinition.swift` — drop `.date` case from `PropertyType` enum; add `timeFormat: TimeFormat?` field.
- Modify: `Pommora/Pommora/ViewSettings/DateFormat.swift` — add new `TimeFormat` enum.
- Modify: `Pommora/Pommora/Properties/Editor/...` — add `TimeFormatPicker` (mirror of `DateFormatPicker`).
- Add: migration step in `Pommora/Pommora/Migration/PropertyIDMigration.swift` (or sibling) to convert old `.date` → `.dateTime` + set `timeFormat = .none`.

**Drag-reorder is new work for the option editors.** SelectOptionsEditor.swift:10 + StatusGroupsEditor.swift:13 explicitly comment "Drag-only reordering ships at Task 11" — it was planned but never shipped. Reuse the pattern from `Pommora/Pommora/Detail/SessionRowOrdering.swift` + `Pommora/Pommora/Detail/DetailRowDragPayload.swift` (table-row drag-reorder shipped in commits 9b4ca3e + 8bf82d9), plus the `.onMove` / `.draggable` / `.dropDestination` patterns established in `PageTypeRow.swift` / `ItemTypeRow.swift` / `TopicRow.swift` / `PageCollectionRow.swift` / `SidebarView.swift`.

**Drag visual requirements (per Nathan):**
- The dragged option row must **preserve its Liquid Glass styling** during drag — no plain placeholder rectangle.
- The other rows must use **Finder-style displacement animation** — non-dragged rows visually slide to make room as the dragged row crosses their position, not a hard snap. Nathan flagged the current sidebar's drag structure can't achieve this; we may need a custom gesture-driven implementation (DragGesture + animated `.offset` per row) rather than relying on `.onMove`'s built-in animation. Verify against `DetailRowDragPayload`'s approach first — if it gives Finder-style displacement out of the box, reuse it. If not, custom gesture handling is in scope for this ship.
- If implementing the Finder-style displacement requires more than a half-day of work or AppKit interop, drag-reorder gets DEFERRED to a v0.3.1.0.2 follow-up patch and v0.3.1.0.1 ships add/remove only. Decision made during execution.

**Files:**
- Modify: `Pommora/Pommora/ViewSettings/EditPropertyPane.swift` — restructure body to wireframe shape. Replace `SelectOptionsEditor` / `StatusGroupsEditor` inline-edit calls with new chevron-row implementations.
- Modify: `Pommora/Pommora/Properties/Editor/SelectOptionsEditor.swift` — full rewrite: chevron-push pattern + drag-reorder per the visual requirements above + replace "Add" with "+".
- Modify: `Pommora/Pommora/Properties/Editor/StatusGroupsEditor.swift` — full rewrite: per-group "+" headers + drag-reorder within and across groups + chevron-push + same drag visuals as SelectOptionsEditor.
- Read first (reuse-or-extend evaluation): `Pommora/Pommora/Detail/SessionRowOrdering.swift` + `Pommora/Pommora/Detail/DetailRowDragPayload.swift` — if generic enough, lift into a shared `Pommora/Pommora/Ordering/` module (folder already exists per filesystem) and reuse from option editors.

##### 2E. Click-Outside Commits Inline Edits

All inline-edit `TextField`s gain `@FocusState` + commit-on-focus-loss. Locked pattern:

```swift
@FocusState private var isFieldFocused: Bool
@State private var draft: String = ""

TextField("...", text: $draft)
    .focused($isFieldFocused)
    .onChange(of: isFieldFocused) { _, focused in
        if !focused { Task { await commit() } }
    }
    .onSubmit { isFieldFocused = false }      // Enter → focus loss → commit
    .onExitCommand { draft = original; isFieldFocused = false }  // ESC reverts
```

Applies to:
- New root Row 1 (Vault/Collection title) + Row 2 (View title) inline-edit TextFields
- `EditPropertyPane` title TextField
- `EditOptionPane` label TextField
- Any inline option-label TextFields inside `SelectOptionsEditor` / `StatusGroupsEditor` (post-2D refactor, most option editing pushes to `EditOptionPane`, so this is the option-label TextField inside that pane)

#### Out of Scope (Deferred)

- Color picker (Row 1 chevron) — lights up in a follow-up patch
- Layout pane (Row 2 chevron) — board / cards / gallery, deferred to v0.5.0
- Group pane content — chevron + destination wire in v0.3.1.4
- Filter pane content — chevron + destination wire in v0.3.1.3
- Sort pane content — chevron + destination wire in v0.3.1.2
- Templates feature — wire when the Templates feature itself lands (post-v1)
- Relation **multi-step wizard** (preview affected entities, cascading scope reconfiguration of existing relations) — v0.3.1.5. (The basic Relation editor — Select Location + Mirror title — ships at v0.3.1.0.1 per 2D-Relation above.)
- Existing-property change-type — v0.3.1.5

All six deferred surfaces render as muted-only rows at v0.3.1.0.1: visible in the popover but inactive, no version annotation, no destination pane.

#### Critical Files

```
Pommora/Pommora/Sidebar/
  SidebarSelection.swift        # Phase 1A: drop AppGlobals — both inits
  SidebarView.swift             # Phase 1A: pass live managers into .onChange
  PageTypeRow.swift             # Phase 1B: ID-based lookup (kill stale capture)
  ItemTypeRow.swift             # Phase 1B: same refactor (defensive symmetry)

Pommora/Pommora/Vaults/
  PageTypeManager.swift         # Phase 1B: verify delete-path clears selection + signals re-render
  PropertyDefinition.swift      # Phase 2D-Schema: drop .date case; add timeFormat + relationLimit fields

Pommora/Pommora/Items/
  ItemTypeManager.swift         # Phase 1B: defensive symmetry on delete-path

Pommora/Pommora/Navigation/  (or wherever BackForwardButtons lives — grep to confirm)
  BackForwardButtons.swift      # Phase 1A: pass live managers into applyStep()

Pommora/Pommora/
  ContentView.swift             # Phase 1A: ensure toolbar back/forward gets live env managers (if constructed inline)

Pommora/Pommora/Detail/
  SessionRowOrdering.swift      # Phase 2D: read first; lift to shared Ordering/ module if generic
  DetailRowDragPayload.swift    # Phase 2D: read first; reuse for option-row drag

Pommora/Pommora/ViewSettings/
  PaneHeader.swift              # NEW — shared header
  PropertyEditorPopover.swift   # NEW — inline popup editor for simple types (Number/URL/Checkbox/File)
  StorageMenuRoot.swift         # full rewrite — new 8-row layout (2 inline-edit + 2 active + 4 muted)
  PropertiesListPane.swift      # use PaneHeader; simple-type rows open popup, rich-type rows push
  PropertyVisibilityPane.swift  # use PaneHeader
  PropertyTypePickerPane.swift  # use PaneHeader + split simple/rich commit branches
  EditPropertyPane.swift        # PaneHeader + wireframe restructure + FocusState (rich types only)
  EditOptionPane.swift          # PaneHeader + FocusState

Pommora/Pommora/Properties/Editor/
  SelectOptionsEditor.swift     # Phase 2D-Options: chevron-push + drag-reorder + "+"
  StatusGroupsEditor.swift      # Phase 2D-Options: per-group "+" + drag-reorder + chevron-push
  TimeFormatPicker.swift        # Phase 2D-Schema: NEW — mirrors DateFormatPicker

Pommora/Pommora/ViewSettings/
  DateFormat.swift              # Phase 2D-Schema: add TimeFormat enum

Pommora/Pommora/Properties/
  PropertyType.swift (or wherever the enum lives)  # Phase 2D-Schema: drop .date; picker shows 9 user-creatable types

Pommora/Pommora/Migration/  (or wherever migrations live)
  PropertyTypeDateMigration.swift  # Phase 2D-Schema: NEW or sibling — old .date → .dateTime + timeFormat=.none
```

#### Implementation Notes (Locked Execution Rules)

- **UI implementation is inline by the controller, never dispatched to a subagent.** Visual fidelity to Nathan's uploaded screenshots is the implementer's direct responsibility. Subagent dispatch is reserved for non-visual work (build verification, doc sweeps, future-feature scaffolding).
- **Screenshots are the canonical visual reference at v0.3.1.0.1.** The three uploaded mockups (new root, property type list, Status property editor) drive layout + interaction shape. Pixel-perfect Figma reference is NOT a v0.3.1.0.1 ship requirement — if higher precision becomes useful during execution (likely for the EditPropertyPane wireframe restructure with section headers + drag-reorder), the controller pauses and asks Nathan for the Figma link, then uses `figma:figma-use` skill + MCP to pull exact specs.
- **Liquid Glass treatment** is hardcoded across all panes via `PaneHeader` + popover-content backdrop inheritance — no per-pane custom chrome.
- **Quirk #8 (stub-and-progressively-replace)** applies — each commit ships green standalone via `xcodebuild build` verification.
- **Quirk #16 (env injection)** — every `@Environment(X.self)` declared on a popover-hosted view must be re-injected by the popover host (`ViewSettingsButton`); both detail-view and popover variants apply to anything we add.

#### Verification (End-to-End Visual Smoke)

1. **Sidebar regression (Phase 1A):** Create new ItemType via sidebar "+" → click → detail view routes. Same for new Set, new PageType, new PageCollection, new Page, new Item. Seed entities still work. Toolbar back/forward steps through history correctly across new + seed entities.
1b. **Vault delete/rename (Phase 1B):** Rename a Vault via sidebar context menu → row immediately reflects new name. Delete a Vault → row disappears + folder to `.trash` + SQLite index updated + selection cleared if was on deleted Vault.
2. **Popover chrome uniform:** Open View Settings → push into Edit Properties + Visibility (the only active rows) + Property Picker + Edit Property + Edit Option → every pane header looks identical, no dark NavigationStack band anywhere. Muted rows (Templates / Filter / Group / Sort) render but are not tappable.
3. **Universal property creation, split surface:** Edit Properties → + New Property → tap every type (9 user-creatable types after Date & Time consolidation):
   - **Simple types** (Number / URL / Checkbox / File) → property is created + inline popup opens anchored to the new row (NOT a pushed pane). Editor has icon + title + (Number only: Format picker) + Duplicate/Delete.
   - **Rich types** (Select / MultiSelect / Status / Date & Time / Relation) → property is created + push to `EditPropertyPane`.
4. **Click-outside commits:** Type into Row 1 title → click outside the popover → name commits. Same for Row 2, property name, option label. ESC reverts. Enter commits.
5. **EditPropertyPane wireframe match:** Status property shows three sections (Awaiting / In Progress / Complete), each with "+". Drag options to reorder within and across sections. Click an option → push to `EditOptionPane`. Display As at bottom shows Chip / Label / Box.
6. **Per-type editor surfaces render correctly:**
   - Number popup → icon + title + Format chevron-row + Delete/Duplicate
   - URL popup → icon + title + Delete/Duplicate
   - Checkbox popup → icon + title + Delete/Duplicate
   - File popup → icon + title + Delete/Duplicate
   - Date & Time pushed pane → icon + title + Display Date + Display Time chevron-rows + Delete/Duplicate
   - Select / MultiSelect pushed pane → icon + title + Options section + "+" + draggable rows + chevron-push to EditOptionPane + Delete/Duplicate
   - Status pushed pane → icon + title + 3 group sections + per-group "+" + draggable rows + chevron-push + Display As picker + Delete/Duplicate
   - Relation pushed pane → icon + title + searchable target picker + mirror toggle + (conditional) mirror name TextField + limit picker + Delete/Duplicate
7. **Relation creation end-to-end (Notion-verified flow):** Edit Properties → + New Property → Relation → land in Relation editor → search target Type/Collection → toggle ON `Show on [target]` → enter mirror name → set Limit if desired → exit popover → reopen → mirror relation property visible on target Type (`DualRelationCoordinator` did its job).
8. **Date & Time consolidation:** Existing user data with `.date` properties migrates cleanly (visible as Date & Time with Display Time = None — renders identically to old `.date`). Type picker no longer shows separate "Date" row; only "Date & Time".
9. **Build:** `xcodebuild -project "Pommora/Pommora.xcodeproj" -scheme Pommora -destination 'platform=macOS' build` clean. Test runner has been intermittently hanging; build-only is the verification standard.

#### Commit Strategy

Each task ships green standalone per quirk #8 (stub-and-progressively-replace). Expected commit count:

- Phase 1A (selection plumbing — fixes sidebar + toolbar back/forward in one shot): 1 commit
- Phase 1B (Vault delete/rename — stable-ID row refactor): 1 commit
- 2A new root layout (8 rows, 2 active + 2 inline-edit + 4 muted): 1 commit
- 2B `PaneHeader` extraction + apply to all 5 existing panes: 1 commit
- 2C split simple/rich property editor surfaces (`PropertyEditorPopover` for simple types + split push logic in `PropertyTypePickerPane`): 1 commit
- 2D-Schema Date & Time consolidation (drop `.date`, add `TimeFormat` enum, migration): 1 commit
- 2D-Editor `EditPropertyPane` wireframe restructure (icon+title universal + per-type middle sections + footer): 1 commit
- 2D-Options `SelectOptionsEditor` rewrite + `StatusGroupsEditor` rewrite + drag-reorder: 2 commits
- 2D-Relation Relation editor (searchable target + mirror toggle + limit picker): 1 commit
- 2E `@FocusState` click-outside-commits across all inline-edit TextFields: 1 commit

Total: 11-12 commits. Plus a Handoff sweep commit at the end.

#### Open Items to Confirm at Approval

1. **`PropertiesListPane` row shape** — keep the existing lock-badge + chevron list with `+ New property` footer, or restructure to match the wireframe's pane 2 (five rows with file-stack icon + chevron)? Plan default: keep existing structure (it already matches Notion's pattern); the wireframe's pane 2 appears to be a stylized representation of the existing pane, not a redesign.
2. **Drag-reorder fallback** — if achieving Liquid Glass + Finder-style displacement in option-row drag requires custom AppKit interop (more than a half-day of work), drag-reorder gets deferred to v0.3.1.0.2 and v0.3.1.0.1 ships add/remove only. Decision deferred to execution time when actual implementation cost is visible.
3. **Property description field (Notion staple I'm currently NOT including)** — Notion lets every property carry a multi-line description that surfaces below the title in the editor + as a tooltip on the column header. Pommora's `PropertyDefinition` doesn't currently have a `description: String?` field. Plan default: NOT included at v0.3.1.0.1 (no sketch from Nathan shows it; keeps schema lean). If Nathan wants this in scope, it's a small additive change: new field on `PropertyDefinition` + a small `TextField(axis: .vertical)` below the title row in EditPropertyPane.
4. **Per-property Sort/Hide/Wrap quick-actions inside EditPropertyPane (Notion pattern)** — Notion's per-property editor includes inline Sort ascending / Sort descending / Hide in view / Wrap column buttons. Pommora's design intentionally separates these into their own panes (Sort pane / Visibility pane / Group pane). Plan default: KEEP the pane-separation (Pommora's architecture); skip per-property quick-actions. If Nathan wants quick-actions in the editor, scope expands.
5. **Relation Limit picker** — Notion offers `1 page` or `No limit` per relation. Plan default: SHIP it at v0.3.1.0.1 (adds `RelationLimit` enum + field to `PropertyDefinition`). If Nathan wants it deferred, drop from 2D-Relation.
