# Views V2 — NSOutlineView Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current SwiftUI `Table` in the detail views with a native AppKit `NSOutlineView` wrapped via `NSViewRepresentable`, with full saved-views (sort/filter/group/column config), cross-group drag, and width/order column persistence — while remaining visually indistinguishable from the current native table.

**Architecture:** An `OutlineItem` class tree (group + leaf nodes) is built from `GroupResolver.[ResolvedGroup]` and fed to an `NSOutlineViewDataSource` Coordinator; SwiftUI property-editor cells are hosted inside `HostingCell<V>` (NSHostingView inside NSTableCellView) using `makeView(withIdentifier:owner:)` reuse. The ViewPipeline (filter → group → sort) and SavedView v2 schema are ported wholesale from the abandoned branch before the renderer is touched.

**Tech Stack:** Swift 6 strict concurrency, AppKit `NSOutlineView`, `NSViewRepresentable`, SwiftUI `NSHostingView`-in-`NSTableCellView`, Nuke (cover/banner thumbnails), GRDB (read-only index queries in pipeline source), existing Pommora managers.

**Source of salvage:** `git show views-FAILED-custom-table:<path>` for every Tier 1 and Tier 2 file listed below. The branch tip is `e3f9c72`.

---

> **UIX gate:** Before implementing any step marked `[UIX]`, STOP and ask Nathan to provide or confirm the Figma/screenshot design for that surface. Do not assume the screenshot reference below is sufficient for new or changed surfaces — get explicit approval first.

---

## Branch Quirks (carry into every subagent dispatch)

- Swift 6 ON: `nonisolated` + `MainActor.assumeIsolated` on every `@objc` coordinator method.
- `OutlineItem` must be a `class` (NSOutlineView tracks items by AnyObject identity).
- `HostingCell<V>.sizingOptions = []` to stop NSHostingView fighting the table layout engine.
- `xcodebuild test` builds + runs the app as the test host; it will block if any launch modal fires — the XCTest guard in `NexusManager.loadOnLaunch()` prevents this.
- Test filter: `-only-testing:PommoraTests/<SuiteTypeName>` must match the `@Suite`/struct name, NOT the file name. Always confirm a non-zero executed count.
- Gallery is OUT OF SCOPE for this branch. Do not port GalleryView or GalleryCard.
- Both targets use `PBXFileSystemSynchronizedRootGroup` — new Swift files auto-include; no pbxproj edits needed.
- Xcode auto-reorders GRDB/Yams in pbxproj on every build — revert those entries before committing.

---

## File Map

### New files (this branch creates them)

| File | Responsibility |
|---|---|
| `Detail/ViewPipeline/ViewItem.swift` | Value-type page row for the pipeline (id, title, modifiedAt, icon, frontmatter, parentID, setLabel) |
| `Detail/ViewPipeline/ResolvedGroup.swift` | One group from GroupResolver (id, title, kind, items, isCollapsed) |
| `Detail/ViewPipeline/FilterEvaluator.swift` | Per-type filter operator matrix |
| `Detail/ViewPipeline/ViewSortComparator.swift` | Sort comparator factory (renamed from SortComparator to avoid Foundation collision) |
| `Detail/ViewPipeline/GroupResolver.swift` | Structural / property / flat grouping engine |
| `Detail/ViewPipeline/ViewItemSource.swift` | Stamps parent + setLabel on ViewItems from manager caches |
| `Detail/ViewPipeline/GroupDropPlanner.swift` | Pure drop-intent decision: .reorder / .move / .rewriteProperty / .none |
| `Detail/ActiveViewStore.swift` | @Observable; reads/writes `state.json` activeViews + viewsButtonStyle |
| `Detail/Covers/CoverAssetStore.swift` | Copy-into-assets, 500MB cap, containment guard, delete |
| `Detail/OutlineTable/OutlineItem.swift` | AnyObject class tree node (group + leaf); feeds NSOutlineViewDataSource |
| `Detail/OutlineTable/OutlineTableView.swift` | NSViewRepresentable wrapping NSOutlineView + NSScrollView |
| `Detail/OutlineTable/OutlineTableCoordinator.swift` | @MainActor class; NSOutlineViewDataSource + Delegate; drag; column notifications |
| `Detail/OutlineTable/HostingCell.swift` | NSTableCellView subclass hosting NSHostingView<AnyView>; reuse-safe configure() |
| `Detail/OutlineTable/GroupHeaderCell.swift` | NSTableCellView for group header rows (title + count label) |
| `Detail/OutlineTable/TableColumnResolver.swift` | Resolves active SavedView's property_order → [OutlineColumn] (id, title, width, SF symbol) |
| `Detail/ViewTabs/ViewsDropdownButton.swift` | Toolbar pill: popover of saved views; inline rename/duplicate/delete/type-switch |
| `Detail/ViewSettings/StorageMenuRoot.swift` | Routing enum for view-settings pane |
| `Detail/ViewSettings/SortPane.swift` | Sort picker (Manual, Title, Created, Recent, property asc/desc) |
| `Detail/ViewSettings/FilterPane.swift` | Filter rule list + match toggle |
| `Detail/ViewSettings/GroupPane.swift` | Group picker (Default / property / Remove grouping) |
| `Detail/ViewSettings/LayoutPane.swift` | Banner toggle + property visibility eye-toggles + drag-to-reorder |
| `Vaults/SavedViewMutations.swift` | Toggle semantics: hide/un-hide, cover excluded, scrubDeletedProperty |

### Modified files

| File | What changes |
|---|---|
| `Vaults/SavedView.swift` | Replace `visibleProperties/hiddenProperties` with `property_order/hidden_properties/column_widths/collapsed_groups/card_size/show_cover/show_banner`; replace `GroupConfig` struct with discriminated enum |
| `Vaults/PageType.swift` | Add `banner: String?` field (nexus-relative path) |
| `Vaults/PageCollection.swift` | Add `banner: String?` field |
| `Vaults/PageFrontmatter.swift` (or equivalent) | Add `cover: String?` reserved field (never surfaced in properties UI) |
| `Vaults/PageTypeManager.swift` | Port `updateView`/`mutateViews` clobber fix (fresh disk read before save); add `addView`, `duplicateView`, `deleteView`, `renameView`; add `reorderPages(in:movingIDs:before:)` |
| `Nexus/NexusState.swift` | Add `activeViews: [String: String]` + `viewsButtonStyle: String?` |
| `Nexus/OrderPersister.swift` | Add `setActiveView(_:for:)` + `setViewsButtonStyle(_:)` |
| `Nexus/NexusEnvironment.swift` | Add `ActiveViewStore` + `CoverAssetStore` as stored properties + environment injections |
| `Nexus/NexusPaths.swift` | Add `assetsDir(for entityID: String, in nexus: URL) -> URL` |
| `Detail/PageTypeDetailView.swift` | Replace SwiftUI `Table` with `OutlineTableView`; add Views dropdown in header |
| `Detail/PageCollectionDetailView.swift` | Replace SwiftUI `Table` with `OutlineTableView`; add Views dropdown in header |
| `Detail/DetailRow.swift` | Keep as-is — still used for context menus / rename / delete routing; `OutlineItem` wraps it |

---

## Task 1: Branch + Baseline Screenshot

**Files:** none (git + screenshot only)

- [ ] **Step 1: Create the branch**

```bash
git -C "/Users/nathantaichman/The Studio/Projects/Project Pommora" checkout -b views-v3
```

Expected: `Switched to a new branch 'views-v2'`

- [ ] **Step 2: Verify clean working tree**

```bash
git -C "/Users/nathantaichman/The Studio/Projects/Project Pommora" status
```

Expected: `nothing to commit, working tree clean`

- [ ] **Step 3: Take a baseline screenshot of the native SwiftUI table**

Build and launch the app, navigate to any collection in The Nexus vault, screenshot the table. Save to `/tmp/pommora-native-table-baseline.png`. This is the visual reference for the NSOutlineView result.

```bash
xcodebuild -project "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora.xcodeproj" \
  -scheme Pommora -configuration Debug build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
```

Then launch the built app and take the screenshot manually.

- [ ] **Step 4: Commit the branch**

```bash
git -C "/Users/nathantaichman/The Studio/Projects/Project Pommora" commit --allow-empty \
  -m "chore: branch views-v3 from main (NSOutlineView retry)"
```

---

## Task 2: SavedView V2 Schema

**Files:**
- Modify: `Pommora/Pommora/Vaults/SavedView.swift`
- Test: `PommoraTests/Vaults/SavedViewV2Tests.swift` (new)
- Test: `PommoraTests/Vaults/GroupConfigV2Tests.swift` (new)

**Source:** `git show views-FAILED-custom-table:Pommora/Pommora/Vaults/SavedView.swift`

The existing `SavedView` has `visibleProperties/hiddenProperties` (v1 schema). We replace this with the v2 schema that the whole pipeline depends on. The old fields become decode-only aliases for migration.

- [ ] **Step 1: Write failing tests**

Create `PommoraTests/Vaults/SavedViewV2Tests.swift`:

```swift
import Testing
@testable import Pommora

@Suite struct SavedViewV2Tests {
    @Test func propertyOrderRoundtrips() throws {
        let view = SavedView(
            id: "view_01",
            name: "All Pages",
            propertyOrder: ["_title", "prop_abc", "_modified_at"],
            hiddenProperties: ["prop_abc"]
        )
        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(SavedView.self, from: data)
        #expect(decoded.propertyOrder == ["_title", "prop_abc", "_modified_at"])
        #expect(decoded.hiddenProperties == ["prop_abc"])
    }

    @Test func columnWidthsRoundtrip() throws {
        var view = SavedView(id: "view_02", name: "T", propertyOrder: ["_title"])
        view.columnWidths = ["_title": 250.0]
        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(SavedView.self, from: data)
        #expect(decoded.columnWidths["_title"] == 250.0)
    }

    @Test func legacyVisiblePropertiesDecodesAsPropertyOrder() throws {
        // v1-era sidecar must decode without crash and populate propertyOrder
        let json = """
        {"id":"view_03","name":"T","type":"table",
         "visible_properties":["prop_x","prop_y"],"hidden_properties":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SavedView.self, from: json)
        #expect(decoded.propertyOrder == ["prop_x", "prop_y"])
    }

    @Test func emptyJsonDecodesWithSaneDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SavedView.self, from: json)
        #expect(decoded.id == "")
        #expect(decoded.propertyOrder.isEmpty)
    }
}
```

