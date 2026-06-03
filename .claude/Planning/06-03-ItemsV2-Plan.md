## ItemsV2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Build per branch quirk #7 (stub-and-progressively-replace, green commit per task) and quirk #13 (verify via background builder agent, `-only-testing:PommoraTests`).

**Goal:** Make Items categorically distinct from Pages through a per-Type **Template** (layout archetype + per-property promoted-display recipe) rendered by **one** config-driven `ItemWindowRenderer` inside a native, draggable, chromeless floating window — without leaving the Markdown substrate.

**Architecture:** Items stay `.md`. A typed `LayoutArchetype` enum + a `[PromotedProperty]` recipe live on `template_config` (Type default → Collection override). One `ItemWindowRenderer` consumes the resolved template via `AnyLayout` over a single shared child set, with a custom `Layout` region-recipe for the archetypes plain stacks can't express. The window becomes a native SwiftUI scene (`WindowGroup(for: ItemRef.self)` + `.windowStyle(.plain)` + `.windowLevel(.floating)`), built as the first consumer of a reusable `PreviewWindow` primitive. Drag-reorder + the read-side value renderer are extracted as shared components reused by both the window and the existing settings panel.

**Tech Stack:** SwiftUI (macOS 26.4 target — all window APIs unconditionally available, no AppKit bridge), Swift 6 strict concurrency + ExistentialAny, MarkdownPM, GRDB/Yams (unchanged), native drag (`.draggable`/`.dropDestination`) — **no new SPM dependency**.

**Source of truth:** spec at `Planning/06-03-ItemsV2-Spec.md` (model + landmines + Open Questions). This plan is built on a 9-agent recon + a reorder-library bench + first-hand reads of all 14 touched files (decisions ratified by Nathan via AskUserQuestion — see Locked Decisions).

