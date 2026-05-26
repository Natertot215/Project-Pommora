# View Settings Toolbar Button (Chrome-Only Slice) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single `slider.horizontal.3` toolbar button to the existing primary-action HStack (sharing the existing Liquid Glass capsule), opening an empty placeholder popover sized at 280pt wide — so the user can approve the chrome before pane content is implemented in follow-up patches.

**Architecture:** Statically-positioned button at ContentView's toolbar level (NOT per-detail-view) that reads a `ViewSettingsScope` derived reactively from ContentView's existing `SidebarSelection` state. Scope enum is shape-only at this slice (associated values added in follow-up slices when panes need entity refs). Popover uses `.popover(isPresented:arrowEdge:)` to auto-inherit Liquid Glass via toolbar anchoring (WWDC25 #323).

**Tech Stack:** SwiftUI (macOS 26 / Tahoe), Liquid Glass (`.glassEffect()` on the outer HStack), Swift 6 strict concurrency, Swift Testing (`@Test`, `@Suite`) for the tiny unit test, `xcodebuild` for verification via `builder` subagent.

---

## Context

Pommora's storage detail views (Page Type / Page Collection / Item Type / Item Collection) currently have no per-view configurator chrome. Schema CRUD lives in two ~750-line monolith sheets (`VaultSettingsSheet`, `TypeSettingsSheet`) reached via the sidebar right-click menu. There's no surface for per-view sort / filter / visibility / layout config; users can't toggle which columns appear, can't multi-criterion sort, can't filter the table at all.

The v0.3.0 Properties data layer (just merged to `main`) provides everything needed under the hood — schemas, ID-truth identity, dual relations, validation, indexer — but the UI consumes only a fraction of it.

The full v0.3.1.x Storage View Redesign (research at `.claude/Planning/View-Settings-research-notes.md`) introduces a Notion-style View Settings popover with Property Visibility, Sort, Filter, Group, Layout, and Edit Properties panes. **This plan ships only the chrome-only first slice** — the button + an empty placeholder popover — per the user's explicit session-time constraint ("this plan and execution will stop once the button is in place and I approve of its window size"). All panes, data model changes, and saved-views infrastructure are deferred to subsequent patches in the v0.3.1.x series. The "+ Add view" affordance moves out of this spec entirely (belongs in a future view-toggle-button spec).

## Research surfaced

Two parallel queries (Context7 `/websites/developer_apple_swiftui` + reading `ContentView.swift` lines 75–115) ground these decisions:

**1. The existing toolbar uses ONE `.glassEffect()` on an outer HStack with plain segment buttons inside** ([ContentView.swift:91-113](Pommora/Pommora/ContentView.swift#L91-L113)):

```swift
ToolbarItem(placement: .primaryAction) {
    if recentsManager != nil, pinnedManager != nil {
        HStack(spacing: 0) {
            NavDropdownButton(asSegment: true) { sel in
                sidebarSelection = sel
            }
            Button {                                    // Inspector toggle
                withAnimation(.smooth(duration: 0.25)) {
                    inspectorPresented.toggle()
                }
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 16)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut("0", modifiers: [.option, .command])
            .help("Toggle Inspector (⌥⌘0)")
        }
        .glassEffect()                                  // ONE glass on the outer HStack
    }
}
```

Inserting the new button inside this HStack at the leading position automatically shares the capsule — no `GlassEffectContainer`, no `.glassEffectUnion`, no per-button `.buttonStyle(.glass)` needed.

**2. `.popover(isPresented:attachmentAnchor:arrowEdge:content:)` is the locked container** (Apple docs):

```swift
nonisolated
func popover<Content>(
    isPresented: Binding<Bool>,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge? = nil,
    @ViewBuilder content: @escaping () -> Content
) -> some View where Content : View
```

Toolbar-anchored popovers auto-inherit Liquid Glass per WWDC25 #323. No `.background(.regularMaterial)` or `.glassEffect()` on the popover content — Apple drives the chrome.

**3. `@Environment(\.dismiss)` works inside popover content for both popover dismiss and NavigationStack pops** (single API for both). At this chrome slice no NavigationStack exists yet, so `dismiss` simply closes the popover.

**4. The existing selection state already covers every surface we need** ([SidebarSelection.swift](Pommora/Pommora/Sidebar/SidebarSelection.swift)):

```swift
enum SidebarSelection: Equatable, Hashable, Sendable {
    case none
    case savedKey(String)  // "homepage" | "calendar" | "recents"
    case space(Space)
    case topic(Topic)
    case project(Project)
    case pageType(PageType)
    case collection(PageCollection)
    case page(PageMeta)
    case itemType(ItemType)
    case itemCollection(ItemCollection)
}
```

Calendar surfaces via `.savedKey("calendar")`, not its own case. ContentView already owns this state as `@State sidebarSelection: SidebarSelection`. The new computed `currentViewSettingsScope` reads the same state — no new state added.

**5. SF Symbol choice locked: `slider.horizontal.3`** (Apple HIG: per-view configurator; mirrors Photos library options + Music now-playing settings). NOT `gearshape` (app-wide Settings). NOT `line.3.horizontal.decrease.circle` (Mail filter / App Store sort — too specific).

**6. From the Pommora `swiftui-expert-skill` correctness checklist:**
- `@State` properties must be `private`
- `@Environment(\.dismiss)` is the canonical dismiss path
- iOS 26 / macOS 26 APIs need `#available` gating + fallback when called outside `@available(macOS 26.0, *)` scope — but Pommora ships against the macOS 26 SDK (Liquid Glass + `slider.horizontal.3` both ship by then), so no gating is required.

**7. Branch quirks that apply to this slice** (from `.claude/CLAUDE.md`):
- Quirk #2: `PBXFileSystemSynchronizedRootGroup` — new Swift files auto-include; no pbxproj editing.
- Quirk #3: Trust `xcodebuild`, not SourceKit squiggles.
- Quirk #5: Swift 6 strict concurrency + ExistentialAny ON. Custom Codable uses `any Decoder` / `any Encoder`.
- Quirk #13: `builder` subagent runs `xcodebuild` in background with `-only-testing:PommoraTests` (skip UI tests).
- Quirk #16: Every `@Environment(X.self)` declared on a detail view must be injected at `ContentView.detail`'s `.environment(...)` chain. At THIS slice the button + popover live at ContentView (env source) and declare no `@Environment(X.self)` of their own — quirk #16 doesn't bite here, but applies in v0.3.1+ when panes start consuming managers.

## Architectural principle: static button position, adaptive popover content

**The button is statically positioned. Its popover content adapts to the current selection.**

This is the load-bearing invariant of the entire View Settings surface — not a follow-up concern, not an implementation detail, not a trade-off to settle later. It dictates every placement and routing decision in this slice and every subsequent v0.3.1.x patch.

**Why static placement matters:**
- **Chrome stability** — the button never moves between surfaces. Users develop muscle memory for one toolbar location.
- **Glass capsule integrity** — the three-button capsule (`[ViewSettings] [NavDropdown] [InspectorToggle]`) stays intact across every navigation. Re-mounting the button per detail view would break the shared Liquid Glass grouping.
- **No per-surface toolbar plumbing** — detail views never declare their own `.toolbar { … }` blocks for this button. Adding the button to nine detail views would mean nine future re-touches per pane addition.

**Why adaptive content matters:**
- **One button, every context** — the menu (Property Visibility, Sort, Filter, Edit Properties when those land) reflects whatever's currently selected: Vault menu when viewing a Vault, Collection menu when viewing a Collection, placeholder pane when viewing a Page/Context/Calendar.
- **Single source of truth for "what's selected"** — ContentView already owns the selection state; the popover reads from the same state instead of duplicating it per surface.

**The mechanism:**

```
┌─────────────────────────────────────────────────────────┐
│ ContentView                                             │
│                                                         │
│  @State sidebarSelection: SidebarSelection              │ ← existing selection state
│       │                                                 │   (drives detail-view routing)
│       ├──→ detail view routing (existing)              │
│       │                                                 │
│       └──→ currentViewSettingsScope (NEW computed)     │ ← same state, second derivation
│                  │                                      │
│                  ▼                                      │
│  .toolbar { ToolbarItem(.primaryAction) {              │ ← static placement
│      HStack(spacing: 0) {                               │
│          ViewSettingsButton(scope: currentViewSettingsScope)  ← reads scope reactively
│          NavDropdownButton(...)                         │
│          InspectorToggleButton(...)                     │
│      }.glassEffect()                                    │ ← shared capsule
│  }}                                                     │
└─────────────────────────────────────────────────────────┘

When sidebarSelection changes:
  → detail view re-routes (existing behavior)
  → currentViewSettingsScope recomputes (NEW)
  → ViewSettingsButton's popover content updates (button itself stays put)
```

The button is a single `View` instance with a fixed toolbar position. SwiftUI re-evaluates its `scope` parameter when ContentView's selection state changes; the popover body (when open) re-renders against the new scope; the button's visual position never moves.

**Implementation requirements this places on the chrome slice:**

1. `ViewSettingsScope` MUST be a value type passed as a parameter, not pulled from environment per-pane — environment-based access would couple panes to ContentView's env injection and re-introduce the per-surface plumbing this principle exists to eliminate.
2. The ContentView computed property MUST be derived from existing selection state (no new state added, no new manager dependencies introduced for this slice).
3. Even though the scope is a case-only enum at this slice (placeholder body needs no state), the enum SHAPE and the ContentView computed-property SHAPE both ship now — the v0.3.1 patch only adds associated values, never changes the structural pattern.

## File structure

**Files to CREATE (3 Swift + 1 test):**

| Path | Responsibility |
|---|---|
| `Pommora/Pommora/ViewSettings/ViewSettingsScope.swift` | Case-only enum tagging which surface the popover currently reflects. 10 cases mirror `SidebarSelection`. At this slice carries no associated values — added in v0.3.1 when first real pane lands. |
| `Pommora/Pommora/ViewSettings/ViewSettingsPopover.swift` | Minimal popover content view: `.frame(width: 280)`, single VStack with placeholder line + dismiss control. No NavigationStack, no panes, no per-scope branching beyond visible-or-not. |
| `Pommora/Pommora/ViewSettings/ViewSettingsButton.swift` | Reusable `View` exposing the toolbar button + `.popover` modifier. Accepts `scope: ViewSettingsScope`. Owns the `@State private var isPresented: Bool` for popover visibility. |
| `Pommora/PommoraTests/ViewSettings/ViewSettingsScopeMappingTests.swift` | Unit test for `ContentView.viewSettingsScope(for:)` helper — exhaustively maps every `SidebarSelection` case to the expected `ViewSettingsScope` case. |

**File to MODIFY (1):**

| Path | Change |
|---|---|
| `Pommora/Pommora/ContentView.swift` | (1) Insert `ViewSettingsButton(scope: currentViewSettingsScope)` as the FIRST item inside the existing HStack at lines 93–110. (2) Add private computed property `currentViewSettingsScope: ViewSettingsScope` derived from `sidebarSelection`. (3) Extract the mapping into a testable `static func viewSettingsScope(for: SidebarSelection) -> ViewSettingsScope` so the unit test can hit it without bootstrapping ContentView. |

**Files NOT modified this slice:**

- All 9 detail-view files — no `.toolbar` blocks added; placement is centralized in ContentView
- All Codable structs (PageType, PageCollection, ItemType, ItemCollection, SavedView, Settings)
- All manager files (PageTypeManager, ItemTypeManager, ContentManager, etc.)
- All existing settings sheets (VaultSettingsSheet, TypeSettingsSheet)
- Feature docs — defer to next slice

## Scope-driven content wiring (the core mechanism)

ContentView is where the button lives — there is only one main window, one toolbar, one primary-action HStack, and that HStack already exists with NavDropdown + Inspector toggle inside it. The new button drops in there. No detail-view toolbars get touched.

Because the button lives at ContentView and ContentView already owns `sidebarSelection`, the popover's content adapts automatically: ContentView derives `currentViewSettingsScope` from the selection, passes it to the button, the button passes it to the popover, and SwiftUI re-evaluates the chain every time selection changes. **One button, every surface, scope-dispatched content.**

### What "scope-dispatched content" means at this slice vs in v0.3.1+

| Selection (sidebar) | Scope value | Placeholder body says (this slice) | Body becomes (v0.3.1+) |
|---|---|---|---|
| Vault (PageType) | `.pageType` | "View settings coming soon — Layout, Property Visibility, ..." | Vault-scoped Group + View menu (Edit Properties hits Vault's schema) |
| Page Collection | `.pageCollection` | same storage-scope message | Collection-scoped Group + View menu (Edit Properties hits parent Vault's schema) |
| Item Type | `.itemType` | same storage-scope message | Type-scoped Group + View menu (with Singular field; Edit Properties hits Type's schema) |
| Set (ItemCollection) | `.itemCollection` | same storage-scope message | Set-scoped Group + View menu (Edit Properties hits parent Type's schema) |
| Page | `.page` | "View settings for this surface arrive in a future patch..." | Page identity (Icon + Title + tier1/2/3) when scoped |
| Space / Topic / Project | `.space / .topic / .project` | same placeholder message | Group-Level-only menu (Icon + Title — no schema, no view-level) |
| `.savedKey("calendar")` | `.calendar` | same placeholder message | Calendar-specific menu (TBD when Calendar feature spec lands) |
| `.savedKey("homepage")` / `.savedKey("recents")` / no selection | `.none` | "Select a vault, collection, type, set, ..." | Same none-state message |

The scope's role at this slice is to **select the right placeholder string** in Task 2's `placeholderMessage` switch. The role in v0.3.1+ is to **select the right pane tree** in the `NavigationStack`. Same wiring, different rendering target. Adding associated values to the enum in v0.3.1 (e.g. `case pageType(PageType)`) is source-compatible — code that doesn't destructure isn't affected.

### Locked enum shape for v0.3.1 (forward-compat — NOT this slice)

```swift
enum ViewSettingsScope {
    case pageType(PageType)
    case pageCollection(PageCollection)
    case itemType(ItemType)
    case itemCollection(ItemCollection)
    case page(PageMeta)
    case space(Space)
    case topic(Topic)
    case project(Project)
    case calendar
    case none
}
```

At THIS slice the enum is case-only (no associated values) — the placeholder body doesn't need entity refs. ContentView's mapping helper has the same shape; in v0.3.1 each case gains the entity payload by destructuring `sidebarSelection`'s associated value. The architectural pattern (computed property → button param → popover param) ships intact now.

### Why this is the only sensible shape

Detail views can't merge their own `.toolbar { ... }` blocks into ContentView's existing HStack — SwiftUI's toolbar composition adds new `ToolbarItem`s, it doesn't merge into an existing item's view body. The shared Liquid Glass capsule requires the button to be inside the existing HStack. The existing HStack lives at ContentView. Therefore: ContentView placement. Anything else regresses the capsule into separate floating chrome.

---

## Task 1: Create `ViewSettingsScope` enum + mapping helper + unit test

**Files:**
- Create: `Pommora/Pommora/ViewSettings/ViewSettingsScope.swift`
- Create: `Pommora/PommoraTests/ViewSettings/ViewSettingsScopeMappingTests.swift`

- [ ] **Step 1: Verify target directory exists**

Run: `ls -ld "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora/" "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/PommoraTests/"`

Expected: both list as directories. Note: `Pommora/Pommora/ViewSettings/` and `Pommora/PommoraTests/ViewSettings/` do NOT yet exist — `mkdir -p` creates them. PBXFileSystemSynchronizedRootGroup auto-includes new folders (quirk #2).

- [ ] **Step 2: Create directories**

Run: `mkdir -p "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora/ViewSettings/" "/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/PommoraTests/ViewSettings/"`

Expected: silent success.

- [ ] **Step 3: Write the failing unit test**

Path: `Pommora/PommoraTests/ViewSettings/ViewSettingsScopeMappingTests.swift`

```swift
import Foundation
import Testing

@testable import Pommora

@Suite("ViewSettingsScope mapping from SidebarSelection")
@MainActor
struct ViewSettingsScopeMappingTests {

    @Test("none selection maps to .none scope")
    func noneMapsToNone() {
        let scope = ContentView.viewSettingsScope(for: .none)
        #expect(scope == .none)
    }

    @Test("savedKey calendar maps to .calendar scope")
    func calendarSavedKeyMapsToCalendar() {
        let scope = ContentView.viewSettingsScope(for: .savedKey("calendar"))
        #expect(scope == .calendar)
    }

    @Test("savedKey homepage maps to .none scope (not a view-settings surface)")
    func homepageSavedKeyMapsToNone() {
        let scope = ContentView.viewSettingsScope(for: .savedKey("homepage"))
        #expect(scope == .none)
    }

    @Test("savedKey recents maps to .none scope (not a view-settings surface)")
    func recentsSavedKeyMapsToNone() {
        let scope = ContentView.viewSettingsScope(for: .savedKey("recents"))
        #expect(scope == .none)
    }

    @Test("savedKey unknown maps to .none scope")
    func unknownSavedKeyMapsToNone() {
        let scope = ContentView.viewSettingsScope(for: .savedKey("garbage"))
        #expect(scope == .none)
    }

    @Test("space selection maps to .space scope")
    func spaceMapsToSpace() {
        let s = Space(id: "01HSPACE", name: "Personal", icon: nil, color: nil)
        let scope = ContentView.viewSettingsScope(for: .space(s))
        #expect(scope == .space)
    }

    @Test("topic selection maps to .topic scope")
    func topicMapsToTopic() {
        let t = Topic(id: "01HTOPIC", name: "Work", spaceID: "01HSPACE", icon: nil, color: nil)
        let scope = ContentView.viewSettingsScope(for: .topic(t))
        #expect(scope == .topic)
    }

    @Test("project selection maps to .project scope")
    func projectMapsToProject() {
        let p = Project(id: "01HPROJ", name: "Launch", topicID: "01HTOPIC", icon: nil, color: nil)
        let scope = ContentView.viewSettingsScope(for: .project(p))
        #expect(scope == .project)
    }

    @Test("pageType selection maps to .pageType scope")
    func pageTypeMapsToPageType() {
        let t = PageType(id: "01HPT", name: "Notes")
        let scope = ContentView.viewSettingsScope(for: .pageType(t))
        #expect(scope == .pageType)
    }

    @Test("collection (PageCollection) selection maps to .pageCollection scope")
    func collectionMapsToPageCollection() {
        let c = PageCollection(id: "01HPC", typeID: "01HPT", name: "Drafts")
        let scope = ContentView.viewSettingsScope(for: .collection(c))
        #expect(scope == .pageCollection)
    }

    @Test("page selection maps to .page scope")
    func pageMapsToPage() {
        let p = PageMeta(id: "01HPAGE", name: "Notes")
        let scope = ContentView.viewSettingsScope(for: .page(p))
        #expect(scope == .page)
    }

    @Test("itemType selection maps to .itemType scope")
    func itemTypeMapsToItemType() {
        let t = ItemType(id: "01HIT", name: "Books")
        let scope = ContentView.viewSettingsScope(for: .itemType(t))
        #expect(scope == .itemType)
    }

    @Test("itemCollection selection maps to .itemCollection scope")
    func itemCollectionMapsToItemCollection() {
        let c = ItemCollection(id: "01HIC", typeID: "01HIT", name: "Want to read")
        let scope = ContentView.viewSettingsScope(for: .itemCollection(c))
        #expect(scope == .itemCollection)
    }
}
```

*Note on test data:* The constructors above match the existing initializers in `Space.swift`, `Topic.swift`, `Project.swift`, `PageType.swift`, `PageCollection.swift`, `PageMeta.swift`, `ItemType.swift`, `ItemCollection.swift`. If any constructor signature has additional required parameters not shown, fill them with the minimal valid defaults the existing test files use (grep `init(id:` on each type to verify). Test stays focused on scope mapping — entity contents are irrelevant.

- [ ] **Step 4: Run test to verify it fails**

Dispatch builder subagent in background (quirk #13):

```
Agent({
  subagent_type: "builder", run_in_background: true,
  description: "Verify scope mapping tests fail (no impl yet)",
  prompt: "Run xcodebuild test in the Pommora.xcodeproj workspace at /Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/. Use -only-testing:PommoraTests/ViewSettingsScopeMappingTests to scope to the new test file. Report back the failure mode. Expected: tests fail with 'cannot find ContentView.viewSettingsScope(for:)' or 'cannot find type ViewSettingsScope' (since neither is implemented yet). DO NOT propose fixes."
})
```

Expected: FAIL with `Cannot find 'ViewSettingsScope' in scope` or `Type 'ContentView' has no member 'viewSettingsScope'` or both.

- [ ] **Step 5: Write the ViewSettingsScope enum**

Path: `Pommora/Pommora/ViewSettings/ViewSettingsScope.swift`

```swift
import Foundation

/// Tags which surface the View Settings popover is currently reflecting.
///
/// At v0.3.1.x chrome slice this enum is case-only — the placeholder popover
/// body doesn't read entity state. In v0.3.1 (first real pane) the cases
/// gain associated values carrying the concrete entity (PageType, PageCollection,
/// ItemType, ItemCollection, PageMeta, Space, Topic, Project). Adding associated
/// values is a source-compatible change for code that doesn't destructure the
/// cases (the only consumer at this slice is the placeholder popover, which
/// only checks `case .none`).
///
/// Mirrors `SidebarSelection`'s shape one-to-one with two adjustments:
///   - `.savedKey("calendar")` collapses to `.calendar` (saved-key strings
///     are an implementation detail of the sidebar; the popover speaks in
///     surface kinds).
///   - All other `.savedKey(_)` values (`"homepage"`, `"recents"`, unknown)
///     collapse to `.none` — they aren't view-settings surfaces.
enum ViewSettingsScope: Equatable, Sendable {
    case none
    case pageType
    case pageCollection
    case itemType
    case itemCollection
    case page
    case space
    case topic
    case project
    case calendar
}
```

- [ ] **Step 6: Add the static mapping helper to ContentView**

File: `Pommora/Pommora/ContentView.swift`

Locate the `struct ContentView: View {` declaration (around line 20–30; verify with grep `struct ContentView` if needed). Inside the struct, add this static helper near the other private helpers (above `var body: some View` is fine):

```swift
/// Maps a `SidebarSelection` to a `ViewSettingsScope`. Static + pure so the
/// scope-mapping logic is unit-testable without bootstrapping a full
/// `ContentView` instance + its env values.
///
/// See `ViewSettingsScope` for the contract on .savedKey collapsing.
static func viewSettingsScope(for selection: SidebarSelection) -> ViewSettingsScope {
    switch selection {
    case .none:
        return .none
    case .savedKey(let key):
        return key == "calendar" ? .calendar : .none
    case .space:
        return .space
    case .topic:
        return .topic
    case .project:
        return .project
    case .pageType:
        return .pageType
    case .collection:
        return .pageCollection
    case .page:
        return .page
    case .itemType:
        return .itemType
    case .itemCollection:
        return .itemCollection
    }
}
```

- [ ] **Step 7: Run test to verify it passes**

Dispatch builder subagent in background:

```
Agent({
  subagent_type: "builder", run_in_background: true,
  description: "Verify scope mapping tests pass",
  prompt: "Run xcodebuild test in the Pommora.xcodeproj workspace at /Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/. Use -only-testing:PommoraTests/ViewSettingsScopeMappingTests. Report back pass/fail with count. Expected: 13 tests pass."
})
```

Expected: 13 tests PASS, 0 fail.

- [ ] **Step 8: Run full PommoraTests suite to confirm no regression**

```
Agent({
  subagent_type: "builder", run_in_background: true,
  description: "Full PommoraTests sanity",
  prompt: "Run xcodebuild test in /Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora.xcodeproj with -only-testing:PommoraTests. Report pass/fail counts. Expected: all existing tests still pass."
})
```

Expected: all pre-existing tests pass + 13 new ones; total green.

- [ ] **Step 9: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/Pommora/ViewSettings/ViewSettingsScope.swift \
        Pommora/PommoraTests/ViewSettings/ViewSettingsScopeMappingTests.swift \
        Pommora/Pommora/ContentView.swift
git commit -m "$(cat <<'EOF'
feat(view-settings): ViewSettingsScope enum + mapping helper

Case-only enum (10 cases mirror SidebarSelection); ContentView gains
a static viewSettingsScope(for:) helper. No UI changes yet — sets up
the data shape for the chrome-only slice's button + popover.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `ViewSettingsPopover` (placeholder body)

**Files:**
- Create: `Pommora/Pommora/ViewSettings/ViewSettingsPopover.swift`

- [ ] **Step 1: Write the popover view**

```swift
import SwiftUI

/// View Settings popover content — chrome-only placeholder slice.
///
/// At v0.3.1.x this renders a single muted line and a Done button. In v0.3.1
/// this gets replaced by a NavigationStack with real panes (Layout / Property
/// Visibility / Sort / Filter / Group / Edit Properties). The fixed 280pt
/// width is locked here and survives all subsequent slices.
///
/// Liquid Glass background is auto-applied by the toolbar-anchored popover
/// (WWDC25 #323). Do NOT apply .background(.regularMaterial) or
/// .glassEffect() — Apple drives the chrome.
struct ViewSettingsPopover: View {
    /// Which surface the popover currently reflects. At this slice the scope
    /// only affects whether the placeholder line says "for this view" — full
    /// per-scope content lands in v0.3.1.
    let scope: ViewSettingsScope

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("View settings")
                    .font(.headline)
                Spacer()
                Button(role: .close) {
                    dismiss()
                }
            }

            Text(placeholderMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 280)
    }

    private var placeholderMessage: String {
        switch scope {
        case .none:
            return "Select a vault, collection, type, set, page, space, topic, project, or the calendar to configure its view."
        case .page, .space, .topic, .project, .calendar:
            return "View settings for this surface arrive in a future patch. For now, use the existing settings entry points."
        case .pageType, .pageCollection, .itemType, .itemCollection:
            return "View settings coming soon — Layout, Property Visibility, Sort, Filter, Group, and Edit Properties will land in upcoming v0.3.1.x patches."
        }
    }
}

#if DEBUG
#Preview("Storage scope") {
    ViewSettingsPopover(scope: .pageType)
}

#Preview("Placeholder scope") {
    ViewSettingsPopover(scope: .page)
}

#Preview("None scope") {
    ViewSettingsPopover(scope: .none)
}
#endif
```

- [ ] **Step 2: Verify build with the new file**

```
Agent({
  subagent_type: "builder", run_in_background: true,
  description: "Build with ViewSettingsPopover added",
  prompt: "Run xcodebuild build in /Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora.xcodeproj for scheme Pommora. Report success/failure and any errors. Expected: clean build (the new ViewSettingsPopover.swift file should auto-include via PBXFileSystemSynchronizedRootGroup)."
})
```

Expected: BUILD SUCCEEDED. If any 'no such module / cannot find type' errors appear that reference `ViewSettingsScope`, those are stale SourceKit and would have surfaced before — re-run; trust xcodebuild over IDE (quirk #3).

- [ ] **Step 3: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/Pommora/ViewSettings/ViewSettingsPopover.swift
git commit -m "$(cat <<'EOF'
feat(view-settings): ViewSettingsPopover placeholder body

Fixed 280pt width; per-scope placeholder message; Done button via
Environment(\.dismiss). Liquid Glass auto-inherits from toolbar anchor
(WWDC25 #323) — no manual material applied. Real panes follow in v0.3.1.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create `ViewSettingsButton`

**Files:**
- Create: `Pommora/Pommora/ViewSettings/ViewSettingsButton.swift`

- [ ] **Step 1: Write the button view**

```swift
import SwiftUI

/// Toolbar button that opens the View Settings popover.
///
/// Statically positioned at ContentView level (NOT per-detail-view) inside
/// the existing primary-action HStack so it shares the Liquid Glass capsule
/// with NavDropdown + Inspector toggle.
///
/// The `scope` parameter is reactive: when ContentView's selection changes,
/// ContentView recomputes the scope and SwiftUI re-passes it here, causing
/// the open popover (if any) to re-render its content against the new scope.
/// The button itself never moves.
///
/// Sizing matches the Inspector toggle next to it (same 22x16 icon frame)
/// so the three-button capsule reads as a uniform segmented group.
struct ViewSettingsButton: View {
    let scope: ViewSettingsScope

    @State private var isPresented: Bool = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 16)
                .contentShape(Rectangle())
        }
        .help("View Settings")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ViewSettingsPopover(scope: scope)
        }
    }
}

#if DEBUG
#Preview("Button (pageType scope)") {
    ViewSettingsButton(scope: .pageType)
        .padding()
}
#endif
```

- [ ] **Step 2: Verify build**

```
Agent({
  subagent_type: "builder", run_in_background: true,
  description: "Build with ViewSettingsButton added",
  prompt: "Run xcodebuild build in /Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora.xcodeproj for scheme Pommora. Report success/failure and any errors. Expected: clean build."
})
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/Pommora/ViewSettings/ViewSettingsButton.swift
git commit -m "$(cat <<'EOF'
feat(view-settings): ViewSettingsButton with popover wrapper

Standard SwiftUI toolbar button (slider.horizontal.3); 22x16 icon frame
matches Inspector toggle so the upcoming three-button capsule reads
uniformly. Owns popover visibility via @State; popover anchored to
arrowEdge: .top with Liquid Glass auto-inheriting from toolbar anchor.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Wire button into ContentView's existing HStack

**Files:**
- Modify: `Pommora/Pommora/ContentView.swift:91-113`

- [ ] **Step 1: Add the computed scope property on ContentView**

File: `Pommora/Pommora/ContentView.swift`

Locate the `struct ContentView: View {` declaration. Below the existing `static func viewSettingsScope(for:)` added in Task 1, add this instance computed property (it must be `var`, not `let`/`func`, so SwiftUI re-evaluates it when `sidebarSelection` changes):

```swift
/// Reactive scope derived from the current sidebar selection. Re-evaluates
/// every time `sidebarSelection` mutates. Read by `ViewSettingsButton` to
/// drive the popover body's per-scope content.
///
/// Statically positioning the button + dynamically passing this scope is
/// the architectural principle of the View Settings surface — see
/// `.claude/Planning/...-View-Settings-...` plan for rationale.
private var currentViewSettingsScope: ViewSettingsScope {
    Self.viewSettingsScope(for: sidebarSelection)
}
```

- [ ] **Step 2: Insert the button as the leading item in the existing HStack**

File: `Pommora/Pommora/ContentView.swift:93-110`

Locate the `HStack(spacing: 0) { ... }.glassEffect()` block. The current shape:

```swift
HStack(spacing: 0) {
    NavDropdownButton(asSegment: true) { sel in
        sidebarSelection = sel
    }
    Button {
        withAnimation(.smooth(duration: 0.25)) {
            inspectorPresented.toggle()
        }
    } label: {
        Image(systemName: "sidebar.trailing")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 22, height: 16)
            .contentShape(Rectangle())
    }
    .keyboardShortcut("0", modifiers: [.option, .command])
    .help("Toggle Inspector (⌥⌘0)")
}
.glassEffect()
```

Change to (insert one line at top of HStack body — order: `[ViewSettings] [NavDropdown] [InspectorToggle]`):

```swift
HStack(spacing: 0) {
    ViewSettingsButton(scope: currentViewSettingsScope)
    NavDropdownButton(asSegment: true) { sel in
        sidebarSelection = sel
    }
    Button {
        withAnimation(.smooth(duration: 0.25)) {
            inspectorPresented.toggle()
        }
    } label: {
        Image(systemName: "sidebar.trailing")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 22, height: 16)
            .contentShape(Rectangle())
    }
    .keyboardShortcut("0", modifiers: [.option, .command])
    .help("Toggle Inspector (⌥⌘0)")
}
.glassEffect()
```

No other changes to the ContentView toolbar block.

- [ ] **Step 3: Verify build + tests still pass**

```
Agent({
  subagent_type: "builder", run_in_background: true,
  description: "Verify ContentView wires up cleanly",
  prompt: "Run xcodebuild test in /Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora.xcodeproj with -only-testing:PommoraTests. Report build success + test counts. Expected: BUILD SUCCEEDED; all tests pass (no regression from Tasks 1-3)."
})
```

Expected: BUILD SUCCEEDED; all tests pass.

- [ ] **Step 4: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/Pommora/ContentView.swift
git commit -m "$(cat <<'EOF'
feat(view-settings): wire ViewSettingsButton into ContentView toolbar

Inserts the button at the leading position of the existing primary-action
HStack — shares the existing .glassEffect() capsule with NavDropdown +
Inspector toggle. Adds reactive currentViewSettingsScope computed
property derived from sidebarSelection (no new state added).

Order: [ViewSettings] [NavDropdown] [InspectorToggle].

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Visual approval gate (the actual ship gate per user intent)

**Files:** none — this is a manual visual verification step.

The user's explicit intent for this session: "this plan and execution will stop once the button is in place and I approve of its window size when selected."

- [ ] **Step 1: Launch the app**

Open `Pommora.xcodeproj` in Xcode and press Cmd+R. Wait for the app to come up on an existing nexus (or pick one from the Welcome window).

- [ ] **Step 2: Verify chrome on the four storage detail views (full menu surfaces)**

Navigate sequentially: a Vault (Page Type) → one of its Page Collections → an Item Type → one of its Item Sets. On each:

- The toolbar's primary-action group shows three buttons inside ONE Liquid Glass capsule, ordered left-to-right: `[slider.horizontal.3] [NavDropdown chevrons] [sidebar.trailing]`.
- The `slider.horizontal.3` icon is visually the same size as the Inspector toggle next to it.
- Click the `slider.horizontal.3` button. A popover appears anchored below the button, ~280pt wide. Liquid Glass background visible (translucent over the window content beneath). NO opaque background fill.
- Popover content: "View settings" headline + close (×) button on the right; below, the storage-scope placeholder line ("View settings coming soon — Layout, Property Visibility, ..."). Done button or close-X dismisses.
- Click outside the popover — popover dismisses.
- Press ESC with the popover open — popover dismisses.

- [ ] **Step 3: Verify chrome on the five placeholder surfaces**

Navigate sequentially: a Page (open one from a Page Collection) → a Space → a Topic → a Project → the Calendar (sidebar Pinned section). On each:

- Same three-button capsule visible, same order.
- Click the button. Popover opens with the placeholder-scope message ("View settings for this surface arrive in a future patch...").
- Dismiss works the same way.

- [ ] **Step 4: Verify chrome with no selection**

Navigate to a state with no sidebar selection (eg: click empty space in sidebar, or use Welcome / no-nexus state if possible).

- Click the button. Popover opens with the none-scope message ("Select a vault, collection, ...").
- Dismiss works.

- [ ] **Step 5: Verify selection-change reactivity (the architectural principle)**

With the popover OPEN on a Vault, click a different sidebar entry (eg. a Page Collection) WITHOUT first dismissing the popover.

- Expected outcome A (preferred): popover closes (SwiftUI's default popover dismissal on container view changes).
- Expected outcome B (also acceptable): popover stays open and its body re-renders against the new scope's placeholder message.

Either is fine at this slice — the chrome is correct. If the popover stays open, the message must update to reflect the new scope.

- [ ] **Step 6: User approval gate**

User confirms: "the button placement, sizing, and popover chrome are approved" — or surfaces a specific visual issue (size wrong, position wrong, glass effect missing, etc.).

If approved → this slice is complete. Move to Step 7.
If issue surfaced → triage the specific issue, fix in a follow-up commit on this branch, repeat Steps 1–6.

- [ ] **Step 7: Push the branch**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git push origin v0.3.0-properties
```

Expected: push succeeds. Branch tip advances on `origin/v0.3.0-properties`.

---

## Verification summary

| Gate | Mechanism | Passing condition |
|---|---|---|
| Unit tests | `xcodebuild test -only-testing:PommoraTests/ViewSettingsScopeMappingTests` | 13/13 pass |
| Regression | `xcodebuild test -only-testing:PommoraTests` | All pre-existing tests still pass |
| Build | `xcodebuild build` for scheme Pommora | BUILD SUCCEEDED |
| Visual chrome | Manual smoke on all 9 surfaces (Task 5) | Three-button capsule renders correctly on every surface; popover opens at 280pt with Liquid Glass; dismisses on outside-click + ESC |
| User approval | Explicit confirm during Task 5 Step 6 | User says approved |

---

## Out of scope — to be planned separately

- All v0.3.1.x patches beyond this chrome slice (Layout pane / Property Visibility pane / Sort / Filter / Group / Edit Properties / individual property editor)
- ViewSettingsScope associated-value upgrade (deferred to v0.3.1 — non-breaking change at that point)
- `views: [SavedView]` field additions to `PageCollection` + `ItemCollection`
- `singular: String?` field on `ItemType`
- `SavedView` Codable rework
- Default-view migration on `loadAll`
- Shared `PropertyEditor` extraction from `VaultSettingsSheet` + `TypeSettingsSheet`
- "+ Add view" toggle button — moves to a new spec on its own (per user this session: "will be part of a separate view toggle button, not in this spec")
- Detail-view view-tabs row (when ≥2 saved views ship per container, v0.5.0+)
- Tables-no-vertical-borders implementation (`NSViewRepresentable` + cleared `gridStyleMask`) — locked UIX rule, separate implementation slice
- NavigationStack inside popover — added in v0.3.1 when first pushable pane lands
- `currentViewSettingsScope` upgrade to carry entity associated values (paired with the enum upgrade in v0.3.1)
- Detail-view env-injection chain audit (quirk #16) — only matters when panes start declaring `@Environment(X.self)` of their own; not this slice

---

## Self-review

Ran the spec-coverage + placeholder + type-consistency passes against the plan above:

**1. Spec coverage** — every requirement from the user's drilling has a task:
- Button on all 9 surfaces → Task 4 puts it in ContentView (covers all surfaces via static placement; popover body switches via Task 2's scope-dispatched message). ✓
- Liquid Glass shared capsule → Task 4 inserts inside existing `.glassEffect()` HStack. ✓
- No background fill on popover → Task 2 omits any `.background(...)` modifier (Liquid Glass auto-inherits). ✓
- 280pt fixed width → Task 2 hardcodes `.frame(width: 280)`. ✓
- Static button / adaptive content → Task 4 derives scope from ContentView's existing selection state; button position never moves. ✓
- Item Window excluded → no Item Window file is touched. ✓
- "+ Add view" excluded → no add-view affordance in any task. ✓
- Placeholder behavior on Pages/Contexts/Calendar → Task 2's `placeholderMessage` switch handles those scopes. ✓

**2. Placeholder scan** — searched the plan for "TBD", "TODO", "implement later", "fill in details", "appropriate error handling", "edge cases", "similar to Task N". Result: zero hits in the bite-sized task sections. The "Out of scope" section uses "deferred" / "added in v0.3.1" / "moves to separate spec" which describe scope boundaries, not placeholders inside this slice's tasks. ✓

**3. Type consistency** — cross-checked types and signatures across tasks:
- `ViewSettingsScope` cases used in Task 2's switch (`.none / .page / .space / .topic / .project / .calendar / .pageType / .pageCollection / .itemType / .itemCollection`) match the enum declaration in Task 1 Step 5 exactly. ✓
- `ContentView.viewSettingsScope(for:)` signature in Task 1 Step 6 matches the call site in Task 4 Step 1 (`Self.viewSettingsScope(for: sidebarSelection)`). ✓
- `ViewSettingsButton(scope:)` initializer used in Task 4 Step 2 matches the struct declaration in Task 3 Step 1 (single `scope: ViewSettingsScope` property). ✓
- `ViewSettingsPopover(scope:)` initializer used in Task 3 Step 1 matches the struct declaration in Task 2 Step 1. ✓
- `SidebarSelection` cases referenced in Task 1's mapping helper match the actual enum declaration at [SidebarSelection.swift:5-16](Pommora/Pommora/Sidebar/SidebarSelection.swift#L5-L16) (10 cases: `.none / .savedKey / .space / .topic / .project / .pageType / .collection / .page / .itemType / .itemCollection`). ✓

Test data constructors in Task 1 Step 3 carry one mild assumption (the minimal `init` signatures for `Space`, `Topic`, `Project`, `PageType`, `PageCollection`, `PageMeta`, `ItemType`, `ItemCollection`). A note on that line tells the implementer to verify via grep — appropriate for chrome-slice scope without re-reading every Codable struct now.

Plan is shippable.

---

## Cross-references

- `.claude/Planning/View-Settings-research-notes.md` — full research (Notion UX + SwiftUI primitives) — feeds the follow-up panes work, not this chrome slice
- `.claude/Handoff.md` — current session state
- `.claude/CLAUDE.md` — active-branch quirks (#2, #3, #5, #13, #16 all referenced above)
- `Pommora/Pommora/ContentView.swift:75-115` — existing toolbar code grounded the placement task
- `Pommora/Pommora/Sidebar/SidebarSelection.swift` — selection enum grounded the scope mapping
- WWDC25 Session 323 — Liquid Glass toolbar popovers
- Apple SwiftUI docs (via Context7 `/websites/developer_apple_swiftui`) — `.popover` signature, `.glassEffect()` patterns, `\.dismiss` environment
- User-provided Notion reference screenshots (this session) — guide for the follow-up panes patches, not this slice