Create `PommoraTests/Vaults/GroupConfigV2Tests.swift`:

```swift
import Testing
@testable import Pommora

@Suite struct GroupConfigV2Tests {
    @Test func structuralRoundtrips() throws {
        let config = GroupConfig.structural
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(GroupConfig.self, from: data)
        #expect(decoded == GroupConfig.structural)
    }

    @Test func propertyGroupingRoundtrips() throws {
        let config = GroupConfig.property(PropertyGrouping(propertyID: "prop_abc", order: ["opt1","opt2"]))
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(GroupConfig.self, from: data)
        if case .property(let g) = decoded {
            #expect(g.propertyID == "prop_abc")
            #expect(g.order == ["opt1","opt2"])
        } else {
            Issue.record("Expected .property case")
        }
    }

    @Test func flatRoundtrips() throws {
        let config = GroupConfig.flat
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(GroupConfig.self, from: data)
        #expect(decoded == GroupConfig.flat)
    }

    @Test func unknownKindDegradesLeniently() throws {
        let json = """{"kind":"future_unknown","property_id":"x"}""".data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(GroupConfig.self, from: json)
        // Must not throw — lenient decode returns nil or .structural fallback
        _ = decoded  // just confirm no throw
    }
}
```

- [ ] **Step 2: Run tests to confirm RED**

```bash
xcodebuild test -project "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora.xcodeproj" \
  -scheme Pommora -destination "platform=macOS" \
  -only-testing:PommoraTests/SavedViewV2Tests \
  -only-testing:PommoraTests/GroupConfigV2Tests 2>&1 | tail -20
```

Expected: compile error (types don't exist yet)

- [ ] **Step 3: Replace SavedView.swift**

Port the v2 version from the failed branch:

```bash
git show views-FAILED-custom-table:Pommora/Pommora/Vaults/SavedView.swift \
  > "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora/Vaults/SavedView.swift"
```

Then verify the file compiles and contains `propertyOrder`, `columnWidths`, `collapsedGroups`, `cardSize`, `showCover`, `showBanner`, the discriminated `GroupConfig` enum, `PropertyGrouping`, `CardSize`, `ReservedPropertyID.title`, and `PropertyType.isSortable`. Make any Swift 6 fixes needed (`any Decoder`, `any Encoder`).

The v2 `GroupConfig` must be:

```swift
enum GroupConfig: Codable, Equatable, Hashable, Sendable {
    case structural
    case property(PropertyGrouping)
    case flat

    // Lenient decode: unknown kind → nil (caller defaults to .structural)
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "structural"
        switch kind {
        case "property":
            let pid = try c.decodeIfPresent(String.self, forKey: .propertyID) ?? ""
            let order = try c.decodeIfPresent([String].self, forKey: .order)
            self = .property(PropertyGrouping(propertyID: pid, order: order))
        case "flat":
            self = .flat
        default:
            self = .structural
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .structural:
            try c.encode("structural", forKey: .kind)
        case .property(let g):
            try c.encode("property", forKey: .kind)
            try c.encode(g.propertyID, forKey: .propertyID)
            try c.encodeIfPresent(g.order, forKey: .order)
        case .flat:
            try c.encode("flat", forKey: .kind)
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case propertyID = "property_id"
        case order
    }
}

struct PropertyGrouping: Codable, Equatable, Hashable, Sendable {
    var propertyID: String
    var order: [String]?

    enum CodingKeys: String, CodingKey {
        case propertyID = "property_id"
        case order
    }
}
```

- [ ] **Step 4: Run tests GREEN**

```bash
xcodebuild test -project "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora.xcodeproj" \
  -scheme Pommora -destination "platform=macOS" \
  -only-testing:PommoraTests/SavedViewV2Tests \
  -only-testing:PommoraTests/GroupConfigV2Tests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **` with 7+ tests executed.

- [ ] **Step 5: Full test suite still green**

```bash
xcodebuild test -project "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora.xcodeproj" \
  -scheme Pommora -destination "platform=macOS" \
  -only-testing:PommoraTests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git -C "/Users/nathantaichman/The Studio/Projects/Project Pommora" add \
  Pommora/Pommora/Vaults/SavedView.swift \
  Pommora/PommoraTests/Vaults/SavedViewV2Tests.swift \
  Pommora/PommoraTests/Vaults/GroupConfigV2Tests.swift
git -C "/Users/nathantaichman/The Studio/Projects/Project Pommora" commit \
  -m "feat(views): SavedView v2 schema (property_order, column_widths, GroupConfig enum)"
```

---

## Task 3: updateView Clobber Fix + View CRUD + reorderPages

**Files:**
- Modify: `Pommora/Pommora/Vaults/PageTypeManager.swift`
- Test: `PommoraTests/Vaults/UpdateViewClobberTests.swift` (new)
- Test: `PommoraTests/Vaults/ViewCRUDTests.swift` (new)

**Source:** `git show views-FAILED-custom-table:Pommora/Pommora/Vaults/PageTypeManager.swift`

The existing `updateView` reads the container's views from an in-memory snapshot, mutates them, and saves — this clobbers `page_order` written by a concurrent reorder. The fix: read the sidecar fresh from disk inside `mutateViews` before every write.

Also adds multi-view CRUD (`addView`, `duplicateView`, `deleteView`, `renameView`) and the `reorderPages(in:movingIDs:before:)` method.

- [ ] **Step 1: Port UpdateViewClobberTests**

```bash
git show views-FAILED-custom-table:Pommora/PommoraTests/Vaults/UpdateViewClobberTests.swift \
  > "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/PommoraTests/Vaults/UpdateViewClobberTests.swift"
```

Verify the file compiles and the test names match their `@Suite` struct name. Run:

```bash
xcodebuild test ... -only-testing:PommoraTests/UpdateViewClobberTests 2>&1 | tail -5
```

Expected: RED (methods don't exist yet).

- [ ] **Step 2: Port ViewCRUDTests**

```bash
git show views-FAILED-custom-table:Pommora/PommoraTests/Vaults/ViewCRUDTests.swift \
  > "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/PommoraTests/Vaults/ViewCRUDTests.swift"
```

- [ ] **Step 3: Port the clobber fix + CRUD + reorderPages into PageTypeManager**

Read the current `PageTypeManager.swift` first, then apply these additions:

**a) Replace `updateView` + add `mutateViews`:**

```swift
/// Mutates the views array on a PageType sidecar. Reads the sidecar FRESH
/// from disk before every write so no in-flight reorder is clobbered.
func mutateViews(
    on type: PageType,
    mutation: (inout [SavedView]) -> Void
) async throws {
    let url = NexusPaths.pageTypeSidecar(type.folder)
    var sidecar = (try? PageTypeSidecar.load(from: url)) ?? PageTypeSidecar()
    mutation(&sidecar.views)
    try sidecar.save(to: url)
    // Publish update so @Observable observers re-render immediately
    if let idx = types.firstIndex(where: { $0.id == type.id }) {
        types[idx].views = sidecar.views
    }
}

func updateView(_ view: SavedView, on type: PageType) async throws {
    try await mutateViews(on: type) { views in
        if let idx = views.firstIndex(where: { $0.id == view.id }) {
            views[idx] = view
        } else {
            views.append(view)
        }
    }
}
```

**b) Add View CRUD:**

```swift
func addView(to type: PageType) async throws -> SavedView {
    let existing = types.first(where: { $0.id == type.id })?.views.map(\.name) ?? []
    let name = DefaultTitleResolver.resolve(label: "Untitled View", existingTitles: existing)
    let view = SavedView(id: "view_\(ULID.generate())", name: name, propertyOrder: [])
    try await mutateViews(on: type) { $0.append(view) }
    return view
}

func duplicateView(_ view: SavedView, on type: PageType) async throws -> SavedView {
    var copy = view
    copy.id = "view_\(ULID.generate())"
    copy.name = "\(view.name) Copy"
    try await mutateViews(on: type) { views in
        if let idx = views.firstIndex(where: { $0.id == view.id }) {
            views.insert(copy, at: views.index(after: idx))
        } else {
            views.append(copy)
        }
    }
    return copy
}

func deleteView(_ view: SavedView, on type: PageType) async throws {
    try await mutateViews(on: type) { views in
        guard views.count > 1 else { return }  // keep at least one
        views.removeAll { $0.id == view.id }
    }
}

func renameView(_ view: SavedView, to newName: String, on type: PageType) async throws {
    let trimmed = newName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    var updated = view; updated.name = trimmed
    try await updateView(updated, on: type)
}
```

**c) Also add equivalent `mutateViews(on collection:)` overload for `PageCollection`.**

**d) Port `reorderPages(in:movingIDs:before:)`:**

```bash
git show views-FAILED-custom-table:Pommora/Pommora/Content/PageContentManager.swift \
  | grep -A 40 "func reorderPages"
```

Port the `reorderPages(in:movingIDs:before:)` method and the pure helper `reorderedIDs(current:movingIDs:before:)` into `PageContentManager.swift`.

The pure helper (testable):

```swift
static func reorderedIDs(
    current: [String],
    movingIDs: [String],
    before anchorID: String?
) -> [String] {
    var remaining = current.filter { !movingIDs.contains($0) }
    let insertAt: Int
    if let anchor = anchorID,
       let anchorIdx = remaining.firstIndex(of: anchor) {
        insertAt = anchorIdx
    } else {
        insertAt = remaining.endIndex
    }
    remaining.insert(contentsOf: movingIDs.filter { current.contains($0) }, at: insertAt)
    return remaining
}
```

- [ ] **Step 4: Run tests GREEN**

```bash
xcodebuild test ... -only-testing:PommoraTests/UpdateViewClobberTests \
  -only-testing:PommoraTests/ViewCRUDTests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Full suite still green**

```bash
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add Pommora/Pommora/Vaults/PageTypeManager.swift \
  Pommora/Pommora/Content/PageContentManager.swift \
  Pommora/PommoraTests/Vaults/UpdateViewClobberTests.swift \
  Pommora/PommoraTests/Vaults/ViewCRUDTests.swift