> **STATUS — BULLETPROOFED & READY TO EXECUTE.** Survived 5 review/correction rounds (R1 adversarial · R2 citations/snowball/simplify/net-reduce · R3 template-editing model correction · R4 final gate: 4 blockers + 5 majors · R5 confirmation gate: **0 blockers / 0 majors**). Build order is dependency-sound and **green-per-task** (quirk #7). **Execute via `superpowers:subagent-driven-development` from Task 1.1.** ⚠️ **Before Phase 3–4, reconcile with the parallel session** now editing `SidebarDetailView` + the four detail views (T4.4) and the new untracked `DetailFooterBar.swift`/`FooterAddMenuButton.swift` (overlaps T3.1's footer) — see `Handoff.md`. The on-disk strings/schema are locked (registry #14 amendment in T6.1).

---

### Locked Decisions & Schema (LD)

Ratified by Nathan during plan prep. These are facts the executor must not re-litigate.

- **LD-1 — One renderer, not six views.** Build a single `ItemWindowRenderer`; a layout is data, never a new view. No `ItemWindowA…F` files.
- **LD-2 — Layout encoding = enum + region-recipe.** `LayoutArchetype` is a typed, tolerant-decode enum; a custom `Layout` region-recipe backs Banner/Two-Column + any side-pane archetype.
- **LD-3 — Roster = 5 distinct + 1 reserved + tolerant unknown.** Cases: `compact`, `standard`, `banner_two_column`, `gallery`, `wide`, `reserved`. Unknown on-disk strings decode to `.unknown(String)` (round-trip-preserving — never data loss). "Inspector" is **not** an archetype; it's a per-archetype **overflow-presentation mode** (`dropdown` | `inspector`).
- **LD-4 — Per-property display, extensible.** `promoted_properties` is `[{ "id", "display"? }]`. `display` is a tolerant-decode `PropertyDisplay` enum (`inline`/`thumbnail`/`banner`/`chips`/`list`/`unknown`). The archetype sets defaults; per-property `display` overrides. A single flat field does **not** carry all rendering.
- **LD-5 — Inspector supplements, never duplicates.** Promoted properties render on the main panel; the rest live in the overflow surface. Resolves the current double-render.
- **LD-6 — Native scene, PreviewWindow-first.** Build a generic `PreviewWindow` primitive; the Item Window is its first consumer. `NSPanel` is fallback only if `.plain` reads too bare.
- **LD-7 — Description: MarkdownPM, 250 cap.** `ItemValidator.maxDescriptionLength = 250`; `template_config.description_cap` is an optional per-type override. In-app over-cap saves reject; external (raw-Obsidian) overflow surfaces a non-blocking warning (no hard file failure).
- **LD-8 — Cover = image-filtered `.file`.** `PropertyDefinition.accept: ["image/*"]`; `template_config.cover_property_id` names which property is the banner. No new `PropertyValue`/`PropertyType` case.
- **LD-9 — Native reorder, shared.** Extract the pure `PropertyIDReorder.move` splice from `PropertyVisibilityPane`; apply `.draggable`/`.dropDestination` **inline** on both surfaces (no generic wrapper view). No dependency.
- **LD-10 — Scope = Type default → Collection override**, governing both archetype and promoted set, one resolution.
- **LD-11 — Deferred (NOT in this plan):** `@item` body grammar + graph edge-weighting (→ v0.4.0); Page "open-in: preview" UI (parallel track once `PreviewWindow` lands — only the inert `open_in` field ships here); per-archetype Figma visuals (filled during execution per directive #3 — tasks ship recipe + structure, not finished pixels).

**Locked on-disk schema (amends registry decision #14):** all fields optional, null-round-trip, additive — existing sidecars are byte-stable until a save rewrites them.

```
_itemtype.json / _itemcollection.json → "template_config":
{
  "layout": "standard",                                  // LayoutArchetype: compact|standard|banner_two_column|gallery|wide|reserved
  "promoted_properties": [{ "id": "prop_01H…", "display": "thumbnail" }],
  "cover_property_id": "prop_01H…",                      // a .file property with accept:["image/*"]
  "description_cap": 250,                                // optional per-type override (Items only)
  "default_description": "…"                             // Items only
}

_pagetype.json / _pagecollection.json → "template_config":   (NEW — reserved parity, minimal)
{
  "layout": null,                                        // reserved (no Page archetypes yet)
  "default_body": "…",
  "open_in": "preview"                                   // OpenInMode: preview|full_page — INERT until PreviewWindow
}
// NOTE: promoted_properties + cover_property_id are NOT carried on the Page side yet —
// added (additively, null-round-trip) when the parallel Page-template track consumes them.
// (Trims the inert duplication flagged in round-2; differs from the ratified preview's full mirror.)
```
Collection-level `template_config` present ⇒ overrides its parent Type; absent ⇒ Type default.

---

### File Structure

**New files**
- `Items/LayoutArchetype.swift` — `LayoutArchetype`, `PropertyDisplay`, `PromotedProperty`, `OpenInMode` (enums/structs + tolerant Codable).
- `Items/TemplateResolver.swift` — resolves the effective `ItemTemplateConfig` for an item (Collection override → Type default) + promoted/cover resolution helpers.
- `Vaults/PageTemplateConfig.swift` — the Page-side reserved-parity config (or co-locate in `PageType.swift`).
- `Content/ItemRef.swift` — stable scene identifier (mirrors `PageRef`).
- `Components/PropertyIDReorder.swift` — pure `[String]`-ID reorder splice helper (`move(_:moving:onto:)`).
- `Window/PreviewWindow.swift` — reusable chromeless floating-scene primitive.
- `ItemWindow/ItemWindowSceneRoot.swift` — resolves an `ItemRef` against `AppGlobals.current` (the live `NexusEnvironment`) and hosts `ItemWindowRenderer` with `.injectNexusEnvironment(env)`; no-ops gracefully if no Nexus is open.
- `ItemWindow/ItemWindowRenderer.swift` — the single config-driven renderer.
- `ItemWindow/ItemWindowLayouts.swift` — the archetype → `any Layout` recipes + the custom region-recipe `Layout`.
- `ViewSettings/ItemTemplatePane.swift` — the unmuted Templates settings pane.

**Modified files**
- `Items/ItemType.swift` — extend `ItemTemplateConfig` (3 new fields).
- `Vaults/PageType.swift` — add `templateConfig: PageTemplateConfig?` (custom Codable lines).
- `Items/ItemCollection.swift` / `Vaults/PageCollection.swift` — add `templateConfig` (custom Codable lines).
- `Validation/ItemValidator.swift` — 250 cap + effective-cap resolver.
- `ItemWindow/ItemWindow.swift` (583 lines) — **net deletion, not a shell.** T4.0 changes `relationDisplay` `let` → `@Environment`; T1.3/T1.6 relocate `friendly` to `ItemValidator`; the Item-specific machinery (`hydrate`, `commitSave`, schema-drift guard, `reloadFromDisk`) **moves into `ItemWindowRenderer`** (T3.x); then **T4.4 deletes the whole file** (incl. the legacy pin cluster `PinnedPropertyChip`/`pinnedChipsBar`/`pin·unpin`/`persistCollection` + the dual-render ≈ **−200 lines**) once the floating scene replaces the `.sheet`. Deletion is deferred to T4.4 — not T3.3 — because `ItemWindow.body` still calls those methods until the sheet is retired (green-per-task, quirk #7).
- `Nexus/NexusEnvironment.swift` — add `AppGlobals.current = self` at end of `init` (publish the live env for cross-scene access).
- `Pages/AppGlobals.swift` — add `static var current: NexusEnvironment?` slot.
- `Detail/SidebarDetailView.swift` — `.sheet` → `openWindow(value: ItemRef)` via `@Environment(\.openWindow)`; resolve Type/Collection in the bridge closure.
- `PommoraApp.swift` — register the `WindowGroup(for: ItemRef.self)` scene (`.windowStyle(.plain)` + `.windowLevel(.floating)` + `.restorationBehavior(.disabled)`).
- `ViewSettings/ViewSettingsRoute.swift` — add `.itemTemplate` (+ `paneTitle`).
- `ViewSettings/ViewSettingsPopover.swift` — add `case .itemTemplate:` to `destination(for:)`.
- `ViewSettings/StorageMenuRoot.swift` — make the Templates row `activeRow(route:.itemTemplate)` for **item** scopes, `mutedRow` for **page** scopes.
- `ViewSettings/PropertyVisibilityPane.swift` — replace its inline reorder splice with `PropertyIDReorder.move` (no behavior change).
- `Detail/Columns/PropertyCellDisplay.swift` — add a `display:` mode (defaulted; the 6 existing call sites stay unchanged) — the one shared read-side renderer.
- `Pages/FrontmatterInspector.swift` — fold its `valueLabel` placeholder switch through the shared renderer.
- `Items/ItemTypeManager.swift` — add `updateTemplateConfig(in:transform:)` (T2.4; mirrors `updateView`, cache write-back) — the single template-persist path, driven by the template editor (T5.2/5.3/5.4 + the renderer's edit mode T3.5).
- `Guidelines/Paradigm-Decisions.md` + `History.md` — amend #14 + log.

> The plan's `Pommora/Pommora/` source root: confirmed paths. `template_config` is **NOT indexed** — `IndexBuilder`/`IndexUpdater` write only fixed columns and ignore unknown keys, so adding it needs **no** index change and **no** `PommoraIndex.currentSchemaVersion` bump.

---

### Phase 1 — Schema Foundation (data model, no UI)

#### Task 1.1: `LayoutArchetype` enum + tolerant Codable

**Files:** Create `Items/LayoutArchetype.swift`; Test `PommoraTests/LayoutArchetypeTests.swift`

- [ ] **Step 1 — Failing test.**
```swift
import Testing
@testable import Pommora

@Suite struct LayoutArchetypeTests {
    @Test func knownValuesRoundTrip() throws {
        for raw in ["compact", "standard", "banner_two_column", "gallery", "wide", "reserved"] {
            let a = LayoutArchetype(rawValue: raw)
            #expect(a.rawValue == raw)
            let data = try JSONEncoder().encode(a)
            #expect(try JSONDecoder().decode(LayoutArchetype.self, from: data) == a)
        }
    }
    @Test func unknownPreservesRawValue() throws {
        let a = LayoutArchetype(rawValue: "future_layout_v9")
        #expect(a == .unknown("future_layout_v9"))
        let data = try JSONEncoder().encode(a)
        #expect(try JSONDecoder().decode(LayoutArchetype.self, from: data).rawValue == "future_layout_v9")
    }
    @Test func selectableExcludesUnknown() {
        #expect(LayoutArchetype.selectable.count == 6)
        #expect(!LayoutArchetype.selectable.contains(.unknown("x")))
    }
}
```
- [ ] **Step 2 — Run, expect FAIL** (`Cannot find 'LayoutArchetype'`). Background builder agent, `-only-testing:PommoraTests/LayoutArchetypeTests`.
- [ ] **Step 3 — Implement.**
```swift
import Foundation

/// Item Window layout archetype. Typed + finite (enum+switch HARD RULE) but
/// forward-expandable: an unrecognized on-disk value decodes to `.unknown`
/// and round-trips unchanged (no data loss). `reserved` is a named 6th slot,
/// muted in the settings pane until promoted to a real archetype.
enum LayoutArchetype: Codable, Hashable, Sendable {
    case compact, standard, bannerTwoColumn, gallery, wide, reserved
    case unknown(String)

    var rawValue: String {
        switch self {
        case .compact: return "compact"
        case .standard: return "standard"
        case .bannerTwoColumn: return "banner_two_column"
        case .gallery: return "gallery"
        case .wide: return "wide"
        case .reserved: return "reserved"
        case .unknown(let s): return s
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "compact": self = .compact
        case "standard": self = .standard
        case "banner_two_column": self = .bannerTwoColumn
        case "gallery": self = .gallery
        case "wide": self = .wide
        case "reserved": self = .reserved
        default: self = .unknown(rawValue)
        }
    }

    init(from decoder: any Decoder) throws {
        self = LayoutArchetype(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    /// Settings-pane roster (the 5 shipping + reserved; never `.unknown`).
    static let selectable: [LayoutArchetype] = [.compact, .standard, .bannerTwoColumn, .gallery, .wide, .reserved]

    /// Overflow surface this archetype declares (LD-3): a side-pane inspector vs a
    /// dropdown. One boolean fact — no separate enum (promote to one only if a
    /// third overflow style ever appears).
    var usesInspector: Bool { self == .bannerTwoColumn }
}
```
> Kept pure data: **no** `displayName` (user-facing labels live in `ItemTemplatePane`, T5.2 — they're per-Nexus renameable, not schema) and **no** `isShipped` flag (T5.2 derives "shipped" from whether `ItemWindowLayouts` has a real recipe — single source, T3.6).
- [ ] **Step 4 — Run, expect PASS.**
- [ ] **Step 5 — Commit.** `feat(items): LayoutArchetype enum with tolerant decode (ItemsV2 T1.1)`

#### Task 1.2: `PropertyDisplay`, `PromotedProperty`, `OpenInMode`

**Files:** Append to `Items/LayoutArchetype.swift`; Test `PommoraTests/PromotedPropertyTests.swift`

- [ ] **Step 1 — Failing test.**
```swift
@Suite struct PromotedPropertyTests {
    @Test func promotedRoundTripsWithAndWithoutDisplay() throws {
        let a = PromotedProperty(id: "prop_1", display: .thumbnail)
        let b = PromotedProperty(id: "prop_2", display: nil)
        for p in [a, b] {
            let data = try JSONEncoder().encode(p)
            #expect(try JSONDecoder().decode(PromotedProperty.self, from: data) == p)
        }
    }
    @Test func displayUnknownPreserved() throws {
        let p = PromotedProperty(id: "p", display: .unknown("carousel"))
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(PromotedProperty.self, from: data).display == .unknown("carousel"))
    }
    @Test func promotedOmitsNilDisplayKey() throws {
        let json = String(data: try JSONEncoder().encode(PromotedProperty(id: "p", display: nil)), encoding: .utf8)!
        #expect(!json.contains("display"))
    }
}
```
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement** (same file):
```swift
/// How a promoted property renders on the main panel (LD-4). Tolerant decode so
/// new options add without breaking older files. The archetype sets a default;
/// a non-nil `PromotedProperty.display` overrides it.
enum PropertyDisplay: Codable, Hashable, Sendable {
    case inline, thumbnail, banner, chips, list
    case unknown(String)

    var rawValue: String {
        switch self {
        case .inline: return "inline"
        case .thumbnail: return "thumbnail"
        case .banner: return "banner"
        case .chips: return "chips"
        case .list: return "list"
        case .unknown(let s): return s
        }
    }
    init(rawValue: String) {
        switch rawValue {
        case "inline": self = .inline
        case "thumbnail": self = .thumbnail
        case "banner": self = .banner
        case "chips": self = .chips
        case "list": self = .list
        default: self = .unknown(rawValue)
        }
    }
    init(from decoder: any Decoder) throws {
        self = PropertyDisplay(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
}

/// A property promoted to a template's main panel, with an optional per-property
/// display override (LD-4). `display == nil` ⇒ the archetype's default treatment.
struct PromotedProperty: Codable, Hashable, Sendable {
    var id: String
    var display: PropertyDisplay?
    enum CodingKeys: String, CodingKey { case id, display }
}

/// Page open-in default (reserved/inert until PreviewWindow — LD-11).
enum OpenInMode: String, Codable, Hashable, Sendable {
    case preview
    case fullPage = "full_page"
}
```
> Note: synthesized Codable on `PromotedProperty` emits `encodeIfPresent` for the optional `display`, so the `display` key is omitted when nil (asserted by the test).
- [ ] **Step 4 — Run, expect PASS.** **Step 5 — Commit.** `feat(items): PropertyDisplay/PromotedProperty/OpenInMode (T1.2)`

#### Task 1.3: Extend `ItemTemplateConfig`

**Files:** Modify `Items/ItemType.swift:109-119`; Test `PommoraTests/ItemTemplateConfigTests.swift`

- [ ] **Step 1 — Failing test** (round-trip + back-compat: a sidecar with only `layout` string still decodes; a fully-null config still round-trips):
```swift
@Suite struct ItemTemplateConfigTests {
    @Test func fullConfigRoundTrips() throws {
        let c = ItemTemplateConfig(
            layout: .gallery,
            promotedProperties: [PromotedProperty(id: "p1", display: .banner)],
            coverPropertyID: "p1", descriptionCap: 250, defaultDescription: "seed")
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(ItemTemplateConfig.self, from: data) == c)
    }
    @Test func legacyLayoutStringStillDecodes() throws {
        let json = #"{"layout":"standard"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(ItemTemplateConfig.self, from: json).layout == .standard)
    }
    @Test func itemTypeWithNilTemplateRoundTrips() throws {  // back-compat guard
        let t = ItemType(id: "01H", title: "T", icon: nil, properties: [], views: [], modifiedAt: .init(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(t)
        #expect(try JSONDecoder().decode(ItemType.self, from: data).templateConfig == nil)
    }
}
```
- [ ] **Step 2 — Run, expect FAIL** (missing-initializer / member errors).
- [ ] **Step 3 — Implement.** `ItemTemplateConfig` (`ItemType.swift:109-119`) already has **three** fields (`layout: String?`, `descriptionCap: Int?`, `defaultDescription: String?`). The change: **retype** `layout` `String?` → `LayoutArchetype?` and **add** `promotedProperties: [PromotedProperty]?` + `coverPropertyID: String?` (`descriptionCap`/`defaultDescription` stay). Replace the struct body with:
```swift
struct ItemTemplateConfig: Codable, Equatable, Hashable, Sendable {
    var layout: LayoutArchetype?
    var promotedProperties: [PromotedProperty]?
    var coverPropertyID: String?
    var descriptionCap: Int?
    var defaultDescription: String?

    init(layout: LayoutArchetype? = nil, promotedProperties: [PromotedProperty]? = nil,
         coverPropertyID: String? = nil, descriptionCap: Int? = nil, defaultDescription: String? = nil) {
        self.layout = layout
        self.promotedProperties = promotedProperties
        self.coverPropertyID = coverPropertyID
        self.descriptionCap = descriptionCap
        self.defaultDescription = defaultDescription
    }

    enum CodingKeys: String, CodingKey {
        case layout
        case promotedProperties = "promoted_properties"
        case coverPropertyID = "cover_property_id"
        case descriptionCap = "description_cap"
        case defaultDescription = "default_description"
    }
}
```
> `layout` was `String?`; `LayoutArchetype` tolerantly decodes any string, so prior free-string layouts round-trip (legacy test). Synthesized Codable keeps null-round-trip (all-optional). `ItemType`'s own custom Codable already calls `decodeIfPresent(ItemTemplateConfig.self, …)` — unchanged. Also **refresh the now-false doc-comments**: the `ItemTemplateConfig` "reserved for post-v1 … nothing renders" comment (`ItemType.swift:106-108`) and the `:19` inline "reserved" note — describe the now-live template config.
- [ ] **Step 4 — Run, expect PASS. Step 5 — Commit.** `feat(items): extend ItemTemplateConfig with promoted/cover (T1.3)`

#### Task 1.4: `PageTemplateConfig` + wire onto `PageType`

**Files:** Create `Vaults/PageTemplateConfig.swift`; Modify `Vaults/PageType.swift`; Test `PommoraTests/PageTemplateConfigTests.swift`

- [ ] **Step 1 — Failing test** (round-trip + `PageType` null-round-trip back-compat, mirroring 1.3).
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement.** New struct:
```swift
import Foundation

/// Page-side template config (reserved parity with ItemTemplateConfig — restores
/// the symmetric-code HARD RULE). All optional, null-round-trip. `layout` is
/// reserved (Pages have no archetype yet); `openIn` is inert until PreviewWindow.
struct PageTemplateConfig: Codable, Equatable, Hashable, Sendable {
    var layout: LayoutArchetype?   // reserved — Pages have no archetype yet
    var defaultBody: String?
    var openIn: OpenInMode?         // inert until PreviewWindow

    init(layout: LayoutArchetype? = nil, defaultBody: String? = nil, openIn: OpenInMode? = nil) {
        self.layout = layout; self.defaultBody = defaultBody; self.openIn = openIn
    }
    enum CodingKeys: String, CodingKey {
        case layout
        case defaultBody = "default_body"
        case openIn = "open_in"
    }
}
```
Then wire onto `PageType` (custom Codable — four edits): add stored `var templateConfig: PageTemplateConfig?`; add `case templateConfig = "template_config"` to `CodingKeys`; add the `init(...)` param (`templateConfig: PageTemplateConfig? = nil`) + assignment; add `self.templateConfig = try c.decodeIfPresent(PageTemplateConfig.self, forKey: .templateConfig)` to `init(from:)`; add `try c.encodeIfPresent(templateConfig, forKey: .templateConfig)` to `encode(to:)`.
- [ ] **Step 4 — Run, expect PASS. Step 5 — Commit.** `feat(pages): PageTemplateConfig reserved parity on PageType (T1.4)`

#### Task 1.5: Collection-level `templateConfig` (override layer)

**Files:** Modify `Items/ItemCollection.swift`, `Vaults/PageCollection.swift`; Test `PommoraTests/CollectionTemplateConfigTests.swift`

- [ ] **Step 1 — Failing test:** an `ItemCollection` with a `templateConfig` round-trips; one without decodes `nil`; existing `pinned_properties` still decodes (no regression).
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement.** On `ItemCollection` (custom Codable): add `var templateConfig: ItemTemplateConfig?`; `case templateConfig = "template_config"`; init param + assignment; `self.templateConfig = try c.decodeIfPresent(ItemTemplateConfig.self, forKey: .templateConfig)`; `try c.encodeIfPresent(templateConfig, forKey: .templateConfig)`. Mirror on `PageCollection` with `PageTemplateConfig?`.
- [ ] **Step 4 — Run, expect PASS. Step 5 — Commit.** `feat(items): Collection-level templateConfig override layer (T1.5)`

#### Task 1.6: 250 cap + effective-cap resolver + relocate `friendly`

**Files:** Modify `Validation/ItemValidator.swift`, `ItemWindow/ItemWindow.swift` (move `friendly` out), `PommoraTests/Validation/ItemValidatorTests.swift` (retype changed error refs); Test `PommoraTests/ItemValidatorCapTests.swift`

- [ ] **Step 1 — Failing test:**
```swift
@Suite struct ItemValidatorCapTests {
    @Test func defaultCapIs250() { #expect(ItemValidator.maxDescriptionLength == 250) }
    @Test func effectiveCapUsesTypeOverride() {
        let withOverride = ItemType(id:"1",title:"T",icon:nil,properties:[],views:[],
            templateConfig: ItemTemplateConfig(descriptionCap: 500), modifiedAt: .init(timeIntervalSince1970:0))
        #expect(ItemValidator.effectiveCap(for: withOverride) == 500)
        let plain = ItemType(id:"2",title:"T",icon:nil,properties:[],views:[],modifiedAt:.init(timeIntervalSince1970:0))
        #expect(ItemValidator.effectiveCap(for: plain) == 250)
    }
    @Test func rejectsOverEffectiveCap() {
        let t = ItemType(id:"1",title:"T",icon:nil,properties:[],views:[],modifiedAt:.init(timeIntervalSince1970:0))
        #expect(throws: ItemValidator.ValidationError.descriptionTooLong(cap: 250)) {
            try ItemValidator.validate(title:"x", tier1:[],tier2:[],tier3:[],
                description: String(repeating:"a", count: 251), properties:[:], itemType: t, context: .empty)
        }
    }
}
```
> `NexusContext.empty` exists (`Validation/NexusContext.swift:21`) and is the established validator-test call — use it directly (it leaves `lookupItemType` at its nil default, fine for the cap test).
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement.** Change `static let maxDescriptionLength = 1000` → `250`. Add:
```swift
/// Effective per-Item cap: the Type template override, else the 250 default (LD-7).
static func effectiveCap(for itemType: ItemType) -> Int {
    itemType.templateConfig?.descriptionCap ?? maxDescriptionLength
}
```
Because `ValidationError.descriptionTooLong` carries **no** payload today and `friendly(...)` is `static` (no `itemType` in scope, `ItemWindow.swift:494-504`), the effective cap can't be "recomputed at the call site." Add the cap to the error:
```swift
case descriptionTooLong(cap: Int)   // was payload-less
```
In `validate(...)`: `let cap = effectiveCap(for: itemType); guard description.count <= cap else { throw .descriptionTooLong(cap: cap) }`. `ValidationError` is `Equatable` — the associated `Int` participates automatically.
- [ ] **Step 3b — Relocate `friendly` so it survives `ItemWindow.swift`'s deletion (T4.4) and stays test-reachable.** Move the `static func friendly(_:) -> String` from `ItemWindow` (`ItemWindow.swift:494-504`) onto **`ItemValidator`** (a non-View error-mapper is the right owner; it's `static` and called from tests). Update its `descriptionTooLong` arm to `case .descriptionTooLong(let cap): "Description over \(cap) source/markdown characters."`. Repoint the renderer + the two test call sites `ItemWindow.friendly(...)` (`ItemValidatorTests.swift:242,248`) → `ItemValidator.friendly(...)`, and retype the **five** bare `.descriptionTooLong` refs → `.descriptionTooLong(cap: 250)` at `ItemValidatorTests.swift:133,152,165,236` **and `:248`** — note **line 248 needs both** the prefix repoint *and* the payload retype (`ItemWindow.friendly(.descriptionTooLong)` → `ItemValidator.friendly(.descriptionTooLong(cap: 250))`).
> External-overflow warning (LD-7) is a **read-path** concern, not a save reject — handled non-blockingly in Task 3.2's counter (warn-color, no throw) so a raw-Obsidian file that overflows still loads. The validator only governs in-app saves.
- [ ] **Step 4 — Run the WHOLE `-only-testing:PommoraTests` target** (not a filtered suite — quirk #1: a filtered run can report green while the target is uncompilable) and **visually confirm a non-zero executed count**. Expect PASS. - [ ] **Step 5 — Commit.** `feat(items): 250 cap + per-type override + relocate friendly to ItemValidator (T1.6)`

---

### Phase 2 — Resolution + Shared DRY Layers (no window yet)

#### Task 2.1: `TemplateResolver`

**Files:** Create `Items/TemplateResolver.swift`; Test `PommoraTests/TemplateResolverTests.swift`

- [ ] **Step 1 — Failing test:** Collection override wins when present; falls back to the Type default when the Collection's `templateConfig` is nil; nil-on-both yields a documented default (`.standard`, empty promoted set).
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement** (pure value logic — no managers, easily unit-tested):
```swift
import Foundation

/// Resolves the effective template for an Item: Collection override → Type
/// default (LD-10). Pure; callers pass the resolved Type + optional Collection.
enum TemplateResolver {
    static func effective(type: ItemType, collection: ItemCollection?) -> ItemTemplateConfig {
        collection?.templateConfig ?? type.templateConfig ?? ItemTemplateConfig()
    }
    // (No standalone `layout()` wrapper — callers read `effective(...).layout ?? .standard` inline.)
    /// Promoted set, migrating a legacy `ItemCollection.pinnedProperties` ([String])
    /// when the template carries none yet (display defaults to nil → archetype default).
    static func promoted(type: ItemType, collection: ItemCollection?) -> [PromotedProperty] {
        if let explicit = effective(type: type, collection: collection).promotedProperties { return explicit }
        return (collection?.pinnedProperties ?? []).map { PromotedProperty(id: $0, display: nil) }
    }
}
```
> **Landmine — pinned→promoted bridge:** the legacy `ItemCollection.pinnedProperties` is read as the promoted set until the template carries its own `promoted_properties`. Writing a promoted set (Task 3.5 / 5.3) writes `template_config.promoted_properties` and leaves `pinned_properties` untouched. **Once `promoted_properties` is set, `pinned_properties` becomes dead-but-preserved** (the resolver returns promoted first) — intentional, non-destructive, consistent with files-are-canonical tolerance of external readers. T5.3 **clears `pinned_properties` on first template write** to collapse to a single source. The **Type-default** promoted set starts **empty** (`ItemType` has no legacy `pinnedProperties` to inherit — that field is Collection-only).
- [ ] **Step 4 — Run, expect PASS. Step 5 — Commit.** `feat(items): TemplateResolver (Collection→Type) (T2.1)`

#### Task 2.2: Generalize the existing `PropertyCellDisplay` (don't build a third renderer)

**Files:** Modify `Detail/Columns/PropertyCellDisplay.swift`, `Pages/FrontmatterInspector.swift`; Test `PommoraTests/PropertyDisplayHelperTests.swift`

> **Net-reduction (round-2):** a rich read-side renderer **already exists** — `PropertyCellDisplay` (315 lines, full 11-`PropertyType` switch with `PropertyChip`/`RelationChip`/`LinkChip`/`FileChip`/`FlowLayout` + a `relationResolver` closure), used at **6 call sites** (`ItemCollectionDetailView`, `ItemTypeDetailView`, `PageTypeDetailView`, `PageCollectionDetailView`, `PropertyCellEditor`, `RelationChip`). Lifting `PinnedPropertyChip`'s weak Text-only switch would create a **third** parallel renderer. Instead **generalize `PropertyCellDisplay`** — this gives T3.4's thumbnail/banner/chips treatments rich rendering essentially for free, and the weak chip switch is **deleted** with the legacy cluster when `ItemWindow.swift` goes (T4.4).

- [ ] **Step 1 — Failing test:** a pure `PropertyDisplay.treatment(for: PropertyType) -> …` resolution helper (which treatment a given display+type yields) — unit-testable without SwiftUI snapshots. (No separate placeholder helper needed — `PropertyCellDisplay.emptyCell` already handles blanks.)
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement.** `PropertyCellDisplay` has an **explicit init** (`:34-42`), so a stored-property default is **not** enough — add a defaulted `display: PropertyDisplay = .inline` **parameter to that init** (insert between `value` and `relationResolver` to keep trailing-default ergonomics) + the stored `var display` + `self.display = display`. The default keeps all **6 existing invocations (across 5 files; `PropertyCellEditor` calls it twice)** compiling unchanged, **and** lets the new `PropertyCellDisplay(definition:value:display:relationResolver:)` sites (T3.1/T3.4) compile. Branch the `.file` arm on `display` (`.thumbnail`/`.banner` → image treatment for image-`accept` files; else today's `FileChip`s) and the `.relation` arm (`.list` → vertical vs default chips); all other displays fall through to today's rendering. **No new renderer type** (`PropertyValueDisplay` is dropped — `PropertyCellDisplay` is the one read-side renderer).
- [ ] **Step 4 — Also fold the second stray switch:** route `FrontmatterInspector.valueLabel(for:)` (`Pages/FrontmatterInspector.swift:242` — an 11-arm placeholder-string switch, structurally the same) through `PropertyCellDisplay`'s rendering (or a tiny shared placeholder helper if a `String` is genuinely needed), deleting the local switch.
- [ ] **Step 5 — Run, expect PASS** (6 existing call sites visually unchanged; one read-side renderer). **Commit.** `refactor(items): generalize PropertyCellDisplay with display modes; fold stray value switches (T2.2)`

#### Task 2.3: Extract the pure reorder splice (`PropertyIDReorder.move`)

**Files:** Create `Components/PropertyIDReorder.swift`; Modify `ViewSettings/PropertyVisibilityPane.swift`; Test `PommoraTests/PropertyIDReorderTests.swift`

> **Simplification (round-2):** the genuine DRY win is the **pure splice**, not a generic `PropertyIDReorderList<Row>` view (the wrapper would share only two `.draggable`/`.dropDestination` lines while forcing a risky refactor of `PropertyVisibilityPane`'s `ForEach`, which is entangled with visible/hidden/unaccounted partitioning the wrapper doesn't model). So: extract **only** the splice; `PropertyVisibilityPane.reorder()` calls it (delete its inline copy); the window's promoted strip applies `.draggable`/`.dropDestination` **inline** (2 lines, in T3.5).

- [ ] **Step 1 — Failing test** on the pure splice (extracted verbatim from `PropertyVisibilityPane.reorder()` math, `:122-132`):
```swift
@Suite struct PropertyIDReorderTests {
    @Test func movesDownAndUp() {
        let order = ["a","b","c","d"]
        #expect(PropertyIDReorder.move(order, moving: "a", onto: "c") == ["b","a","c","d"])  // downward move lands BEFORE the target (source removed first, dst-1)
        #expect(PropertyIDReorder.move(order, moving: "d", onto: "b") == ["a","d","b","c"])
        #expect(PropertyIDReorder.move(order, moving: "a", onto: "a") == order)        // no-op
        #expect(PropertyIDReorder.move(order, moving: "z", onto: "b") == order)        // unknown
    }
}
```
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement** the pure helper only:
```swift
import Foundation

enum PropertyIDReorder {
    /// Moves `moving` to `target`'s slot in an ID array. Mirrors PropertyVisibilityPane's
    /// shift-adjusted splice exactly (downward move targets dstIdx-1 after removal).
    static func move(_ order: [String], moving: String, onto target: String) -> [String] {
        guard moving != target,
              let src = order.firstIndex(of: moving),
              let dst = order.firstIndex(of: target) else { return order }
        var out = order
        let item = out.remove(at: src)
        let adjusted = src < dst ? dst - 1 : dst
        out.insert(item, at: min(max(adjusted, 0), out.count))
        return out
    }
}
```
Then **replace** the whole guard + splice (`:122-132`) with: `let newOrder = PropertyIDReorder.move(currentOrder, moving: droppedID, onto: ontoTargetID); guard newOrder != currentOrder else { return false }` — then the existing persistence routing. The `move` helper already no-ops on same/unknown IDs (returns the array unchanged), so the `!=` guard preserves `.dropDestination`'s accept/reject behavior **and** avoids dangling `srcIdx`/`dstIdx` locals (unused-var warning). **No behavior change** — existing visibility-pane tests stay green, and the logic now lives in exactly one place.
- [ ] **Step 4 — Run, expect PASS (new + existing pane tests). Step 5 — Commit.** `refactor(viewsettings): extract PropertyIDReorder splice; de-dup PropertyVisibilityPane (T2.3)`

#### Task 2.4: `ItemTypeManager.updateTemplateConfig` (the single template-persist path)

**Files:** Modify `Items/ItemTypeManager.swift`; Test `PommoraTests/UpdateTemplateConfigTests.swift`

> The template editor (T5.x) is the **only** writer of `template_config`; the live window never mutates it. This is that single persist path. (Lives in Phase 2 — pure manager/data — so it exists before any T5 consumer.)

- [ ] **Step 1 — Failing test (both scopes — the contract):** the **caller passes a scope-resolved `containerID`** (a Type id *or* a Collection id, exactly as T3.5/T5.x derive from `scope`); the method **searches both containers** (types, then `itemCollectionsByType`). Assert: a **Type-scope** id mutates the Type's `templateConfig` + persists; a **Collection-scope** id mutates that Collection's; the in-memory cache reflects each immediately (read back from `types`/`itemCollectionsByType` without reload). Write these cases against T3.5/T5.3's concrete calling pattern since T2.4 is linearized before them.
- [ ] **Step 2 — FAIL → Step 3 — Implement** `func updateTemplateConfig(in containerID: String, transform: (inout ItemTemplateConfig) -> Void) async throws` — a two-branch lookup (search `types`, then `itemCollectionsByType`) **mirroring `updateView` (`ItemTypeManager.swift:700`) exactly, including the in-memory cache write-back** (`types[i] = updated` / `itemCollectionsByType[typeID]?[ci] = updated`) so the template editor + any open window reflect live, plus the disk save. Seed a fresh `ItemTemplateConfig()` when nil before applying `transform`. **Not** the bare `ItemType.save`/`persistCollection` direct-save (bypasses cache). - [ ] **Step 4 — PASS. Step 5 — Commit.** `feat(items): updateTemplateConfig manager method with cache write-back (T2.4)`

---

### Phase 3 — Single Renderer (`ItemWindowRenderer`)

> Per LD-11/directive #3, these tasks ship the **structure + recipe**, not finished archetype visuals. Each archetype recipe returns a valid layout and is selectable; Figma-driven polish lands per-archetype in later sessions. `standard` is the one fully-built archetype (it equals today's panel) so the window is never broken.

#### Task 3.1: `ItemWindowRenderer` skeleton + `ItemWindowLayouts` recipes

**Files:** Create `ItemWindow/ItemWindowRenderer.swift`, `ItemWindow/ItemWindowLayouts.swift`; Test `PommoraTests/ItemWindowLayoutsTests.swift`

- [ ] **Step 1 — Failing test:** `ItemWindowLayouts.layout(for:)` returns a non-nil `AnyLayout` for every `LayoutArchetype.selectable` case (+ `.unknown` falls back to the `standard` layout). Pure, no view host.
- [ ] **Step 2 — Run, expect FAIL.**
- [ ] **Step 3 — Implement.** `ItemWindowLayouts.layout(for archetype:) -> AnyLayout` switching over the enum — **stock `VStackLayout`/`HStackLayout` for all v1 stubs**, incl. `bannerTwoColumn` as a plain `HStackLayout` for now; `.unknown`/`reserved` → standard. The bespoke custom region-recipe `Layout` (LD-2's eventual encoding for Banner/Two-Column) is **deferred to the Banner archetype's own Figma-driven session** that defines its regions — don't front-load the hardest layout primitive for an unshipped stub. Also add `ItemWindowLayouts.hasRecipe(for:) -> Bool` (true once an archetype has a real, non-fallback recipe) — the single source T5.2 mutes from. `ItemWindowRenderer` takes `(item, resolvedTemplate, itemType, collection?)` and composes header → cover slot → `AnyLayout(ItemWindowLayouts.layout(for: archetype)) { promotedRegion; bodyRegion }` → overflow surface → relations → meta → **footer bar** (container breadcrumb left + an options control right that opens the template / view options, per the Figma mockup). Render promoted + overflow rows through the generalized `PropertyCellDisplay` (T2.2) as `icon + name + value`. In inspector mode the tier relations (**Spaces/Topics/Projects**) render as their own rows **above** the user properties (mockup).
> **AnyLayout identity (scoped claim).** `AnyLayout` preserves view identity/state across a layout-type swap **only when the child set is constant**. So render a **fixed** child set with stable `.id(propertyID)` and let the archetype change **placement + treatment** (via the `Layout` + a per-child display flag) rather than conditionally including/excluding children. Where archetypes genuinely differ in *content* (e.g. a banner image present vs absent), treat the transition as a **cross-fade**, not state-preserving animation — don't oversell smooth animation there.
- [ ] **Step 4 — Run, expect PASS. Step 5 — Commit.** `feat(items): ItemWindowRenderer + AnyLayout archetype recipes (T3.1)`

#### Task 3.2: MarkdownPM description + effective-cap counter

**Files:** Modify `ItemWindow/ItemWindowRenderer.swift` (the **bodyRegion** — the description IS the body, LD-7); Test: manual + a counter-color unit test if extracted.

> Build this in the **renderer** that survives, **not** the soon-deleted `ItemWindow.swift:212-230` (which has no `itemType` at render time anyway). The renderer takes `itemType` as a param, so the counter reads `ItemValidator.effectiveCap(for: itemType)` directly (no `hydrate()` dependency, no default-cap fallback window). Manual test must verify a Type with a custom `descriptionCap` (e.g. 500) shows the override, not the 250 default.

- [ ] **Step 1** — In the renderer's bodyRegion, render the description via `MarkdownPMEditor` using the **full** app parameter set (the real call site is `PageEditorView.swift:224`, **not** the `:210` comment — a bare `Binding<String>` init defaults `documentId` to a shared value, sharing undo history across every item, and yields the un-themed `.default` config):
```swift
MarkdownPMEditor(
    text: $draftDescription,
    foldedHeadings: $foldedHeadings,                 // new @State Set<String>
    configuration: Self.pommoraEditorConfiguration,  // hoist PageEditorView's private static config to a shared location, or a description-scoped variant
    fontName: "SF Pro Text",
    fontSize: 15,
    documentId: item.id,                             // scoped undo/editor state per item
    onScrollOffsetChange: { _ in }
)
```
Counter reads `ItemValidator.effectiveCap(for: itemType)` (the renderer holds `itemType` directly — no `hydrate()`/nil window); over-cap ⇒ warn color only (non-blocking — LD-7).
- [ ] **Step 2** — Build + manual verify (markdown renders; counter warns past the effective cap; a raw-Obsidian overflow still loads — no save block). - [ ] **Step 3 — Commit.** `feat(items): MarkdownPM-rendered description + effective-cap counter (T3.2)`

#### Task 3.3: Promoted/overflow split — fix the double-render

**Files:** Modify `ItemWindow/ItemWindowRenderer.swift`.

- [ ] **Step 1 — Failing test:** a helper `partition(properties:promoted:) -> (main: [ID], overflow: [ID])` returns disjoint sets (promoted on main; the remainder in overflow) — asserts no ID appears in both (the bug).
- [ ] **Step 2 — Run FAIL → Step 3 — Implement** the partition **inside `ItemWindowRenderer.swift`** (matching this task's Files scope): the renderer's main region renders only promoted, the overflow region renders the remainder; overflow presentation branches on `archetype.usesInspector` (`true` ⇒ side-pane; `false` ⇒ dropdown). By construction the renderer has **no** double-render (FixLog #10 is resolved structurally — promoted and overflow are disjoint sets). - [ ] **Step 4 — Run PASS. Commit.** `fix(items): promoted/overflow split in the renderer, no double-render (T3.3, FixLog #10)`
> **Deletion is deferred to T4.4, not here.** The legacy `ItemWindow.swift` cluster (`inspectorPanel :147`, `propertiesSection :232`, `pinnedChipsBar :120`, "Pin to Chips" `:174-183`, `pin`/`unpin` `:338/:346`, `persistCollection` `:352`, `PinnedPropertyChip` `:510-583`) is still **called by `ItemWindow.body`** (`:34/:42/:44/:55`) and `ItemWindow.swift` is the live `.sheet` until T4.4 — deleting it now would break the build (quirk #7). It is removed wholesale when `ItemWindow.swift` is deleted in T4.4; only then does `pinned_properties` lose its last in-app writer.

#### Task 3.4: Apply per-property `display`

**Files:** Modify `ItemWindow/ItemWindowRenderer.swift` (the `PropertyCellDisplay` `display:` branches landed in T2.2).

- [ ] **Step 1 — Failing test:** a `resolvedDisplay(for promoted:archetype:) -> PropertyDisplay` helper — per-property `display` override **else** the archetype's default treatment for that property type. Test the resolution (which treatment wins), not pixels.
- [ ] **Step 2 — FAIL → Step 3 — Implement** the resolver + thread its result into `PropertyCellDisplay(…, display:)` for each promoted property. - [ ] **Step 4 — PASS. Step 5 — Commit.** `feat(items): per-property display resolution (T3.4)`

#### Task 3.5: Renderer **edit/mockup mode** (the template-editing engine)

> **Pinning + placement are edited in the TEMPLATE, not the live item** (Nathan). The live window renders the resolved template (and edits property *values*). So instead of inline promote/reorder controls on the live window, `ItemWindowRenderer` gains an **edit mode** that the Templates pane (T5.3) reuses WYSIWYG as the "mockup item frame."

**Files:** Modify `ItemWindow/ItemWindowRenderer.swift`.

- [ ] **Step 1 — Failing test:** with `editing == false`, no pin/reorder affordances are produced and `promoted_properties` is never mutated (pure render); the promoted-order reorder helper produces the expected `[PromotedProperty]` order preserving each entry's `display`.
- [ ] **Step 2 — FAIL → Step 3 — Implement** an `editing: Bool = false` (or `mode: .live | .templateEdit`) parameter on `ItemWindowRenderer`. When `editing`: overlay a **pin/unpin "Add Property" checklist** + **drag-reorder** on the promoted/overflow regions (rows get `.draggable(id)` + `.dropDestination(for: String.self)` routed through `PropertyIDReorder.move`, T2.3), and on each change call `updateTemplateConfig` (T2.4) to rewrite `template_config.promoted_properties` (Collection override → Type, LD-10). When **not** editing, the live window shows neither — it renders the template's order read-only and edits only property **values**. Representative/placeholder values fill the mockup in edit mode.
- [ ] **Step 4 — PASS. Step 5 — Commit.** `feat(items): ItemWindowRenderer edit/mockup mode (template-editing engine) (T3.5)`

#### Task 3.6: Archetype recipe stubs (muted-until-shipped)

**Files:** `ItemWindow/ItemWindowLayouts.swift`.

- [ ] **Step 1** — For each of `compact`, `bannerTwoColumn`, `gallery`, `wide`: a minimal-but-correct **stock-layout** recipe (`usesInspector` set correctly + sensible default displays); `reserved` → standard layout, and `hasRecipe(for:)` returns false for it (so T5.2 mutes it). - [ ] **Step 2** — Build; switching a Type's `layout` re-lays the **same fixed child set** via `AnyLayout` (identity preserved per T3.1's scoped claim; content-differing transitions are cross-fades, not state-preserving). - [ ] **Step 3 — Commit.** `feat(items): stock archetype recipe stubs (compact/banner/gallery/wide) (T3.6)`

---

### Phase 4 — Floating Window Scene (`PreviewWindow` primitive)

> **Greenfield, not a mirror.** There is **no** existing `WindowGroup(for:)` scene and **no** `openWindow(value:)` *call* in the repo (the `@Environment(\.openWindow)` property already exists at `PommoraApp.swift:11`, just unused for values) — `PageRef.swift:3` + `AppGlobals.swift:10` only *mention* the pattern in doc-comments. This phase builds the window infra from scratch. The hard prerequisite (T4.0) is cross-scene environment access: a sibling `WindowGroup` can't reach `ContentView`'s `@State` `NexusEnvironment`, so a naïve scene would SIGTRAP on first open (quirk #15) because `ItemWindow` reads `@Environment(ItemTypeManager.self)`/`@Environment(ItemContentManager.self)` and (today) takes a required `relationDisplay` `let`.

#### Task 4.0: Cross-scene environment access (prerequisite)

**Files:** Modify `Pages/AppGlobals.swift`, `Nexus/NexusEnvironment.swift`, `ItemWindow/ItemWindow.swift`, `Detail/SidebarDetailView.swift` (sheet call site).

- [ ] **Step 1 — Implement.** Publish the live env: add `static var current: NexusEnvironment?` to `AppGlobals`; at the end of `NexusEnvironment.init` (after all stored props are set, alongside the existing `AppGlobals.publish(...)` at `:196`) add `AppGlobals.current = self`. Refactor `ItemWindow` to read `@Environment(RelationDisplayResolver.self) private var relationDisplay` (drop the constructor `let` at `ItemWindow.swift:5`); update the **existing** `.sheet` call site (`SidebarDetailView.swift:132`) to `ItemWindow(item: item)` (no `relationDisplay:` arg — the resolver is already injected in the main scene via `injectNexusEnvironment`, so the sheet keeps working).
- [ ] **Step 2 — Verify** `xcodebuild` **builds** after dropping the `relationDisplay` param (not just the filtered test), `xcodebuild test` still bootstraps, and the sheet still opens an item correctly. - [ ] **Step 3 — Commit.** `refactor(items): publish NexusEnvironment for cross-scene access; ItemWindow relationDisplay via env (T4.0)`
> Chosen over the AppGlobals-9-manager route because `relationResolver` is **not** in `AppGlobals.publish(...)` (`AppGlobals.swift:36-56`); publishing the whole env reuses the single `injectNexusEnvironment` modifier (`NexusEnvironment.swift:240`), so a consumer gets **every** manager — quirk-#15-safe by construction.
> **Scope the "inherited env" claim to the sheet ONLY.** The `.sheet` works because it's a descendant of the `injectNexusEnvironment`-modified main scene. This does **not** generalize — the new `WindowGroup(for: ItemRef.self)` scene (T4.3) and the View Settings popover (T5.1) are **not** descendants and must each independently `injectNexusEnvironment(AppGlobals.current)`.

#### Task 4.1: `ItemRef`

**Files:** Create `Content/ItemRef.swift`; Test `PommoraTests/ItemRefTests.swift`

- [ ] **Step 1 — Failing test:** `ItemRef` is `Codable & Hashable`, round-trips, and `resolve(...)` returns the live `(Item, ItemType, ItemCollection?)` via the managers (the `PageRef.resolve` *signature shape* is a sound template — that resolver is correct even though its scene consumer never existed).
- [ ] **Step 2 — FAIL → Step 3 — Implement** `struct ItemRef: Codable, Hashable, Sendable { let itemID, typeID: String; let collectionID: String? }` + `@MainActor func resolve(itemTypeManager:itemContentManager:) -> (Item, ItemType, ItemCollection?)?` using `itemTypeManager.types/.itemCollections(in:)` + `itemContentManager.items(in:)`. - [ ] **Step 4 — PASS. Step 5 — Commit.** `feat(items): ItemRef scene identifier (T4.1)`

#### Task 4.2: `PreviewWindow` primitive

**Files:** Create `Window/PreviewWindow.swift`; Test: manual (window chrome can't be unit-tested).

- [ ] **Step 1 — Implement** a reusable scene-content wrapper, generic over content (so Pages can consume it later — LD-6/LD-11): content wrapped in a `.regularMaterial` rounded-rect card + shadow (compensates for `.windowStyle(.plain)` stripping material/shadow); a top header region with **two custom corner affordances** (per the Figma mockup — a custom **close** + a custom control/drag handle, never traffic lights) carrying `.windowDragGesture()` (the modifier — **not** a bare `WindowDragGesture()` value); `.onKeyPress(.escape)` → `@Environment(\.dismissWindow)` (re-adds the keyboard close `.plain` removes). The footer bar (breadcrumb + options control) is **item-specific content** supplied by the renderer (T3.1), not this generic primitive. `.windowStyle(.plain)` + `.windowLevel(.floating)` are applied at the **scene** (T4.3), not here.
- [ ] **Step 2 — Acceptance checklist (manual):** (a) floats above the main window; (b) **no traffic lights**; (c) drags by the custom region; (d) closes via Esc **and** the custom button; (e) material + shadow read as a floating card. **NSPanel fallback criterion:** adopt `NSPanel` only if `.plain` cannot render the material card or cannot suppress traffic lights on the target OS — otherwise stay native.
- [ ] **Step 3 — Commit.** `feat(window): chromeless floating PreviewWindow primitive (T4.2)`
> Verify `.windowLevel(_:)`, `.windowStyle(.plain)`, `.windowDragGesture()`, `.onKeyPress(.escape)` against current SwiftUI macOS docs at build time (zero in-repo precedent — greenfield).

#### Task 4.3: Register the Item scene

**Files:** Create `ItemWindow/ItemWindowSceneRoot.swift`; Modify `PommoraApp.swift` (`body: some Scene`).

- [ ] **Step 1 — Implement.** `ItemWindowSceneRoot` reads `AppGlobals.current` (the live env): if nil (cold-launch restore before any Nexus opens), render a small "No Nexus open" card and return; else resolve the `ItemRef` against `env.itemTypeManager`/`env.itemContentManager` and host `ItemWindowRenderer(...).injectNexusEnvironment(env)` (deleted item → "Item no longer available" card). Add the scene:
```swift
WindowGroup(for: ItemRef.self) { $ref in
    if let ref = $ref.wrappedValue { ItemWindowSceneRoot(ref: ref) }
}
.windowStyle(.plain)
.windowLevel(.floating)
.windowResizability(.contentSize)
.restorationBehavior(.disabled)   // value-based WindowGroups default to .automatic — disable so macOS doesn't restore Item windows at cold launch before the Nexus env exists (crash / quirk-#16 launch-modal hazard)
```
- [ ] **Step 2 — Verify (critical):** opening an item does **NOT** SIGTRAP and dismisses cleanly — do this BEFORE T4.4 removes the working `.sheet` fallback. - [ ] **Step 3 — Commit.** `feat(app): register WindowGroup(for: ItemRef.self) floating scene (T4.3)`
> **Resolution depends on loaded items.** `ItemContentManager.items(in:)` loads lazily on detail-view appear, so `ItemRef.resolve` can return nil for a present file if its collection hasn't been browsed. `.restorationBehavior(.disabled)` + the live open-path always going through the loaded sidebar make this an edge case — but `ItemWindowSceneRoot` should trigger a load for the ref's container before resolving (or document the cold-open limitation) rather than mis-showing "Item no longer available."

#### Task 4.4: Switch the open path off `.sheet`

**Files:** Modify `Detail/SidebarDetailView.swift` + the **four** detail views that write `presentedItem` (`ItemTypeDetailView.swift:54,:344`, `ItemCollectionDetailView.swift:29,:264`, `PageTypeDetailView.swift:7,:373`, `PageCollectionDetailView.swift:8,:192`); **delete** `ItemWindow/ItemWindow.swift`.

- [ ] **Step 1 — Rewire the open path.** `presentItemAction` is `((Item) -> Void)` (`AppGlobals.swift:62`) and `@Environment(\.openWindow)` is a **View** value (can't live on the `AppGlobals` enum). Declare `@Environment(\.openWindow) private var openWindow` on `SidebarDetailView`; capture it into a local in `body`; in the `.onAppear` assignment set `AppGlobals.presentItemAction = { item in /* resolve type+collection, then */ openWindow(value: ItemRef(...)) }` (hoist `resolveItemType`/`resolveParentCollection` into a shared helper so `ItemRef` carries the resolved `collectionID`). **`presentedItem` is a `@Binding` threaded into the four detail views** (each writes `presentedItem = item` as its open action — `:344/:264/:373/:192`). Repoint all four to call `AppGlobals.presentItemAction?(item)` instead, then **delete** the `@State`/`@Binding presentedItem` plumbing across all five files and the `.sheet(item: $presentedItem)`.
- [ ] **Step 2 — Delete `ItemWindow.swift`.** Its body is replaced by the renderer/scene; its hydrate/commit/schema-drift machinery already moved to the renderer (T3.x) and `friendly` to `ItemValidator` (T1.6). Deleting it now also removes the legacy pin cluster (`pinnedChipsBar`/`PinnedPropertyChip`/`pin·unpin`/`persistCollection`) — so `pinned_properties` loses its last in-app writer (T2.1 fallback becomes read-only). Confirm no remaining references (grep `ItemWindow(` / `PinnedPropertyChip` / `persistCollection`). **Also delete the orphaned `PommoraTests/Items/ItemWindowInspectorTests.swift`** — it tests the now-deleted pin-to-chips UI but re-implements the logic inline against `ItemCollection.pinnedProperties` with **zero `ItemWindow` references**, so it stays green after deletion and the symbol-grep won't flag it (round-trip coverage already lives in `ItemCollectionPinningTests.swift`, so it's redundant).
- [ ] **Step 3 — Verify** the test host still bootstraps (quirk #16) and the WHOLE `xcodebuild test` target compiles + connects; manual: selecting an item opens the **floating** window, not the centered sheet. - [ ] **Step 4 — Commit.** `feat(items): open Item Window as floating scene; delete ItemWindow.swift + legacy cluster (T4.4)`
> **Safe-deletion notes:** (1) `BackForwardButtons.swift:89` is a *second* consumer of `AppGlobals.presentItemAction` — it keeps working (we rewrite the closure **body**, not the slot); **do not delete the `presentItemAction` slot.** (2) `NavDropdownButton.openItemWindow` is a no-op stub; pointing it at `openWindow(value:)` is **out of scope** (follow-up). (3) Confirm `ItemCollection.pinnedProperties` has no *other* live reader that breaks when the cluster goes (T2.1's resolver still reads it as a fallback — keep the field). (4) Refresh the now-stale doc-comments while in these files: `AppGlobals.swift:61` ("flips … presentedItem, which drives the ItemWindow sheet") and the four detail views' `@Binding var presentedItem` comments (e.g. `PageTypeDetailView.swift:7` uses the "popover" wording CLAUDE.md flags as stale) — reword to the `openWindow(value: ItemRef)` floating-scene model.

---

### Phase 5 — Settings: Unmute the Item Templates Pane

#### Task 5.1: Route + pane shell

**Files:** Modify `ViewSettings/ViewSettingsRoute.swift`, `ViewSettings/ViewSettingsPopover.swift`, `ViewSettings/StorageMenuRoot.swift`; create `ViewSettings/ItemTemplatePane.swift`.

> The route-bearing Templates row is `StorageMenuRoot.swift:56` (`mutedRow(icon:"doc.on.doc", title:"Templates")`) — it holds the `@Binding var path` (`:24`) and routes via `activeRow(...,route:)` → `path.append` (`:231`). (The `TypeSettingsSheet.swift:549` "Templates — reserved" is a static placeholder with **no** path — wiring it would no-op; leave it / retire separately.) The destination switch is `ViewSettingsPopover.destination(for:)` (`:63-75`). Panes take `scope` + `$path`, so `.itemTemplate` stays **payload-free** and `ItemTemplatePane` reads scope via the same `containerID()`/`side` pattern `PropertyVisibilityPane` uses.

- [ ] **Step 1 — Failing test:** `ViewSettingsRoute.itemTemplate.paneTitle == "Templates"` (matches the existing row label — no singular/plural drift; `paneTitle` is an exhaustive switch with no `default`, so the compiler forces the new case to be handled).
- [ ] **Step 2 — FAIL → Step 3 — Implement.** (1) Add `case itemTemplate` + its `paneTitle` ("Templates") to `ViewSettingsRoute.swift`. (2) Add `case .itemTemplate: ItemTemplatePane(scope: scope, path: $path)` to `ViewSettingsPopover.destination(for:)` (`:63`). (3) In `StorageMenuRoot` (`:56`), branch the Templates row on a scope-derived item/page flag (mirror `PropertyVisibilityPane`'s `side`): item scopes → `activeRow(icon:"doc.on.doc", title:"Templates", route:.itemTemplate)`; page scopes → keep `mutedRow("Templates")` (the row is currently emitted unconditionally for all 4 scopes — without the branch, Pages would unmute too). (4) **Full env on the popover (quirk #15 — required for T5.3's embedded renderer):** the View Settings popover (`ViewSettingsButton.swift:54-59`) currently hand-injects only `pageTypeManager`/`itemTypeManager`/`tierConfigManager`/`pageContentManager` — it is **missing `ItemContentManager` + `RelationDisplayResolver`** that `ItemWindowRenderer` reads, so an embedded renderer would SIGTRAP. Apply `.injectNexusEnvironment(env)` to the popover content so **every** manager the renderer transitively reads is present — `env` from `if let env = AppGlobals.current` (it's `NexusEnvironment?`; `injectNexusEnvironment(_:)` takes a non-optional, so unwrap — non-nil whenever a Nexus is open, which is always true when the popover is reachable). - [ ] **Step 4 — PASS. Step 5 — Commit.** `feat(viewsettings): unmute item Templates pane + route + full env on popover (T5.1)`

#### Task 5.2: Archetype picker (muted-until-shipped)

**Files:** `ViewSettings/ItemTemplatePane.swift`.

- [ ] **Step 1** — Render `LayoutArchetype.selectable` as a selectable list with human labels owned **here** (a local `label(for:)` — "Compact Stack" / "Standard Panel" / …; kept out of the schema enum so per-Nexus renaming stays a view concern). Each row tertiary-styled + `.disabled` when `!ItemWindowLayouts.hasRecipe(for: archetype)` (single source — only `standard` active initially; `reserved` muted). Selecting persists `template_config.layout` via `updateTemplateConfig` (T2.4), scope-resolved (Collection scope → Collection, Type scope → Type). - [ ] **Step 2** — Build + manual. - [ ] **Step 3 — Commit.** `feat(viewsettings): archetype picker, muted-until-shipped (T5.2)`

#### Task 5.3: Promoted-property + cover management

**Files:** `ViewSettings/ItemTemplatePane.swift`.

- [ ] **Step 1** — Build the **mockup item frame**: embed `ItemWindowRenderer(editing: true)` (T3.5) for the scope's representative item — this is the WYSIWYG surface where pin/unpin (the "Add Property" checklist) + drag-reorder placement happen, so the pane *looks like the item it governs*. Add alongside it a per-property `display` picker (`PropertyDisplay`) and a cover picker limited to `.file` properties whose `accept` contains `image/*` (sets `cover_property_id`). **All writes go through `updateTemplateConfig` (T2.4)** — never a direct save. Also **clear `pinned_properties` on first template write** = set it to `[]` (`ItemCollection.encode` always emits the key, so the on-disk array becomes empty, not absent — functionally single-source since the resolver returns `promoted` first; T2.1). The embedded renderer **depends on T5.1's `.injectNexusEnvironment(env)` on the popover** (else quirk #15 SIGTRAP). - [ ] **Step 2** — Build + manual: **verify opening the template pane does NOT SIGTRAP** (the env fix); edits in the mockup frame apply to governed items; a separately-open live window reflects live. - [ ] **Step 3 — Commit.** `feat(viewsettings): template editor mockup-item-frame (pin/sort/cover) (T5.3)`

#### Task 5.4: Scope wiring (Type default vs Collection override)

**Files:** `ViewSettings/ItemTemplatePane.swift`.

- [ ] **Step 1** — `ItemTemplatePane` reads the active scope via the existing `containerID()`/`side` pattern `PropertyVisibilityPane` uses (the `.itemTemplate` route stays **payload-free** — no invented route payload). When scope is `.itemCollection`, edits the Collection's `templateConfig` (created on first edit) via `updateTemplateConfig` (T2.4) and shows an "Overrides Type default" affordance + reset-to-default (clears the Collection's `templateConfig` → falls back to Type). `.itemType` scope edits the default. - [ ] **Step 2** — Build + manual. - [ ] **Step 3 — Commit.** `feat(viewsettings): Type-default vs Collection-override scope in template pane (T5.4)`

---

### Phase 6 — Registry + Docs

#### Task 6.1: Amend registry decision #14 + History

**Files:** Modify `Guidelines/Paradigm-Decisions.md`, `History.md`.

- [ ] Amend #14 to record the `template_config` schema (LayoutArchetype enum + values, `promoted_properties` `[{id,display}]`, `cover_property_id`, Page parity, Collection override, OpenInMode reserved). Add a one-line History entry. **Commit.** `docs: amend registry #14 with ItemsV2 template_config schema (T6.1)`

#### Task 6.2: Doc-sweep — popover→floating panel + Item-Templates correctness

**Files:** `PommoraPRD.md`, `Features/Items.md`, `Features/Pages.md`, `Features/Agenda.md`, `Features/Properties.md`, `Features/Prospects.md`.

- [ ] Replace stale "popover/anchored/never standalone window" Item-Window wording with the floating-panel model. Reconcile any existing Item-Templates descriptions to the locked ItemsV2 model (single renderer, overflow-mode-per-archetype, native reorder, image-filtered cover, per-property display). **Commit.** `docs: Item Window floating-panel + Item-Templates correctness sweep (T6.2)`

---

### Deferred (out of scope — see LD-11)

- **`@item` body grammar + chips + graph edge-weighting** → v0.4.0 wikilink/graph session. (`open_in` and grammar are pre-decided, not built here.)
- **Page "open-in: preview" UI** → parallel track once `PreviewWindow` ships; this plan lands only the inert `open_in` field + the shared primitive.
- **Per-archetype Figma visuals** → filled per-archetype in their own sessions; this plan ships compiling, selectable recipes + the muted settings options.

---

### Self-Review

- **Spec coverage:** every locked decision LD-1…LD-10 maps to a task (renderer T3.1/3.3; encoding T1.1; roster T1.1; display T1.2/3.4; supplement T3.3; native scene T4.0-4.4; cap T1.6/3.2; cover T1.4/5.3; reorder T2.3/3.5; scope T2.1/5.4). LD-11 deferrals are explicit.
- **Review-applied (round 1 — adversarial):** env-injection blocker → T4.0 (publish `NexusEnvironment` + `injectNexusEnvironment` on the scene); reorder-test math corrected (T2.3); T5.1 retargeted to `StorageMenuRoot`/`ViewSettingsPopover` + scope-conditional; cap error gains `cap:` payload (T1.6); MarkdownPM full init + `documentId: item.id` (T3.2); `AnyLayout` identity claim scoped (T3.1); openWindow env path corrected (T4.4); persistence via manager (T3.5); `template_config` not-indexed note; pinned→promoted shadow documented (T2.1).
- **Review-applied (round 2 — citations / snowball / simplify / net-reduce):** phantom `updateTemplateConfig` made an explicit named deliverable cross-referenced everywhere (snowball); legacy pin cluster + dual-render explicitly **deleted** (in T4.4 with `ItemWindow.swift`, after T3.3 builds the renderer's clean partition) — `pinned_properties` left with no in-app writer; T2.2 **consolidates onto the existing `PropertyCellDisplay`** (no third renderer) + folds `FrontmatterInspector.valueLabel`; generic `PropertyIDReorderList` dropped → pure splice + inline drag (T2.3); `OverflowMode` → `usesInspector: Bool`; `displayName`/`isShipped` removed from the schema enum (labels → pane, shipped → recipe registry); `PageTemplateConfig` trimmed to `layout`/`defaultBody`/`openIn`; custom region-recipe `Layout` deferred to the Banner session (stock stubs for v1); `TemplateResolver.layout()` dropped; `ItemWindow.swift` deletion quantified (~−200 lines); "Templates" label unified; T1.3 new-vs-existing fields clarified.
- **Review-applied (round 4 — final bulletproof gate):** legacy-cluster deletion moved T3.3 → **T4.4** (so the build never goes red while `ItemWindow.body` still calls those methods); `friendly` relocated to `ItemValidator` (T1.6) + the 6 `ItemValidatorTests` refs retyped (`.descriptionTooLong(cap:)` ×4, `ItemValidator.friendly` ×2) + run-whole-target gate (quirk #1); T4.4 now rewires the **four** `presentedItem`-writing detail views + deletes `ItemWindow.swift` (with `BackForwardButtons` slot kept); T2.2 adds the `display:` **init parameter** (not just a stored default); T3.2 retargeted to the renderer's body region (survives deletion); **T5.1 injects the full env on the View Settings popover** (it lacked `ItemContentManager` + `RelationDisplayResolver` → the embedded mockup renderer would SIGTRAP); T2.4 scope contract made explicit; T4.0 env claim scoped to the sheet path + build-verify; T2.3 no-op-reject preserved; cold-restore + doc-comment + `openWindow`-property minors noted.
- **Spec correction (round 3 — template-editing model, Nathan):** pinning/placement/order is edited **in the template, not the live item**. `updateTemplateConfig` moved to its own data task **T2.4**; **T3.5 repurposed** from "live-window promote/reorder controls" to the **renderer's edit/mockup mode**; **T5.3** is now the **mockup-item-frame editor** (embeds `ItemWindowRenderer(editing: true)`); the live window renders the template's order read-only and edits only values. Resolves the "re-ordered via sorting" question: the order is the stored `promoted_properties` array, not a per-item sort.
- **Type consistency:** `template_config` shape, `LayoutArchetype`/`PropertyDisplay`/`PromotedProperty`/`OpenInMode`, `ItemRef`, `PropertyIDReorder.move`, `TemplateResolver.effective/promoted` are used identically across tasks.
- **Landmines flagged inline:** pinned→promoted non-destructive bridge (T2.1); `.plain` chrome/keyboard caveats (T4.2); XCTest launch-modal guard (T4.4, quirk #16); cover via `accept` not a new case (T1.4/5.3); back-compat null-round-trip tests (T1.3/1.4/1.5).
- **Green-per-task:** `standard` is fully built first so the window is never broken; other archetypes are selectable stubs (quirk #7).
