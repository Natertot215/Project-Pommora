# Grouping Redesign — Implementation Plan

> **PROGRESS (2026-06-15, branch `grouping-redesign`):** Phase 0 (schema), Phase 1 (resolver), and Phase 2 (the Grouping pane) are **DONE + green**, plus a full UIX-review pass with Nathan (chevron animation, order-reverses-chips, flush picker list, disclosure interaction, button-anchored popouts, footer styling, property-visibility list fix). **REMAINING (next session):** Phase 3 — view-level group-header **manual drag** (table + gallery) + mutual exclusion with page-drag, AND the table **disclosure-chevron animation** (deferred from Phase 2 — the table uses NSOutlineView's native triangle, so this needs a custom chevron wired into the outline view's expand/collapse). Phase 4 — polish + finish branch.
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement the remaining phases task-by-task. Steps use checkbox (`- [ ]`) syntax. Ground every `file:line` against real code before editing — the anchors below were confirmed 2026-06-15 but verify on touch. Spec: `// Planning//06-15-Grouping-Redesign.md`.

**Goal:** Replace the radio-list grouping pane with a Notion-style Grouping pane (toggle → group-by property → per-type order + manual reorder), backed by an extended `PropertyGrouping` schema, date bucketing, and view-level group-header drag.

**Architecture:** Additive `PropertyGrouping` schema (new enums, custom backward-compatible `Codable`); a pure `GroupResolver` extension for date buckets + order modes; a rebuilt `GroupingPane` SwiftUI surface reusing `ViewSettingsPane`/`ChipDropdown`/the Edit-Properties option editors; and a group-header drag target added to the existing `RowDragCoordinator`, mutually exclusive with the structural page-drag.

**Tech Stack:** SwiftUI + AppKit (NSOutlineView), Swift 6 strict concurrency, `@Observable`, Swift Testing (`@Suite`), Yams/GRDB. macOS 26 target.

**Branch quirks (carry to every subagent):** test filter = `@Suite`/type name not filename (verify non-zero executed count); trust `xcodebuild` not SourceKit; builder verification via background `Agent` with `-only-testing:PommoraTests` (no window focus); new Swift files auto-include (no pbxproj edit). Custom Codable uses `init(from decoder: any Decoder)` / `encode(to encoder: any Encoder)`.

---

## File Structure

**Create**
- `Pommora/Pommora/Vaults/GroupingEnums.swift` — `GroupOrderMode`, `DateGranularity`, `EmptyPlacement`.
- `Pommora/Pommora/Detail/ViewPipeline/DateBucket.swift` — pure date→bucket-key + bucket-title helper.
- `Pommora/Pommora/ViewSettings/GroupingPane.swift` — the new pane (replaces `GroupPane.swift`).
- `Pommora/Pommora/ViewSettings/GroupingOptionsList.swift` — the reorderable Options area (reuses the Edit-Properties editor look, no Add).
- `Pommora/PommoraTests/Vaults/PropertyGroupingCodableTests.swift`
- `Pommora/PommoraTests/Detail/DateBucketTests.swift`
- `Pommora/PommoraTests/Detail/GroupResolverOrderModeTests.swift`

**Modify**
- `Pommora/Pommora/Vaults/SavedView.swift:305-313` — extend `PropertyGrouping` + custom `Codable`.
- `Pommora/Pommora/Detail/ViewPipeline/GroupResolver.swift:283-317` — `bucketKey` (date), `bucketOrder` (orderMode + emptyPlacement), checkbox nil→Unchecked, missing-property fallback.
- `Pommora/Pommora/ViewSettings/FilterPane.swift:289-293` — add `.date` to `isGroupable`.
- `Pommora/Pommora/Detail/Table/ViewOutlineTable.swift` + `ViewTableCells.swift` — group-header drag (NSOutlineView).
- `Pommora/Pommora/Detail/Gallery/GalleryView.swift:105-129` — section-header drag.
- `Pommora/Pommora/Detail/RowDragCoordinator.swift:18-31` — add a `reorderGroups` commit closure.
- Delete `Pommora/Pommora/ViewSettings/GroupPane.swift` after `GroupingPane` lands; repoint the `ViewSettingsRoute.group` destination.

