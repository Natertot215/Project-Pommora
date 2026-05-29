## Make Relations Real — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Implementer subagents WRITE code only; the controller runs every build via a background `builder` Agent (`-only-testing:PommoraTests`, quirk #14) and commits to `main` on green (stub-and-progressively-replace, quirk #8).

**Goal:** Make the shipped relations + tiers feature actually render (icon + title) and edit on every surface — closing the gap where it stores correctly but shows "(missing)" in tables and can't be edited in the Item Window / inspector.

**Architecture:** Denormalize entity `icon` into the SQLite index so a single shared `RelationDisplayResolver` can turn any target ID into icon + title; route every render surface through it and every edit surface through the existing `RelationPicker`. Tiers are relations, so they flow through the same two seams.

**Tech stack:** SwiftUI (macOS), Swift 6 strict concurrency + ExistentialAny, GRDB SQLite index, Swift Testing.

---

### Grounding facts (verified against code — this plan rests on these)

Each claim was read directly; citation is `path:line`. If code and this list ever disagree, the code wins — re-verify before proceeding.

- **`relationResolver` is `{ _ in nil }` at all 4 detail-view call sites** → relations render the literal italic text **"(missing)"**. `PageTypeDetailView.swift:130,148`, `PageCollectionDetailView.swift:100,118`, `ItemTypeDetailView.swift:169,187`, `ItemCollectionDetailView.swift:138,156`; fallback at `PropertyCellDisplay.swift:257`.
- **The index does NOT store operational-entity icons.** `icon TEXT` exists only on `page_types` (`IndexSchema.swift:26`) and `item_types` (`:36`). `pages`, `items`, `contexts`, `agenda_tasks`, `agenda_events` have `title` but no `icon`. `EntityRef` is `{id, kind, title}` (`IndexQuery.swift:550`); `entitiesByTarget` SELECTs only `id, title` (`:14-62`). **→ icon must be added before any resolver can return it.**
- **The detail views already hold the index.** Each has `@Environment(NexusManager.self)` and passes `index: nexusManager.currentIndex` to `PropertyCellEditor` (`PageTypeDetailView.swift:142`, etc.).
- **`RelationPicker` is fully reusable for editing.** `RelationPicker(selectedIDs:scope:index:onSelect:)` loads candidates via `IndexQuery.entitiesByTarget(scope)` (`RelationPicker.swift:7-82`). The exact wiring template is `PropertyCellEditor.relationEditor` (`:316-334`); the status template is `statusEditor` (`:276-292`).
- **`PropertyEditorRow` (used by ItemWindow / PropertyPanel / FrontmatterInspector / PropertiesPulldown) takes only `definition` + `@Binding value`** — no index. Its relation case is a placeholder (`PropertyEditorRow.swift:32-33`); status is read-only text (`:116-124`); file is read-only count (`:138-146`).
- **`FrontmatterInspectorViewModel` already has tier-edit plumbing** — `draftTier1/2/3` + `handleTierChange(_:_:)` (`FrontmatterInspector.swift:39-47`). Only the Tiers *section* is read-only `LabeledContent` (`:139-147`). `entitiesByTarget(.contextTier(N))` returns the Spaces/Topics/Projects for that tier (`IndexQuery.swift` contextTier case).
- **Context-delete cascade is already wired** (do NOT touch): `cascadeUnlinkTier` (`SidebarView.swift:243`) is called from every Context delete button (`:150,160-173,193`). One real residual: `IndexUpdater.deleteContext` (`:332`) has no caller — deleted-Context index rows linger until rebuild (minor; Fix Log candidate, out of scope here).

### Scoping decisions (controller's call; veto on review)

- **Add `icon` to the index** (schema 3→4) rather than resolve icons from in-memory managers — the index is the query layer, icon is denormalized display data, the bump is regeneratable + proven (we just shipped 2→3), and it also fixes the picker's missing icons. 
- **Include the `status` editor in `PropertyEditorRow`** (real "can't edit status in Item Window" bug, trivial mirror of the cell editor). **Defer the `file` editor** — needs `AttachmentManager` threading; the code itself defers it to v0.3.1.x (`PropertyCellEditor.swift:341`).
- **Editors are mechanics over shared infrastructure, visuals-agnostic.** The relation / status / tier editors route through existing component-library primitives (`ChipDropdown`, `RelationPicker`) bound to the value + commit pipeline — no bespoke chrome baked into `PropertyEditorRow`. The forthcoming Item Window visual redesign must be able to sit *on top of* this infrastructure as a presentational swap, never a re-plumb. Build the data/binding/commit mechanics correctly now; leave the styling to the design pass.

### File map