git commit -m "feat(views): updateView clobber fix + view CRUD + reorderPages"
```

---

## Task 4: ViewPipeline (FilterEvaluator, ViewSortComparator, GroupResolver, ViewItem, ResolvedGroup, ViewItemSource, GroupDropPlanner)

**Files:**
- Create: `Pommora/Pommora/Detail/ViewPipeline/` (new folder, 7 files)
- Test: `PommoraTests/Detail/ViewPipeline/` (7 test files)

**Source:** Port all 7 files from `views-FAILED-custom-table:Pommora/Pommora/Detail/ViewPipeline/`. The pipeline is pure Foundation logic with no SwiftUI or AppKit dependencies — port as-is.

- [ ] **Step 1: Port all 7 source files**

```bash
DEST="/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora/Detail/ViewPipeline"
mkdir -p "$DEST"
for f in ViewItem ResolvedGroup FilterEvaluator ViewSortComparator GroupResolver ViewItemSource GroupDropPlanner; do
  git show "views-FAILED-custom-table:Pommora/Pommora/Detail/ViewPipeline/$f.swift" > "$DEST/$f.swift"
done
```

- [ ] **Step 2: Port all pipeline test files**

```bash
TDEST="/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/PommoraTests/Detail/ViewPipeline"
mkdir -p "$TDEST"
for f in FilterEvaluatorTests SortComparatorTests GroupResolverTests ViewItemSourceTests GroupDropPlannerTests; do
  git show "views-FAILED-custom-table:Pommora/PommoraTests/Detail/ViewPipeline/${f}.swift" > "$TDEST/${f}.swift"
done
# Also port fixtures
git show "views-FAILED-custom-table:Pommora/PommoraTests/Detail/ViewPipeline/ViewPipelineFixtures.swift" \
  > "$TDEST/ViewPipelineFixtures.swift"
```

- [ ] **Step 3: Fix any Swift 6 compile errors**

The files should be near-clean already. Common issues:
- `SortComparator` type collision with Foundation: the file should use `ViewSortComparator` (already renamed in the failed branch; verify the type name).
- `ViewScope` renamed to `ViewItemScope` in the failed branch — verify the rename is consistent.
- Any `@Sendable` closure captures.

Build with:

```bash
xcodebuild build -project "..." -scheme Pommora -destination "platform=macOS" 2>&1 | grep error:
```

- [ ] **Step 4: Run pipeline tests GREEN**

```bash
xcodebuild test ... \
  -only-testing:PommoraTests/FilterEvaluatorTests \
  -only-testing:PommoraTests/SortComparatorTests \
  -only-testing:PommoraTests/GroupResolverTests \
  -only-testing:PommoraTests/ViewItemSourceTests \
  -only-testing:PommoraTests/GroupDropPlannerTests 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **` with 30+ tests.

- [ ] **Step 5: Full suite still green**

```bash
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add Pommora/Pommora/Detail/ViewPipeline/ Pommora/PommoraTests/Detail/ViewPipeline/
git commit -m "feat(views): port ViewPipeline (filter/sort/group/drop planner)"
```

---

## Task 5: Active-View Persistence

**Files:**
- Create: `Pommora/Pommora/Detail/ActiveViewStore.swift`
- Modify: `Pommora/Pommora/Nexus/NexusState.swift`
- Modify: `Pommora/Pommora/Nexus/OrderPersister.swift`
- Modify: `Pommora/Pommora/Nexus/NexusEnvironment.swift`
- Test: `PommoraTests/Detail/ActiveViewStoreTests.swift`

**Source:** `git show views-FAILED-custom-table:Pommora/Pommora/Detail/ActiveViewStore.swift`

Tracks which `SavedView` ID is active per container ID across sessions, stored in `state.json` under `active_views`.

- [ ] **Step 1: Port ActiveViewStore + its tests**

```bash
git show views-FAILED-custom-table:Pommora/Pommora/Detail/ActiveViewStore.swift \
  > ".../Pommora/Detail/ActiveViewStore.swift"
git show views-FAILED-custom-table:Pommora/PommoraTests/Detail/ActiveViewStoreTests.swift \
  > ".../PommoraTests/Detail/ActiveViewStoreTests.swift"
```

- [ ] **Step 2: Add `activeViews` + `viewsButtonStyle` to `NexusState`**

Read `NexusState.swift`, then add:

```swift
var activeViews: [String: String]  // containerID → viewID
var viewsButtonStyle: String?       // "iconOnly" | "iconAndTitle" | nil (default)
```

Decode with `decodeIfPresent` + default to `[:]` / `nil`.

- [ ] **Step 3: Add helpers to `OrderPersister`**

```swift
static func setActiveView(_ viewID: String, for containerID: String, nexus: URL) throws {
    var state = (try? NexusState.load(from: nexus)) ?? NexusState()
    state.activeViews[containerID] = viewID
    try state.save(to: nexus)
}

static func setViewsButtonStyle(_ style: String?, nexus: URL) throws {
    var state = (try? NexusState.load(from: nexus)) ?? NexusState()
    state.viewsButtonStyle = style
    try state.save(to: nexus)
}
```

- [ ] **Step 4: Add `ActiveViewStore` to `NexusEnvironment`**

In `NexusEnvironment.swift`, add `let activeViewStore = ActiveViewStore()` as a stored property and `.environment(activeViewStore)` in the injection modifier.

- [ ] **Step 5: Run tests GREEN**

```bash
xcodebuild test ... -only-testing:PommoraTests/ActiveViewStoreTests 2>&1 | tail -5
```

- [ ] **Step 6: Full suite still green, then commit**

```bash
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
git add ... && git commit -m "feat(views): active-view persistence (ActiveViewStore, NexusState)"
```

---

## Task 6: Covers + Banners Storage

**Files:**
- Modify: `Pommora/Pommora/Nexus/NexusPaths.swift`
- Modify: `Pommora/Pommora/Vaults/PageFrontmatter.swift` (add `cover` field)
- Modify: `Pommora/Pommora/Vaults/PageCollection.swift` (add `banner` field)
- Modify: `Pommora/Pommora/Vaults/PageType.swift` (add `banner` field)
- Create: `Pommora/Pommora/Detail/Covers/CoverAssetStore.swift`
- Test: `PommoraTests/Detail/CoverAssetStoreTests.swift`
- Test: `PommoraTests/Content/CoverFieldTests.swift`

**Source:** `git show views-FAILED-custom-table:Pommora/Pommora/Detail/Covers/CoverAssetStore.swift`

- [ ] **Step 1: Add `assetsDir` to `NexusPaths`**

Read `NexusPaths.swift`, then add:

```swift
/// Per-entity assets folder for covers and banners.
/// e.g. `.nexus/assets/<entityID>/`
static func assetsDir(for entityID: String, in nexus: URL) -> URL {
    nexus.appending(components: "assets", entityID)
}
```

- [ ] **Step 2: Add `cover` field to PageFrontmatter**

Find the frontmatter type (likely `PageFrontmatter.swift`). Add:

```swift
var cover: String?  // nexus-relative path; never surfaced in property UI
```

Decode with `decodeIfPresent`, preserve on every write (foreign-frontmatter preservation rule). On encode: write only when non-nil.

- [ ] **Step 3: Add `banner` to PageType + PageCollection**

In both sidecar types:

```swift
var banner: String?  // nexus-relative path into assetsDir
```

`decodeIfPresent` + encode only when non-nil.

- [ ] **Step 4: Port CoverAssetStore + tests**

```bash
git show views-FAILED-custom-table:Pommora/Pommora/Detail/Covers/CoverAssetStore.swift \
  > ".../Detail/Covers/CoverAssetStore.swift"
git show views-FAILED-custom-table:Pommora/PommoraTests/Detail/CoverAssetStoreTests.swift \
  > ".../PommoraTests/Detail/CoverAssetStoreTests.swift"
git show views-FAILED-custom-table:Pommora/PommoraTests/Content/CoverFieldTests.swift \
  > ".../PommoraTests/Content/CoverFieldTests.swift"
```

`CoverAssetStore` key contract:
- `storeSync(sourceURL:for entityID:in nexus:)` — copies the file synchronously inside a security-scope access grant, adds a collision suffix if the destination exists, enforces a 500 MB total cap for the entity's assets folder, returns the nexus-relative path.
- `delete(path:in nexus:)` — removes the file, verifying it lives inside `assetsDir` (containment guard against path traversal).

- [ ] **Step 5: Add `CoverAssetStore` to `NexusEnvironment`**

Add `let coverAssetStore = CoverAssetStore()` as a stored property and `.environment(coverAssetStore)` in the injection modifier.

- [ ] **Step 6: Run tests GREEN + full suite + commit**

```bash
xcodebuild test ... -only-testing:PommoraTests/CoverAssetStoreTests \
  -only-testing:PommoraTests/CoverFieldTests 2>&1 | tail -5
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
git add ... && git commit -m "feat(views): covers + banners storage (CoverAssetStore, cover/banner fields)"
```

---

## Task 7: SavedViewMutations

**Files:**
- Create: `Pommora/Pommora/Vaults/SavedViewMutations.swift`
- Test: `PommoraTests/Vaults/SavedViewMutationsTests.swift`

**Source:** `git show views-FAILED-custom-table:Pommora/Pommora/Vaults/SavedViewMutations.swift`

Pure helpers for toggling column visibility, scrubbing deleted properties from all views. No disk I/O — takes a `SavedView` and returns a mutated copy.

- [ ] **Step 1: Port the file + tests**

```bash
git show views-FAILED-custom-table:Pommora/Pommora/Vaults/SavedViewMutations.swift \
  > ".../Vaults/SavedViewMutations.swift"
git show views-FAILED-custom-table:Pommora/PommoraTests/Vaults/SavedViewMutationsTests.swift \
  > ".../PommoraTests/Vaults/SavedViewMutationsTests.swift"