---

## Phase 0 — Schema

### Task 0.1: Grouping enums

**Files:** Create `Vaults/GroupingEnums.swift`; Test `PommoraTests/Vaults/PropertyGroupingCodableTests.swift`.

- [ ] **Step 1 — failing test** (in `PropertyGroupingCodableTests.swift`):

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("PropertyGroupingCodableTests") struct PropertyGroupingCodableTests {
    @Test("enums round-trip via raw value")
    func enumRawValues() {
        #expect(GroupOrderMode.configured.rawValue == "configured")
        #expect(GroupOrderMode.reversed.rawValue == "reversed")
        #expect(GroupOrderMode.manual.rawValue == "manual")
        #expect(DateGranularity.week.rawValue == "week")
        #expect(EmptyPlacement.bottom.rawValue == "bottom")
    }
}
```

- [ ] **Step 2 — run, expect compile failure** ("cannot find GroupOrderMode"). Builder: `-only-testing:PommoraTests/PropertyGroupingCodableTests`.
- [ ] **Step 3 — implement** `Vaults/GroupingEnums.swift`:

```swift
/// How a property's groups are ordered. One enum backs all groupable types;
/// the pane exposes a type-specific label subset (see // Planning//06-15-Grouping-Redesign.md).
enum GroupOrderMode: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case configured  // schema option order (Select "Default" / Status & Date "Ascending" / Checkbox "Off")
    case reversed    // configured flipped ("Descending" / Checkbox "On")
    case manual      // the PropertyGrouping.order array
}

enum DateGranularity: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case day, week, month, year
}

enum EmptyPlacement: String, Codable, Equatable, Hashable, Sendable {
    case top, bottom
}
```

- [ ] **Step 4 — run, expect PASS.**
- [ ] **Step 5 — commit:** `git add` both files; `feat(grouping): add GroupOrderMode/DateGranularity/EmptyPlacement enums`.

### Task 0.2: Extend `PropertyGrouping` with backward-compatible `Codable`

**Files:** Modify `Vaults/SavedView.swift:305-313`; Test same suite.

- [ ] **Step 1 — failing tests** (append to `PropertyGroupingCodableTests`):

```swift
@Test("legacy {property_id, order} decodes with safe defaults")
func legacyDecode() throws {
    let json = #"{"property_id":"prop_x","order":["a","b"]}"#.data(using: .utf8)!
    let g = try JSONDecoder().decode(PropertyGrouping.self, from: json)
    #expect(g.propertyID == "prop_x")
    #expect(g.order == ["a","b"])
    #expect(g.orderMode == .configured)       // legacy order is dormant until Manual
    #expect(g.emptyPlacement == .bottom)
    #expect(g.hideEmptyGroups == false)
    #expect(g.dateGranularity == nil)
}

@Test("full round-trip preserves every field")
func fullRoundTrip() throws {
    let g = PropertyGrouping(propertyID: "p", orderMode: .manual, order: ["x"],
                             dateGranularity: .month, emptyPlacement: .top, hideEmptyGroups: true)
    let data = try JSONEncoder().encode(g)
    let back = try JSONDecoder().decode(PropertyGrouping.self, from: data)
    #expect(back == g)
}
```

- [ ] **Step 2 — run, expect FAIL** (extra args to init / fields absent).
- [ ] **Step 3 — replace** the `PropertyGrouping` struct at `SavedView.swift:305-313`. **First read the current struct** to preserve its exact existing `CodingKeys` for `property_id`/`order`. Modern-Codable rule: non-optional-with-default THROWS on a missing key under synthesis, so a custom `init(from:)` is required.

```swift
struct PropertyGrouping: Codable, Equatable, Hashable, Sendable {
    var propertyID: String
    var orderMode: GroupOrderMode = .configured
    var order: [String]?
    var dateGranularity: DateGranularity?
    var emptyPlacement: EmptyPlacement = .bottom
    var hideEmptyGroups: Bool = false