- **Create:** `Pommora/Pommora/Properties/RelationDisplayResolver.swift`
- **Create (tests):** `PommoraTests/Index/ResolveEntitiesTests.swift`, `PommoraTests/Properties/RelationDisplayResolverTests.swift`, `PommoraTests/Index/IconBackfillTests.swift`
- **Modify (index):** `Index/IndexSchema.swift` (+icon ×5 tables), `Index/PommoraIndex.swift` (3→4), `Index/IndexBuilder.swift` (+icon on insert ×5), `Index/IndexUpdater.swift` (+icon on upsert ×5), `Index/IndexQuery.swift` (`EntityRef.icon`, `entitiesByTarget` SELECT icon, new `resolveEntities`)
- **Modify (render):** 4 detail views (warm + real resolver), `Properties/RelationPicker.swift` (picker rows show icon), `ItemWindow/ItemWindow.swift` + `Properties/PropertyPanel.swift` (tier rows via `RelationChip`)
- **Modify (edit):** `ItemWindow/PropertyEditorRow.swift` (+index, relation + status editors) and its hosts; `Pages/FrontmatterInspector.swift` (editable tiers + chip display); `ContentView.swift` (create + inject `RelationDisplayResolver`; inject it + `NexusManager` into the inspector and the `.detail` env chain — quirk #16)

---

### Task 1: Index — denormalize `icon` + add `resolveEntities` by-ID query

**Files:**
- Modify: `Index/IndexSchema.swift` (the 5 CREATE TABLE blocks: `pages`, `items`, `contexts`, `agenda_tasks`, `agenda_events`)
- Modify: `Index/PommoraIndex.swift` (`currentSchemaVersion`)
- Modify: `Index/IndexBuilder.swift` (insert statements for the 5 kinds), `Index/IndexUpdater.swift` (upsert statements for the 5 kinds)
- Modify: `Index/IndexQuery.swift` (`EntityRef`, `entitiesByTarget`, new `resolveEntities`)
- Test: `PommoraTests/Index/ResolveEntitiesTests.swift`

- [ ] **Step 1 — Add the `icon` column to 5 tables.** Read each CREATE TABLE block (`IndexSchema.swift` pages `:63`, items `:74`, agenda_tasks `:86`, agenda_events `:96`, contexts `:107`) and insert `icon TEXT,` immediately after the `title TEXT NOT NULL,` line. (Nullable — entities without an icon stay NULL.)

- [ ] **Step 2 — Bump the schema version.** In `PommoraIndex.swift`, change `currentSchemaVersion` from `3` to `4`. Update the adjacent version comment to: `// v4 (2026-05-29): denormalize entity icon into pages/items/contexts/agenda_* so relation values resolve to icon+title from the index.` This forces the existing delete+rebuild path (no new migration code needed — the rebuild repopulates).

- [ ] **Step 3 — Populate `icon` on full rebuild.** In `IndexBuilder.swift`, find the INSERT for each of the 5 kinds (search `INSERT INTO pages`, `items`, `contexts`, `agenda_tasks`, `agenda_events`). Add the `icon` column + bind the entity's `icon` value (e.g. `page.frontmatter.icon`, `item.icon`, `space/topic/project.icon`, `task.icon`, `event.icon`). Mirror the existing `title` binding exactly — same snapshot struct, one extra field.

- [ ] **Step 4 — Populate `icon` on incremental upsert.** In `IndexUpdater.swift`, do the identical change for the `upsertPage` / `upsertItem` / `upsertContext` (or `upsertSpace`/`upsertTopic`/`upsertProject`) / `upsertAgendaTask` / `upsertAgendaEvent` statements: add `icon` to the `INSERT OR REPLACE` column list + bind the entity icon.

- [ ] **Step 5 — Add `icon` to `EntityRef` (defaulted, so existing call sites still compile).** In `IndexQuery.swift:550`, replace the struct with:

```swift
struct EntityRef: Equatable, Hashable, Sendable {
    let id: String
    let kind: EntityKind
    let title: String
    let icon: String?
    init(id: String, kind: EntityKind, title: String, icon: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.icon = icon
    }
}
```

- [ ] **Step 6 — Have `entitiesByTarget` read icon.** In each `entitiesByTarget` case (`IndexQuery.swift:14-62`), add `icon` to the SELECT and pass it to `EntityRef`. Pattern for the `.pageType` case (apply the same to all 7 cases — every one selects from a table that now has `icon`):

```swift
case .pageType(let id):
    return try Row.fetchAll(db, sql: "SELECT id, title, icon FROM pages WHERE page_type_id = ?", arguments: [id])
        .map { EntityRef(id: $0["id"], kind: .page, title: $0["title"], icon: $0["icon"]) }
```

- [ ] **Step 7 — Write the failing test for the new batch query.** Create `PommoraTests/Index/ResolveEntitiesTests.swift`:

```swift
import Testing
@testable import Pommora

@Suite("ResolveEntitiesTests")
struct ResolveEntitiesTests {
    @Test("resolveEntities returns icon + title for a page ID and a context ID")
    func resolvesAcrossTables() async throws {
        let index = try PommoraIndex.inMemory()        // existing test helper
        try await index.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO pages (id, title, icon, page_type_id) VALUES (?,?,?,?)",
                           arguments: ["P1", "My Page", "doc.text", "PT1"])
            try db.execute(sql: "INSERT INTO contexts (id, title, icon, tier) VALUES (?,?,?,?)",
                           arguments: ["S1", "Work", "square.stack.3d.up", 1])
        }
        let out = try await IndexQuery(index).resolveEntities(ids: ["P1", "S1", "missing"])
        #expect(out["P1"]?.title == "My Page")
        #expect(out["P1"]?.icon == "doc.text")
        #expect(out["S1"]?.kind == .space)
        #expect(out["missing"] == nil)
    }
}
```

(If `PommoraIndex.inMemory()` / the exact insert columns differ, read an existing test in `PommoraTests/Index/` and match its setup verbatim — do NOT invent a helper.)

- [ ] **Step 8 — Run it; expect FAIL** (`resolveEntities` undefined). Controller runs via background builder: `xcodebuild test … -only-testing:PommoraTests/ResolveEntitiesTests`. Visually confirm a non-zero executed count (quirk #18).

- [ ] **Step 9 — Implement `resolveEntities`.** Add to `IndexQuery` (after `entitiesByTarget`):

```swift
/// Batch-resolve relation/tier target IDs to their current display (icon + title).
/// Searches every table a relation value can point at (pages, items, contexts,
/// agenda tasks/events). IDs are globally-unique ULIDs, so a hit in one table is
/// authoritative. Missing IDs are absent from the result (caller renders the
/// "(missing)" fallback).
func resolveEntities(ids: [String]) async throws -> [String: EntityRef] {
    guard !ids.isEmpty else { return [:] }
    return try await index.dbQueue.read { db in
        var out: [String: EntityRef] = [:]
        let qs = databaseQuestionMarks(count: ids.count)
        let args = StatementArguments(ids)
        func collect(_ sql: String, _ make: (Row) -> EntityRef) throws {
            for row in try Row.fetchAll(db, sql: sql, arguments: args) { let r = make(row); out[r.id] = r }
        }
        try collect("SELECT id, title, icon FROM pages WHERE id IN (\(qs))") {
            EntityRef(id: $0["id"], kind: .page, title: $0["title"], icon: $0["icon"])
        }
        try collect("SELECT id, title, icon FROM items WHERE id IN (\(qs))") {
            EntityRef(id: $0["id"], kind: .item, title: $0["title"], icon: $0["icon"])
        }
        try collect("SELECT id, title, icon, tier FROM contexts WHERE id IN (\(qs))") { row in
            let t = (row["tier"] as Int?) ?? 1
            let kind: EntityKind = t == 1 ? .space : (t == 2 ? .topic : .project)
            return EntityRef(id: row["id"], kind: kind, title: row["title"], icon: row["icon"])
        }
        try collect("SELECT id, title, icon FROM agenda_tasks WHERE id IN (\(qs))") {
            EntityRef(id: $0["id"], kind: .agendaTask, title: $0["title"], icon: $0["icon"])
        }
        try collect("SELECT id, title, icon FROM agenda_events WHERE id IN (\(qs))") {
            EntityRef(id: $0["id"], kind: .agendaEvent, title: $0["title"], icon: $0["icon"])
        }
        return out
    }
}
```

(`databaseQuestionMarks(count:)` is a GRDB global. If the same-`args`-reused-across-statements form triggers a GRDB quirk, fall back to building per-statement `StatementArguments(ids)` inside `collect`.)

- [ ] **Step 10 — Run the full index test target; expect PASS.** `-only-testing:PommoraTests`. Confirm non-zero count + green (only the known `debounceCoalescesRapidEdits` flake may fail). Controller commits on green.

---

### Task 2: `RelationDisplayResolver` (shared) + inject at `ContentView`

**Files:**
- Create: `Properties/RelationDisplayResolver.swift`
- Modify: `ContentView.swift` (instantiate + `.environment(...)` at root AND the `.detail` chain, quirk #16)
- Test: `PommoraTests/Properties/RelationDisplayResolverTests.swift`

- [ ] **Step 1 — Create the resolver.** New file `Properties/RelationDisplayResolver.swift`:

```swift
import SwiftUI

/// Shared, app-wide resolver: a relation/tier target ID → its current display
/// (icon + title). Render surfaces call `resolve(_:)` SYNCHRONOUSLY during
/// layout, so the host must `warm(_:)` the needed IDs first (async, off the
/// index); resolved values land in the cache and `resolve` is a pure dict read.
/// One instance is injected at `ContentView` and shared by every surface —
/// the single source of truth for relation display resolution (DRY).
@Observable
@MainActor
final class RelationDisplayResolver {
    private var cache: [String: EntityRef] = [:]
    private let index: () -> PommoraIndex?

    init(index: @escaping () -> PommoraIndex?) { self.index = index }

    /// Synchronous render-time read. Returns nil for un-warmed / unknown IDs.
    func resolve(_ id: String) -> (icon: String, title: String)? {
        guard let ref = cache[id] else { return nil }
        return (ref.icon ?? Self.defaultIcon(for: ref.kind), ref.title)
    }

    /// Batch-load IDs into the cache. Call from `.task`/`.onChange` when the
    /// visible relation/tier values change. Already-cached IDs are skipped.
    func warm(_ ids: [String]) async {
        let missing = ids.filter { cache[$0] == nil }
        guard !missing.isEmpty, let idx = index() else { return }
        let resolved = (try? await IndexQuery(idx).resolveEntities(ids: missing)) ?? [:]
        for (id, ref) in resolved { cache[id] = ref }
    }

    /// Drop the cache after a rename/icon edit so the next warm re-reads.
    func invalidate() { cache.removeAll() }

    static func defaultIcon(for kind: EntityKind) -> String {
        switch kind {
        case .page, .pageType, .pageCollection: return "doc.text"
        case .item, .itemType, .itemCollection: return "square.grid.2x2"
        case .space: return "square.stack.3d.up"
        case .topic: return "folder"
        case .project: return "list.bullet.rectangle"
        case .agendaTask: return "checklist"
        case .agendaEvent: return "calendar"
        }
    }
}
```

- [ ] **Step 2 — Write the failing test.** `PommoraTests/Properties/RelationDisplayResolverTests.swift`. **Test-setup convention (verified in Task 1):** there is NO `PommoraIndex.inMemory()` helper — copy the index setup + seeding pattern from `PommoraTests/Index/ResolveEntitiesTests.swift` verbatim (temp-dir `PommoraIndex.open(at:)` with `defer` cleanup; seed the `page_types` PARENT row + a `modified_at` before inserting a page — `page_type_id` is an enforced FK and `modified_at` is `NOT NULL`).

```swift
import Testing
@testable import Pommora

@MainActor
@Suite("RelationDisplayResolverTests")
struct RelationDisplayResolverTests {
    @Test("warm then resolve returns icon+title; unknown IDs stay nil")
    func warmsAndResolves() async throws {
        // <index setup + seed a page "P1" (title "Doc", icon "star") exactly as
        //  ResolveEntitiesTests.swift does — parent page_type + modified_at included>
        let resolver = RelationDisplayResolver(index: { index })
        #expect(resolver.resolve("P1") == nil)         // not warmed yet
        await resolver.warm(["P1", "P2"])
        #expect(resolver.resolve("P1")?.title == "Doc")
        #expect(resolver.resolve("P1")?.icon == "star")
        #expect(resolver.resolve("P2") == nil)          // no such entity
    }
}
```

- [ ] **Step 3 — Run; expect FAIL** (type undefined). `-only-testing:PommoraTests/RelationDisplayResolverTests`.

- [ ] **Step 4 — Build green** (the type now exists). Re-run; expect PASS.

- [ ] **Step 5 — Instantiate + inject at `ContentView`.** Where the other managers are constructed/injected (`ContentView.constructManagers` / the root `.environment(...)` block near `:228`), add:

```swift
@State private var relationResolver = RelationDisplayResolver(index: { nexusManager.currentIndex })
```

and add `.environment(relationResolver)` to the root environment chain. **Quirk #16:** also add `.environment(relationResolver)` to the `.detail` env chain (`ContentView.swift:344-350`) so detail views that read it via `@Environment` don't SIGTRAP.

- [ ] **Step 6 — Build green; commit.** No behavior change yet (resolver injected, unused). Confirms wiring compiles.

---

### Task 3: Tables render relations + tiers (kill "(missing)")

**Files:** `Detail/PageTypeDetailView.swift`, `Detail/PageCollectionDetailView.swift`, `Detail/ItemTypeDetailView.swift`, `Detail/ItemCollectionDetailView.swift`

- [ ] **Step 1 — Read the resolver from the environment.** In each of the 4 views, add near the other `@Environment` lines (e.g. beside `@Environment(NexusManager.self) private var nexusManager`):

```swift
@Environment(RelationDisplayResolver.self) private var relationResolver
```

- [ ] **Step 2 — Add a warm helper + `.task`.** In each view, add a computed list of the relation/tier target IDs across the rows it renders, and warm them. Pattern for `PageTypeDetailView` (the rows expose `pageMeta.frontmatter`):

```swift
private var visibleRelationIDs: [String] {
    rows.flatMap { row -> [String] in
        guard case .page(let m) = row.kind else { return [] }
        let tiers = m.frontmatter.tier1 + m.frontmatter.tier2 + m.frontmatter.tier3
        let props = userPropertyColumns
            .filter { $0.type == .relation }
            .flatMap { m.frontmatter.relationIDs(forPropertyID: $0.id) }
        return tiers + props
    }
}
```

Attach to the table container: `.task(id: visibleRelationIDs) { await relationResolver.warm(visibleRelationIDs) }`. (Use the view's actual rows source — `rows`, `pages`, etc. Match the existing identifier in that file; for Item views use `.item(let m)` and `m.relationIDs(forPropertyID:)`.)

- [ ] **Step 3 — Replace the dead resolver closures.** In each view, change every `relationResolver: { _ in nil }` to `relationResolver: { relationResolver.resolve($0) }`. Exact sites: `PageTypeDetailView.swift:130,148`; `PageCollectionDetailView.swift:100,118`; `ItemTypeDetailView.swift:169,187`; `ItemCollectionDetailView.swift:138,156`.

- [ ] **Step 4 — Build green; commit.** Verification is build + manual (UI render isn't unit-testable). Manual check after the session: relation + tier columns show icon + title, not "(missing)".

---

### Task 4: RelationPicker redesign — grouped, drill-in custom dropdown

Replaces the flat `RelationPickerList` (the old multi-select stub being retired) with the grouped two-section dropdown from Nathan's spec + 2 mockups. **Design (confirmed):** TOP LEVEL = collections/sets of the scope (folder glyph + title + chevron `›`, no checkbox — drill in) → divider → root-level leaves not in any collection (entity icon + title + **right-side blue checkbox**). DRILLED-IN = collection header (folder + title, tap to return) → divider → member leaves (same selectable checkbox row). Selection is always-multi, by ID, so a checked leaf reads correctly at any level. Reuses the existing `.chipDropdownPanel()` chrome (`RelationPicker.swift:51`) — **same dropdown the whole app uses, only the contents change.** Frame **235×160**, **body regular** type, **12pt** between rows, scrolls past 160. Drill-in is in-panel `@State` (no submenu/window — lowest-risk).

**Files:**
- Modify: `Index/IndexQuery.swift` (add `GroupedEntities`/`EntityGroup` + `entitiesByTargetGrouped`)
- Modify: `Properties/RelationPicker.swift` (rewrite body as grouped + drill-in; keep `computeSelection` `:66-68`)
- Test: `PommoraTests/Index/EntitiesByTargetGroupedTests.swift`

- [ ] **Step 1 — Add the grouped query types + method to `IndexQuery`.** Only `.pageType` / `.itemType` scopes produce groups; everything else returns flat (reuses `entitiesByTarget` — DRY). **Before writing: read the `page_collections` / `item_collections` CREATE TABLE blocks (`IndexSchema.swift:43,53`) and confirm the parent-type FK column name (assumed `page_type_id` / `item_type_id`) — use the real name.**

```swift
struct EntityGroup: Sendable, Equatable { let container: EntityRef; let members: [EntityRef] }
struct GroupedEntities: Sendable, Equatable { let groups: [EntityGroup]; let rootEntities: [EntityRef] }

/// Collection/set groups + loose (no-collection) leaves, for the grouped
/// relation picker. Groups appear only for `.pageType` / `.itemType`; every
/// other scope returns its entities flat in `rootEntities`.
func entitiesByTargetGrouped(_ target: PropertyDefinition.RelationTarget) async throws -> GroupedEntities {
    switch target {
    case .pageType(let typeID):
        return try await index.dbQueue.read { db in
            // Collections carry no icon column — the picker renders a folder glyph, so SELECT id+title only.
            let cols = try Row.fetchAll(db, sql: "SELECT id, title FROM page_collections WHERE page_type_id = ? ORDER BY title", arguments: [typeID])
                .map { EntityRef(id: $0["id"], kind: .pageCollection, title: $0["title"]) }
            var groups: [EntityGroup] = []
            for c in cols {
                let members = try Row.fetchAll(db, sql: "SELECT id, title, icon FROM pages WHERE page_collection_id = ? ORDER BY title", arguments: [c.id])
                    .map { EntityRef(id: $0["id"], kind: .page, title: $0["title"], icon: $0["icon"]) }
                groups.append(EntityGroup(container: c, members: members))
            }
            let root = try Row.fetchAll(db, sql: "SELECT id, title, icon FROM pages WHERE page_type_id = ? AND page_collection_id IS NULL ORDER BY title", arguments: [typeID])
                .map { EntityRef(id: $0["id"], kind: .page, title: $0["title"], icon: $0["icon"]) }
            return GroupedEntities(groups: groups, rootEntities: root)
        }
    case .itemType(let typeID):
        // Identical shape against item_collections / items (item_collection_id / item_type_id). Mirror the .pageType block.
        return try await index.dbQueue.read { db in
            let cols = try Row.fetchAll(db, sql: "SELECT id, title FROM item_collections WHERE item_type_id = ? ORDER BY title", arguments: [typeID])
                .map { EntityRef(id: $0["id"], kind: .itemCollection, title: $0["title"]) }
            var groups: [EntityGroup] = []
            for c in cols {
                let members = try Row.fetchAll(db, sql: "SELECT id, title, icon FROM items WHERE item_collection_id = ? ORDER BY title", arguments: [c.id])
                    .map { EntityRef(id: $0["id"], kind: .item, title: $0["title"], icon: $0["icon"]) }
                groups.append(EntityGroup(container: c, members: members))
            }
            let root = try Row.fetchAll(db, sql: "SELECT id, title, icon FROM items WHERE item_type_id = ? AND item_collection_id IS NULL ORDER BY title", arguments: [typeID])
                .map { EntityRef(id: $0["id"], kind: .item, title: $0["title"], icon: $0["icon"]) }
            return GroupedEntities(groups: groups, rootEntities: root)
        }
    default:
        return GroupedEntities(groups: [], rootEntities: try await entitiesByTarget(target))
    }
}
```

- [ ] **Step 2 — Write the failing test** (`PommoraTests/Index/EntitiesByTargetGroupedTests.swift`, struct named to match the file, quirk #18). Seed a page_type with one collection (2 member pages) + 1 loose page; assert `groups.count == 1`, `groups[0].members.count == 2`, `rootEntities.count == 1`, and member/root rows carry `icon`. Match the existing in-memory index test helper verbatim.

- [ ] **Step 3 — Run; expect FAIL, then implement to PASS.** `-only-testing:PommoraTests/EntitiesByTargetGroupedTests` (controller, background builder).

- [ ] **Step 4 — Rewrite `RelationPicker` body with drill-in state.** Replace the flat-list body. Keep the existing `selectedIDs`/`scope`/`index`/`onSelect` API + `computeSelection`. Load `entitiesByTargetGrouped` in `.task`. Per quirk #13, keep all row rendering in private value-type sub-views.

```swift
@State private var grouped: GroupedEntities = .init(groups: [], rootEntities: [])
@State private var drilled: EntityGroup? = nil      // nil = top level

// body: panel chrome (.chipDropdownPanel()), fixed 235×160, ScrollView with 12pt VStack spacing.
//   if let g = drilled {  CollectionHeader(title: g.container.title, onBack: { drilled = nil }); Divider();
//                         ForEach(g.members) { LeafRow(...) } }
//   else {  ForEach(grouped.groups) { CollectionRow(group: $0, onDrill: { drilled = $0 }) }
//           if !grouped.groups.isEmpty && !grouped.rootEntities.isEmpty { Divider() }
//           ForEach(grouped.rootEntities) { LeafRow(...) } }
```

- [ ] **Step 5 — The three row sub-views** (private structs, plain value types):
  - `CollectionRow` — folder glyph (`Image(systemName: "folder")`) + title (body) + `Spacer()` + chevron (`Image(systemName: "chevron.right")`); whole row is the drill button.
  - `CollectionHeader` — back affordance (folder + title, tappable → `onBack`) styled as the drilled-in title.
  - `LeafRow` — `RelationChip(icon: entity.icon ?? RelationDisplayResolver.defaultIcon(for: entity.kind), title: entity.title)` + `Spacer()` + the blue checkbox. **Checkbox: reuse the component-library checkbox primitive** (the same blue filled-square + white check used elsewhere — `PropertyCheckbox` or the multi-select chip's checkbox). If no primitive matches the screenshot's blue square exactly, add it to the Component Library and reuse — no one-off (HARD RULE). Tap toggles via `computeSelection(id:wasSelected:current:)` → set `selectedIDs` + call `onSelect`.

- [ ] **Step 6 — Build green; commit.** Manual check after the session: inline relation editing shows collections (drill in) + loose leaves with working blue checkboxes; selecting commits the same `[ID]` value as before.

---

### Task 5: Tier rows render via `RelationChip` (not raw IDs) — Fix Log #11

**Files:** `ItemWindow/ItemWindow.swift` (`relationLine`, `:267-280`), `Properties/PropertyPanel.swift` (`tierRow`, `:161-180`)

- [ ] **Step 1 — Item Window tier rows.** In `ItemWindow`, add `@Environment(RelationDisplayResolver.self) private var relationResolver` and a `.task` that warms `item.tier1 + item.tier2 + item.tier3`. Replace `relationLine`'s raw-ID `Text` (`:273`) with a chip row:

```swift
private func relationLine(label: String, ids: [String]) -> some View {
    HStack(spacing: 4) {
        Text(label).frame(width: 100, alignment: .leading).foregroundStyle(.secondary)
        if ids.isEmpty {
            Text("—").foregroundStyle(.tertiary)
        } else {
            ForEach(ids, id: \.self) { id in
                if let r = relationResolver.resolve(id) { RelationChip(icon: r.icon, title: r.title) }
                else { Text("(missing)").font(.system(size: 12).italic()).foregroundStyle(.tertiary) }
            }
        }
    }
}
```

Delete the TODO comment at `:268-270`.

- [ ] **Step 2 — PropertyPanel tier rows.** Apply the identical chip pattern to `PropertyPanel.tierRow` (`:161-180`); add the same `@Environment` + warm `.task` to `PropertyPanel`.

- [ ] **Step 3 — Build green; commit.** Manual check: tiers show icon + title in the Item Window + property panel.

---

### Task 6: Editable tiers on Pages + relation/status editors in `PropertyEditorRow`

**Files:** `ItemWindow/PropertyEditorRow.swift`, its hosts (`ItemWindow.swift`, `Properties/PropertyPanel.swift`), `Pages/FrontmatterInspector.swift`, `ContentView.swift` (inspector + detail env, quirk #16)

- [ ] **Step 1 — `PropertyEditorRow` gains `index`.** Change the struct head (`PropertyEditorRow.swift:3-5`) to:

```swift
struct PropertyEditorRow: View {
    let definition: PropertyDefinition
    @Binding var value: PropertyValue
    var index: PommoraIndex? = nil          // for the relation editor
```

- [ ] **Step 2 — Real relation editor** (replace the placeholder at `:32-33`). Mirror `PropertyCellEditor.relationEditor:316-334`:

```swift
case .relation:
    if let target = definition.relationTarget {
        RelationPicker(
            selectedIDs: Binding(
                get: { if case .relation(let ids) = value { return ids }; return [] },
                set: { value = .relation($0) }
            ),
            scope: target,
            index: index,
            onSelect: { value = .relation($0) }
        )
    } else {
        Text("Relation has no target").font(.caption).foregroundStyle(.secondary)
    }
```

- [ ] **Step 3 — Real status editor** (replace read-only text at `:116-124`). Mirror `PropertyCellEditor.statusEditor:276-292`:

```swift
private var statusEditor: some View {
    let groups = definition.statusGroups ?? []
    let opts: [PropertyChipOption] = groups.flatMap { g in g.options.map { $0.asChipOption(groupColor: g.color) } }
    let current: String? = { if case .status(let v) = value { return v }; return nil }()
    return ChipDropdown(
        options: .constant(opts),
        selectionMode: .single,
        selectedIDs: current.map { Set([$0]) } ?? [],
        onPick: { opt in value = .status(opt.id) },
        size: .compact
    )
}
```

(Leave `file` as-is — deferred. Add a one-line code comment: `// file editor deferred to v0.3.1.x (needs AttachmentManager threading) — see PropertyCellEditor.swift:341`.)

- [ ] **Step 4 — Thread `index` from hosts.** Wherever `PropertyEditorRow(definition:value:)` is constructed in `ItemWindow.swift` and `PropertyPanel.swift`, add `index: <hostIndex>`. ItemWindow/PropertyPanel read it via `@Environment(NexusManager.self)` → pass `nexusManager.currentIndex`. (Add the env to those hosts if absent.)

- [ ] **Step 5 — Make `FrontmatterInspector` tiers editable.** Add to `FrontmatterInspector`:

```swift
@Environment(NexusManager.self) private var nexusManager
```

Replace the read-only `tiersSection` (`:139-147`) with a relation picker per tier, bound to the VM's existing tier drafts + `handleTierChange`:

```swift
private var tiersSection: some View {
    Section("Tiers") {
        if let model = vm {
            tierPicker("Spaces",   tier: 1, ids: model.draftTier1) { model.handleTierChange(1, $0) }
            tierPicker("Topics",   tier: 2, ids: model.draftTier2) { model.handleTierChange(2, $0) }
            tierPicker("Projects", tier: 3, ids: model.draftTier3) { model.handleTierChange(3, $0) }
        }
    }
}

private func tierPicker(_ label: String, tier: Int, ids: [String], set: @escaping ([String]) -> Void) -> some View {
    LabeledContent(label) {
        RelationPicker(
            selectedIDs: Binding(get: { ids }, set: { set($0) }),
            scope: .contextTier(tier),
            index: nexusManager.currentIndex,
            onSelect: { set($0) }
        )
    }
}
```

- [ ] **Step 6 — Inject env into the inspector + detail chain (quirk #16).** `FrontmatterInspector` now reads `NexusManager` (and uses `RelationDisplayResolver` if you also route its tier *display* through chips). Confirm `NexusManager` is injected wherever `FrontmatterInspector` is mounted (`ContentView` inspector content, ~`:314-320`) AND, if any `.task`-bearing detail view newly reads these envs, that they're in the `.detail` chain (`:344-350`). Add whatever is missing.

- [ ] **Step 7 — Build green; commit.** Manual check: a Page's Spaces/Topics/Projects are now editable from the inspector; Item relation + status properties are editable in the Item Window.

---

### Task 7: Migration / index smoke-test (3→4 backfill)

**Files:** Test `PommoraTests/Index/IconBackfillTests.swift`

- [ ] **Step 1 — Write a backfill test.** Build an index from a fixture nexus (or seed the tables) containing entities WITH icons + tier values, run a full `IndexBuilder` rebuild, and assert: (a) `pages.icon` / `contexts.icon` are populated, (b) `resolveEntities` returns those icons, (c) tier `relations` rows still exist (no regression from Task 1).

```swift
import Testing
@testable import Pommora

@Suite("IconBackfillTests")
struct IconBackfillTests {
    @Test("Full rebuild populates entity icon and tier relations resolve with icon")
    func rebuildBackfillsIcon() async throws {
        // Use the existing IndexBuilder fixture pattern in PommoraTests/Index/.
        // Seed a Space (icon "star", tier 1) + a Page (icon "doc", tier1=[Space]).
        // Rebuild, then:
        //   #expect(resolveEntities(["<pageID>"])["<pageID>"]?.icon == "doc")
        //   #expect(resolveEntities(["<spaceID>"])["<spaceID>"]?.icon == "star")
        //   #expect(brokenLinks contains nothing for the tier link)
    }
}
```

Read an existing `PommoraTests/Index/` builder test and copy its fixture-nexus construction verbatim; fill in the assertions above. Do NOT launch the app for this (XCTest launch-modal guard, quirk #17) — exercise `IndexBuilder` directly.

- [ ] **Step 2 — Run; iterate to green.** `-only-testing:PommoraTests/IconBackfillTests`. Confirm non-zero count.

- [ ] **Step 3 — Manual real-nexus check (controller, after the session).** On next real launch the v3 DB deletes + rebuilds; confirm relations/tiers render (no "(missing)") in a real nexus with existing data. Note the outcome in `Handoff.md`.

- [ ] **Step 4 — Final commit + docs.** After all tasks green: update `Features/Properties.md` (relations now render icon+title from the index; `PropertyEditorRow` edits relation+status), `Features/Pages.md` (tiers editable from the inspector), `Index/Architecture` note (icon denormalized, schema v4). Move this plan to `Planning/Superseded/` and log the milestone in `History.md`.

---

### Risks / notes

- **Display-cache staleness.** `RelationDisplayResolver` caches icon+title; after a target is renamed or its icon changes, call `relationResolver.invalidate()` (or warm-overwrite). For v1, surfaces warm on appear, so staleness is bounded to a live session; wire `invalidate()` into rename/icon-edit commit paths if it shows. (Acceptable, log if deferred.)
- **`@Environment(RelationDisplayResolver.self)` must be in the `.detail` chain** for every `.task`-using detail view that reads it — quirk #16 (SIGTRAP otherwise). Task 2 Step 5 + Task 6 Step 6 cover this; verify with an actual launch/test bootstrap, not just compile.
- **Schema v4 is the second bump in two sessions.** Harmless (index is regeneratable) but means another forced rebuild on launch; Task 7 Step 3 is the real-data confidence check.
- **GRDB String-overload pollution** in `@ViewBuilder` closures (quirk #13): keep relation row rendering in the existing isolated sub-views; use `first(where:)` not `contains`.
- **Default-MainActor isolation (quirk #5) — verified the hard way in Task 1.** The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so any *explicit* `init` on a value type becomes `@MainActor`-isolated and CANNOT be called inside a GRDB `dbQueue.read/write { }` closure (nonisolated thread). `EntityRef.init` is therefore `nonisolated init`. **For Task 4:** give `GroupedEntities`/`EntityGroup` implicit memberwise inits (nonisolated by default) — do NOT add explicit inits, or mark them `nonisolated` if you must.