```

Key contracts to verify are present:
- `toggleHidden(_:in:)` — toggles a property in `hiddenProperties`; `_title` is a no-op (never hideable); `_modified_at` IS hideable; `cover` is always excluded (never a column).
- `scrubDeletedProperty(_:from:)` — removes a deleted property ID from `propertyOrder`, `hiddenProperties`, `columnWidths`, and from sort/filter/group configs in every view.

- [ ] **Step 2: Run tests GREEN + full suite + commit**

```bash
xcodebuild test ... -only-testing:PommoraTests/SavedViewMutationsTests 2>&1 | tail -5
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
git add ... && git commit -m "feat(views): SavedViewMutations (toggle visibility, scrub deleted property)"
```

---

## Task 8: OutlineItem + HostingCell + OutlineTableView (Core NSViewRepresentable)

**Files:**
- Create: `Pommora/Pommora/Detail/OutlineTable/OutlineItem.swift`
- Create: `Pommora/Pommora/Detail/OutlineTable/HostingCell.swift`
- Create: `Pommora/Pommora/Detail/OutlineTable/GroupHeaderCell.swift`
- Create: `Pommora/Pommora/Detail/OutlineTable/OutlineTableCoordinator.swift`
- Create: `Pommora/Pommora/Detail/OutlineTable/OutlineTableView.swift`
- Test: `PommoraTests/Detail/OutlineTable/OutlineItemTests.swift`

This task builds the skeleton that renders data. Columns, drag, and detail-view wiring come in later tasks.

- [ ] **Step 1: Write OutlineItem.swift**

`OutlineItem` is a **class** (not struct) so NSOutlineView can use AnyObject identity:

```swift
import Foundation

/// AnyObject tree node for NSOutlineView.
/// Groups are never leaf rows; leaves are never expandable.
final class OutlineItem: @unchecked Sendable {
    enum Kind {
        case group(id: String, title: String, count: Int, isCollapsed: Bool)
        case leaf(DetailRow)
    }

    let kind: Kind
    var children: [OutlineItem]  // non-empty only for group items

    init(kind: Kind, children: [OutlineItem] = []) {
        self.kind = kind
        self.children = children
    }

    var isGroup: Bool {
        if case .group = kind { return true }
        return false
    }

    var id: String {
        switch kind {
        case .group(let id, _, _, _): return "group:\(id)"
        case .leaf(let row): return row.id
        }
    }
}
```

- [ ] **Step 2: Write failing OutlineItemTests**

Create `PommoraTests/Detail/OutlineTable/OutlineItemTests.swift`:

```swift
import Testing
@testable import Pommora

@Suite struct OutlineItemTests {
    @Test func groupIsGroup() {
        let item = OutlineItem(kind: .group(id: "g1", title: "Set A", count: 3, isCollapsed: false))
        #expect(item.isGroup)
    }

    @Test func leafIsNotGroup() {
        let row = DetailRow(id: "r1", title: "Page", kind: .page(.stub()), iconName: "doc", modifiedAt: .now, children: nil)
        let item = OutlineItem(kind: .leaf(row))
        #expect(!item.isGroup)
    }

    @Test func groupIDPrefixed() {
        let item = OutlineItem(kind: .group(id: "abc", title: "X", count: 0, isCollapsed: false))
        #expect(item.id == "group:abc")
    }
}
```

(Add `PageMeta.stub()` or `DetailRow` factory helper if needed in `ViewPipelineFixtures.swift`.)

- [ ] **Step 3: Write HostingCell.swift**

```swift
import AppKit
import SwiftUI

/// NSTableCellView subclass that hosts an NSHostingView<AnyView>.
/// Call `configure(with:)` every time a cell is vended (first use OR reuse).
/// sizingOptions = [] prevents NSHostingView constraints fighting the table layout.
final class HostingCell: NSTableCellView {
    private var hostingView: NSHostingView<AnyView>?

    func configure(with view: some View) {
        let wrapped = AnyView(view)
        if let hv = hostingView {
            hv.rootView = wrapped
        } else {
            let hv = NSHostingView(rootView: wrapped)
            hv.translatesAutoresizingMaskIntoConstraints = false
            hv.sizingOptions = []
            addSubview(hv)
            NSLayoutConstraint.activate([
                hv.leadingAnchor.constraint(equalTo: leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: trailingAnchor),
                hv.topAnchor.constraint(equalTo: topAnchor),
                hv.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            hostingView = hv
        }
    }
}
```

- [ ] **Step 4: Write GroupHeaderCell.swift**

This is the disclosure-row cell for Set/Collection group rows. It must look identical to native macOS expandable folder rows (think Finder sidebar items): icon on the left, slightly bold title, native disclosure triangle provided automatically by NSOutlineView on the `outlineTableColumn`. Do NOT hand-roll the triangle or the expand animation — NSOutlineView owns both.

The cell uses `NSTableCellView`'s built-in `imageView` + `textField` slots so NSOutlineView's layout engine wires them automatically. Do NOT use a HostingCell here.

```swift
import AppKit

/// NSTableCellView for expandable group rows (Sets / structural containers).
/// Uses NSTableCellView's standard imageView + textField slots — NSOutlineView
/// places the native disclosure triangle in the outlineTableColumn automatically.
/// Do NOT draw the triangle or animate expand/collapse manually.
final class GroupHeaderCell: NSTableCellView {

    override init(frame: NSRect) {
        super.init(frame: frame)

        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyDown
        addSubview(iv)
        imageView = iv

        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)  // match the sidebar's native folder-row weight
        tf.lineBreakMode = .byTruncatingTail
        addSubview(tf)
        textField = tf

        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iv.centerYAnchor.constraint(equalTo: centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 4),
            tf.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, iconName: String) {
        textField?.stringValue = title
        imageView?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
    }
}
```

- [ ] **Step 5: Write OutlineTableCoordinator.swift (skeleton)**

The coordinator skeleton — data source + delegate only; drag comes in Task 10:

```swift
import AppKit
import SwiftUI

@MainActor
final class OutlineTableCoordinator: NSObject {

    // MARK: Mutable state (driven by updateNSView)
    var rootItems: [OutlineItem] = []
    var expandedIDs: Set<String> = []
    var selectedIDs: Set<String> = []

    // Callbacks wired back to SwiftUI
    var onSelectionChange: (Set<String>) -> Void = { _ in }
    var onItemDoubleClick: (OutlineItem) -> Void = { _ in }

    // The managed view — set in makeNSView
    weak var outlineView: NSOutlineView?

    // MARK: Reload helpers

    func reload(animated: Bool = true) {
        guard let ov = outlineView else { return }
        let expanded = expandedIDs
        ov.reloadData()
        // Restore expansion
        for item in rootItems where item.isGroup {
            if expanded.contains(item.id) { ov.expandItem(item) }
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension OutlineTableCoordinator: NSOutlineViewDataSource {

    nonisolated func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        MainActor.assumeIsolated {
            guard let parent = item as? OutlineItem else { return rootItems.count }
            return parent.children.count
        }
    }

    nonisolated func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        MainActor.assumeIsolated {
            guard let parent = item as? OutlineItem else { return rootItems[index] }
            return parent.children[index]
        }
    }

    nonisolated func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        MainActor.assumeIsolated {
            (item as? OutlineItem)?.isGroup ?? false
        }
    }
}

// MARK: - NSOutlineViewDelegate

extension OutlineTableCoordinator: NSOutlineViewDelegate {

    // isGroupItem intentionally NOT implemented — default is false.
    // Returning true gives the flat uppercase source-list section header style.
    // We want standard expandable rows (native chevron + icon + regular-weight text),
    // identical to the Pommora sidebar's folder rows.

    nonisolated func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        MainActor.assumeIsolated {
            !((item as? OutlineItem)?.isGroup ?? true)
        }
    }

    nonisolated func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        MainActor.assumeIsolated {
            guard let oi = item as? OutlineItem else { return nil }

            if oi.isGroup, case .group(_, let title, let count, _) = oi.kind {
                let cellID = NSUserInterfaceItemIdentifier("GroupHeaderCell")
                let cell: GroupHeaderCell
                if let reused = outlineView.makeView(withIdentifier: cellID, owner: nil)
                        as? GroupHeaderCell {
                    cell = reused
                } else {
                    cell = GroupHeaderCell()
                    cell.identifier = cellID
                }
                cell.configure(title: title, count: count)
                return cell
            }

            guard case .leaf(let row) = oi.kind else { return nil }
            let colID = tableColumn?.identifier.rawValue ?? "title"
            let reuseID = NSUserInterfaceItemIdentifier("HostingCell-\(colID)")
            let cell: HostingCell
            if let reused = outlineView.makeView(withIdentifier: reuseID, owner: nil) as? HostingCell {
                cell = reused
            } else {
                cell = HostingCell()
                cell.identifier = reuseID
            }

            switch colID {
            case "title":
                cell.configure(with: TitleCellView(row: row))
            default:
                // Property columns wired in Task 9
                cell.configure(with: EmptyView())
            }
            return cell
        }
    }

    nonisolated func outlineViewSelectionDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let ov = notification.object as? NSOutlineView else { return }
            var selected = Set<String>()
            ov.selectedRowIndexes.forEach { idx in
                if let item = ov.item(atRow: idx) as? OutlineItem,
                   case .leaf(let row) = item.kind {
                    selected.insert(row.id)
                }
            }
            selectedIDs = selected
            onSelectionChange(selected)
        }
    }

    nonisolated func outlineViewItemDidExpand(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let item = notification.userInfo?["NSObject"] as? OutlineItem {
                expandedIDs.insert(item.id)
            }
        }
    }

    nonisolated func outlineViewItemDidCollapse(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let item = notification.userInfo?["NSObject"] as? OutlineItem {
                expandedIDs.remove(item.id)
            }
        }
    }
}

// MARK: - Stub cell view (replaced in Task 9)

private struct TitleCellView: View {
    let row: DetailRow
    var body: some View {
        Label(row.title, systemImage: row.iconName)
            .foregroundStyle(.primary)
    }
}
```

- [ ] **Step 6: Write OutlineTableView.swift**

```swift
import AppKit
import SwiftUI

/// NSViewRepresentable wrapping NSOutlineView. Driven by `rootItems`
/// (built externally from GroupResolver output). Column setup in Task 9.
struct OutlineTableView: NSViewRepresentable {

    var rootItems: [OutlineItem]
    var autosaveName: String
    var onSelectionChange: (Set<String>) -> Void
    var onItemAction: (OutlineItem) -> Void  // double-click / enter