    init(propertyID: String, orderMode: GroupOrderMode = .configured, order: [String]? = nil,
         dateGranularity: DateGranularity? = nil, emptyPlacement: EmptyPlacement = .bottom,
         hideEmptyGroups: Bool = false) {
        self.propertyID = propertyID; self.orderMode = orderMode; self.order = order
        self.dateGranularity = dateGranularity; self.emptyPlacement = emptyPlacement
        self.hideEmptyGroups = hideEmptyGroups
    }

    enum CodingKeys: String, CodingKey {
        case propertyID = "property_id"
        case orderMode = "order_mode"
        case order
        case dateGranularity = "date_granularity"
        case emptyPlacement = "empty_placement"
        case hideEmptyGroups = "hide_empty_groups"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        propertyID = try c.decode(String.self, forKey: .propertyID)
        orderMode = try c.decodeIfPresent(GroupOrderMode.self, forKey: .orderMode) ?? .configured
        order = try c.decodeIfPresent([String].self, forKey: .order)
        dateGranularity = try c.decodeIfPresent(DateGranularity.self, forKey: .dateGranularity)
        emptyPlacement = try c.decodeIfPresent(EmptyPlacement.self, forKey: .emptyPlacement) ?? .bottom
        hideEmptyGroups = try c.decodeIfPresent(Bool.self, forKey: .hideEmptyGroups) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(propertyID, forKey: .propertyID)
        try c.encode(orderMode, forKey: .orderMode)
        try c.encodeIfPresent(order, forKey: .order)
        try c.encodeIfPresent(dateGranularity, forKey: .dateGranularity)
        try c.encode(emptyPlacement, forKey: .emptyPlacement)
        try c.encode(hideEmptyGroups, forKey: .hideEmptyGroups)
    }
}
```

- [ ] **Step 4 — run, expect PASS.** Then run the whole target (`-only-testing:PommoraTests`) to prove no existing `SavedView`/`GroupConfig` decode test regressed (the existing `GroupConfig` lenient-decode tests must stay green).
- [ ] **Step 5 — commit:** `feat(grouping): extend PropertyGrouping schema with backward-compatible Codable`.

---

## Phase 1 — Resolver

### Task 1.1: Date bucket keys + titles (pure)

**Files:** Create `Detail/ViewPipeline/DateBucket.swift`; Test `PommoraTests/Detail/DateBucketTests.swift`.

- [ ] **Step 1 — failing test:**

```swift
import Foundation
import Testing
@testable import Pommora

@Suite("DateBucketTests") struct DateBucketTests {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }
    @Test("month/day/year keys are zero-padded ISO and sort chronologically")
    func calendarKeys() {
        #expect(DateBucket.key(for: date(2026, 6, 15), granularity: .year) == "2026")
        #expect(DateBucket.key(for: date(2026, 6, 15), granularity: .month) == "2026-06")
        #expect(DateBucket.key(for: date(2026, 6, 15), granularity: .day) == "2026-06-15")
        #expect(DateBucket.key(for: date(2026, 1, 5), granularity: .month)
                < DateBucket.key(for: date(2026, 12, 5), granularity: .month))
    }
    @Test("ISO-8601 week pairs weekOfYear with yearForWeekOfYear at the boundary")
    func isoWeek() {
        // 2026-12-31 falls in ISO week 53 of 2026 (Thursday); key uses ISO year.
        let k = DateBucket.key(for: date(2026, 12, 31), granularity: .week)
        #expect(k.hasPrefix("2026-W"))
        #expect(k.count == "2026-W53".count)
    }
}
```

- [ ] **Step 2 — run, expect compile fail.**
- [ ] **Step 3 — implement** `DateBucket.swift` (modern Calendar APIs — `Calendar.current` for civil components, `Calendar(identifier:.iso8601)` for the week; NEVER `weekOfYear` with `.year`):

```swift
import Foundation

/// Pure date → stable bucket key + human title. Keys are zero-padded ISO so
/// lexicographic order == chronological order. Buckets are display-local
/// (device calendar + timezone), not UTC.
enum DateBucket {
    static func key(for date: Date, granularity: DateGranularity) -> String {
        switch granularity {
        case .year:
            return String(format: "%04d", Calendar.current.component(.year, from: date))
        case .month:
            let c = Calendar.current.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", c.year!, c.month!)
        case .day:
            let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        case .week:
            let iso = Calendar(identifier: .iso8601)
            let c = iso.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
            return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
        }
    }

    /// Display title for a bucket key (e.g. "June 2026", "Week 53, 2026", "Jun 15, 2026", "2026").
    static func title(for key: String, granularity: DateGranularity) -> String {
        // Parse the stable key back to a representative date for formatting.
        // (Implementation: split key, build DateComponents, format with .formatted(.dateTime…).)
        // Keep it deterministic; covered by a title test added alongside.
        DateBucketTitle.render(key: key, granularity: granularity)
    }
}
```

(Implement `DateBucketTitle.render` inline in the same file; add a `title` test asserting the month key `"2026-06"` renders a non-empty string containing `"2026"`.)

- [ ] **Step 4 — run, expect PASS.**
- [ ] **Step 5 — commit:** `feat(grouping): pure DateBucket key+title helper`.

### Task 1.2: `bucketKey` — date case

**Files:** Modify `GroupResolver.swift:283-290`.

- [ ] **Step 1 — failing test** (`GroupResolverOrderModeTests.swift`): build a `ViewItem` whose page has a `.date` property and assert the resolver places it in the granularity bucket. (Use the existing `GroupResolver` test harness pattern — read a current GroupResolver test to mirror `ViewItem` construction.)
- [ ] **Step 2 — run, expect FAIL** (date currently → nil bucket).
- [ ] **Step 3 — extend** `bucketKey(_:propertyID:)` to accept the grouping config (so it knows the granularity) and add:

```swift
case .date(let d), .datetime(let d):
    return DateBucket.key(for: d, granularity: grouping.dateGranularity ?? .month)