    func makeCoordinator() -> OutlineTableCoordinator { OutlineTableCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let ov = NSOutlineView()
        ov.delegate = context.coordinator
        ov.dataSource = context.coordinator
        context.coordinator.outlineView = ov

        // Title column (only column in this skeleton; more added in Task 9)
        let titleCol = NSTableColumn(identifier: .init("title"))
        titleCol.title = "Title"
        titleCol.minWidth = 120
        titleCol.width = 240
        ov.addTableColumn(titleCol)
        ov.outlineTableColumn = titleCol

        // Native table behaviors
        ov.autosaveName = autosaveName
        ov.autosaveTableColumns = true
        ov.allowsMultipleSelection = true
        ov.allowsColumnReordering = true
        ov.allowsColumnResizing = true
        ov.floatsGroupRows = false
        // rowHeight: do NOT hardcode — let NSOutlineView use the system default for .automatic style
        ov.usesAlternatingRowBackgroundColors = true
        ov.style = .automatic          // full-width detail table, NOT .inSourceList (sidebar style)
        ov.selectionHighlightStyle = .none   // clicks do not highlight rows; keyboard/drag selection still works via callbacks
        ov.gridStyleMask = .solidVerticalGridLineMask  // native column separator lines (segmented-control outline look)

        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onItemDoubleClick = onItemAction

        let scroll = NSScrollView()
        scroll.documentView = ov
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.rootItems = rootItems
        coordinator.onSelectionChange = onSelectionChange
        coordinator.onItemDoubleClick = onItemAction
        coordinator.reload(animated: true)
    }
}
```

- [ ] **Step 7: Run OutlineItemTests GREEN + build clean**

```bash
xcodebuild test ... -only-testing:PommoraTests/OutlineItemTests 2>&1 | tail -5
xcodebuild build ... 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 8: Full suite still green, then commit**

```bash
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
git add Pommora/Pommora/Detail/OutlineTable/ Pommora/PommoraTests/Detail/OutlineTable/
git commit -m "feat(views): OutlineItem + HostingCell + GroupHeaderCell + OutlineTableView skeleton"
```

---

## Task 9: Columns — Resolver, NSTableColumn Setup, Notifications, Property Cells

**Files:**
- Create: `Pommora/Pommora/Detail/OutlineTable/TableColumnResolver.swift`
- Modify: `Pommora/Pommora/Detail/OutlineTable/OutlineTableView.swift`
- Modify: `Pommora/Pommora/Detail/OutlineTable/OutlineTableCoordinator.swift`
- Test: `PommoraTests/Detail/OutlineTable/TableColumnResolverTests.swift`

**Source:** `git show views-FAILED-custom-table:Pommora/Pommora/Detail/Table/TableColumnResolver.swift`

Port the column resolution logic (which columns from `property_order` + schema, `hidden_properties` respected, `cover` never a column, `_title` structurally guaranteed, per-type SF Symbol). Discard `ColumnLayout` — NSOutlineView handles geometry.

- [ ] **Step 1: Port TableColumnResolver + tests**

```bash
git show views-FAILED-custom-table:Pommora/Pommora/Detail/Table/TableColumnResolver.swift \
  > ".../OutlineTable/TableColumnResolver.swift"
git show views-FAILED-custom-table:Pommora/PommoraTests/Detail/Table/TableColumnResolverTests.swift \
  > ".../PommoraTests/Detail/OutlineTable/TableColumnResolverTests.swift"
```

Verify the output type is `[OutlineColumn]` (or adapt to a plain struct — not `ColumnLayout`). The resolver is pure: `TableColumnResolver.columns(view: SavedView, schema: [PropertyDefinition]) -> [OutlineColumn]`.

```swift
struct OutlineColumn: Equatable {
    let id: String           // property_id or "_title" / "_modified_at"
    let title: String
    let width: CGFloat
    let minWidth: CGFloat
    let symbolName: String?  // SF Symbol for the column header icon
    let isHidden: Bool
}
```

- [ ] **Step 2: Wire columns in OutlineTableView.makeNSView**

Replace the hard-coded single title column with columns from the resolver. Pass `columns: [OutlineColumn]` into `OutlineTableView`:

```swift
struct OutlineTableView: NSViewRepresentable {
    var rootItems: [OutlineItem]
    var columns: [OutlineColumn]   // NEW
    var autosaveName: String
    // ...

    func makeNSView(context: Context) -> NSScrollView {
        let ov = NSOutlineView()
        // ...
        for col in columns where !col.isHidden {
            let tc = NSTableColumn(identifier: .init(col.id))
            tc.title = col.title
            tc.width = col.width
            tc.minWidth = col.minWidth
            // .userResizingMask only — strips .autoresizingMask so resizing one
            // column never touches adjacent columns (the scroll view absorbs the delta).
            tc.resizingMask = .userResizingMask
            ov.addTableColumn(tc)
        }
        if let first = ov.tableColumns.first { ov.outlineTableColumn = first }
        // noColumnAutoresizing: window resize never redistributes column widths.
        // Each column is a fully independent width island — the horizontal scroll view grows instead.
        ov.columnAutoresizingStyle = .noColumnAutoresizing
        // Use the window background colour — NOT a hardcoded colour or .clear.
        // The hand-rolled SwiftUI table drew its own background, which was a few
        // points off from the actual window background under vibrancy/materials.
        ov.backgroundColor = .windowBackgroundColor
        ov.autosaveName = autosaveName
        ov.autosaveTableColumns = true
        // ...
    }
}
```

- [ ] **Step 3: Wire property-cell rendering in OutlineTableCoordinator**

In `viewFor tableColumn:item:`, replace the `default: EmptyView()` stub with full property cell rendering. The coordinator needs `schema: [PropertyDefinition]` and manager references passed in via the representable. Add to coordinator:

```swift
var schema: [PropertyDefinition] = []
var onPropertyCommit: (String, String, PropertyValue?) -> Void = { _, _, _ in }
// propertyID, pageID, newValue
```

In `viewFor`:

```swift
case let colID where colID != "title":
    // Find the PropertyDefinition for this column
    if let def = schema.first(where: { $0.id == colID }),
       case .leaf(let row) = oi.kind,
       case .page(let meta) = row.kind {
        cell.configure(with:
            PropertyCellEditor(
                definition: def,
                value: meta.frontmatter.properties[def.id],
                relationResolver: { /* pass in via closure */ nil },
                commit: { newValue in
                    onPropertyCommit(def.id, meta.id, newValue)
                },
                index: nexusIndex
            )
        )
    }
```

Pass `nexusIndex` and `relationResolver` via coordinator stored properties set in `updateNSView`.

- [ ] **Step 4: Add column resize + reorder notifications to OutlineTableView.makeNSView**

```swift
NotificationCenter.default.addObserver(
    context.coordinator,
    selector: #selector(OutlineTableCoordinator.columnDidResize(_:)),
    name: NSTableView.columnDidResizeNotification,
    object: ov
)
NotificationCenter.default.addObserver(
    context.coordinator,
    selector: #selector(OutlineTableCoordinator.columnDidMove(_:)),
    name: NSTableView.columnDidMoveNotification,
    object: ov
)
```

And in the coordinator:

```swift
@objc nonisolated func columnDidResize(_ note: Notification) {
    MainActor.assumeIsolated {
        guard let col = note.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        onColumnWidthChange?(col.identifier.rawValue, col.width)
    }
}

@objc nonisolated func columnDidMove(_ note: Notification) {
    MainActor.assumeIsolated {
        guard let ov = note.object as? NSOutlineView else { return }
        let order = ov.tableColumns.map(\.identifier.rawValue)
        onColumnOrderChange?(order)
    }
}
```

Add `var onColumnWidthChange: ((String, CGFloat) -> Void)?` and `var onColumnOrderChange: (([String]) -> Void)?` to the coordinator.

- [ ] **Step 5: Add right-click column header → "Hide Property" menu**

Override `NSOutlineView`'s `menu(for:)` so right-clicking a column header offers "Hide Property" (with Title exempt). The NSOutlineView sends `menu(for:)` with a click event; check whether the click hit the header area:

In `OutlineTableView.makeNSView`, subclass `NSOutlineView` to override the header menu:

```swift
// Thin NSOutlineView subclass — only purpose is to intercept header right-click
final class PommoraOutlineView: NSOutlineView {
    var onHideColumn: ((String) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = headerView?.convert(event.locationInWindow, from: nil) ?? .zero
        guard let headerView,
              headerView.frame.contains(point),
              let col = column(at: convert(event.locationInWindow, from: nil)).nonNegative,
              col < tableColumns.count
        else { return super.menu(for: event) }

        let colID = tableColumns[col].identifier.rawValue
        guard colID != "title" && colID != "_title" else { return nil }  // Title non-hideable

        let menu = NSMenu()
        let item = NSMenuItem(title: "Hide Property", action: #selector(hideColumnAction(_:)), keyEquivalent: "")
        item.representedObject = colID
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func hideColumnAction(_ sender: NSMenuItem) {
        guard let colID = sender.representedObject as? String else { return }
        onHideColumn?(colID)
    }
}

private extension Int {
    var nonNegative: Int? { self >= 0 ? self : nil }
}
```

Use `PommoraOutlineView` instead of `NSOutlineView()` in `makeNSView`. Wire `onHideColumn` to call `onColumnHide` on the coordinator, which calls back to SwiftUI to update the view's `hidden_properties` via `SavedViewMutations.toggleHidden`.

- [ ] **Step 6: Dismantling (remove observers)**

```swift
static func dismantleNSView(_ scrollView: NSScrollView, coordinator: OutlineTableCoordinator) {
    NotificationCenter.default.removeObserver(coordinator)
}
```

- [ ] **Step 7: Run tests GREEN + full suite + commit**

```bash
xcodebuild test ... -only-testing:PommoraTests/TableColumnResolverTests 2>&1 | tail -5
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
git add ... && git commit -m "feat(views): columns — resolver, NSTableColumn setup, resize/reorder notifications"
```

---

## Task 10: Drag + Drop (Cross-Group Moves + Reorder)