```

(Thread `grouping` into `bucketKey` if not already; default granularity `.month`.)

- [ ] **Step 4 — run, expect PASS.** **Step 5 — commit:** `feat(grouping): date-property bucketing in GroupResolver`.

### Task 1.3: `bucketOrder` — orderMode + emptyPlacement + checkbox

**Files:** Modify `GroupResolver.swift:295-317`.

- [ ] **Step 1 — failing tests:** (a) `.reversed` returns the configured order flipped; (b) `.configured` for status flattens `statusGroups.flatMap{options}` in order; (c) `emptyPlacement == .top` puts the nil bucket first; (d) `hideEmptyGroups` drops the nil bucket; (e) checkbox unset item lands in Unchecked, not a nil bucket.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement.** Update `bucketOrder(grouping:def:present:)` to branch on `grouping.orderMode`:
  - `.configured` → existing schema-option/checkbox/lexicographic order (keep current logic as the configured baseline).
  - `.reversed` → that baseline `.reversed()`.
  - `.manual` → `grouping.order` honored as today (stale keys yield no bucket; present-not-in-order appended at tail).
  - Place the nil bucket per `grouping.emptyPlacement`; omit it when `grouping.hideEmptyGroups`.
  - In `bucketKey`, route a `nil`/unset **checkbox** to `"false"` (Unchecked) — checkbox never produces a nil bucket.
- [ ] **Step 4 — run, expect PASS.** Run full target. **Step 5 — commit:** `feat(grouping): orderMode + emptyPlacement + checkbox-nil in resolver`.

### Task 1.4: Missing-property fallback

**Files:** Modify `GroupResolver.swift` resolve entry (`:17-37`).

- [ ] **Step 1 — failing test:** a `.property(PropertyGrouping(propertyID: "gone"))` config whose `propertyID` is absent from `schema` resolves identically to `.structural` (no crash, same group set).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:** at the top of the `.property` branch, `guard schema.contains(where: { $0.id == grouping.propertyID }) else { return resolve(...config: .structural...) }`.
- [ ] **Step 4 — PASS.** **Step 5 — commit:** `feat(grouping): fall back to structural when group property is missing`.

### Task 1.5: Enable date grouping in the property filter

**Files:** Modify `FilterPane.swift:289-293`.

- [ ] **Step 1 — failing test:** `ViewSettingsProperties.groupable(...)` includes a `.date` property (and still excludes `.multiSelect`, `.relation`).
- [ ] **Step 2 — FAIL. Step 3 —** add `case .date: return true` to `isGroupable`. **Step 4 — PASS. Step 5 — commit:** `feat(grouping): allow grouping by date properties`.

---

## Phase 2 — Grouping pane

> UI tasks: TDD via a `@MainActor` view-model (`GroupingPaneModel`) that holds the draft `PropertyGrouping` + the toggle, exactly like `FrontmatterInspectorViewModel` (J.5 pattern) — test the model, not the SwiftUI render. The SwiftUI views are thin and assembled from existing components.

### Task 2.1: `GroupingPaneModel` (@Observable)

**Files:** Create model inside `GroupingPane.swift`; Test `PommoraTests/ViewSettings/GroupingPaneModelTests.swift`.

- [ ] **Step 1 — failing tests:** toggling grouping ON with a remembered property restores `.property`; ON with none stays `.structural` (UI-only intermediate, nothing written); selecting a property writes `.property(PropertyGrouping(propertyID:))`; picking an Order mode updates `orderMode`; a Manual reorder writes `order`; `hideEmptyGroups`/`emptyPlacement` setters persist.
- [ ] **Step 2 — FAIL.**
- [ ] **Step 3 — implement** `@Observable @MainActor final class GroupingPaneModel` with `var config: GroupConfig`, the `onSave: (GroupConfig) -> Void` closure, and the setters above. Mirror `FrontmatterInspectorViewModel`'s shape (no debounce needed — these are discrete picks; commit immediately per the inline-edit-commit precedent).
- [ ] **Step 4 — PASS. Step 5 — commit:** `feat(grouping): GroupingPaneModel`.

### Task 2.2: Pane shell — toggle + inline Group By picker

**Files:** `GroupingPane.swift`.

- [ ] Build the `GroupingPane: View` using `ViewSettingsPane` + `PaneHeader` (back-to-Settings). Rows: a **Grouping** `Toggle`; a **Group By** row that inline-expands the groupable-property list (`ViewSettingsProperties.groupable`), pick collapses it. States per spec (off / on-nothing-picked / on-picked). Wire to `GroupingPaneModel`. No new test (covered by 2.1 + manual UIX in Phase 4). Build green via builder.
- [ ] **Commit:** `feat(grouping): pane shell with toggle + inline Group By picker`.

### Task 2.3: Order popout + Date By row

**Files:** `GroupingPane.swift`.

- [ ] Add the **Order** disclosure row → `.popover(arrowEdge:.bottom)` listing the type-specific `GroupOrderMode` subset with type-specific labels (Select: Default/Manual · Status: Asc/Desc/Manual · Date: Asc/Desc · Checkbox: On/Off). For `.date`, add the **Date By** row → popout of `DateGranularity`. Reuse `ChipDropdown`/popover patterns. Build green.
- [ ] **Commit:** `feat(grouping): Order + Date By popouts`.

### Task 2.4: Options reorder area

**Files:** Create `GroupingOptionsList.swift`.

- [ ] Reuse the Edit-Properties option editor look (`SelectOptionsEditor` / `StatusGroupsEditor`) **without the Add affordance** (pass a no-op / omit `onAddOption`). Draggable only when `orderMode == .manual` (writes `order`); a non-draggable preview otherwise (Status nests under its 3 group labels in fixed modes, flat in Manual). Hidden entirely when the property has zero options. Build green.
- [ ] **Commit:** `feat(grouping): manual Options reorder area (no Add)`.

### Task 2.5: Empty controls + swap in the pane

**Files:** `GroupingPane.swift`; repoint `ViewSettingsRoute.group`; delete `GroupPane.swift`.

- [ ] Add **Hide empty groups** `Toggle` and the **Empty group** Top/Bottom control (the Empty-group row hides while hide-empty is on). Repoint the `.group` navigation destination to `GroupingPane`; delete the old `GroupPane.swift`. Run the FULL target — the existing sidebar/launch tests (quirk 8) must stay green.
- [ ] **Commit:** `feat(grouping): empty-group controls; replace GroupPane`.

---

## Phase 3 — View-level manual header drag

### Task 3.1: `RowDragCoordinator` — group reorder closure

**Files:** Modify `RowDragCoordinator.swift:18-31`.

- [ ] Add `var reorderGroups: ([String], Int) -> Void` (the new flat group-key order, or moved-key + target index). Wire its host (ViewSurface) to write `PropertyGrouping.order` via the existing `updateView`/`pageTypeManager` path. Unit-test the host wiring writes `order`. **Commit:** `feat(grouping): group-reorder commit path`.

### Task 3.2: NSOutlineView group-header drag (table)

**Files:** `ViewOutlineTable.swift`, `ViewTableCells.swift`.

- [ ] Install drag ONLY when `GroupConfig == .property && orderMode == .manual` (else the existing page-drag stays — mutual exclusion). Use the modern surface: `registerForDraggedTypes([.init(UTType.data.identifier)])` + `setDraggingSourceOperationMask(.move, forLocal: true)`; `pasteboardWriterForItem` → `NSItemProvider` encoding the group id; `validateDrop` returns `.move` only for root-level group reorder (`item == nil`), `.none` for the locked "No […]" group except top/bottom; `acceptDrop` mutates + calls `reorderGroups` then `moveItem(at:inParent:to:inParent:)` (NOT `reloadData`). Header chip shows a `≡` handle only in Manual. Build green.
- [ ] **Commit:** `feat(grouping): drag-reorder group headers in the table`.

### Task 3.3: Gallery section-header drag + regression gate

**Files:** `GalleryView.swift:105-129`.

- [ ] Render section headers as draggable in Manual mode (`.draggable`/`.dropDestination` with a `Transferable` group id, or route through `reorderGroups` consistent with the table). None obeys top/bottom only.
- [ ] **Regression gate:** run the FULL target; the existing structural page-drag/reorder tests must stay green (mutual exclusion proven). **Commit:** `feat(grouping): drag-reorder gallery section headers`.

---

## Phase 4 — Polish + review

### Task 4.1: Post-functional UIX review (MANDATORY)

- [ ] Run the app; exercise every state (off/structural; each groupable type; each order mode; manual drag in pane + in table + in gallery; hide-empty; empty top/bottom; date granularities). Dispatch a UIX review of the *actual working UI* per Review Discipline. Fix findings. Final full-target green + a clean review round before closeout.
- [ ] **Commit** any fixes; log the feature in `History.md`; move this plan + the spec to `Superseded/` (or remove) per Planning convention.

---

## Self-review (author checklist — completed)

- **Spec coverage:** every spec section maps to a task — schema (0.1–0.2), date buckets (1.1–1.2), order/empty/checkbox (1.3), missing-property fallback (1.4), groupable date (1.5), pane states + picker + popouts + Options + empty controls (2.1–2.5), manual drag in pane (2.4) + table + gallery (3.2–3.3), mutual exclusion (3.2/3.3 gate), UIX review (4.1). Deferred items (sort pane, tiers, system dates, relative, sub-groups) are out of scope by design.
- **Type consistency:** `GroupOrderMode`/`DateGranularity`/`EmptyPlacement` and `PropertyGrouping` field names are used identically across Phase 0→3; `DateBucket.key` signature matches its caller in Task 1.2.
- **Placeholders:** UI tasks (2.2–2.5, 3.2–3.3) specify components + behavior + reuse anchors rather than full SwiftUI bodies — the implementer assembles from the named existing components against the cited files; the load-bearing logic (schema, resolver, date keys, drag delegate surface) carries full code. This is the right altitude for a SwiftUI feature whose pieces are reused, not greenfield.