**Files:**
- Modify: `Pommora/Pommora/Detail/OutlineTable/OutlineTableCoordinator.swift`
- Modify: `Pommora/Pommora/Detail/OutlineTable/OutlineTableView.swift`

Wires `GroupDropPlanner` into NSOutlineView's native drag API. No custom drag image or geometry — AppKit provides the drag preview for free.

- [ ] **Step 1: Register drag types in makeNSView**

```swift
ov.registerForDraggedTypes([.string])
ov.setDraggingSourceOperationMask(.move, forLocal: true)
```

- [ ] **Step 2: Add NSOutlineViewDataSource drag methods to coordinator**

```swift
// Step 1: Write items to pasteboard
nonisolated func outlineView(
    _ outlineView: NSOutlineView,
    pasteboardWriterForItem item: Any
) -> (any NSPasteboardWriting)? {
    MainActor.assumeIsolated {
        guard let oi = item as? OutlineItem,
              case .leaf(let row) = oi.kind else { return nil }
        let pb = NSPasteboardItem()
        pb.setString(row.id, forType: .string)
        return pb
    }
}

// Step 2: Validate drop
nonisolated func outlineView(
    _ outlineView: NSOutlineView,
    validateDrop info: any NSDraggingInfo,
    proposedItem item: Any?,
    proposedChildIndex index: Int
) -> NSDragOperation {
    MainActor.assumeIsolated {
        // Redirect leaf-on-leaf hover to that leaf's parent group
        if let target = item as? OutlineItem, !target.isGroup {
            if let parent = findParent(of: target) {
                outlineView.setDropItem(parent, dropChildIndex: NSOutlineViewDropOnItemIndex)
            }
            return .move
        }
        if let group = item as? OutlineItem, group.isGroup { return .move }
        if item == nil { return .move }  // root drop
        return []
    }
}

// Step 3: Accept drop
nonisolated func outlineView(
    _ outlineView: NSOutlineView,
    acceptDrop info: any NSDraggingInfo,
    item: Any?,
    childIndex index: Int
) -> Bool {
    MainActor.assumeIsolated {
        var draggedIDs: [String] = []
        info.draggingPasteboard.pasteboardItems?.forEach { pb in
            if let id = pb.string(forType: .string) { draggedIDs.append(id) }
        }
        guard !draggedIDs.isEmpty else { return false }

        let targetGroupID: String?
        if let group = item as? OutlineItem, case .group(let id, _, _, _) = group.kind {
            targetGroupID = id
        } else {
            targetGroupID = nil
        }

        let insertionIndex = index == NSOutlineViewDropOnItemIndex ? Int.max : index

        // Delegate to the GroupDropPlanner decision the caller injected
        onDrop?(draggedIDs, targetGroupID, insertionIndex)
        return true
    }
}
```

Add `var onDrop: (([String], String?, Int) -> Void)?` to the coordinator.

- [ ] **Step 2: Add `findParent` helper to coordinator**

```swift
private func findParent(of target: OutlineItem) -> OutlineItem? {
    func search(in items: [OutlineItem]) -> OutlineItem? {
        for item in items {
            if item.children.contains(where: { $0.id == target.id }) { return item }
            if let found = search(in: item.children) { return found }
        }
        return nil
    }
    return search(in: rootItems)
}
```

- [ ] **Step 3: Wire `onDrop` in updateNSView**

In `OutlineTableView.updateNSView`, wire `context.coordinator.onDrop` to the caller's drop handler (which runs `GroupDropPlanner.plan` and calls the right manager).

- [ ] **Step 4: Build clean + full suite green + commit**

```bash
xcodebuild build ... 2>&1 | grep -E "error:|BUILD"
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
git add ... && git commit -m "feat(views): drag-and-drop (cross-group moves, reorder via GroupDropPlanner)"
```

---

## Task 11: Wire PageTypeDetailView

**Files:**
- Modify: `Pommora/Pommora/Detail/PageTypeDetailView.swift`

Replace the SwiftUI `Table` in `PageTypeDetailView` with `OutlineTableView`. Keep all alerts, confirmations, footer, header, `.task` warm-ups, and context menus intact — only the table body changes.

- [ ] **Step 1: Add `OutlineItem` tree builder**

Add a computed property that converts the current `rows: [DetailRow]` into `[OutlineItem]`:

```swift
private func outlineItems(from rows: [DetailRow]) -> [OutlineItem] {
    rows.map { row in
        if let children = row.children, !children.isEmpty {
            let leafItems = children.map { OutlineItem(kind: .leaf($0)) }
            return OutlineItem(
                kind: .group(
                    id: row.id,
                    title: row.title,
                    count: children.count,
                    isCollapsed: false
                ),
                children: leafItems
            )
        }
        return OutlineItem(kind: .leaf(row))
    }
}
```

- [ ] **Step 2: Replace `private var table` with `OutlineTableView`**

Remove the `Table(of: DetailRow.self) { ... } rows: { ... }` body and replace with:

```swift
private var table: some View {
    OutlineTableView(
        rootItems: outlineItems(from: rows),
        columns: TableColumnResolver.columns(
            view: livePageType.views.first ?? SavedView.defaultTable(visiblePropertyIDs: []),
            schema: livePageType.resolvedProperties(tierConfig: tierConfigManager.config)
        ),
        autosaveName: "PageType-\(pageType.id)",
        onSelectionChange: { _ in },
        onItemAction: { item in
            if case .leaf(let row) = item.kind { handleDoubleTap(row) }
        }
    )
    .task(id: visibleContextLinkIDs) {
        await contextDisplay.warm(visibleContextLinkIDs)
    }
}
```

- [ ] **Step 3: [UIX] Build clean + launch visually check**

> **STOP** — before proceeding, ask Nathan to confirm the visual design for the vault table (row fills, disclosure rows, column headers, banner area). Use the screenshot from Task 1 baseline as the reference, but get explicit sign-off.

```bash
xcodebuild build ... 2>&1 | grep -E "error:|BUILD"
```

Launch the app, navigate to a vault — verify:
- Alternating row fills extend edge-to-edge (no rounded sub-frame; the outline IS the window).
- Diagonal trackpad scroll shows no row-breakout artifact.
- Column separator lines appear between every column.
- Clicking a row does NOT produce a blue highlight.
- Native drag produces the standard insertion-indicator line (not a custom overlay).
- The vault banner (if set) fills the full-width header area and bleeds behind the vault title label (title renders on top, not beside the banner). Confirm that right-clicking the banner shows a two-item context menu: "Change Banner" / "Remove" — wire both to `CoverAssetStore` helpers and re-save the sidecar.

If column headings or alternating colors differ from the baseline, fix in `OutlineTableView.makeNSView`.

- [ ] **Step 4: Full suite green + commit**

```bash
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
git add ... && git commit -m "feat(views): wire PageTypeDetailView to OutlineTableView"
```

---

## Task 12: Wire PageCollectionDetailView

**Files:**
- Modify: `Pommora/Pommora/Detail/PageCollectionDetailView.swift`

Mirror Task 11 but for collection detail (Sets are the disclosure groups here, not Collections).

- [ ] **Step 1: Add `outlineItems(from:)` for collection rows**

Sets become group nodes; their pages become leaf children. Root pages (no Set) become flat leaves:

```swift
private func outlineItems(from rows: [DetailRow]) -> [OutlineItem] {
    rows.map { row in
        switch row.kind {
        case .set:
            let kids = (row.children ?? []).map { OutlineItem(kind: .leaf($0)) }
            return OutlineItem(
                kind: .group(id: row.id, title: row.title, count: kids.count, isCollapsed: false),
                children: kids
            )
        default:
            return OutlineItem(kind: .leaf(row))
        }
    }
}
```

- [ ] **Step 2: Replace `private var table` with OutlineTableView**

Same pattern as Task 11. `autosaveName: "Collection-\(collection.id)"`.

Wire `onDrop` to a handler that calls `pageSetManager.set(containing:)` + `GroupDropPlanner.plan(...)` to distinguish reorder vs. structural Set move vs. property rewrite.

- [ ] **Step 3: [UIX] Build + visual check + full suite + commit**

> **STOP** — ask Nathan to confirm the collection detail visual design before verifying. Same visual check list as Task 11. Confirm banner bleeds behind collection title header; right-click shows "Change Banner" / "Remove".

```bash
xcodebuild build ... 2>&1 | grep -E "error:|BUILD"
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
git add ... && git commit -m "feat(views): wire PageCollectionDetailView to OutlineTableView"
```

---

## Task 13: Views Dropdown + View Settings Panes

**Files:**
- Create: `Pommora/Pommora/Detail/ViewTabs/ViewsDropdownButton.swift`
- Create: `Pommora/Pommora/Detail/ViewSettings/StorageMenuRoot.swift`
- Create: `Pommora/Pommora/Detail/ViewSettings/SortPane.swift`
- Create: `Pommora/Pommora/Detail/ViewSettings/FilterPane.swift`
- Create: `Pommora/Pommora/Detail/ViewSettings/GroupPane.swift`
- Create: `Pommora/Pommora/Detail/ViewSettings/LayoutPane.swift`
- Create: `Pommora/Pommora/Detail/ViewSettings/PropertiesListPane.swift`
- Test: `PommoraTests/Detail/ViewSettings/FilterGroupPaneTests.swift`
- Test: `PommoraTests/Detail/ViewSettings/SortPersistenceTests.swift`

**Source:** Port all from `views-FAILED-custom-table:Pommora/Pommora/Detail/ViewTabs/` and `ViewSettings/`.

**Views button design (confirmed from screenshot):**
- A **standalone pill button** in the toolbar — completely separate from the Sort/Filter/Layout controls capsule to its right.
- The button's icon is the **active view's type icon**: `table.cells` when the active view is Table, `square.grid.3x1.below.line.grid.1x2` when it's Gallery.
- **Right-clicking** the Views button shows a context menu: "Display as Icon Only" / "Display as Icon + Title". The chosen style persists via `viewsButtonStyle` in `NexusState`.
- **Left-clicking** opens the Views popover.
- The **popover** row design (confirmed from screenshot):
  - Each row: `[view icon]  [view name]  [chevron ›]` — icon on left, name in middle, right-aligned chevron button.
  - **Selected view uses a full-row fill highlight** (not a checkmark). Background fill uses the list selection material; unselected rows have a clear background.
  - The **chevron (›)** on the right is a button. Tapping it opens a small horizontal type-picker submenu (a popover anchored to the chevron) showing the available type icons — currently **table icon** (`tablecells`) and **gallery icon** (`square.grid.2x2`). Tapping a type icon changes that view's type and dismisses the submenu. The active type is shown with a fill/selected state in the picker.
  - Tapping anywhere else on the row (not the chevron) **selects that view** and closes the popover.
- **"New View" footer**: pinned at the popover bottom, separated by a `PaneDivider` (no extra top padding — the row's own padding provides the gap). Single label+icon button using footnote/caption typography — the same pattern as "New property" and the "Display As" selector footer.

> **[UIX]** STOP before building `ViewsPanel` / `ViewsPanelRow`. Ask Nathan for Figma design confirmation of the row layout, fill selection colour, and type-picker submenu shape before writing code.

- [ ] **Step 1: Port ViewsDropdownButton + ViewsPanel + ViewsPanelRow**

```bash
for f in ViewsDropdownButton ViewsPanel ViewsPanelRow; do
  git show "views-FAILED-custom-table:Pommora/Pommora/Detail/ViewTabs/$f.swift" \
    > ".../Detail/ViewTabs/$f.swift"
done
```

After porting, rework `ViewsDropdownButton` to match the confirmed design above. The failed branch version may not match — treat the port as a starting scaffold, not final. Specifically:
- Button label must show the active view's SF Symbol icon (`table.cells` for table, `square.grid.3x1.below.line.grid.1x2` for gallery). Icon-only vs. icon+title toggles via the persisted `viewsButtonStyle`.
- Right-click context menu uses `.contextMenu { }` on the button label.
- "New View" footer uses `.font(.footnote)` + `.foregroundStyle(.secondary)` with a leading `plus` SF Symbol, pinned below a `PaneDivider`.

```swift
// ViewsDropdownButton skeleton — write fresh from this spec, using port as reference
struct ViewsDropdownButton: View {
    var views: [SavedView]
    var activeViewID: String?
    var buttonStyle: ViewsButtonStyle  // .iconOnly | .iconAndTitle
    var onSelect: (SavedView) -> Void
    var onTypeChange: (SavedView, ViewType) -> Void
    var onAdd: () -> Void
    var onDuplicate: (SavedView) -> Void
    var onDelete: (SavedView) -> Void
    var onRename: (SavedView, String) -> Void
    var onButtonStyleChange: (ViewsButtonStyle) -> Void

    @State private var isOpen = false

    private var activeView: SavedView? { views.first { $0.id == activeViewID } ?? views.first }

    private var activeIcon: String {
        switch activeView?.type {
        case .gallery: return "square.grid.3x1.below.line.grid.1x2"
        default: return "tablecells"
        }
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            Group {
                switch buttonStyle {
                case .iconOnly:
                    Image(systemName: activeIcon)
                case .iconAndTitle:
                    Label(activeView?.name ?? "Views", systemImage: activeIcon)
                }
            }
        }
        .buttonStyle(.bordered)
        .contextMenu {
            Button("Display as Icon Only") { onButtonStyleChange(.iconOnly) }
            Button("Display as Icon + Title") { onButtonStyleChange(.iconAndTitle) }
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ViewsPanel(
                views: views,
                activeViewID: activeViewID,
                onSelect: { onSelect($0); isOpen = false },
                onTypeChange: onTypeChange,
                onAdd: onAdd,
                onDuplicate: onDuplicate,
                onDelete: onDelete,
                onRename: onRename
            )
        }
    }
}

enum ViewsButtonStyle: String, Codable, Sendable {
    case iconOnly
    case iconAndTitle
}
```

`ViewsPanel` body: a `VStack(spacing: 0)` of `ViewsPanelRow` items, then `PaneDivider()`, then the "New View" footer button.

**`ViewsPanelRow` — fill selection + chevron type-picker:**

```swift
/// One row in the Views popover.
/// - Full-row fill highlights the selected view (no checkmark).
/// - The trailing chevron opens a horizontal type-picker submenu.
struct ViewsPanelRow: View {
    let view: SavedView
    let isSelected: Bool
    let onSelect: () -> Void
    let onTypeChange: (ViewType) -> Void
    var onRename: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @State private var showTypePicker = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: view.icon ?? view.type.defaultIcon)
                .frame(width: 16)
            Text(view.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Chevron opens type-picker submenu
            Button {
                showTypePicker.toggle()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showTypePicker, arrowEdge: .trailing) {
                // Horizontal type picker: table + gallery icons only (two for now)
                HStack(spacing: 12) {
                    ForEach(ViewType.allCases.filter(\.isImplemented), id: \.self) { type in
                        Button {
                            onTypeChange(type)
                            showTypePicker = false
                        } label: {
                            Image(systemName: type.defaultIcon)
                                .imageScale(.large)
                                .padding(6)
                                .background(
                                    view.type == type
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .padding(.horizontal, PUI.Pane.contentPadding)
        .padding(.vertical, 7)
        // Full-row fill for the selected view — no checkmark
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Rename") { onRename() }
            Button("Duplicate") { onDuplicate() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}
```

Footer inside `ViewsPanel`:

```swift
// Footer inside ViewsPanel — caption typography, same as "New property" footer
Button(action: onAdd) {
    Label("New View", systemImage: "plus")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PUI.Pane.contentPadding)
        .padding(.vertical, 8)
}
.buttonStyle(.plain)
```

**View row context menu (right-click on a view row inside the popover):**

Each view row has `.contextMenu` with a type-conditional structure. Exact capitalization is locked — copy verbatim:

```swift
// For a GALLERY view row:
// ┌─────────────────────────────┐
// │  [S]  [M]  [L]   ← palette │  (card size picker — NSMenuItemView with 3 toggle buttons)
// ├─────────────────────────────┤
// │  Display As              ›  │  (submenu)
// │    ○  Icon Only             │
// │    ○  Icon + Title          │
// ├─────────────────────────────┤
// │  Rename                     │
// │  Edit Icon                  │
// │  Duplicate                  │
// ├─────────────────────────────┤
// │  Delete                     │  (destructive role)
// └─────────────────────────────┘

// For a TABLE view row (no size palette):
// ┌─────────────────────────────┐
// │  Display As              ›  │  (submenu)
// │    ○  Icon Only             │
// │    ○  Icon + Title          │
// ├─────────────────────────────┤
// │  Rename                     │
// │  Edit Icon                  │
// │  Duplicate                  │
// ├─────────────────────────────┤
// │  Delete                     │  (destructive role)
// └─────────────────────────────┘
```

Implementation in SwiftUI `.contextMenu`:

```swift
.contextMenu {
    // Gallery-only: card size palette (S / M / L)
    if view.type == .gallery {
        // SwiftUI doesn't have a built-in palette picker in contextMenu —
        // use three Buttons styled as a segmented palette row via a custom
        // NSMenuItemView. Simplest SwiftUI-compatible approach: three
        // checkmark-style items with the active size marked.
        Button { onSetCardSize(view, .small) } label: {
            Label("Small", systemImage: view.cardSize == .small ? "checkmark" : "")
        }
        Button { onSetCardSize(view, .medium) } label: {
            Label("Medium", systemImage: view.cardSize == .medium ? "checkmark" : "")
        }
        Button { onSetCardSize(view, .large) } label: {
            Label("Large", systemImage: view.cardSize == .large ? "checkmark" : "")
        }
        Divider()
    }

    // "Display As" submenu — controls Views pill button style
    Menu("Display As") {
        Button {
            onButtonStyleChange(.iconOnly)
        } label: {
            Label("Icon Only",
                  systemImage: buttonStyle == .iconOnly ? "checkmark" : "")
        }
        Button {
            onButtonStyleChange(.iconAndTitle)
        } label: {
            Label("Icon + Title",
                  systemImage: buttonStyle == .iconAndTitle ? "checkmark" : "")
        }
    }

    Divider()
    Button("Rename") { onBeginRename(view) }
    Button("Edit Icon") { onEditIcon(view) }
    Button("Duplicate") { onDuplicate(view) }
    Divider()
    Button("Delete", role: .destructive) { onDelete(view) }
}
```

Add `onSetCardSize: (SavedView, CardSize) -> Void` and `onEditIcon: (SavedView) -> Void` to `ViewsPanel`'s callback set. Wire `onSetCardSize` to call `mutateViews` updating `view.cardSize` and re-saving the sidecar. Wire `onEditIcon` to open the icon picker sheet (reuse the existing `SidebarSheet.editIcon` pattern).

- [ ] **Step 2: Port View Settings panes**

```bash
for f in StorageMenuRoot SortPane FilterPane GroupPane LayoutPane PropertiesListPane; do
  git show "views-FAILED-custom-table:Pommora/Pommora/Detail/ViewSettings/$f.swift" \
    > ".../Detail/ViewSettings/$f.swift" 2>/dev/null || true
done
```

Fix any import or type-name changes from this branch's schema (e.g., `GroupConfig` is now a discriminated enum, not a struct).

- [ ] **Step 3: Port pane tests**

```bash
git show views-FAILED-custom-table:Pommora/PommoraTests/Detail/ViewSettings/FilterGroupPaneTests.swift \
  > ".../PommoraTests/Detail/ViewSettings/FilterGroupPaneTests.swift"
git show views-FAILED-custom-table:Pommora/PommoraTests/Detail/ViewSettings/SortPersistenceTests.swift \
  > ".../PommoraTests/Detail/ViewSettings/SortPersistenceTests.swift"
```

- [ ] **Step 4: Add Views dropdown to detail view headers**

In both `PageTypeDetailView` and `PageCollectionDetailView`, add `ViewsDropdownButton` to the `header` HStack alongside the title. The Sort/Filter/Layout controls are SEPARATE buttons and stay in a separate toolbar capsule to the right:

```swift
private var header: some View {
    HStack {
        // ... existing title label ...
        Spacer()
        // Views pill — standalone, separate from the settings controls
        ViewsDropdownButton(
            views: livePageType.views,
            activeViewID: activeViewStore.activeViewID(for: pageType.id),
            buttonStyle: activeViewStore.viewsButtonStyle,
            onSelect: { view in activeViewStore.setActive(view, for: pageType.id) },
            onAdd: { Task { try? await pageTypeManager.addView(to: pageType) } },
            onDuplicate: { view in Task { try? await pageTypeManager.duplicateView(view, on: pageType) } },
            onDelete: { view in Task { try? await pageTypeManager.deleteView(view, on: pageType) } },
            onRename: { view, name in Task { try? await pageTypeManager.renameView(view, to: name, on: pageType) } },
            onButtonStyleChange: { style in activeViewStore.setViewsButtonStyle(style) }
        )
        // Sort / Filter / Layout controls capsule goes here (existing or new)
    }
    .padding()
}
```

- [ ] **Step 5: Run pane tests + full suite + commit**

```bash
xcodebuild test ... \
  -only-testing:PommoraTests/FilterGroupPaneTests \
  -only-testing:PommoraTests/SortPersistenceTests 2>&1 | tail -5
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
git add ... && git commit -m "feat(views): Views dropdown + Sort/Filter/Group/Layout settings panes"
```

---

## Task 14: Adversarial Review + Visual Comparison + Fix Loop

**Goal:** Zero issues before merging. The bar: the table must be visually indistinguishable from the native SwiftUI Table baseline and every UIX interaction path must work cleanly.

- [ ] **Step 1: Take the NSOutlineView screenshot**

Build + launch the app, navigate to the same collection used for the Task 1 baseline. Save to `/tmp/pommora-outline-table.png`.

```bash
xcodebuild build ... 2>&1 | grep -E "error:|BUILD"
# Launch manually, navigate to the same collection, screenshot
```

- [ ] **Step 2: Side-by-side visual comparison**

Compare `/tmp/pommora-native-table-baseline.png` with `/tmp/pommora-outline-table.png`. Check:
- Row height: system default (NOT hardcoded — NSOutlineView automatic style sets its own native height)
- Alternating row fills extend to the full view edges with no sub-frame rounding artifact; diagonal trackpad scroll does NOT break rows out of a nested frame
- Column separator lines visible between every column (solid vertical grid lines)
- Disclosure triangle: native chevron, not a custom arrow
- Group header style: uppercase small bold label + count, NOT filled dark bands
- Column headers: native macOS header style — not custom styled
- Selection highlight: clicking a row does NOT produce a blue row highlight; row color stays neutral
- Background colour: table background matches the rest of the window exactly (no off-white or grey mismatch — `backgroundColor = .windowBackgroundColor`)
- Column resize: dragging a column header divider resizes ONLY that column; adjacent columns do not shift (scroll view absorbs the delta)
- Column reorder: drag a column header to reorder uses the native drag animation, not a floating SwiftUI preview
- Native drag insertion indicator: the standard underline/drop-target line appears at the drop destination (NOT a custom overlay drawn on top)
- Banner fills the full-width header and bleeds behind the title label; right-click on banner shows "Change Banner" / "Remove"
- Page icons: SF Symbols AND emoji render correctly (no broken glyph boxes)
- Modified column text: secondary color, date-time formatted
- Fonts: system body/callout scale — no hardcoded sub-system sizes in property cells

Fix any visible divergence before proceeding.

- [ ] **Step 3: UIX test checklist — manually exercise every interaction**

For each item below, test it live in the running app and confirm zero errors:

**Sorting:**
- [ ] Sort by Title A→Z → rows reorder, disclosure headers stay
- [ ] Sort by Modified (Recent) → correct chronological order
- [ ] Switch back to Manual → manual order restored from sidecar
- [ ] Sort by a user-defined property (Select) → groups by option order, not alphabetic

**Filtering:**
- [ ] Add a filter rule → only matching rows visible
- [ ] Add a second rule with Match Any → OR behavior works
- [ ] Delete all rules → all rows visible again

**Grouping:**
- [ ] Default (structural) grouping: vault shows Collections, collection shows Sets
- [ ] Group by a Select property → one disclosure group per option value + "_ungrouped" bucket
- [ ] Remove grouping (flat) → all rows in one headerless band
- [ ] Collapse a group → group header stays, children hidden; persists across close + reopen

**Column management:**
- [ ] Drag a column header to reorder → new order persists after app restart
- [ ] Drag column edge to resize → new width persists after app restart
- [ ] Right-click column header → context menu appears with "Hide Property"; clicking it hides that column
- [ ] Title column right-click shows no menu (non-hideable)
- [ ] Hidden column can be re-shown via Layout pane eye-toggle
- [ ] Title column cannot be hidden

**Drag to reorder (manual sort active):**
- [ ] Drag a page within its Set → order updates in sidebar too
- [ ] Drag a page from Set A to Set B root → page moves to Set B (structural move on disk)
- [ ] Drag a page to a property-group bucket → property value updated in frontmatter
- [ ] Multi-select + drag → all selected rows move together
- [ ] Drag with active sort → drag disabled (no phantom reorder when sort overrides manual)

**Selection + keyboard:**
- [ ] Single click selects row
- [ ] ⌘-click adds to selection
- [ ] ⇧-click range selects
- [ ] Arrow keys navigate (up/down, ← collapses group, → expands group)
- [ ] Return or double-click opens the page
- [ ] Double-click a Collection (vault detail) → navigates to collection
- [ ] Selecting a row does NOT highlight the entire pane (per-row only)

**Context menus:**
- [ ] Page row: Edit Title, Edit Icon, Pin/Unpin, Delete
- [ ] Collection row (vault detail): Open, Edit Title, Edit Icon, Delete (with confirmation)
- [ ] Set row (collection detail): Open, Edit Title, Edit Icon, Delete (Set Only vs. Set and Pages)

**Views pill button:**
- [ ] Views button shows `table.cells` icon when active view is Table
- [ ] Views button shows `square.grid.3x1.below.line.grid.1x2` when active view is Gallery
- [ ] Right-click Views button → "Display as Icon Only" / "Display as Icon + Title" menu appears
- [ ] Choosing "Display as Icon + Title" → button shows icon + active view name; persists after restart
- [ ] Views button is visually separate from the Sort/Filter/Layout controls to its right

**Views dropdown:**
- [ ] Mint new view via "New View" footer → "Untitled View" appears in dropdown
- [ ] Switch view → table rerenders with that view's config
- [ ] Right-click a Table view row → context menu: Display As ▶ / Rename / Edit Icon / Duplicate / Delete (no size palette)
- [ ] Right-click a Gallery view row → context menu: S/M/L size items (with checkmark on active) / Display As ▶ / Rename / Edit Icon / Duplicate / Delete
- [ ] Display As ▶ Icon Only → Views pill shows icon only; persists after restart
- [ ] Display As ▶ Icon + Title → Views pill shows icon + view name; persists after restart
- [ ] Rename view → name updates in dropdown row and in Views pill (when icon+title mode)
- [ ] Edit Icon (view row) → icon picker opens; new icon reflects in dropdown row + Views pill
- [ ] Duplicate view → copy appears with all config preserved
- [ ] Delete view → removes from dropdown; last view cannot be deleted (Delete item absent or disabled)
- [ ] Set gallery card size via S/M/L → grid reflows to 8/6/4 columns; checkmark moves to selected size

- [ ] **Step 4: Dispatch adversarial code review agent**

```
Launch Agent (subagent_type: "code-reviewer"):
Review the Views V2 implementation on branch views-v2 against:
1. Spec: .claude/Planning/06-11-Views-Spec.md
2. Salvage manifest: .claude/Planning/Views-Salvage-Manifest.md
3. CLAUDE.md hard rules (native-first, condensed control flow, DRY, no hand-rolled mechanism)

Focus on:
- Any hand-rolled behavior that NSOutlineView provides natively for free
- Swift 6 concurrency issues (nonisolated + MainActor.assumeIsolated correctness)
- GroupDropPlanner wiring: are all three intents (.reorder / .move / .rewriteProperty) correctly dispatched?
- Manual reorder scoping: structural grouping + manual sort persists to sidebar; property grouping + manual sort is view-local ONLY; any active sort disables drag
- updateView clobber fix: is mutateViews reading fresh from disk before every save?
- Column autosave: is autosaveName set per-container (not a shared global)?
- HostingCell reuse: is rootView being updated on reuse (not creating a new NSHostingView)?
- Environment injection: are all managers (ActiveViewStore, CoverAssetStore) in NexusEnvironment?

Report every issue with file:line citation. Severity: HIGH (correctness / data loss / spec violation) or MEDIUM (UX degradation / style).
```

- [ ] **Step 5: Fix all HIGH issues, review MEDIUMs with Nathan, then full suite green**

```bash
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
```

- [ ] **Step 6: Nathan personal review**

Nathan navigates the full app with the outline table, confirms it looks and behaves like native. This is the final gate.

- [ ] **Step 7: Final commit**

```bash
xcodebuild test ... -only-testing:PommoraTests 2>&1 | tail -5
git add -A
git commit -m "feat(views): Views V2 complete — NSOutlineView table, saved views, sort/filter/group, drag"
```

---

## Self-Review Notes

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Native-first, real disclosure groups | Task 8 (NSOutlineView, `isGroupItem`) |
| Column resize + persist | Task 9 (autosaveName + notifications) |
| Column reorder + persist | Task 9 (columnDidMove) |
| Column hide/show | Task 9 (right-click header menu) + Task 13 (LayoutPane eye-toggles) |
| Views pill button (standalone, shows active view icon) | Task 13 |
| Right-click Views pill → Display as Icon Only / Icon + Title | Task 13 |
| Saved views (sort/filter/group) | Tasks 2–7 + Task 13 |
| Cross-group drag (reorder/move/rewrite) | Task 10 |
| Views dropdown toolbar pill | Task 13 |
| Per-row selection (not full-pane blue) | Task 8 (`.style = .inSourceList`) |
| Context menus (Edit Title, Edit Icon, Pin, Delete) | Tasks 11–12 (preserved from main) |
| Covers + banners storage | Task 6 |
| Active view persists per container | Task 5 |
| updateView clobber fix | Task 3 |
| Gallery | ❌ OUT OF SCOPE — separate branch |
| Views Settings panes (Sort/Filter/Group/Layout) | Task 13 |
| Adversarial review gate | Task 14 |
