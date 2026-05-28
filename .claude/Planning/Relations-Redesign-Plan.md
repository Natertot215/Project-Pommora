### Pommora — Relations Property v1 Redesign Plan

> **For agentic workers:** REQUIRED SUB-SKILL — use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Verification commands dispatch `xcodebuild` via background `Agent` (per CLAUDE.md branch quirk #14) — never run `xcodebuild` in the foreground.

**Goal:** Implement Pommora's Relations property at v1 shape. Spaces/Topics/Projects collapse into the standard relation property pipeline as three pre-configured built-in properties. User-creatable relations target Pages, Items, Agenda Tasks, Agenda Events. Storage is always-multi (array of `$rel` tagged objects). Rendering is chip-everywhere via a single `RelationChip` primitive. Value-assignment pickers are hierarchical for container targets. Tier values live at frontmatter root (`tier1` / `tier2` / `tier3`) for LLM legibility.

**Architecture:** Brainstorming session settled all design ambiguity; 8 parallel verification agents confirmed prescriptions against current code; this plan codifies the execution. Stub-and-progressively-replace sequencing — each task ships green standalone, later tasks replace earlier stubs (paradigm decision #4). Plan incorporates verification findings — notably the wizard-constructor drift (already 6-arg, plan augments rather than rewrites), the ItemContentManager+CRUD `stageBackRefClear` gap (pre-existing broken state Phase 2 repairs), the Agenda `Property` / `PropertyDefinition` divergence (Phase 4 unifies), and the EntityStateRef naming (Phase 17 stub references the actual type).

**Tech Stack:** SwiftUI primary + AppKit where needed · Swift 6 strict concurrency + ExistentialAny ON · GRDB.swift for SQLite · Apple swift-markdown + vendored swift-markdown-engine for the page editor · Yams for YAML frontmatter · TextKit 2 for editor surface.

**Conventions:**
- File paths in tables and code blocks use `/` (real OS notation); prose mentions paths with `//`.
- Test filter form: `-only-testing:PommoraTests/<FilenameWithTests>` (FILENAME of the test file, not the `@Suite` name).
- Each task ends with a commit; commits are intentional and focused.
- Trust `xcodebuild`, not SourceKit squiggles (branch quirk #3).
- Per `@Environment(X.self)` declaration on a detail view: also add to `ContentView.swift:325-331` unwrap chain AND `.environment(...)` chain at `:339-344` (branch quirk #16, corrected line numbers).

**Decisions locked (from brainstorming):**

| Topic | Resolution |
|---|---|
| Tier label scope | Per-Type override. Sidecar `_tier1` / `_tier2` / `_tier3` entries carry `displayName` (+ `icon`, `reverseName`, `reverseIcon`). `BuiltInRelationProperties` MERGES sidecar override with TierConfig default. |
| Validator signature | Cascade — `validate(_:in:nexus:)`. ~11 call sites updated. |
| ContextDetailPlaceholder | Untouched in v1. `LinkedFromDropdown` ships as bare stub. Full Context dropdown surface defers to a future plan. |
| Value-assignment picker | Existing `ChipDropdown` popover chrome (the multi-select popover shown in the spec screenshot). Flat list for every target type; rows are `RelationChip` + checkbox. Hierarchical UI (Topics tree, Projects tree, Vault > Collection > Pages, Item Type > Set > Items) defers to a post-v1 redesign. `HierarchicalEntityMenu` retires. |
| Singleton type IDs | `_agenda_tasks` / `_agenda_events` via new `ReservedTypeID` enum. |
| History.md acknowledgment | "rebuilt" — forbidden-word-free. |
| CLAUDE.md branch quirk #16 | Stale "line 237" — actual unwrap chain at `ContentView.swift:325-331`. Plan fixes the quirk text. |
| Tier column ordering | Rightmost three positions, default order Projects / Topics / Spaces, reorderable. |
| Tier props in Type Settings | Inline with user-created in Properties list; no delete affordance for tier rows. |
| Tier in-line cell editor | Extends the existing Status/Select/Multi-select cell-editor pattern (single-file switch in `PropertyCellEditor`); same `ChipDropdown` popover chrome; rows are `RelationChip` + checkbox. |
| RelationChip data model | `RelationChip(icon: scopedEntity.icon, title: scopedEntity.title)` — both fields resolve from the LINKED target entity (the Page/Item/Task/Event/Context the chip references), NOT from the source-side property's icon/name. Existing `RelationChip(icon: resolved.icon, title: resolved.title)` signature already matches. |
| RelationChip v1 visual | Plain styled text placeholder. Existing minimal `RoundedRectangle(cornerRadius: 4)` + `Color(.tertiarySystemFill)` body already meets this — no visual change. Redesign follows. |
| Tier property edit pane | Pre-populates Spaces/Topics/Projects entries; edits home name+icon AND context-side name+icon. `PropertyDefinition` gains `reverseName` + `reverseIcon` optional fields. |
| Relations table FK behavior | Application-layer source-side cascade (ratified 2026-05-28 — deleting a Context auto-removes its tag from every referencing entity). Context delete routines walk incoming relations, strip target ID from source entities' tier arrays, delete the relations rows. No DB-level FK changes. |
| Agenda schema shape | Already unified — `AgendaTaskSchema` / `AgendaEventSchema` already use `[PropertyDefinition]` with a `LegacyProperty` decode-tolerance struct. NO Property→PropertyDefinition migration. Agenda Tasks/Events ARE relation targets in v1 (ratified) — reverse relation properties append to the existing schema; `defaultSeed()` stays a single `_status` (decision #7). See Reconciliation pass + Phase 4. |
| Relation cardinality | Always-multi (ratified 2026-05-28). `allows_multiple` dropped; a single `{"$rel":id}` migrates to a one-element array; an empty relation OMITS the property key on disk (no `[]`) — this also avoids the schema-blind decoder's empty-array ambiguity (empty `[]` currently decodes as `.file([])`). |
| Tier value storage | Tier values stay at frontmatter ROOT (`tier1`/`tier2`/`tier3`); the `_tier1/2/3` properties read/write them through a NEW translator/adapter (Phase 6.5), NOT the `properties` dict. Preserves decision #6 (agent-legible root tiers). |

---

#### Reconciliation pass (2026-05-28) — read before executing

Code re-verification this session (four Explore passes against the live tree) found the plan's pre-write verification had drifted. The corrections below supersede the body where they conflict. Ratified product decisions (Nathan, this session) are folded into the decision table above.

**Ratified decisions:** relations are always-multi (single-pick dropped); deleting a Context auto-removes its tag from every referencing entity (source-side cascade); Agenda Tasks/Events ARE valid relation targets in v1; value pickers are flat lists in v1 (hierarchy deferred).

**Corrections to the body:**

1. **Phase 2 is obsolete — skip it.** `stageBackRefClear` is already defined in `ItemContentManager+CRUD.swift:504-574` (the "504" the body reads as a missing call site is the definition). No port needed.
2. **Phase 4 is rescoped to verify-only.** `AgendaTaskSchema` / `AgendaEventSchema` ALREADY use `[PropertyDefinition]` (with a `LegacyProperty` decode-tolerance struct). The plan's example seed (`_due_date`/`_priority`) is WRONG — the seed is and stays a single `_status` (locked decision #7). Phase 19.9's Agenda "Property→PropertyDefinition" migration likewise reduces to "confirm `LegacyProperty` read-tolerance covers old files" (already present).
3. **New Phase 6.5 — Tier value adapter (the translator).** Tier values live at frontmatter ROOT, not in `properties`, and no bridge to the property pipeline exists. Phase 6.5 builds it; Phases 13 / 14 / 15 / 16 / 18 route through it instead of touching `properties[id]` or root fields directly.
4. **Phase 8 / 10 — coordinator method name + edit path.** The real method is `createPairedRelation(...)`, not `createDualProperty`. It only CREATES (appends) — there is NO edit path, and the wizard never completed container-scope creation (`commitSave` returns `.nexusNotBound`). So the single-pane editor must (a) wire the coordinator with a bound nexus (net-new, not a move), (b) branch create-vs-edit: on create → `createPairedRelation`; on edit → `updateProperty` / `renameOneSide` for name/icon/mirror only, with the **target locked after creation** (matches "a relation targets one container at creation; for another, make another relation").
5. **Phase 13 — `ChipDropdown` is NOT generic** (hardcoded to `PropertyChipOption`, no `@ViewBuilder` row). Parameterize it over row content (update Status/Select/Multi-select call sites) or build a relation-specific sibling. The body's `ChipDropdown(options:) { … }` sample does not match the real API.
6. **Phase 18 — `unlinkTier` must use the Phase 6.5 adapter** (`setRelationIDs`), NOT `properties["_tierN"]` (the body's sample reads the wrong location and would silently no-op).
7. **Counts / citations:** the validator has 20 call sites (8 prod + 12 test), not "~11"; the "Phase 9.5" reference in Phase 20.2 means Phase 9.4; Phase 16.1's `resolvedProperties` is the Phase 5.2 `.properties` computed accessor.
8. **Work on `main`** (Nathan's explicit direction, 2026-05-28). Commit per task directly to `main`; no feature branch. Phase 0 cleanup (fix the 3 stale `"Types"`→`"Items"` label-default tests) lands first so the per-task TDD baseline is green; the 1 known `debounceCoalescesRapidEdits` flake is accepted/documented and dodged by targeted `-only-testing` runs.

---

#### Phase 0 — Working tree baseline

##### Task 0.1 — Confirm clean baseline

**Files:**
- Verify: working tree state

- [ ] **Step 1: Pull latest main**

```bash
git pull origin main
```

Expected: up-to-date with `origin/main` per Handoff.

- [ ] **Step 2: Confirm clean working tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`. If unattributed changes exist, surface to Nathan per branch quirk #11 (parallel session caveat — never revert unattributed changes).

- [ ] **Step 3: Run baseline test sweep**

Dispatch builder Agent in background:
```
xcodebuild test -project Pommora/Pommora.xcodeproj -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests
```

Expected: `** TEST SUCCEEDED **` with non-zero test count. If tests fail at baseline, stop and triage before proceeding.

---

#### Phase 1 — Foundational types (additive, no breaking changes)

##### Task 1.1 — Add named tier constants to `ReservedPropertyID`

**Files:**
- Modify: `Pommora/Pommora/Vaults/ReservedPropertyID.swift`
- Test: `Pommora/PommoraTests/Vaults/ReservedPropertyIDTests.swift`

- [ ] **Step 1: Add failing test**

Create `ReservedPropertyIDTests.swift`:
```swift
import Testing
@testable import Pommora

@Suite("ReservedPropertyID")
struct ReservedPropertyIDTests {
    @Test func tierConstantsResolveToExpectedStrings() {
        #expect(ReservedPropertyID.tier1 == "_tier1")
        #expect(ReservedPropertyID.tier2 == "_tier2")
        #expect(ReservedPropertyID.tier3 == "_tier3")
        #expect(ReservedPropertyID.isReserved(ReservedPropertyID.tier1))
        #expect(ReservedPropertyID.isReserved(ReservedPropertyID.tier2))
        #expect(ReservedPropertyID.isReserved(ReservedPropertyID.tier3))
    }
}
```

- [ ] **Step 2: Run failing test**

```
xcodebuild test ... -only-testing:PommoraTests/ReservedPropertyIDTests
```

Expected: FAIL with `Cannot find 'tier1' in scope` (or similar).

- [ ] **Step 3: Add named constants**

Edit `ReservedPropertyID.swift` — add three `static let` constants alongside the existing `Set<String>`:
```swift
enum ReservedPropertyID {
    static let tier1 = "_tier1"
    static let tier2 = "_tier2"
    static let tier3 = "_tier3"
    static let modifiedAt = "_modified_at"
    // … other reserved IDs that currently live as raw strings inside `all`

    static let all: Set<String> = [tier1, tier2, tier3, modifiedAt, /* … */]

    static func isReserved(_ id: String) -> Bool { all.contains(id) }
}
```

Hoist every raw string literal currently in the set to a named constant; the `all` set is then expressed in terms of the constants (DRY).

- [ ] **Step 4: Run tests**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pommora/Pommora/Vaults/ReservedPropertyID.swift Pommora/PommoraTests/Vaults/ReservedPropertyIDTests.swift
git commit -m "refactor(properties): hoist ReservedPropertyID raw strings to named constants"
```

##### Task 1.2 — Define `ReservedTypeID` enum for Agenda singletons

**Files:**
- Create: `Pommora/Pommora/Vaults/ReservedTypeID.swift`
- Test: `Pommora/PommoraTests/Vaults/ReservedTypeIDTests.swift`

- [ ] **Step 1: Add failing test**

```swift
import Testing
@testable import Pommora

@Suite("ReservedTypeID")
struct ReservedTypeIDTests {
    @Test func agendaSingletonsResolveToExpectedStrings() {
        #expect(ReservedTypeID.agendaTasks == "_agenda_tasks")
        #expect(ReservedTypeID.agendaEvents == "_agenda_events")
    }
}
```

- [ ] **Step 2: Run failing test** — expected FAIL: `Cannot find type 'ReservedTypeID'`.

- [ ] **Step 3: Define the enum**

```swift
/// Reserved type identifiers for singleton operational schemas.
/// Used by `DualRelationCoordinator.TypeKind.typeID` to identify Agenda Tasks
/// and Agenda Events as relation targets in reverse-property storage.
enum ReservedTypeID {
    static let agendaTasks = "_agenda_tasks"
    static let agendaEvents = "_agenda_events"
}
```

- [ ] **Step 4: Run tests** — PASS.

- [ ] **Step 5: Commit**

```bash
git add Pommora/Pommora/Vaults/ReservedTypeID.swift Pommora/PommoraTests/Vaults/ReservedTypeIDTests.swift
git commit -m "feat(properties): add ReservedTypeID for Agenda singleton type IDs"
```

##### Task 1.3 — Define `MigrationEvent` enum

**Files:**
- Create: `Pommora/Pommora/Nexus/MigrationEvent.swift`
- Test: `Pommora/PommoraTests/Nexus/MigrationEventTests.swift`

- [ ] **Step 1: Add failing test**

```swift
import Testing
@testable import Pommora

@Suite("MigrationEvent")
struct MigrationEventTests {
    @Test func eventCasesExist() {
        let events: [MigrationEvent] = [
            .relationShapeWrapped(propertyID: "p1", entityID: "e1"),
            .allowsMultipleStripped(propertyID: "p1", typeID: "t1"),
            .pageCollectionRewritten(propertyID: "p1", from: "c1", to: "t1"),
            .itemCollectionRewritten(propertyID: "p1", from: "c1", to: "t1"),
            .contextTierDropped(propertyID: "p1", tier: 2, typeID: "t1"),
            .agendaSchemaUnified(typeID: "_agenda_tasks", propertyCount: 4),
        ]
        #expect(events.count == 6)
    }
}
```

- [ ] **Step 2: Run failing test** — FAIL: `Cannot find type 'MigrationEvent'`.

- [ ] **Step 3: Define enum**

```swift
/// One per-property event surfaced in the adoption preview sheet during
/// nexus open. Aggregates into per-Type summaries for `AdoptionPreviewView`.
enum MigrationEvent: Sendable, Equatable {
    /// Legacy single `$rel` tagged object was wrapped into a one-element array.
    case relationShapeWrapped(propertyID: String, entityID: String)

    /// `allows_multiple` field stripped from a PropertyDefinition.
    case allowsMultipleStripped(propertyID: String, typeID: String)

    /// `page_collection` scope rewrote to `page_type` via the Collection-parent map.
    case pageCollectionRewritten(propertyID: String, from collectionID: String, to typeID: String)

    /// `item_collection` scope rewrote to `item_type` via the Collection-parent map.
    case itemCollectionRewritten(propertyID: String, from collectionID: String, to typeID: String)

    /// User-created PropertyDefinition with `target = .contextTier(N)` dropped from a Type schema.
    /// Requires explicit user acknowledgment in the preview sheet (the only "lossy" event).
    case contextTierDropped(propertyID: String, tier: Int, typeID: String)

    /// AgendaTaskSchema or AgendaEventSchema migrated from `Property` shape to `PropertyDefinition`.
    case agendaSchemaUnified(typeID: String, propertyCount: Int)
}
```

- [ ] **Step 4: Run tests** — PASS.

- [ ] **Step 5: Commit**

```bash
git add Pommora/Pommora/Nexus/MigrationEvent.swift Pommora/PommoraTests/Nexus/MigrationEventTests.swift
git commit -m "feat(migration): add MigrationEvent enum for adoption preview surfacing"
```

_Phase 1 ends here — `BuiltInRelationProperties` is created with its real merge logic in Phase 5 (no intermediate stub needed; nothing between here and Phase 5 calls it)._

---

#### Phase 2 — ~~Fix `ItemContentManager` stageBackRefClear gap~~ (OBSOLETE — skip)

> **Skip this phase (2026-05-28 re-verification).** `stageBackRefClear` IS already defined in `ItemContentManager+CRUD.swift:504-574` — the "504" cited below is the definition, not a missing call site. No port is needed; the symmetric back-ref clearing Phase 8 requires already exists. Task 2.1 below is void. Proceed to Phase 3.
>
> _(Optional cleanup, not required: the method is duplicated near-verbatim across `ItemContentManager+CRUD` and `PageContentManager+CRUD`. A DRY hoist is a separate, optional refactor — do not bundle it into this plan.)_

##### Task 2.1 — Port `stageBackRefClear` to `ItemContentManager+CRUD`

**Files:**
- Modify: `Pommora/Pommora/Items/ItemContentManager+CRUD.swift`
- Reference: `Pommora/Pommora/Vaults/PageContentManager+CRUD.swift:524-599`
- Test: `Pommora/PommoraTests/Items/ItemContentManagerBackRefTests.swift` (new file)

- [ ] **Step 1: Add failing test**

```swift
import Testing
@testable import Pommora

@Suite("ItemContentManager back-ref clearing")
struct ItemContentManagerBackRefTests {
    @Test func deletingItemClearsReverseRefsOnRelatedPages() async throws {
        // Set up a nexus with an Item Type and a Page Type that target it,
        // create a Page with a relation pointing at an Item, then delete the
        // Item and verify the Page's relation array no longer contains the deleted ID.
        // (Test scaffolding mirrors PageContentManagerBackRefTests pattern.)
        // … detailed test body uses the existing NexusContext closure pattern
    }
}
```

(Mirror the test structure already in place for `PageContentManager+CRUD.swift` — find the existing back-ref test file under PommoraTests and replicate.)

- [ ] **Step 2: Run failing test** — expect FAIL: either compile error (`stageBackRefClear` undefined) or runtime assertion failure if call sites silently no-op today.

- [ ] **Step 3: Port the method**

Open `PageContentManager+CRUD.swift:524-599`. Copy `stageBackRefClear` verbatim into `ItemContentManager+CRUD.swift`, adapting:
- Receiver type: `extension ItemContentManager`
- File-loading calls: use ItemContentManager's atomic-JSON load/save path instead of Pages' YAML+Markdown path
- Property iteration: use `Item.properties` instead of `Page.frontmatter.properties`
- ID resolution: through `ItemTypeManager` parent lookup pattern

Preserve the dual-relation semantics: for each property whose value contains the target ID, remove that ID from the array and stage a save. For empty arrays after removal, keep the empty array (the property remains; CLAUDE.md HARD RULE: "filename = title, no name field on Items" — properties can be empty arrays).

- [ ] **Step 4: Run tests** — PASS for the new test AND no regression in existing PageContentManager back-ref tests.

- [ ] **Step 5: Commit**

```bash
git add Pommora/Pommora/Items/ItemContentManager+CRUD.swift Pommora/PommoraTests/Items/ItemContentManagerBackRefTests.swift
git commit -m "fix(items): port stageBackRefClear to ItemContentManager (was missing)"
```

---

#### Phase 3 — Add `reverseName` / `reverseIcon` to `PropertyDefinition`

These fields enable per-Type tier property overrides for the context-side rendering (e.g., a Books vault's tier1 entry can carry `reverseName: "Books from this Branch"` so the eventual LinkedFromDropdown groups appropriately). For user-created relations, these fields stay nil — the reverse side lives on the target's PropertyDefinition.

##### Task 3.1 — Add fields + Codable + tests

**Files:**
- Modify: `Pommora/Pommora/Vaults/PropertyDefinition.swift`
- Test: `Pommora/PommoraTests/Vaults/PropertyDefinitionTests.swift` (extend existing)

- [ ] **Step 1: Add failing test**

```swift
@Test func propertyDefinitionRoundTripsReverseFields() throws {
    let def = PropertyDefinition(
        id: "_tier1",
        name: "Library Branches",
        icon: "books.vertical",
        kind: .relation,
        relationScope: .contextTier(1),
        reverseName: "Books from this Branch",
        reverseIcon: "book"
    )
    let data = try JSONEncoder().encode(def)
    let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: data)
    #expect(decoded.reverseName == "Books from this Branch")
    #expect(decoded.reverseIcon == "book")
}

@Test func legacyPropertyDefinitionDecodesWithNilReverseFields() throws {
    let json = #"{"id":"p1","name":"Author","icon":"person","kind":"relation","relation_scope":{"kind":"item_type","id":"t1"}}"#
    let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: Data(json.utf8))
    #expect(decoded.reverseName == nil)
    #expect(decoded.reverseIcon == nil)
}
```

- [ ] **Step 2: Run failing test** — FAIL on signature mismatch.

- [ ] **Step 3: Add the fields**

In `PropertyDefinition.swift`, add two optional fields after the existing `relationScope` field:

```swift
struct PropertyDefinition: /* existing conformances */ {
    // … existing fields
    var relationScope: RelationScope?

    /// Reverse-side display name override. v1 semantics: populated only on tier
    /// property entries (`_tier1` / `_tier2` / `_tier3`) where the target is a
    /// Context and no symmetric reverse-side PropertyDefinition can exist.
    /// User-created relations leave this nil; their reverse-side fields live on
    /// the target schema's PropertyDefinition (per dual-relations always rule).
    var reverseName: String?

    /// Reverse-side icon override. Same semantics as `reverseName`.
    var reverseIcon: String?

    // … existing fields
}
```

Update `CodingKeys`:
```swift
enum CodingKeys: String, CodingKey {
    case id, name, icon, kind
    case relationScope = "relation_scope"
    case reverseName = "reverse_name"
    case reverseIcon = "reverse_icon"
    // … existing keys
}
```

Update encode/decode to round-trip the new fields. Both are `Optional` so absence is preserved (nil decodes from missing key; nil encodes as omitted via encoder's `.iso8601` config or explicit `encodeIfPresent`).

- [ ] **Step 4: Run tests** — PASS, including any existing PropertyDefinition tests.

- [ ] **Step 5: Commit**

```bash
git add Pommora/Pommora/Vaults/PropertyDefinition.swift Pommora/PommoraTests/Vaults/PropertyDefinitionTests.swift
git commit -m "feat(properties): add reverseName/reverseIcon optional fields to PropertyDefinition"
```

---

#### Phase 4 — Agenda schema: verify already-unified (RESCOPED)

> **Rescoped (2026-05-28 re-verification).** `AgendaTaskSchema` / `AgendaEventSchema` ALREADY use `var properties: [PropertyDefinition]`, with a `LegacyProperty` struct providing decode tolerance for old `_taskconfig.json` / `_eventconfig.json` files. The `PropertyIDMigration.swift:35-37` comment claiming "separate `Property` struct without an `id` field" is STALE. There is no Property→PropertyDefinition change to make.
>
> **Do instead (verify-only):** (1) confirm both schemas decode legacy + current shapes via the `LegacyProperty` path; (2) confirm `defaultSeed()` is a SINGLE `_status` property and LEAVE IT — do NOT add `_due_date` / `_priority` / `_start` / `_end` (locked decision #7). EKReminder/EKEvent native fields are not schema properties.
>
> Tasks 4.1–4.5 below are superseded — their `Property`-shape premise is void. Phase 19.9's Agenda migration similarly reduces to confirming the existing `LegacyProperty` read-tolerance. Agenda-as-relation-target work (the part that survives) lives in Phase 8, which appends a reverse property to the already-`PropertyDefinition` schema with no shape change.

##### Task 4.1 — Migrate `AgendaTaskSchema` to `PropertyDefinition`

**Files:**
- Modify: `Pommora/Pommora/Agenda/AgendaTaskSchema.swift`
- Test: `Pommora/PommoraTests/Agenda/AgendaTaskSchemaTests.swift`

- [ ] **Step 1: Read current shape**

Open `AgendaTaskSchema.swift`. Note the existing `Property` struct shape (no `id` field). List fields it carries that must transfer to `PropertyDefinition` (likely: `name`, `kind`, `icon`, maybe option lists for Select-kind, etc.).

- [ ] **Step 2: Write failing test for new shape**

```swift
@Test func agendaTaskSchemaUsesPropertyDefinition() throws {
    let schema = AgendaTaskSchema(properties: [
        PropertyDefinition(
            id: "_due_date",
            name: "Due",
            icon: "calendar",
            kind: .date
        )
    ])
    let data = try JSONEncoder().encode(schema)
    let decoded = try JSONDecoder().decode(AgendaTaskSchema.self, from: data)
    #expect(decoded.properties.count == 1)
    #expect(decoded.properties[0].id == "_due_date")
}
```

- [ ] **Step 3: Run failing test** — FAIL on type mismatch.

- [ ] **Step 4: Change schema shape**

In `AgendaTaskSchema.swift`:
- Replace `var properties: [Property]` with `var properties: [PropertyDefinition]`
- Remove the nested `Property` struct definition
- Update default values / defaultSeed() to use PropertyDefinition with stable reserved IDs for built-in fields (e.g., `_due_date`, `_priority`, `_status`)
- Preserve existing Codable round-trip (test in step 2 catches drift)

For built-in task fields, assign reserved IDs prefixed with `_`. Example seed:
```swift
extension AgendaTaskSchema {
    static func defaultSeed() -> AgendaTaskSchema {
        AgendaTaskSchema(properties: [
            PropertyDefinition(id: "_due_date", name: "Due", icon: "calendar", kind: .date),
            PropertyDefinition(id: "_priority", name: "Priority", icon: "exclamationmark", kind: .select, options: ["Low", "Medium", "High"]),
            PropertyDefinition(id: "_status", name: "Status", icon: "checkmark.circle", kind: .status),
            // …
        ])
    }
}
```

- [ ] **Step 5: Run tests** — PASS. (Migration of existing sidecar files happens in Phase 19; this task only changes the in-memory shape.)

- [ ] **Step 6: Commit**

```bash
git add Pommora/Pommora/Agenda/AgendaTaskSchema.swift Pommora/PommoraTests/Agenda/AgendaTaskSchemaTests.swift
git commit -m "refactor(agenda): unify AgendaTaskSchema to PropertyDefinition shape"
```

##### Task 4.2 — Migrate `AgendaEventSchema` to `PropertyDefinition`

Mirror Task 4.1 for `AgendaEventSchema`. Seed default properties: `_start`, `_end`, `_all_day`, `_calendar`, etc. (whatever the current `Property`-based schema exposes).

**Files:**
- Modify: `Pommora/Pommora/Agenda/AgendaEventSchema.swift`
- Test: `Pommora/PommoraTests/Agenda/AgendaEventSchemaTests.swift`

- [ ] **Step 1: Mirror Task 4.1 — write test, see fail, change shape, see pass.**

- [ ] **Step 2: Commit**

```bash
git commit -m "refactor(agenda): unify AgendaEventSchema to PropertyDefinition shape"
```

##### Task 4.3 — Update `AgendaTaskManager` load/save paths

**Files:**
- Modify: `Pommora/Pommora/Agenda/AgendaTaskManager.swift`
- Test: `Pommora/PommoraTests/Agenda/AgendaTaskManagerTests.swift`

- [ ] **Step 1: Identify load + save touchpoints**

Find every place AgendaTaskManager reads or writes a Property/PropertyDefinition. Likely:
- `loadAll()` reads `_taskconfig.json` and constructs AgendaTaskSchema
- Save path serializes AgendaTaskSchema back to disk

- [ ] **Step 2: Write failing test for round-trip**

```swift
@Test func agendaTaskManagerRoundTripsUnifiedSchema() async throws {
    // Setup test nexus, save AgendaTaskSchema with PropertyDefinition entries,
    // reload via loadAll, verify properties round-trip cleanly
}
```

- [ ] **Step 3: Update load/save**

Replace any `[Property]` references with `[PropertyDefinition]`. Update serialization key from whatever Property used to PropertyDefinition's nested encoding shape.

- [ ] **Step 4: Run tests** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor(agenda): update AgendaTaskManager load/save for PropertyDefinition"
```

##### Task 4.4 — Update `AgendaEventManager` load/save paths

Mirror Task 4.3 for AgendaEventManager.

- [ ] **Step 1-5: Mirror Task 4.3 pattern.**

- [ ] **Step 6: Commit**

```bash
git commit -m "refactor(agenda): update AgendaEventManager load/save for PropertyDefinition"
```

##### Task 4.5 — Update any Agenda-property consumers in UI

Search for `.properties` accesses on AgendaTaskSchema / AgendaEventSchema across the codebase. Update each consumer to expect `[PropertyDefinition]`. Likely consumers:
- AdoptionPreviewView (renders property counts)
- Any agenda detail surface (doesn't exist yet but stubs might exist)
- IndexBuilder if it walks Agenda properties (it shouldn't today; verify)

- [ ] **Step 1: Sweep consumers**

```bash
grep -rn "AgendaTaskSchema\|AgendaEventSchema" Pommora/Pommora/ --include='*.swift'
```

- [ ] **Step 2: Update each consumer for PropertyDefinition shape.**

- [ ] **Step 3: Run full test suite** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(agenda): cascade PropertyDefinition shape to schema consumers"
```

---

#### Phase 5 — `BuiltInRelationProperties` registry (real merge logic)

Now that Agenda schemas are unified (Phase 4) and PropertyDefinition has reverse fields (Phase 3), the registry can produce real merged definitions for every operational schema.

##### Task 5.1 — Implement merge logic

**Files:**
- Modify: `Pommora/Pommora/Vaults/BuiltInRelationProperties.swift`
- Test: `Pommora/PommoraTests/Vaults/BuiltInRelationPropertiesTests.swift`

- [ ] **Step 1: Add failing tests for merge behavior**

```swift
@Test func mergeAppendsThreeTierEntriesWhenNoneInSidecar() {
    let merged = BuiltInRelationProperties.merge(
        existing: [],
        tierConfig: .defaultSeed(),
        sourceTypeID: "type1"
    )
    #expect(merged.count == 3)
    #expect(merged.contains { $0.id == ReservedPropertyID.tier1 })
    #expect(merged.contains { $0.id == ReservedPropertyID.tier2 })
    #expect(merged.contains { $0.id == ReservedPropertyID.tier3 })
}

@Test func mergeHonorsSidecarDisplayNameOverride() {
    let sidecar = PropertyDefinition(
        id: ReservedPropertyID.tier1,
        name: "Library Branches",  // override
        icon: "books.vertical",
        kind: .relation,
        relationScope: .contextTier(1)
    )
    let merged = BuiltInRelationProperties.merge(
        existing: [sidecar],
        tierConfig: .defaultSeed(),
        sourceTypeID: "type1"
    )
    let tier1 = try! #require(merged.first { $0.id == ReservedPropertyID.tier1 })
    #expect(tier1.name == "Library Branches")
    #expect(tier1.icon == "books.vertical")
}

@Test func mergeUsesTierConfigDefaultWhenSidecarNameAbsent() {
    let merged = BuiltInRelationProperties.merge(
        existing: [],
        tierConfig: .defaultSeed(),  // produces "Space"/"Spaces", "Topic"/"Topics", "Project"/"Projects"
        sourceTypeID: "type1"
    )
    let tier1 = try! #require(merged.first { $0.id == ReservedPropertyID.tier1 })
    #expect(tier1.name == "Spaces")  // plural form for property display
}

@Test func mergeUsesHardcodedFallbackIconsWhenSidecarAndConfigAbsent() {
    let merged = BuiltInRelationProperties.merge(
        existing: [],
        tierConfig: .defaultSeed(),
        sourceTypeID: "type1"
    )
    #expect(merged.first { $0.id == ReservedPropertyID.tier1 }?.icon == "building.2")
    #expect(merged.first { $0.id == ReservedPropertyID.tier2 }?.icon == "tag")
    #expect(merged.first { $0.id == ReservedPropertyID.tier3 }?.icon == "briefcase")
}

@Test func mergeIgnoresStructurallyLockedFieldsInSidecar() {
    // Even if sidecar tries to override relationScope, the merged result keeps .contextTier(1)
    let sidecar = PropertyDefinition(
        id: ReservedPropertyID.tier1,
        name: "Library",
        icon: "book",
        kind: .relation,
        relationScope: .pageType("tampered")  // attempt to override
    )
    let merged = BuiltInRelationProperties.merge(
        existing: [sidecar],
        tierConfig: .defaultSeed(),
        sourceTypeID: "type1"
    )
    let tier1 = try! #require(merged.first { $0.id == ReservedPropertyID.tier1 })
    if case .contextTier(let n) = tier1.relationScope { #expect(n == 1) }
    else { Issue.record("Expected .contextTier(1), got \(String(describing: tier1.relationScope))") }
}
```

- [ ] **Step 2: Implement real merge**

```swift
enum BuiltInRelationProperties {
    private struct TierDescriptor {
        let id: String
        let tierNumber: Int
        let fallbackIcon: String
    }

    private static let descriptors: [TierDescriptor] = [
        .init(id: ReservedPropertyID.tier1, tierNumber: 1, fallbackIcon: "building.2"),
        .init(id: ReservedPropertyID.tier2, tierNumber: 2, fallbackIcon: "tag"),
        .init(id: ReservedPropertyID.tier3, tierNumber: 3, fallbackIcon: "briefcase"),
    ]

    static func merge(
        existing: [PropertyDefinition],
        tierConfig: TierConfig,
        sourceTypeID: String
    ) -> [PropertyDefinition] {
        // Pass 1: filter out any existing entries with tier IDs (we re-emit them merged)
        let userDefined = existing.filter { def in
            !ReservedPropertyID.isReserved(def.id) || def.id == ReservedPropertyID.modifiedAt
        }

        // Pass 2: emit merged tier entries for each descriptor
        let tierEntries = descriptors.map { descriptor in
            let sidecar = existing.first(where: { $0.id == descriptor.id })
            let tier = tierConfig.tiers.first(where: { $0.level == descriptor.tierNumber })
            return PropertyDefinition(
                id: descriptor.id,
                // displayName: sidecar override → tier config plural → hardcoded fallback
                name: sidecar?.name ?? tier?.plural ?? "Tier \(descriptor.tierNumber)",
                // icon: sidecar override → fallback (IconConfig effort defers — TODO)
                icon: sidecar?.icon ?? descriptor.fallbackIcon,
                kind: .relation,
                // relationScope: structurally locked, ignore sidecar override
                relationScope: .contextTier(descriptor.tierNumber),
                reverseName: sidecar?.reverseName,
                reverseIcon: sidecar?.reverseIcon
            )
        }

        // TODO: Icon override for tier properties currently falls back when sidecar is nil.
        // A future IconConfig effort will provide nexus-level icon defaults; until then,
        // sidecar-or-fallback is the resolution order.

        return userDefined + tierEntries
    }
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(properties): implement BuiltInRelationProperties merge logic"
```

##### Task 5.2 — Wire registry into operational schema load paths

**Files:**
- Modify: `Pommora/Pommora/Vaults/PageType.swift` (and ItemType, AgendaTaskSchema, AgendaEventSchema)
- Test: existing manager round-trip tests + new tier-merge test

- [ ] **Step 1: Add failing test**

```swift
@Test func pageTypePropertiesIncludeThreeTierEntries() async throws {
    // Setup nexus + PageType with no sidecar tier overrides
    // Verify that pageType.properties contains _tier1, _tier2, _tier3 entries
}
```

- [ ] **Step 2: Make `properties` return the merged list**

Use private storage + public computed merge — single API, no consumer confusion:

```swift
struct PageType {
    private var storedProperties: [PropertyDefinition]  // on-disk list

    /// User-visible properties, including pre-configured tier relation entries
    /// merged from BuiltInRelationProperties. ALL consumers read this.
    var properties: [PropertyDefinition] {
        BuiltInRelationProperties.merge(
            existing: storedProperties,
            tierConfig: tierConfig,
            sourceTypeID: id
        )
    }

    // Writers (schema edits) modify storedProperties directly; reads always merge.
}
```

`Codable` encodes only `storedProperties` (round-trip preserves on-disk shape; merged tier entries never persist). Repeat the pattern verbatim for ItemType / AgendaTaskSchema / AgendaEventSchema.

Consumers (PropertyColumnBuilder, PropertyVisibilityPane, PropertyPanel, EditPropertyPane, Table column builders) need no changes — they already read `.properties` and now get tier entries for free.

- [ ] **Step 3: Run tests** — PASS for new test AND no regression in existing tests.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(properties): wire BuiltInRelationProperties via merged-public/stored-private pattern"
```

---

#### Phase 6 — `PropertyValue.relation` array shape + decoder tolerance

##### Task 6.1 — Change `.relation(String)` to `.relation([String])`

**Files:**
- Modify: `Pommora/Pommora/Vaults/PropertyValue.swift`
- Test: `Pommora/PommoraTests/Vaults/PropertyValueTests.swift`

- [ ] **Step 1: Add failing tests for new shape**

```swift
@Test func relationStoresArrayOfIDs() throws {
    let value = PropertyValue.relation(["01HABC", "01HDEF"])
    let data = try JSONEncoder().encode(value)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains("01HABC"))
    #expect(json.contains("01HDEF"))
}

@Test func relationRoundTripsThroughArrayShape() throws {
    let value = PropertyValue.relation(["01HABC"])
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
    if case .relation(let ids) = decoded { #expect(ids == ["01HABC"]) }
    else { Issue.record("Expected .relation, got \(decoded)") }
}

@Test func decoderToleratesLegacySingleObjectShape() throws {
    // Legacy shape: { "$rel": "01HABC" } — pre-migration, single object
    let legacy = #"{"$rel":"01HABC"}"#
    let decoded = try JSONDecoder().decode(PropertyValue.self, from: Data(legacy.utf8))
    if case .relation(let ids) = decoded { #expect(ids == ["01HABC"]) }
    else { Issue.record("Expected .relation, got \(decoded)") }
}

@Test func decoderAcceptsNewArrayShape() throws {
    let new = #"[{"$rel":"01HABC"},{"$rel":"01HDEF"}]"#
    let decoded = try JSONDecoder().decode(PropertyValue.self, from: Data(new.utf8))
    if case .relation(let ids) = decoded { #expect(ids == ["01HABC", "01HDEF"]) }
    else { Issue.record("Expected .relation, got \(decoded)") }
}
```

- [ ] **Step 2: Run failing tests** — FAIL on signature mismatch.

- [ ] **Step 3: Change enum case + Codable**

In `PropertyValue.swift`:
```swift
enum PropertyValue: Sendable, Equatable {
    // … other cases
    case relation([String])
}

extension PropertyValue: Codable {
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()

        // Try legacy single-object shape first: {"$rel": "..."}
        if let dict = try? c.decode([String: String].self), let id = dict["$rel"] {
            self = .relation([id])
            return
        }

        // Try new array shape: [{"$rel": "..."}, …]
        if let array = try? c.decode([[String: String]].self) {
            let ids = array.compactMap { $0["$rel"] }
            // Tolerance: empty array is legitimate (empty multi-pick state)
            // Single-element array also legitimate (one pick)
            self = .relation(ids)
            return
        }

        // … fall through to other PropertyValue cases (number, text, date, etc.)
        // following the existing pattern in PropertyValue.swift's decoder.
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .relation(let ids):
            // Always emit array shape (new canonical form)
            let array = ids.map { ["$rel": $0] }
            try c.encode(array)
        // … other cases
        }
    }
}
```

- [ ] **Step 4: Run tests** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(properties): change PropertyValue.relation to array shape with legacy tolerance"
```

##### Task 6.2 — Update `PropertyValue.relation` consumers across codebase

Compile sweep — anywhere the codebase pattern-matched on `.relation(String)` (single-pick), update to `.relation([String])`.

- [ ] **Step 1: Sweep call sites**

```bash
grep -rn "case .relation" Pommora/Pommora/ --include='*.swift'
grep -rn ".relation(" Pommora/Pommora/ --include='*.swift'
```

- [ ] **Step 2: Update each site**

For each call site that destructured a single ID, update to handle the array. Examples:
- `if case .relation(let id) = value { resolve(id) }` → `if case .relation(let ids) = value { ids.forEach { resolve($0) } }`
- Single-pick UIs that committed `.relation(pickedID)` → `.relation([pickedID])`
- Empty / clearing assignments: `.relation([])` instead of `.relation(nil)` (no nil state)

- [ ] **Step 3: Run full test suite** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(properties): sweep PropertyValue.relation consumers to array shape"
```

##### Task 6.3 — Drop `allowsMultiple` from `PropertyDefinition`

**Files:**
- Modify: `Pommora/Pommora/Vaults/PropertyDefinition.swift`
- Test: `Pommora/PommoraTests/Vaults/PropertyDefinitionTests.swift`

- [ ] **Step 1: Add tolerance test**

```swift
@Test func decoderToleratesLegacyAllowsMultipleField() throws {
    let json = #"{"id":"p1","name":"X","icon":"i","kind":"relation","relation_scope":{"kind":"item_type","id":"t1"},"allows_multiple":true}"#
    let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: Data(json.utf8))
    // The field is silently dropped on decode; no public access to it.
    #expect(decoded.id == "p1")
}

@Test func encoderDoesNotEmitAllowsMultiple() throws {
    let def = PropertyDefinition(id: "p1", name: "X", icon: "i", kind: .relation, relationScope: .itemType("t1"))
    let data = try JSONEncoder().encode(def)
    let json = String(data: data, encoding: .utf8)!
    #expect(!json.contains("allows_multiple"))
}
```

- [ ] **Step 2: Remove the field**

Delete `var allowsMultiple: Bool?` from PropertyDefinition. Remove from `CodingKeys`. Update `init(from:)` to silently ignore `allows_multiple` on decode (read it via `decodeIfPresent` but discard).

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Sweep consumers**

```bash
grep -rn "allowsMultiple" Pommora/Pommora/ --include='*.swift'
```

Update each consumer:
- UI toggle removal in any property edit pane
- Wizard step removal (the wizard no longer asks "allow multiple"; always-multi)
- Tests referencing `allowsMultiple` — update or delete

- [ ] **Step 5: Run full test suite** — PASS.

- [ ] **Step 6: Commit**

```bash
git commit -m "refactor(properties): drop allowsMultiple field; always-multi storage"
```

---

#### Phase 6.5 — Tier value adapter (root-field ↔ property translator)

> **Why this phase exists (2026-05-28).** Verification found tier values are stored at frontmatter ROOT (`tier1` / `tier2` / `tier3`) on Page / Item / AgendaTask / AgendaEvent — NOT in the `properties` dictionary — and that NO code bridges them to the property pipeline (the `_tier1/2/3` reserved IDs exist but are never instantiated as schema properties; `FrontmatterInspector.onSave` is even unwired today). The redesign treats `_tier1/2/3` as relation properties, so every value surface (picker, cell editor, panel, column display, validator, `unlinkTier`) must read/write tier values through ONE adapter that maps the reserved tier IDs to the root fields. Locked decision #6 (tiers at root for agent-legibility) is preserved — values stay at root; only the access path is unified. This phase lands after Phase 6 (`.relation([String])` exists) and before the picker/cell wiring (Phases 13–14) that depends on it.

##### Task 6.5.1 — Add relation-value accessors to each operational entity

**Files:**
- Modify: `Pommora/Pommora/Content/PageFrontmatter.swift`, `Pommora/Pommora/Content/Item.swift`, `Pommora/Pommora/Agenda/AgendaTask.swift`, `Pommora/Pommora/Agenda/AgendaEvent.swift`
- Test: `Pommora/PommoraTests/Content/TierValueAdapterTests.swift` (new)

- [ ] **Step 1: Add failing tests**

```swift
@Test func tierPropertyIDsReadFromRootFields() {
    var fm = PageFrontmatter.empty()
    fm.tier1 = ["01SPACE"]; fm.tier3 = ["01PROJ"]
    #expect(fm.relationIDs(forPropertyID: ReservedPropertyID.tier1) == ["01SPACE"])
    #expect(fm.relationIDs(forPropertyID: ReservedPropertyID.tier2) == [])
    #expect(fm.relationIDs(forPropertyID: ReservedPropertyID.tier3) == ["01PROJ"])
}

@Test func tierPropertyIDsWriteToRootFields() {
    var fm = PageFrontmatter.empty()
    fm.setRelationIDs(["01SPACE", "01SPACE2"], forPropertyID: ReservedPropertyID.tier1)
    #expect(fm.tier1 == ["01SPACE", "01SPACE2"])
}

@Test func userRelationIDsRoundTripThroughProperties() {
    var fm = PageFrontmatter.empty()
    fm.setRelationIDs(["01T"], forPropertyID: "prop_rel")
    #expect(fm.relationIDs(forPropertyID: "prop_rel") == ["01T"])
    if case .relation(let ids)? = fm.properties["prop_rel"] { #expect(ids == ["01T"]) }
    else { Issue.record("expected .relation") }
}

@Test func emptyUserRelationOmitsTheKey() {
    var fm = PageFrontmatter.empty()
    fm.setRelationIDs(["01T"], forPropertyID: "prop_rel")
    fm.setRelationIDs([], forPropertyID: "prop_rel")
    #expect(fm.properties["prop_rel"] == nil)   // omitted, NOT stored as []
}
```

- [ ] **Step 2: Implement the adapter on each entity**

Illustrative for `PageFrontmatter` (mirror verbatim on Item / AgendaTask / AgendaEvent — all four carry root `tier1/2/3` + a `properties` dict):

```swift
extension PageFrontmatter {
    /// Canonical READ for any relation-typed property, including the three
    /// built-in tier properties whose values live at frontmatter root.
    func relationIDs(forPropertyID id: String) -> [String] {
        switch id {
        case ReservedPropertyID.tier1: return tier1
        case ReservedPropertyID.tier2: return tier2
        case ReservedPropertyID.tier3: return tier3
        default:
            if case .relation(let ids)? = properties[id] { return ids }
            return []
        }
    }

    /// Canonical WRITE. Tier IDs route to the root field; user relations route
    /// to `properties`. An empty user-relation value OMITS the key (no `[]` on
    /// disk) so the schema-blind decoder never sees an ambiguous empty array.
    mutating func setRelationIDs(_ ids: [String], forPropertyID id: String) {
        switch id {
        case ReservedPropertyID.tier1: tier1 = ids
        case ReservedPropertyID.tier2: tier2 = ids
        case ReservedPropertyID.tier3: tier3 = ids
        default: properties[id] = ids.isEmpty ? nil : .relation(ids)
        }
    }
}
```

- [ ] **Step 3: Run tests** — PASS for all four entities.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(relations): tier value adapter — root-field/property translator on all 4 entities"
```

##### Task 6.5.2 — Adapter is the sole tier-value access path (gate)

This is a checklist gate enforced as later phases land (no code of its own here beyond the audit):

- Phases 13 / 14 (picker + cell editor) read/write via `relationIDs(forPropertyID:)` / `setRelationIDs(_:forPropertyID:)`.
- Phases 15 / 16 (chip-everywhere surfaces + table columns) resolve tier values via the same read accessor.
- Phase 18 (`unlinkTier`) mutates via `setRelationIDs`, NOT `properties["_tierN"]`.

- [ ] **Step 1: Audit** — after Phase 18, grep confirms no surface indexes `properties["_tier` and no relation surface assigns `.tier1/2/3` directly except the adapter + Codable:

```bash
grep -rn 'properties\["_tier' Pommora/Pommora/ --include='*.swift'   # expect: none
grep -rn '\.tier[123] = ' Pommora/Pommora/ --include='*.swift'        # expect: only adapter + Codable + FrontmatterInspector flush
```

- [ ] **Step 2: No commit** unless the audit surfaces a stray direct access to fix.

---

#### Phase 7 — `RelationScope` → `RelationTarget` rename + case sweep

##### Task 7.1 — Add `agendaTasks` + `agendaEvents` cases to existing `RelationScope`

**Files:**
- Modify: `Pommora/Pommora/Vaults/PropertyDefinition.swift` (where RelationScope lives at lines 172-177)
- Test: `Pommora/PommoraTests/Vaults/RelationScopeTests.swift`

- [ ] **Step 1: Add failing tests**

```swift
@Test func agendaTasksAndEventsCasesExist() throws {
    let t: PropertyDefinition.RelationScope = .agendaTasks
    let e: PropertyDefinition.RelationScope = .agendaEvents
    #expect(t != e)
}

@Test func agendaCasesRoundTripJSON() throws {
    let cases: [(PropertyDefinition.RelationScope, String)] = [
        (.agendaTasks, "agenda_tasks"),
        (.agendaEvents, "agenda_events"),
    ]
    for (value, expectedKind) in cases {
        let data = try JSONEncoder().encode(value)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains(expectedKind))
        let decoded = try JSONDecoder().decode(PropertyDefinition.RelationScope.self, from: data)
        #expect(decoded == value)
    }
}
```

- [ ] **Step 2: Add the new cases**

In the enum:
```swift
enum RelationScope: Codable, Equatable, Sendable {
    case pageType(String)
    case itemType(String)
    case pageCollection(String)    // ← retires after Phase 19 migration
    case itemCollection(String)    // ← retires after Phase 19 migration
    case contextTier(Int)
    case agendaTasks               // NEW
    case agendaEvents              // NEW
}
```

Update Codable to handle the new no-associated-value cases:
```swift
private enum Kind: String, Codable {
    case pageType = "page_type"
    case itemType = "item_type"
    case pageCollection = "page_collection"
    case itemCollection = "item_collection"
    case contextTier = "context_tier"
    case agendaTasks = "agenda_tasks"
    case agendaEvents = "agenda_events"
}
```

Encode `.agendaTasks` as `{"kind": "agenda_tasks"}` (no `id`/`tier` field). Same for `.agendaEvents`.

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(properties): add agendaTasks/agendaEvents cases to RelationScope"
```

##### Task 7.2 — Rename `RelationScope` to `RelationTarget`

Mechanical rename. Use Xcode's refactor or sed-based sweep.

**Files:** every file referencing `RelationScope`.

- [ ] **Step 1: Inventory references**

```bash
grep -rn "RelationScope" Pommora/ --include='*.swift' | wc -l
```

- [ ] **Step 2: Mechanical rename**

```bash
find Pommora/ -name '*.swift' -type f -exec sed -i '' 's/RelationScope/RelationTarget/g' {} +
```

Also rename `relationScope` field name on PropertyDefinition to `relationTarget`:
```bash
find Pommora/ -name '*.swift' -type f -exec sed -i '' 's/relationScope/relationTarget/g' {} +
```

Be careful: `relationScope` appears in CodingKeys (`case relationScope = "relation_scope"`). The on-disk JSON key stays `relation_scope` UNTIL the migration phase (Phase 19) updates it to `relation_target`. So in CodingKeys:
```swift
case relationTarget = "relation_scope"  // transitional — Phase 19 changes string value to "relation_target"
```

Add a TODO comment:
```swift
case relationTarget = "relation_scope"  // TODO: Phase 19 migration changes on-disk key to "relation_target"
```

- [ ] **Step 3: Verify build**

Background Agent: `xcodebuild build -project Pommora/Pommora.xcodeproj -scheme Pommora`. Expected: SUCCEEDED.

- [ ] **Step 4: Run test suite** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor(properties): rename RelationScope → RelationTarget (in-memory; on-disk key migrates Phase 19)"
```

##### Task 7.3 — Add decoder tolerance for legacy `relation_scope` JSON key

When the migration runs in Phase 19, it'll rewrite `relation_scope` → `relation_target` in sidecars. Until then (and for unmigrated files: backups, external edits, cross-device sync), the decoder must accept both.

- [ ] **Step 1: Add test**

```swift
@Test func decoderAcceptsBothRelationScopeAndRelationTargetKeys() throws {
    let legacyKey = #"{"id":"p1","name":"X","icon":"i","kind":"relation","relation_scope":{"kind":"item_type","id":"t1"}}"#
    let newKey = #"{"id":"p1","name":"X","icon":"i","kind":"relation","relation_target":{"kind":"item_type","id":"t1"}}"#

    let legacy = try JSONDecoder().decode(PropertyDefinition.self, from: Data(legacyKey.utf8))
    let new = try JSONDecoder().decode(PropertyDefinition.self, from: Data(newKey.utf8))

    #expect(legacy.relationTarget == new.relationTarget)
}
```

- [ ] **Step 2: Implement dual-key decoder**

```swift
init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // … other field decodes

    // Accept either relation_scope (legacy) or relation_target (post-migration)
    if let target = try c.decodeIfPresent(RelationTarget.self, forKey: .relationTarget) {
        self.relationTarget = target
    } else if let legacy = try c.decodeIfPresent(RelationTarget.self, forKey: .legacyRelationScope) {
        self.relationTarget = legacy
    } else {
        self.relationTarget = nil
    }
    // … rest
}

private enum CodingKeys: String, CodingKey {
    case relationTarget = "relation_target"
    case legacyRelationScope = "relation_scope"
    // … other keys
}
```

Encoder always emits `relation_target` (new canonical):
```swift
func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(relationTarget, forKey: .relationTarget)
    // … rest (never emit legacy key)
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(properties): accept legacy relation_scope JSON key alongside relation_target"
```

_Case lifecycle doc-comments land as part of Task 7.2's rename diff — no separate commit. Lifecycle text to embed:_

```swift
enum RelationTarget: Codable, Equatable, Sendable {
    /// User-creatable: targets a Page Type by ID.
    case pageType(String)

    /// User-creatable: targets an Item Type by ID.
    case itemType(String)

    /// LEGACY — decoded for tolerance; never produced by code paths after Phase 7.
    /// Migration (Phase 19) rewrites to .pageType via Collection-parent map.
    case pageCollection(String)

    /// LEGACY — same as pageCollection.
    case itemCollection(String)

    /// Internal-only: built-in tier properties (Spaces/Topics/Projects).
    /// Editor never exposes; only emitted by BuiltInRelationProperties.
    case contextTier(Int)

    /// User-creatable: targets the singleton Agenda Tasks schema.
    case agendaTasks

    /// User-creatable: targets the singleton Agenda Events schema.
    case agendaEvents
}
```

---

#### Phase 8 — `DualRelationCoordinator` Agenda extension

##### Task 8.1 — Extend `TypeKind` with Agenda singleton cases

**Files:**
- Modify: `Pommora/Pommora/Vaults/DualRelationCoordinator.swift:34-37` (current 2-case enum)
- Test: `Pommora/PommoraTests/Vaults/DualRelationCoordinatorTests.swift`

- [ ] **Step 1: Add failing test**

```swift
@Test func typeKindAgendaCasesExist() {
    let taskSchema = AgendaTaskSchema(properties: [])
    let eventSchema = AgendaEventSchema(properties: [])
    let kindTasks: DualRelationCoordinator.TypeKind = .agendaTasks(taskSchema)
    let kindEvents: DualRelationCoordinator.TypeKind = .agendaEvents(eventSchema)

    #expect(kindTasks.typeID == ReservedTypeID.agendaTasks)
    #expect(kindEvents.typeID == ReservedTypeID.agendaEvents)
}
```

- [ ] **Step 2: Add the cases**

```swift
extension DualRelationCoordinator {
    enum TypeKind {
        case pageType(PageType)
        case itemType(ItemType)
        case agendaTasks(AgendaTaskSchema)
        case agendaEvents(AgendaEventSchema)

        var typeID: String {
            switch self {
            case .pageType(let pt): return pt.id
            case .itemType(let it): return it.id
            case .agendaTasks: return ReservedTypeID.agendaTasks
            case .agendaEvents: return ReservedTypeID.agendaEvents
            }
        }
    }
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(dual-relations): extend TypeKind with agendaTasks/agendaEvents cases"
```

##### Task 8.2 — Update `DualRelationCoordinating` protocol signature

**Files:**
- Modify: `Pommora/Pommora/Vaults/RelationPropertyWizard.swift:7-39` (protocol declaration)
- Modify: `Pommora/Pommora/Vaults/DualRelationCoordinator.swift` (conformance)
- Test: `Pommora/PommoraTests/Vaults/RelationPropertyWizardTests.swift` (MockDualRelationCoordinating)

- [ ] **Step 1: Update protocol method signatures**

Where the protocol uses `RelationScope`, it now uses `RelationTarget` (already renamed in Phase 7). Methods that operate on a specific Type now accept any of the 4 TypeKind cases:

```swift
protocol DualRelationCoordinating {
    func createDualProperty(
        source: PropertyDefinition,
        sourceTarget: RelationTarget,
        targetKind: DualRelationCoordinator.TypeKind,
        // … other params
    ) async throws

    // … other methods, all updated for RelationTarget + 4-case TypeKind
}
```

- [ ] **Step 2: Update conformance + Mock**

Update `DualRelationCoordinator` and `MockDualRelationCoordinating` (in tests) to satisfy the new signature. Mock can return canned responses for the Agenda cases.

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(dual-relations): update DualRelationCoordinating protocol for Agenda targets"
```

##### Task 8.3 — Implement Agenda-target dual-relation operations

Now `DualRelationCoordinator` must support creating a reverse property on `AgendaTaskSchema` / `AgendaEventSchema` when a user creates a relation pointing at one of them. The reverse property gets written to `_taskconfig.json` / `_eventconfig.json` (via NexusPaths.taskSchemaURL / eventSchemaURL).

**Files:**
- Modify: `Pommora/Pommora/Vaults/DualRelationCoordinator.swift`
- Test: `Pommora/PommoraTests/Vaults/DualRelationCoordinatorAgendaTests.swift` (new)

- [ ] **Step 1: Add failing test**

```swift
@Test func creatingRelationTargetingAgendaTasksWritesReversePropertyToTaskSchema() async throws {
    // Setup nexus, create a Page Type "Notes" with a relation "RelatedTask" → .agendaTasks
    // After create, AgendaTaskSchema (loaded via NexusPaths.taskSchemaURL) should contain
    // a reverse PropertyDefinition pointing back to Notes via .pageType("notes_id")
}
```

- [ ] **Step 2: Implement reverse-write for Agenda cases**

In `DualRelationCoordinator`, the `.agendaTasks` / `.agendaEvents` branches read the singleton schema, append the reverse PropertyDefinition (using `ReservedTypeID.agendaTasks` / `agendaEvents` as the source typeID context), and write back via the atomic JSON helper. Mirror the existing PageType/ItemType code path.

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(dual-relations): implement reverse-property writes for Agenda targets"
```

---

#### Phase 9 — Index layer rebuild

##### Task 9.1 — Add `@Observable` to `PommoraIndex`

**Files:**
- Modify: `Pommora/Pommora/Index/PommoraIndex.swift:8`
- Test: existing PommoraIndex tests should pass

- [ ] **Step 1: Add annotation**

```swift
import Observation

@MainActor
@Observable
final class PommoraIndex {
    // … existing implementation
}
```

Note: `@Observable` + `@MainActor` is required by Swift 6 strict concurrency for a class observable from main-actor SwiftUI views. Verify the existing PommoraIndex isn't already `@MainActor`-isolated; if it's not, this annotation needs surrounding analysis.

- [ ] **Step 2: Run full test suite** — PASS.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(index): make PommoraIndex @Observable for SwiftUI environment injection"
```

##### Task 9.2 — Rename `IndexQuery.entitiesByScope` → `entitiesByTarget`

**Files:**
- Modify: `Pommora/Pommora/Index/IndexQuery.swift`
- Test: any IndexQuery test files

- [ ] **Step 1: Rename mechanically**

```bash
find Pommora/ -name '*.swift' -type f -exec sed -i '' 's/entitiesByScope/entitiesByTarget/g' {} +
```

Update the method signature to switch on `RelationTarget` (already renamed in Phase 7). The 5-case switch covers `pageType`, `itemType`, `agendaTasks`, `agendaEvents`, `contextTier`. Legacy `pageCollection` / `itemCollection` cases still exist in the enum (per Phase 7 lifecycle); the method maps them through the Collection-parent map to their parent Type for query purposes. Queries inline per the existing IndexQuery pattern:

```swift
func entitiesByTarget(_ target: RelationTarget) async throws -> [EntityRef] {
    switch target {
    case .pageType(let id):
        return try await index.db.read { db in
            try Row.fetchAll(db, sql: "SELECT id FROM pages WHERE page_type_id = ?", arguments: [id])
                .compactMap { ($0["id"] as String?).map { EntityRef(kind: .page, id: $0) } }
        }

    case .itemType(let id):
        return try await index.db.read { db in
            try Row.fetchAll(db, sql: "SELECT id FROM items WHERE item_type_id = ?", arguments: [id])
                .compactMap { ($0["id"] as String?).map { EntityRef(kind: .item, id: $0) } }
        }

    case .pageCollection(let id):
        // Legacy: resolve to parent type via collection-parent map; queries pages-in-type
        guard let parentID = await collectionParentMap.parentPageTypeID(forCollection: id) else { return [] }
        return try await entitiesByTarget(.pageType(parentID))

    case .itemCollection(let id):
        guard let parentID = await collectionParentMap.parentItemTypeID(forCollection: id) else { return [] }
        return try await entitiesByTarget(.itemType(parentID))

    case .agendaTasks:
        return try await index.db.read { db in
            try Row.fetchAll(db, sql: "SELECT id FROM agenda_tasks")
                .compactMap { ($0["id"] as String?).map { EntityRef(kind: .agendaTask, id: $0) } }
        }

    case .agendaEvents:
        return try await index.db.read { db in
            try Row.fetchAll(db, sql: "SELECT id FROM agenda_events")
                .compactMap { ($0["id"] as String?).map { EntityRef(kind: .agendaEvent, id: $0) } }
        }

    case .contextTier(let n):
        let table = ["spaces", "topics", "projects"][n - 1]
        return try await index.db.read { db in
            try Row.fetchAll(db, sql: "SELECT id FROM \(table)")
                .compactMap { ($0["id"] as String?).map { EntityRef(kind: contextKind(tier: n), id: $0) } }
        }
    }
}
```

- [ ] **Step 2: Run tests** — PASS.

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor(index): rename entitiesByScope → entitiesByTarget; 5-case dispatch"
```

##### Task 9.3 — Define `incomingRelations(targetID:)` query

This is the canonical reverse-view query. Powers the future LinkedFromDropdown when wired (deferred); also usable by any consumer that asks "what points at this entity?"

**Files:**
- Modify: `Pommora/Pommora/Index/IndexQuery.swift`
- Test: `Pommora/PommoraTests/Index/IndexQueryReverseTests.swift`

- [ ] **Step 1: Add failing test**

```swift
@Test func incomingRelationsReturnsAllSourcesPointingAtTarget() async throws {
    // Seed: 2 Pages and 1 Item with relation properties pointing at a target entity X.
    // Expect: incomingRelations(targetID: X) returns 3 EntityRefs (2 Pages + 1 Item).
}

@Test func incomingRelationsHandlesTierLinks() async throws {
    // Seed: 1 Page with tier1: [spaceA_id]. After Phase 20 (tier_links retire),
    // this relation lives in the `relations` table.
    // Expect: incomingRelations(targetID: spaceA_id) returns 1 EntityRef (the page).
}
```

- [ ] **Step 2: Implement query**

```swift
extension IndexQuery {
    /// Returns every operational entity (Page / Item / Task / Event) whose
    /// `relations` table rows point at the specified target ID.
    func incomingRelations(targetID: String) async throws -> [EntityRef] {
        try await index.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT source_id, source_kind
                FROM relations
                WHERE target_id = ?
                """, arguments: [targetID])
            return rows.compactMap { row in
                guard let id: String = row["source_id"],
                      let kindRaw: String = row["source_kind"],
                      let kind = EntityKind(rawValue: kindRaw)
                else { return nil }
                return EntityRef(kind: kind, id: id)
            }
        }
    }
}
```

- [ ] **Step 3: Run tests** — PASS for non-tier case; tier case PASSES after Phase 20 migration populates relations rows from tier1/2/3 frontmatter.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(index): add incomingRelations(targetID:) canonical reverse-view query"
```

##### Task 9.4 — Unify `target_kind` derivation in `IndexBuilder` + `IndexUpdater`

**Files:**
- Modify: `Pommora/Pommora/Index/IndexBuilder.swift`
- Modify: `Pommora/Pommora/Index/IndexUpdater.swift:399` (the "unknown" hardcode)
- Create: `Pommora/Pommora/Index/RelationTargetKind.swift` (shared helper)
- Test: `Pommora/PommoraTests/Index/RelationTargetKindTests.swift`

- [ ] **Step 1: Define shared helper**

```swift
/// Canonical mapping from RelationTarget to the `target_kind` string written
/// into the `relations` SQLite table. Used by IndexBuilder + IndexUpdater so
/// the values stay consistent (avoids the prior IndexUpdater "unknown" hardcode).
enum RelationTargetKind {
    static func string(from target: RelationTarget) -> String {
        switch target {
        case .pageType: return "page"
        case .itemType: return "item"
        case .pageCollection: return "page"   // legacy → resolved to parent at query
        case .itemCollection: return "item"
        case .agendaTasks: return "agenda_task"
        case .agendaEvents: return "agenda_event"
        case .contextTier(let n):
            return "context_tier_\(n)"  // distinct per tier for query selectivity
        }
    }
}
```

- [ ] **Step 2: Add tests**

```swift
@Test func targetKindDerivationCoversAllRelationTargets() {
    let cases: [(RelationTarget, String)] = [
        (.pageType("t"), "page"),
        (.itemType("t"), "item"),
        (.agendaTasks, "agenda_task"),
        (.agendaEvents, "agenda_event"),
        (.contextTier(1), "context_tier_1"),
        (.contextTier(2), "context_tier_2"),
        (.contextTier(3), "context_tier_3"),
    ]
    for (target, expected) in cases {
        #expect(RelationTargetKind.string(from: target) == expected)
    }
}
```

- [ ] **Step 3: Update IndexUpdater**

Replace the `"unknown"` hardcode at `IndexUpdater.swift:399` with `RelationTargetKind.string(from: target)`. The `target` value comes from the PropertyDefinition's `relationTarget` field.

- [ ] **Step 4: Update IndexBuilder**

Sweep IndexBuilder's relations-table emit sites for any `target_kind` string. Replace with `RelationTargetKind.string(from:)` calls.

- [ ] **Step 5: Run tests** — PASS.

- [ ] **Step 6: Commit**

```bash
git commit -m "refactor(index): unify target_kind derivation via RelationTargetKind helper"
```

---

#### Phase 10 — Relation property editor (single pane)

Locked direction: relation properties are created and edited via a single `EditPropertyPane` variant — same pattern as Status / Select / Multi-Select. No multi-step wizard. The pane has three rows: (1) "This property" — home-side icon + name; (2) "Mirror" — reverse-side icon + name; (3) a two-level Select menu for target (Items ▸ Item Type, Vaults ▸ Page Type, Events, Tasks). `RelationPropertyWizard` retires entirely.

##### Task 10.1 — Define `RelationTargetCatalog`

**Files:**
- Create: `Pommora/Pommora/Properties/RelationTargetCatalog.swift`
- Test: `Pommora/PommoraTests/Properties/RelationTargetCatalogTests.swift`

- [ ] **Step 1: Add failing tests**

```swift
@Test func catalogReturnsFourSectionsInOrder() {
    let nexus = TestNexusContext.seed()  // with 2 PageTypes "Books"/"Notes", 1 ItemType "Tasks", Agenda enabled
    let catalog = RelationTargetCatalog(nexus: nexus, settings: SettingsManager.default)
    let sections = catalog.sections()

    #expect(sections.count == 4)
    #expect(sections[0].header == "Items")
    #expect(sections[1].header == "Vaults")
    #expect(sections[2].header == "Events")
    #expect(sections[3].header == "Tasks")
}

@Test func itemsSectionListsItemTypesByDisplayTitle() { /* … */ }
@Test func vaultsSectionListsPageTypesByDisplayTitle() { /* … */ }
@Test func eventsSectionRendersSingleEntry() { /* … */ }
@Test func tasksSectionRendersSingleEntry() { /* … */ }

@Test func sectionHeadersUseSettingsLabelsPluralAccessors() {
    // Settings overrides labels for itemType.plural = "Sets"
    // Verify section[0].header reflects the override
}
```

- [ ] **Step 2: Implement catalog**

```swift
/// Shared accessor for the four-section target catalog. Used by both the
/// RelationPropertyWizard target step and the EditPropertyPane (DRY).
///
/// Section order locked: Items → Vaults → Events → Tasks (Tasks + Events
/// are adjacent peers; no Agenda parent header).
///
/// Section headers read from `SettingsLabels` nested LabelPair (.plural).
/// Affordance labels (e.g. "Select Item") read from .singular.
/// Row labels (per Type) read from the Type's own display title.
struct RelationTargetCatalog {
    let nexus: NexusContext
    let settings: SettingsManager

    struct Row: Identifiable {
        let id: String           // target ID (or ReservedTypeID for singletons)
        let label: String        // display title
        let target: RelationTarget
    }

    struct Section {
        let header: String       // plural label
        let affordance: String   // "Select Item" / "Select Vault" / etc.
        let rows: [Row]
    }

    func sections() -> [Section] {
        [
            Section(
                header: settings.labels.itemType.plural,
                affordance: "Select \(settings.labels.itemType.singular)",
                rows: nexus.itemTypes.map { Row(id: $0.id, label: $0.displayTitle, target: .itemType($0.id)) }
            ),
            Section(
                header: settings.labels.pageType.plural,
                affordance: "Select \(settings.labels.pageType.singular)",
                rows: nexus.pageTypes.map { Row(id: $0.id, label: $0.displayTitle, target: .pageType($0.id)) }
            ),
            Section(
                header: settings.labels.agendaEvent.plural,
                affordance: "Select \(settings.labels.agendaEvent.singular)",
                rows: [Row(id: ReservedTypeID.agendaEvents, label: settings.labels.agendaEvent.plural, target: .agendaEvents)]
            ),
            Section(
                header: settings.labels.agendaTask.plural,
                affordance: "Select \(settings.labels.agendaTask.singular)",
                rows: [Row(id: ReservedTypeID.agendaTasks, label: settings.labels.agendaTask.plural, target: .agendaTasks)]
            ),
        ]
    }
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(properties): add RelationTargetCatalog shared accessor (wizard + edit pane DRY)"
```

##### Task 10.2 — Two-level target selector menu

**Files:**
- Create: `Pommora/Pommora/Properties/RelationTargetMenu.swift`
- Test: `Pommora/PommoraTests/Properties/RelationTargetMenuTests.swift`

- [ ] **Step 1: Add failing tests**

```swift
@Test func menuShowsKindHeadersAsTopLevel() throws {
    let catalog = TestCatalog.seed()  // Items: 2 types, Vaults: 2 types, Events, Tasks
    let menu = RelationTargetMenu(catalog: catalog, selection: .constant(nil))
    // Snapshot or accessibility-tree assertion: 4 top-level menu entries
    // labeled Items, Vaults, Events, Tasks
}

@Test func selectingItemTypeSetsTargetToItemTypeCase() { /* … */ }
@Test func selectingPageTypeSetsTargetToPageTypeCase() { /* … */ }
@Test func selectingEventsSetsTargetToAgendaEventsCase() { /* … */ }
@Test func selectingTasksSetsTargetToAgendaTasksCase() { /* … */ }
@Test func menuButtonLabelShowsCurrentSelectionTitle() {
    // When selection is .itemType("books_id"), button shows "Books"
}
```

- [ ] **Step 2: Implement the menu**

SwiftUI `Menu` with nested `Menu` per kind. Items + Vaults expand to their specific Types; Events + Tasks are direct leaves.

```swift
/// Two-level Select menu for picking a relation target.
///
/// Level 1: Items / Vaults / Events / Tasks (kind headers from RelationTargetCatalog).
/// Level 2: specific Types within Items + Vaults; Events + Tasks are direct selections
/// with no submenu (singleton targets).
///
/// Used by EditPropertyPane's relation case. Per branch quirk #13 (GRDB String
/// overload pollution in @ViewBuilder), per-row label resolution stays inside
/// private struct sub-views with plain value types.
struct RelationTargetMenu: View {
    let catalog: RelationTargetCatalog
    @Binding var selection: RelationTarget?

    var body: some View {
        Menu {
            ForEach(catalog.sections(), id: \.header) { section in
                if section.rows.count == 1, let only = section.rows.first {
                    // Singleton kinds (Events / Tasks): direct button at top level
                    Button {
                        selection = only.target
                    } label: {
                        TargetMenuLabel(row: only, isSelected: selection == only.target)
                    }
                } else {
                    // Multi-row kinds (Items / Vaults): nested submenu
                    Menu(section.header) {
                        ForEach(section.rows) { row in
                            Button {
                                selection = row.target
                            } label: {
                                TargetMenuLabel(row: row, isSelected: selection == row.target)
                            }
                        }
                    }
                }
            }
        } label: {
            buttonLabel
        }
    }

    @ViewBuilder
    private var buttonLabel: some View {
        if let resolved = catalog.resolve(target: selection) {
            HStack {
                Image(systemName: resolved.icon)
                Text(resolved.label)
            }
        } else {
            Text("Select target")
        }
    }
}

private struct TargetMenuLabel: View {
    let row: RelationTargetCatalog.Row
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: row.icon)
            Text(row.label)
            if isSelected { Image(systemName: "checkmark") }
        }
    }
}
```

`RelationTargetCatalog` gains a `resolve(target:) -> Row?` accessor used by the button label (returns the row matching the current selection so the button shows the chosen target's icon + name).

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(properties): add RelationTargetMenu two-level Select for relation editor"
```

##### Task 10.3 — Extend `EditPropertyPane` with relation editor

**Files:**
- Modify: `Pommora/Pommora/Properties/EditPropertyPane.swift` (the `.relation` case body)
- Test: `Pommora/PommoraTests/Properties/EditPropertyPaneRelationTests.swift`

- [ ] **Step 1: Add failing tests**

```swift
@Test func relationEditorExposesHomeMirrorAndTargetRows() {
    // Mount EditPropertyPane with a relation PropertyDefinition (user-created, not tier)
    // Assert: home name + home icon + mirror name + mirror icon + target Select all visible
}

@Test func relationEditorPersistsHomeFields() async throws {
    // Edit home name + icon, save
    // Verify PropertyDefinition.name and .icon updated
}

@Test func relationEditorPersistsMirrorFields() async throws {
    // Edit reverse name + reverse icon, save
    // Verify PropertyDefinition.reverseName / .reverseIcon updated
}

@Test func relationEditorPersistsTargetSelection() async throws {
    // Pick a target via the menu, save
    // Verify PropertyDefinition.relationTarget updated
}

@Test func relationEditorSaveInvokesDualRelationCoordinator() async throws {
    // Pick a target (an ItemType), save
    // Verify coordinator.createDualProperty invoked with the chosen target
    // Verify reverse PropertyDefinition lands on the target schema
}

@Test func relationEditorValidatesBothNamesBeforeAllowingSave() {
    // Leave mirror name empty, attempt save
    // Verify save is blocked with a validation message
}
```

- [ ] **Step 2: Implement the editor**

```swift
struct EditPropertyPane: View {
    @State var draft: PropertyDefinition
    let isTierEntry: Bool
    let coordinator: any DualRelationCoordinating
    let catalog: RelationTargetCatalog
    let onSave: (PropertyDefinition) -> Void
    let onDelete: (() -> Void)?  // nil for tier entries

    var body: some View {
        ScrollView {
            // Universal: icon + name (top section)
            Section("Home") {
                HStack {
                    IconPicker(selection: $draft.icon)
                    TextField("Name", text: $draft.name)
                }
            }

            // Relation-specific: mirror + target
            if draft.kind == .relation {
                Section("Mirror") {
                    HStack {
                        IconPicker(selection: Binding(
                            get: { draft.reverseIcon ?? "" },
                            set: { draft.reverseIcon = $0.isEmpty ? nil : $0 }
                        ))
                        TextField("Name", text: Binding(
                            get: { draft.reverseName ?? "" },
                            set: { draft.reverseName = $0.isEmpty ? nil : $0 }
                        ))
                    }
                }

                if !isTierEntry {
                    // Target selector: only for user-created relations.
                    // Tier rows lock target to .contextTier(N) — selector hidden.
                    Divider()
                    HStack {
                        Text("Target")
                        Spacer()
                        RelationTargetMenu(
                            catalog: catalog,
                            selection: $draft.relationTarget
                        )
                    }
                }
            }

            // Other property kinds: existing per-kind editors (Status, Select, etc.)
            // (Unchanged from current EditPropertyPane structure.)

            // Footer: Save / Cancel + (optional) Delete
            HStack {
                if let onDelete, !isTierEntry {
                    Button("Delete", role: .destructive) { onDelete() }
                }
                Spacer()
                Button("Save") {
                    saveIfValid()
                }
                .disabled(!isValid)
            }
        }
    }

    private var isValid: Bool {
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if draft.kind == .relation {
            guard let _ = draft.reverseName, !draft.reverseName!.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            if !isTierEntry {
                guard draft.relationTarget != nil else { return false }
            }
        }
        return true
    }

    private func saveIfValid() {
        guard isValid else { return }
        // For relation kind: invoke DualRelationCoordinator to land both source + reverse
        // For tier entries: no coordinator call needed (target locked; reverse view is LinkedFromDropdown, not a target schema property)
        if draft.kind == .relation && !isTierEntry {
            Task {
                do {
                    try await coordinator.createDualProperty(
                        source: draft,
                        sourceTarget: draft.relationTarget!,
                        targetKind: resolveTargetKind(draft.relationTarget!)
                    )
                    onSave(draft)
                } catch {
                    // Surface error to the user (toast or inline)
                }
            }
        } else {
            onSave(draft)
        }
    }
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(properties): single-pane relation editor in EditPropertyPane"
```

##### Task 10.4 — Retire `RelationPropertyWizard`

**Files:**
- Delete: `Pommora/Pommora/Vaults/RelationPropertyWizard.swift`
- Delete: `Pommora/PommoraTests/Vaults/RelationPropertyWizardTests.swift`
- Modify: `Pommora/Pommora/Vaults/VaultSettingsSheet.swift:278-299` (remove wizard sheet)
- Modify: `Pommora/Pommora/Vaults/TypeSettingsSheet.swift:232-249` (remove wizard sheet)

- [ ] **Step 1: Sweep for remaining wizard references**

```bash
grep -rn "RelationPropertyWizard" Pommora/ --include='*.swift'
```

Should show only the two sheet sites + tests + the wizard file itself.

- [ ] **Step 2: Remove sheet integration**

The "+ Add property → Relation" flow at the sheet sites currently presents the wizard. Replace with: open `EditPropertyPane` directly with a blank-draft relation PropertyDefinition (`kind: .relation`, all other fields nil).

```swift
// VaultSettingsSheet:~278 — was: .sheet(item: $newRelationDraft) { _ in RelationPropertyWizard(…) }
// Now: directly opens EditPropertyPane via the same property-edit pattern Select/Status use
```

Match the existing per-kind property-creation flow (look at how Select / Status open EditPropertyPane when "+ Add property → Select" is chosen — the relation case mirrors that exactly).

- [ ] **Step 3: Delete files**

```bash
git rm Pommora/Pommora/Vaults/RelationPropertyWizard.swift
git rm Pommora/PommoraTests/Vaults/RelationPropertyWizardTests.swift
```

- [ ] **Step 4: Verify build + tests pass**

Background Agent: `xcodebuild test ...`. Expected SUCCESS with the wizard tests gone and no compile errors at the former call sites.

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor(properties): retire RelationPropertyWizard; relation editing in EditPropertyPane"
```

_Coordinator invocation surface alignment lands as part of Task 10.3's editor wiring — if `DualRelationCoordinator.createDualProperty` had a wizard-shaped result-object signature, refactor it to the `(source: PropertyDefinition, sourceTarget: RelationTarget, targetKind: TypeKind)` shape used by `saveIfValid()` in the same commit. No separate task._

---

#### Phase 11 — _(consolidated into Phases 5 + 10)_

Phase 11 was originally a separate phase for "tier property UI in EditPropertyPane." Its responsibilities are now fully covered:

- **Pre-populating `_tier1` / `_tier2` / `_tier3` in the property list** — handled by Phase 5.2's merged-properties pattern. Every consumer of `pageType.properties` (Type Settings list, PropertyColumnBuilder, PropertyVisibilityPane, PropertyPanel, etc.) gets tier entries automatically.
- **Hiding the delete affordance for tier rows** — handled by Phase 10.3's `isTierEntry` flag in EditPropertyPane (the `if let onDelete, !isTierEntry` guard in the footer).
- **Home + context-side editors for tier rows** — handled by Phase 10.3's editor body, which always renders the Home + Mirror sections; the Mirror section's `reverseName` / `reverseIcon` bindings ARE the context-side overrides for tier rows.

No standalone tasks. Phase 12 follows.

---

#### Phase 12 — `PropertyDefinitionValidator` cascade

##### Task 12.1 — Change signature to `validate(_:in:nexus:)`

**Files:**
- Modify: `Pommora/Pommora/Vaults/Validation/PropertyDefinitionValidator.swift`
- Test: `Pommora/PommoraTests/Vaults/Validation/PropertyDefinitionValidatorTests.swift`

- [ ] **Step 1: Add failing tests for new rules**

```swift
@Test func validatorRejectsRelationPropertyMissingRelationTarget() throws {
    let def = PropertyDefinition(id: "p1", name: "X", icon: "i", kind: .relation, relationTarget: nil)
    let nexus = TestNexusContext.empty()
    #expect(throws: PropertyDefinitionValidator.ValidationError.self) {
        try PropertyDefinitionValidator.validate(def, in: [], nexus: nexus)
    }
}

@Test func validatorRejectsRelationPropertyWithUnresolvableTargetID() throws {
    let def = PropertyDefinition(id: "p1", name: "X", icon: "i", kind: .relation, relationTarget: .pageType("does_not_exist"))
    let nexus = TestNexusContext.empty()  // no PageTypes
    #expect(throws: PropertyDefinitionValidator.ValidationError.self) {
        try PropertyDefinitionValidator.validate(def, in: [], nexus: nexus)
    }
}

@Test func validatorAcceptsAgendaTargetsWithoutCatalogLookup() throws {
    // .agendaTasks / .agendaEvents are singletons — no ID lookup required
    let def = PropertyDefinition(id: "p1", name: "X", icon: "i", kind: .relation, relationTarget: .agendaTasks)
    let nexus = TestNexusContext.empty()
    #expect(throws: Never.self) {
        try PropertyDefinitionValidator.validate(def, in: [], nexus: nexus)
    }
}
```

- [ ] **Step 2: Update validator signature**

```swift
enum PropertyDefinitionValidator {
    enum ValidationError: Error {
        case duplicateName(String)
        case relationMissingTarget
        case relationTargetNotResolvable(typeID: String)
        // … other existing cases (NOT Rule 6 contextTier-dual; that retires)
    }

    static func validate(
        _ def: PropertyDefinition,
        in existing: [PropertyDefinition],
        nexus: NexusContext
    ) throws {
        // Rule 1-4: existing rules (unchanged)
        // Rule 5: case-insensitive duplicate name (unchanged)
        try validateNoDuplicateName(def, in: existing)

        // Rule 6 (RETIRED): contextTier-dual rejection — removed entirely

        // NEW Rule: relation property must carry a relationTarget
        if def.kind == .relation && def.relationTarget == nil {
            throw ValidationError.relationMissingTarget
        }

        // NEW Rule: container-kind target ULID must resolve in nexus catalog
        if def.kind == .relation, let target = def.relationTarget {
            switch target {
            case .pageType(let id):
                guard nexus.pageTypes.contains(where: { $0.id == id }) else {
                    throw ValidationError.relationTargetNotResolvable(typeID: id)
                }
            case .itemType(let id):
                guard nexus.itemTypes.contains(where: { $0.id == id }) else {
                    throw ValidationError.relationTargetNotResolvable(typeID: id)
                }
            case .agendaTasks, .agendaEvents, .contextTier:
                // Singletons / system targets — no catalog lookup
                break
            case .pageCollection, .itemCollection:
                // Legacy targets — validator REJECTS at save time; migration handles read-tolerance
                throw ValidationError.relationTargetNotResolvable(typeID: "legacy_collection_target")
            }
        }
    }
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(validation): cascade validator signature; add relation target rules; retire Rule 6"
```

##### Task 12.2 — Cascade ~11 call sites

Find every caller and add `nexus:` argument.

- [ ] **Step 1: Sweep call sites**

```bash
grep -rn "PropertyDefinitionValidator.validate" Pommora/ --include='*.swift'
```

Expected: ~11 sites across `PageTypeManager`, `ItemTypeManager`, `AgendaTaskManager`, `AgendaEventManager` (plus any tests).

- [ ] **Step 2: Update each call site**

Each manager already has `@MainActor @escaping () -> NexusContext` parameter pattern per branch quirk #5. Use it to resolve the nexus context for the validator call.

- [ ] **Step 3: Run full test suite** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(validation): cascade validator nexus arg to 11 call sites"
```

---

#### Phase 13 — Relation value picker (existing multi-select chrome + RelationChip rows)

Locked direction: the value-assignment picker reuses the existing `ChipDropdown` popover chrome (the same surface that powers Multi-Select cell editors today, per the spec screenshot). For relation values, each row in the popover is a `RelationChip` + checkbox. Flat list for every target type — no hierarchical UI in v1.

`HierarchicalEntityMenu` retires entirely. Hierarchical UIs (Vault > Collection > Pages, Item Type > Set > Items, Topics tree, Projects tree) defer to a post-v1 redesign and live in Phase 22's deferred-items log.

##### Task 13.1 — Anchor `RelationChip` doc-comment (consumers + data model contract)

`RelationChip` exists at `Pommora/Pommora/Properties/Chips/RelationChip.swift` with `(icon: String, title: String)` signature. This task anchors BOTH contracts via one combined header doc-comment: the single-source rendering contract (every surface routes through this primitive) AND the data-model contract (both fields resolve from the linked target entity).

**Files:**
- Modify: `Pommora/Pommora/Properties/Chips/RelationChip.swift`

- [ ] **Step 1: Add the combined header doc-comment**

```swift
/// **Single rendering primitive for relation property values across every Pommora surface.**
///
/// Consumers (every surface that renders a relation value):
/// - PropertyPanel (single-entity property panel)
/// - PropertiesPulldown (nav-pulldown property summary)
/// - FrontmatterInspector (page editor inspector)
/// - ItemWindow (item popover)
/// - PropertyCellDisplay (Table cells)
/// - LinkedFromDropdown (Context-side reverse view — stub in v1; deferred)
///
/// All consumers MUST route relation rendering through this primitive.
/// Adding a parallel rendering path violates the chip-everywhere paradigm.
///
/// **Data model contract:**
/// Both `icon` and `title` resolve from the LINKED target entity — the Page,
/// Item, Task, Event, or Context that the chip references. NEVER from the
/// source-side relation property's icon/name. Resolution happens at the
/// consumer (PropertyCellDisplay, PropertyPanel, etc.) via the relation
/// resolver, then passed in as plain String values.
///
/// **v1 visual:** plain styled text placeholder with minimal chip chrome.
/// Redesign follows.
///
/// Stays at this path (`Properties/Chips/`). Do NOT move.
struct RelationChip: View {
    // … existing implementation
}
```

- [ ] **Step 2: Commit**

```bash
git commit -m "docs(chips): anchor RelationChip consumer + data model contracts"
```

(Phase 15.1 — which previously added a separate consumer-list doc-comment — folds into this task. Phase 15.1 placeholder retained for sequence continuity but contains no code.)

`ChipDropdown` (at `Pommora/Pommora/Properties/Chips/ChipDropdown.swift`) is the popover chrome shared by Status / Select / Multi-Select cell editors today. Verification found `.regularMaterial` + 0.5pt border + drag-reorder multi-select. The relation picker reuses this chrome.

If ChipDropdown is not already parameterized over row content, parameterize it (preferred — DRY across all kinds): add a generic `Row: View` type and a `@ViewBuilder` row-builder parameter; update Status / Select / Multi-Select call sites to pass their existing PropertyChip builders. If parameterization is invasive, build a thin sibling that wraps the same chrome — acceptable but less DRY.

**Files:**
- Modify: `Pommora/Pommora/Properties/Chips/ChipDropdown.swift` (parameterize if needed)
- Modify: `Pommora/Pommora/Properties/RelationPicker.swift` (rewrite as thin ChipDropdown invocation)
- Test: `Pommora/PommoraTests/Properties/RelationPickerTests.swift`

- [ ] **Step 1: Add failing test**

```swift
@Test func relationPickerRendersChipDropdownWithRelationChipRows() {
    // Mount RelationPicker with target = .pageType("books_id") and a few candidate Pages
    // Assert: ChipDropdown popover appears
    // Assert: each row renders a RelationChip (icon + title of the candidate Page) + checkbox
    // Assert: tapping a row toggles its inclusion in the selectedIDs binding
}
```

- [ ] **Step 2: Rewrite `RelationPicker` body**

```swift
struct RelationPicker: View {
    let target: RelationTarget
    @Binding var selectedIDs: Set<String>
    @Environment(PommoraIndex.self) private var index
    @State private var candidates: [RelationCandidate] = []

    var body: some View {
        ChipDropdown(options: candidates) { option in
            HStack {
                Toggle(isOn: Binding(
                    get: { selectedIDs.contains(option.id) },
                    set: { sel in
                        if sel { selectedIDs.insert(option.id) }
                        else { selectedIDs.remove(option.id) }
                    }
                )) {
                    RelationChip(icon: option.icon, title: option.title)
                }
                .toggleStyle(.checkbox)
            }
        }
        .task {
            let refs = (try? await IndexQuery(index).entitiesByTarget(target)) ?? []
            candidates = refs.compactMap { resolve(ref: $0) }
        }
    }
}

private struct RelationCandidate: Identifiable {
    let id: String
    let icon: String
    let title: String
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(properties): wire RelationChip rows into ChipDropdown for relation picker"
```

---

#### Phase 14 — `PropertyCellEditor` relation case wired to RelationPicker

`RelationPicker` was rewritten in Phase 13.3 as a flat ChipDropdown + RelationChip rows shared across every target type. Pre-scoping happens entirely via the candidate query (`IndexQuery.entitiesByTarget`): tier-1 returns Spaces, tier-2 returns Topics, tier-3 returns Projects, `.pageType(X)` returns Pages in that Type, `.itemType(X)` returns Items, `.agendaTasks` returns all Tasks, `.agendaEvents` returns all Events. **All target types render identically — flat list, no per-target branching, no hierarchy in v1.**

Phase 14 wires this picker into the Table cell-editor path.

##### Task 14.1 — Extend `PropertyCellEditor` relation case

**Files:**
- Modify: `Pommora/Pommora/Properties/PropertyCellEditor.swift:311` (placeholder line)
- Modify: PropertyCellEditor's parameter list (add `relationBinding`, `index`)
- Test: `Pommora/PommoraTests/Properties/PropertyCellEditorRelationTests.swift`

- [ ] **Step 1: Add failing test**

```swift
@Test func propertyCellEditorRelationCaseInvokesRelationPicker() {
    // Mount PropertyCellEditor with a relation PropertyDefinition
    // Verify RelationPicker appears in the popover
}
```

- [ ] **Step 2: Expand params + wire RelationPicker**

```swift
struct PropertyCellEditor: View {
    let definition: PropertyDefinition
    let value: PropertyValue
    let relationResolver: (String) -> EntityRef?   // existing
    let commit: (PropertyValue) -> Void
    let relationBinding: Binding<[String]>          // NEW
    let index: PommoraIndex?                        // NEW (optional for graceful degradation in previews)

    var body: some View {
        switch definition.kind {
        case .status: StatusCellEditor(…)
        case .select: SelectCellEditor(…)
        case .multiSelect: MultiSelectCellEditor(…)
        case .relation:
            if let target = definition.relationTarget {
                RelationPicker(target: target, selectedIDs: Binding(
                    get: { Set(relationBinding.wrappedValue) },
                    set: { relationBinding.wrappedValue = Array($0) }
                ))
                .frame(width: 320)
            } else {
                Text("Property missing relationTarget")
                    .foregroundStyle(.secondary)
            }
        // … other cases unchanged
        }
    }
}
```

The Status/Select/Multi-select cell editor pattern is preserved (popover wiring at `:78` and `:97-112`; `isChipDropdownEditor` gate at `:119-124`; commit on `.onDisappear`). The `.relation` case becomes a `RelationPicker` invocation inside the same popover frame.

- [ ] **Step 3: Update call sites**

Every place that constructs `PropertyCellEditor` (likely each detail view's TableColumnForEach body) now supplies `relationBinding` and `index`. The binding routes the picker's selection back into the source entity's property dictionary; the commit closure handles the persistence.

- [ ] **Step 4: Run tests** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(properties): wire RelationPicker into PropertyCellEditor relation case"
```

---

#### Phase 15 — Chip-everywhere conversion

Verification found `RelationChip` is currently used by only 1/6 planned surfaces. This phase converts the 4 remaining active surfaces (LinkedFromDropdown defers per the deferral lock).

##### Task 15.1 — _(consolidated into Task 13.1)_

`RelationChip`'s header doc-comment lands in Task 13.1 (combined consumer + data model contract). No separate task here.

##### Task 15.2 — `PropertyPanel.tierRow` → `RelationChip`

**Files:**
- Modify: `Pommora/Pommora/Detail/PropertyPanel.swift` (the `tierRow(label:tier:ids:)` helper and its call sites)
- Test: existing PropertyPanel tests

- [ ] **Step 1: Locate `tierRow`**

```bash
grep -n "tierRow" Pommora/Pommora/Detail/PropertyPanel.swift
```

- [ ] **Step 2: Replace `tierRow` body with `RelationChip` rendering**

Inline the chip rendering: for each ID in the `ids` array, resolve the target entity (via the panel's relation resolver), construct a RelationChip for it, and arrange in a flowing HStack with wrapping behavior matching how non-tier relation columns already render (look at the existing PropertyCellDisplay relation rendering for the pattern).

- [ ] **Step 3: Delete the `tierRow` helper** (no remaining callers after the inline conversion). The label parameter becomes the property's `displayName` from the resolved PropertyDefinition; the `tier:` parameter has no meaning under chip-everywhere (it was only used for label resolution which now happens at the resolved-property layer).

- [ ] **Step 4: Run tests** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor(property-panel): convert tierRow to RelationChip rendering"
```

##### Task 15.3 — `PropertiesPulldown.tierRow` → `RelationChip`

Mirror Task 15.2 for the PropertiesPulldown variant. Note: PropertiesPulldown's `tierRow` signature lacks the `tier:` parameter (verification finding); conversion drops the helper entirely.

- [ ] **Step 1-5: Mirror Task 15.2 pattern for PropertiesPulldown.**

- [ ] **Step 6: Commit**

```bash
git commit -m "refactor(properties-pulldown): convert tierRow to RelationChip rendering"
```

##### Task 15.4 — `FrontmatterInspector` LabeledContent + `tier{1,2,3}Names` → `RelationChip`

**Files:**
- Modify: `Pommora/Pommora/Pages/FrontmatterInspector.swift` (LabeledContent uses at lines 143-145; helpers at 194-207)

- [ ] **Step 1: Replace LabeledContent rows with RelationChip rows**

Each row that used `LabeledContent { Text(tier1Names) }` becomes a chip-row that resolves IDs to chips:

```swift
private func relationRow(label: String, ids: [String]) -> some View {
    HStack(alignment: .top) {
        Text(label).foregroundStyle(.secondary)
        FlowLayout(spacing: 4) {
            ForEach(ids, id: \.self) { id in
                if let ref = relationResolver(id) {
                    RelationChip(icon: ref.iconName, title: ref.title)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Delete `tier1Names` / `tier2Names` / `tier3Names` helpers** (no callers after conversion).

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(frontmatter-inspector): convert tier LabeledContent to RelationChip rows"
```

##### Task 15.5 — `ItemWindow.relationLine` → `RelationChip`

**Files:**
- Modify: `Pommora/Pommora/ItemWindow/ItemWindow.swift`

- [ ] **Step 1: Replace `relationLine` body with `RelationChip` rendering** (same pattern as 15.2-15.4).

- [ ] **Step 2: Delete `relationLine` helper.**

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(item-window): convert relationLine to RelationChip rendering"
```

---

#### Phase 16 — Tier-column injection in Tables

##### Task 16.1 — Allowlist tier IDs in `PropertyColumnBuilder` reserved-ID filter

**Files:**
- Modify: `Pommora/Pommora/Vaults/PropertyColumnBuilder.swift:67`
- Test: `Pommora/PommoraTests/Vaults/PropertyColumnBuilderTests.swift`

- [ ] **Step 1: Add failing test**

```swift
@Test func columnBuilderEmitsTierColumnsByDefault() {
    let pageType = TestPageType.seed(properties: [])  // no user-defined props
    let view = SavedView(visibleProperties: [], hiddenProperties: [])
    let columns = PropertyColumnBuilder.columns(view: view, schema: pageType.resolvedProperties)
    let columnIDs = columns.map(\.id)
    #expect(columnIDs.contains(ReservedPropertyID.tier1))
    #expect(columnIDs.contains(ReservedPropertyID.tier2))
    #expect(columnIDs.contains(ReservedPropertyID.tier3))
}

@Test func columnBuilderPlacesTierColumnsRightmostInProjectTopicSpaceOrder() {
    let pageType = TestPageType.seed(properties: [/* Author, Status */])
    let view = SavedView(visibleProperties: ["author", "status"])
    let columns = PropertyColumnBuilder.columns(view: view, schema: pageType.resolvedProperties)
    let lastThree = columns.suffix(3).map(\.id)
    #expect(lastThree == [ReservedPropertyID.tier3, ReservedPropertyID.tier2, ReservedPropertyID.tier1])
}
```

- [ ] **Step 2: Update filter + ordering**

```swift
enum PropertyColumnBuilder {
    static func columns(view: SavedView, schema: [PropertyDefinition]) -> [PropertyColumn] {
        let hiddenSet = view.hiddenProperties

        // User-defined columns (existing logic — excludes ALL reserved IDs including tier)
        let userColumns = schema.filter { def in
            !hiddenSet.contains(def.id) && !ReservedPropertyID.isReserved(def.id)
        }

        // Tier columns at rightmost, reverse-order: Project / Topic / Space
        let tierOrder = [ReservedPropertyID.tier3, ReservedPropertyID.tier2, ReservedPropertyID.tier1]
        let tierColumns = tierOrder.compactMap { tierID -> PropertyDefinition? in
            guard !hiddenSet.contains(tierID) else { return nil }
            return schema.first(where: { $0.id == tierID })
        }

        return (userColumns + tierColumns).map { PropertyColumn(definition: $0) }
    }
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(table): inject tier columns rightmost (Project/Topic/Space) in PropertyColumnBuilder"
```

##### Task 16.2 — Allowlist tier IDs in `PropertyVisibilityPane`

**Files:**
- Modify: `Pommora/Pommora/Vaults/PropertyVisibilityPane.swift:193-207`

- [ ] **Step 1: Add failing test**

```swift
@Test func visibilityPaneShowsTierRowsAsHideable() {
    let pageType = TestPageType.seed()
    let pane = PropertyVisibilityPane(pageType: pageType)
    let rows = pane.parentTypeProperties()
    let rowIDs = rows.map(\.id)
    #expect(rowIDs.contains(ReservedPropertyID.tier1))
    #expect(rowIDs.contains(ReservedPropertyID.tier2))
    #expect(rowIDs.contains(ReservedPropertyID.tier3))
}
```

- [ ] **Step 2: Update filter**

```swift
private func parentTypeProperties() -> [PropertyDefinition] {
    let allowedReservedIDs: Set<String> = [
        ReservedPropertyID.modifiedAt,
        ReservedPropertyID.tier1,
        ReservedPropertyID.tier2,
        ReservedPropertyID.tier3,
    ]
    return schema.filter { def in
        !ReservedPropertyID.isReserved(def.id) || allowedReservedIDs.contains(def.id)
    }
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(visibility): allowlist tier IDs in PropertyVisibilityPane filter"
```

_Tier column sort/filter inherits whatever the generic relation sort/filter wiring becomes (SavedView stubs at lines 38-40; deferred per Phase 22). No tier-specific work in this phase._

---

#### Phase 17 — Context detail + Env injection

##### Task 17.1 — Inject `PommoraIndex` via environment

**Files:**
- Modify: `Pommora/Pommora/ContentView.swift:325-331` (unwrap chain) + `:339-344` (environment chain)
- Test: build verification

- [ ] **Step 1: Update unwrap chain**

Add PommoraIndex to the existing optional-unwrap guard:

```swift
// ContentView.swift line ~325-331
if let spaceMgr = spaceManagerOpt,
   let vaultMgr = pageTypeManagerOpt,
   let itemTypeMgr = itemTypeManagerOpt,
   let contentMgr = pageContentManagerOpt,
   let itemContentMgr = itemContentManagerOpt,
   let settingsMgr = settingsManagerOpt,
   let index = pommoraIndexOpt {           // NEW
    // … detail view branches
}
```

- [ ] **Step 2: Update environment chain**

Add `.environment(index)` to the `.environment(...)` cascade at lines 339-344:

```swift
SidebarDetailView(/* … */)
    .environment(spaceMgr)
    .environment(vaultMgr)
    .environment(itemTypeMgr)
    .environment(contentMgr)
    .environment(itemContentMgr)
    .environment(settingsMgr)
    .environment(index)                    // NEW
```

- [ ] **Step 3: Verify build**

Background Agent: `xcodebuild build`. Expected SUCCEEDED. (No new test; existing PommoraIndex tests stay green.)

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(content-view): inject PommoraIndex via environment chain"
```

##### Task 17.2 — Stub `LinkedFromDropdown`

**Files:**
- Create: `Pommora/Pommora/Detail/LinkedFromDropdown.swift`
- Test: `Pommora/PommoraTests/Detail/LinkedFromDropdownStubTests.swift`

- [ ] **Step 1: Add stub**

```swift
/// **Phase 17 STUB** — Context-side reverse view.
///
/// In v1 this is a bare scaffold. The real implementation ships with the future
/// Context-detail dropdown surface plan (per the brainstorming "defer per Nathan"
/// decision). At that point this file becomes the real dropdown button + popover
/// listing entities whose tier1/tier2/tier3 array points at the given context.
///
/// **Supporting infrastructure that DOES ship in v1:**
/// - `IndexQuery.incomingRelations(targetID:)` (Phase 9)
/// - `PommoraIndex` environment injection (Phase 17.1)
///
/// **Deferred to the future Context-views plan:**
/// - `EntityStateRef.iconName` extension
/// - `EntityKind.displayLabel` extension
/// - `EntityStateRef → SidebarSelection` resolver
/// - `ContextDetailPlaceholder` `@ViewBuilder footer:` slot
/// - Real popover button surface
/// - Aggregate-view header (TierConfig default label since per-Type overrides
///   diverge across contributing source Types)
struct LinkedFromDropdown: View {
    let targetID: String
    let targetKind: EntityKind

    var body: some View {
        EmptyView()
    }
}
```

- [ ] **Step 2: Add basic test**

```swift
@Test func linkedFromDropdownStubRendersAsEmptyView() {
    let dropdown = LinkedFromDropdown(targetID: "anything", targetKind: .space)
    // Stub verification: compile-only test, ensures the type exists.
    _ = dropdown
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(detail): stub LinkedFromDropdown (real impl ships with Context-views plan)"
```

_Component Library Gallery entry for LinkedFromDropdown lands when the real implementation ships in the future Context-views plan (an EmptyView stub has nothing to render in the gallery)._

---

#### Phase 18 — Context delete cleanup (source-side cascade)

Per Nathan's decision: when a Context (Space/Topic/Project) is deleted, the deletion routine walks all source entities that reference it (via the `relations` table reverse query) and strips the Context's ID from their tier arrays.

##### Task 18.1 — Add `unlinkTier(contextID:)` to `PageContentManager`

**Files:**
- Modify: `Pommora/Pommora/Vaults/PageContentManager+CRUD.swift`
- Test: `Pommora/PommoraTests/Vaults/PageContentManagerUnlinkTests.swift`

- [ ] **Step 1: Add failing test**

```swift
@Test func unlinkTierRemovesContextIDFromAllPagesTier1Arrays() async throws {
    // Seed: 2 Pages with tier1: [spaceA_id, spaceB_id]
    // Call: pageContentManager.unlinkTier(contextID: spaceA_id, tier: 1)
    // Expect: both pages now have tier1: [spaceB_id]; spaceA_id removed
}

@Test func unlinkTierAcrossTier2AndTier3() async throws {
    // Mirror test for tier2 + tier3
}
```

- [ ] **Step 2: Implement method**

```swift
extension PageContentManager {
    /// Removes the specified context ID from the tier{N} array of every Page that
    /// references it. Atomically saves each affected Page via AtomicYAMLMarkdown.
    /// Called by SpaceManager/TopicManager/ProjectManager delete routines.
    func unlinkTier(contextID: String, tier: Int) async throws {
        let propertyID: String
        switch tier {
        case 1: propertyID = ReservedPropertyID.tier1
        case 2: propertyID = ReservedPropertyID.tier2
        case 3: propertyID = ReservedPropertyID.tier3
        default: return  // invalid tier — no-op
        }

        // Query relations table for incoming references
        let sources = try await index.query.incomingRelations(targetID: contextID)
        let pageSources = sources.filter { $0.kind == .page }

        for sourceRef in pageSources {
            guard var page = try await loadPage(id: sourceRef.id) else { continue }
            if case .relation(var ids) = page.frontmatter.properties[propertyID] ?? .relation([]) {
                ids.removeAll { $0 == contextID }
                page.frontmatter.properties[propertyID] = .relation(ids)
                try await savePage(page)  // atomically writes via AtomicYAMLMarkdown
            }
        }

        // Relations rows will be cleaned up automatically when IndexUpdater
        // observes the page-save events. If updater isn't on the same actor,
        // a final cleanup pass deletes orphaned relations rows.
    }
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(pages): add unlinkTier(contextID:tier:) for context-delete cascade"
```

##### Task 18.2 — Mirror for `ItemContentManager`

Same pattern, but operates on Items + AtomicJSON.

- [ ] **Steps 1-4: Mirror Task 18.1 for ItemContentManager. Commit.**

##### Task 18.3 — Mirror for `AgendaTaskManager`

- [ ] **Steps 1-4: Mirror for AgendaTaskManager. Commit.**

##### Task 18.4 — Mirror for `AgendaEventManager`

- [ ] **Steps 1-4: Mirror for AgendaEventManager. Commit.**

##### Task 18.5 — Wire Context delete to cascade

**Files:**
- Modify: `Pommora/Pommora/Contexts/SpaceManager.swift` (delete routine)
- Modify: `Pommora/Pommora/Contexts/TopicManager.swift`
- Modify: `Pommora/Pommora/Contexts/ProjectManager.swift`
- Test: `Pommora/PommoraTests/Contexts/ContextDeleteCascadeTests.swift`

- [ ] **Step 1: Add failing integration test**

```swift
@Test func deletingSpaceRemovesItsIDFromAllReferencingEntities() async throws {
    // Seed: Space + 2 Pages + 1 Item + 1 AgendaTask, each with tier1: [spaceID]
    // Delete the Space
    // Expect: all 4 entities have tier1 arrays without spaceID
    // Expect: no relations table rows reference spaceID
}
```

- [ ] **Step 2: Wire into delete routine**

```swift
extension SpaceManager {
    func delete(_ space: Space) async throws {
        let contextID = space.id

        // Cascade-clean references before deleting the Space file itself
        try await pageContentManager.unlinkTier(contextID: contextID, tier: 1)
        try await itemContentManager.unlinkTier(contextID: contextID, tier: 1)
        try await agendaTaskManager.unlinkTier(contextID: contextID, tier: 1)
        try await agendaEventManager.unlinkTier(contextID: contextID, tier: 1)

        // Then delete the Space's own file
        try await deleteSpaceFile(at: space.url)

        // IndexUpdater observes the deletions and removes Space from `spaces` table
    }
}
```

Mirror for TopicManager (tier 2) and ProjectManager (tier 3).

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(contexts): cascade-clean references when deleting Space/Topic/Project"
```

---

#### Phase 19 — Migration + Adoption

The largest single phase. Eight migration sub-phases land as separate tasks; each ships green, each is testable independently.

##### Task 19.1 — Add Agenda walkers to `PropertyIDMigration`

**Files:**
- Modify: `Pommora/Pommora/Nexus/PropertyIDMigration.swift`
- Test: `Pommora/PommoraTests/Nexus/PropertyIDMigrationAgendaTests.swift`

- [ ] **Step 1: Add failing tests**

```swift
@Test func applyAgendaTaskSchemaMigratesPropertyShape() async throws { /* … */ }
@Test func applyAgendaEventSchemaMigratesPropertyShape() async throws { /* … */ }
```

- [ ] **Step 2: Add walkers**

```swift
extension PropertyIDMigration {
    private static func applyAgendaTaskSchema(_ migration: TypeMigration, into report: inout Report) {
        // Mirror applyPageType structure:
        // - Open the AgendaTaskSchema sidecar at NexusPaths.taskSchemaURL
        // - For each Property entry in legacy shape, transform to PropertyDefinition
        // - Stage via SchemaTransaction
        // - Walk task files for value-shape migration
    }

    private static func applyAgendaEventSchema(_ migration: TypeMigration, into report: inout Report) {
        // Mirror for AgendaEventSchema + .event.json files
    }
}
```

- [ ] **Step 3: Wire into migration dispatch**

The top-level migration entry point that calls `applyPageType` / `applyItemType` now also calls the new Agenda walkers.

- [ ] **Step 4: Run tests** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(migration): add Agenda walkers to PropertyIDMigration"
```

##### Task 19.2 — Build Collection-parent map via `NexusAdopter` pass

**Files:**
- Modify: `Pommora/Pommora/Nexus/NexusAdopter.swift`
- Modify: `Pommora/Pommora/Nexus/PropertyIDMigration.swift`
- Test: `Pommora/PommoraTests/Nexus/CollectionParentMapTests.swift`

- [ ] **Step 1: Add failing test**

```swift
@Test func collectionParentMapResolvesEveryCollectionToParentType() async throws {
    // Seed: PageType "Books" + PageCollection "Fiction" + PageCollection "Non-fiction"
    // Build map; expect map["fiction_id"] == "books_id"
}
```

- [ ] **Step 2: Implement map builder**

```swift
struct CollectionParentMap {
    let pageCollections: [String: String]  // collectionID → parentPageTypeID
    let itemCollections: [String: String]

    static func build(adopter: NexusAdopter) async throws -> CollectionParentMap {
        // Walk every Type's collection sub-folders via adopter.walkDepth1
        // For each collection sidecar found, record the relationship
    }
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(migration): build Collection-parent map for scope-case migration"
```

##### Task 19.3 — Migration phase: value-shape wrap

Transform every legacy single `$rel` tagged object into a one-element array. The decoder tolerance from Phase 6 means files load correctly today; this migration normalizes the on-disk shape so future reads are uniform.

- [ ] **Step 1: Add failing test**

```swift
@Test func valueShapeMigrationWrapsSingleRelObjectsIntoArray() async throws {
    // Seed file with `prop_X: {"$rel": "01HABC"}`
    // Run migration
    // Verify file now has `prop_X: [{"$rel": "01HABC"}]`
}
```

- [ ] **Step 2: Implement migration step inside applyPageType / applyItemType**

For each property whose Codable decode produces `.relation([single])` AND whose on-disk JSON shape is the legacy single-object form, re-encode using the new array shape and stage the file save. Emit `MigrationEvent.relationShapeWrapped(...)` per occurrence.

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(migration): value-shape wrap (single \$rel → array)"
```

##### Task 19.4 — Migration phase: `allows_multiple` strip

- [ ] **Step 1: Add test** for the field being stripped from every PropertyDefinition entry.

- [ ] **Step 2: Implement in walkers** — scan each PropertyDefinition, if `allows_multiple` key is present in the raw JSON, re-emit without it. Emit `MigrationEvent.allowsMultipleStripped(...)`.

- [ ] **Step 3: Run tests + Commit**

```bash
git commit -m "feat(migration): strip allows_multiple from schemas"
```

##### Task 19.5 — Migration phase: `relation_scope` → `relation_target` key rename

- [ ] **Step 1: Add test** for the JSON key transition.

- [ ] **Step 2: Implement** — re-emit each PropertyDefinition with the new key. Decoder already accepts both per Phase 7.3.

- [ ] **Step 3: Run tests + Commit**

```bash
git commit -m "feat(migration): rename on-disk relation_scope key to relation_target"
```

##### Task 19.6 — Migration phase: `page_collection` → `page_type` via parent map

- [ ] **Step 1: Add test** — property with `relation_target: { kind: "page_collection", id: "c1" }` migrates to `{ kind: "page_type", id: "<parent_of_c1>" }`.

- [ ] **Step 2: Implement** — for each PropertyDefinition with collection scope, look up parent via Collection-parent map, rewrite the target. Emit `MigrationEvent.pageCollectionRewritten`.

- [ ] **Step 3: Run tests + Commit**

```bash
git commit -m "feat(migration): rewrite page_collection scope to parent page_type"
```

##### Task 19.7 — Migration phase: `item_collection` → `item_type`

Mirror Task 19.6 for items.

- [ ] **Step 1-3: Mirror + commit**

##### Task 19.8 — Migration phase: `context_tier` drop with explicit acknowledgment

- [ ] **Step 1: Add test** — property with `relation_target: { kind: "context_tier", tier: 2 }` is removed from the schema after migration AND triggers a MigrationEvent that requires user acknowledgment.

- [ ] **Step 2: Implement** — surface a list of contextTier-scoped properties to AdoptionPreviewView; require explicit checkbox before commit. On commit, remove them from the schema and emit `MigrationEvent.contextTierDropped`. **No data loss** because tier values were never stored on these legacy properties anyway (tier values live in `tier1`/`tier2`/`tier3` frontmatter root, not in custom contextTier-targeted properties); the schema entry being removed only removes the schema declaration.

- [ ] **Step 3: Run tests + Commit**

```bash
git commit -m "feat(migration): drop context_tier-scoped properties with user acknowledgment"
```

##### Task 19.9 — Migration phase: Agenda `Property` → `PropertyDefinition`

- [ ] **Step 1: Add test** — load a legacy `_taskconfig.json` with `Property` shape, run migration, verify it now uses `PropertyDefinition` (with stable `_*` IDs).

- [ ] **Step 2: Implement** — walker assigns stable reserved IDs to existing Property entries (preserve user names; generate IDs from `_due_date`, `_priority`, etc. for known built-ins; ULID for any user-added). Emit `MigrationEvent.agendaSchemaUnified`.

- [ ] **Step 3: Run tests + Commit**

```bash
git commit -m "feat(migration): unify Agenda Property→PropertyDefinition shape"
```

##### Task 19.10 — Broaden `needsMigration` triggers

- [ ] **Step 1: Add test** — a nexus whose sidecars have `schemaVersion = 1` but still contain `relation_scope` or `allows_multiple` triggers migration.

- [ ] **Step 2: Implement** — scan sidecars for the legacy field names; trigger migration if any present.

```swift
static func needsMigration(_ schema: PageType) -> Bool {
    if schema.schemaVersion < 2 { return true }
    if schema.properties.contains(where: { $0.id.isEmpty }) { return true }
    // NEW: detect legacy field presence
    if rawSchemaContainsKey(schema, key: "relation_scope") { return true }
    if rawSchemaContainsKey(schema, key: "allows_multiple") { return true }
    return false
}
```

Bump `schemaVersion` to 2 after successful migration.

- [ ] **Step 3: Run tests + Commit**

```bash
git commit -m "feat(migration): broaden needsMigration triggers for legacy fields"
```

##### Task 19.11 — Extend `AdoptionPreviewView` with `context_tier` drop acknowledgment

**Files:**
- Modify: `Pommora/Pommora/Nexus/AdoptionPreviewView.swift`
- Test: `Pommora/PommoraTests/Nexus/AdoptionPreviewViewTests.swift`

- [ ] **Step 1: Add failing test**

```swift
@Test func adoptionPreviewBlocksCommitWhenContextTierDropsArePending() {
    // Mount preview view with MigrationEvent.contextTierDropped events
    // Verify the "Continue" button is disabled until the user checks the acknowledgment box
}
```

- [ ] **Step 2: Add acknowledgment UI**

Add a section to the preview view that renders contextTier drops with their owning Type, the dropped property name, and an explicit "I understand these will be removed" checkbox. Disable the Continue button until checked.

- [ ] **Step 3: Run tests + Commit**

```bash
git commit -m "feat(adoption-preview): add explicit acknowledgment UI for context_tier drops"
```

##### Task 19.12 — Surface all MigrationEvent kinds in AdoptionPreviewView

- [ ] **Step 1: Add test** verifying each MigrationEvent case renders an appropriate row in the preview.

- [ ] **Step 2: Implement** — switch over `MigrationEvent` cases, render per-case rows with counts/details.

- [ ] **Step 3: Run tests + Commit**

```bash
git commit -m "feat(adoption-preview): surface all MigrationEvent cases in preview"
```

---

#### Phase 20 — `tier_links` retirement

##### Task 20.1 — Re-scan files during migration to populate `relations` from tier{1,2,3} frontmatter

Since tier values continue to live on disk at frontmatter root, the migration can populate `relations` table rows from scanning every operational entity's frontmatter. This happens BEFORE the tier_links drop so reverse queries work continuously.

**Files:**
- Modify: `Pommora/Pommora/Nexus/PropertyIDMigration.swift`
- Test: `Pommora/PommoraTests/Nexus/TierToRelationsBackfillTests.swift`

- [ ] **Step 1: Add failing test**

```swift
@Test func tierToRelationsBackfillPopulatesRelationsTable() async throws {
    // Seed: Page with tier1: ["spaceA"], tier2: ["topicB"]
    // Run migration
    // Verify `relations` table contains 2 rows (one per tier value) targeting spaceA / topicB
}
```

- [ ] **Step 2: Implement backfill step**

For each operational entity walked during migration, extract its `tier1` / `tier2` / `tier3` arrays from frontmatter root. For each value in each array, insert a `relations` row with `source_id = entity.id`, `source_kind = <kind>`, `target_id = <tierValue>`, `target_kind = "context_tier_<N>"`, `property_id = _tier<N>`.

- [ ] **Step 3: Run tests + Commit**

```bash
git commit -m "feat(migration): backfill relations table from tier1/2/3 frontmatter fields"
```

##### Task 20.2 — Drop `tier_links` DDL

**Files:**
- Modify: `Pommora/Pommora/Index/IndexSchema.swift:128-136` (tier_links DDL)
- Test: existing index schema tests

- [ ] **Step 1: Remove the table from `IndexSchema.apply()`**

Delete the `CREATE TABLE IF NOT EXISTS tier_links ...` block and its indexes. Add a `DROP TABLE IF EXISTS tier_links` statement that runs once per schema migration. (GRDB pattern: track schema version in `pommora_schema_version` PRAGMA or similar; bump on apply.)

- [ ] **Step 2: Sweep tier_links references**

```bash
grep -rn "tier_links" Pommora/ --include='*.swift'
```

Remove every read/write reference (`IndexBuilder` lines 662, 665, 668, delete 404; `IndexUpdater` lines 135, 224, 417, insert 425). Their tier-emit logic now flows through the regular `relations` table emit path (which was updated in Phase 9.5 to handle context_tier targets correctly).

- [ ] **Step 3: Run full test suite** — PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(index): drop tier_links table; all tier rows now flow through relations table"
```

_Legacy `pageCollection` / `itemCollection` case retention is documented inline in `RelationTarget` (Phase 7.2 doc-comments) and listed in Phase 22's deferred items. No standalone task._

---

#### Phase 21 — Documentation rewrite (gated on code-as-landed verification)

Documentation lands LAST — after code is landed and verified.

##### Rewrite Rule (apply to every doc body Phase 21 touches)

Existing docs that contradict the v1 Relations design get **rewritten in place to read as correct** — as if they always described the current design. **No amendment notes. No evolution framing.** A reader encountering Properties.md (or any other touched doc) for the first time sees the current design as **the design**. No trace of prior shape. The doc reads forward-only.

**Forbidden language anywhere in a doc body:** "previously," "now" (contrastive), "updated," "evolves," "refines," "next iteration," "scaffolding," "durable shape," "revised," "reversed," "instead of," "no longer," "still" (contrastive), "remains" (contrastive), "in v0.3.0" (contrastive), "the old," "the new" (contrastive), "moved to," "we used to," "deprecated."

**Exceptions:**
- `History.md` — chronological ship log. Rewrite the v0.3.0 Properties entry in place to describe the v1 Relations shape as if it shipped at v0.3.0. Add a new v0.3.1.x entry covering the landed work with the one acknowledgment line.
- `Handoff.md` — working snapshot. Update Current state and Next focuses additively to reflect today; remove resolved Fix Log entries.
- This plan document + commit messages — describe the work itself; not subject to the rule.

##### Files to touch

| File | Change |
|---|---|
| `.claude/CLAUDE.md` | Core Principle at lines 47-48 rewritten in place — chip-everywhere rendering, array-shape storage, tier-as-property, wikilink distinction. Branch quirk #16 line citation updated from "237" to "325-331". |
| `.claude/Features/Properties.md` | Largest rewrite — Relation row in type catalog; § Relation target (renamed from § Relation scope); § Dual relations expanded for Agenda; new § Context-side linked-from picker; new § Agenda Tasks and Events as relation targets; new § Built-in tier columns in Table views; vocabulary scrub "scope" → "target" throughout. |
| `.claude/Features/Domain-Model.md` | Tier rendering prose updated (PropertyEditorRow path; pre-configured Table columns). |
| `.claude/Features/Contexts.md` | Linked-from section added (describes the future surface); tier-relation dual surface specified. |
| `.claude/Features/PageTypes.md` | JSON example cleanup — drop `allows_multiple`, rename `relation_scope` → `relation_target`, use array shape. Pre-configured tier-column mention. |
| `.claude/Features/Items.md` | Tier-row prose updated. Pre-configured tier-column mention. |
| `.claude/Features/Agenda.md` | New § Agenda Tasks and Events as relation targets. Reflects PropertyDefinition shape (Agenda schemas were unified in Phase 4). |
| `.claude/Features/Pages.md` | Wikilink-vs-relation distinction made explicit. |
| `.claude/Features/PageEditor.md` | Body-only wikilink statement. Note: actual wikilink content is at line 66 (verify before edit). |
| `.claude/Features/Homepage.md` | Widget rendering note — chips for relation values; inline-styled text for wikilinks inside embedded previews. |
| `.claude/Features/Architecture.md` | New § Context-side reverse-view query shape (describes `incomingRelations(targetID:)`). Note: SQLite section content at line 13 (verify before edit). |
| `.claude/History.md` | Rewrite v0.3.0 Properties entry in place; add v0.3.1.x entry: "**Relations property layer rebuilt per the Relations Redesign plan.**" |
| `.claude/Guidelines/Paradigm-Decisions.md` | Amend entry #1 (line 44) to describe array-wrapped tagged-object encoding. Add net-new entries #8-#12: chip-as-sole-primitive, RelationTarget 4-case user-creatable + internal contextTier, Context-side LinkedFromDropdown pattern, tier-as-property registry merge, tier label override resolution order. |
| `.claude/Handoff.md` | Additive update — Current state mentions Relations v1 shipped; remove resolved Fix Log entries. |

##### Task 21.1 — Spot-check landed code before docs

For each file in the touch table, open the landed code and confirm: section locations, line numbers, type names, and method signatures match what the planned doc edits describe. Adjust per-doc tasks inline where the executor finds drift (line numbers shifted, sections renamed during implementation, etc.). No formal agent dispatch — this is a 10-15 minute scan, not a verification phase.

- [ ] **Step 1: Open each file in the touch table in turn; cross-check planned change against actual state.**

- [ ] **Step 2: Adjust the per-doc tasks below where line citations or section names need updating.**

##### Task 21.2 — Update `.claude/CLAUDE.md`

Per verification, the relevant lines are 47-48 (Core Principle "Relations stored by ID, displayed by title", NOT HARD RULES at 21-27). Rewrite the Core Principle in place to describe the v1 shape. Update branch quirk #16 line citation from "line 237" to "lines 325-331".

- [ ] **Step 1: Rewrite lines 47-48 in place**

Per the Rewrite Rule, no amendment language. Read-as-if-always-correct.

- [ ] **Step 2: Update branch quirk #16**

```
16. **Every `@Environment(X.self)` declared on a detail view must be injected at `ContentView.detail`'s `.environment(...)` chain.** Locked 2026-05-25 via `c8b3cbc`. … Symptom is "crash on first selection routing to that view." When adding a new env to a detail view, ALSO add it to the optional-unwrap chain at `ContentView.swift:325-331` AND the `.environment(...)` chain immediately after at `:339-344`.
```

- [ ] **Step 3: Commit**

```bash
git commit -m "docs(claude-md): rewrite Relations core principle for v1; fix branch quirk #16 line citation"
```

##### Task 21.3 — `Features/Properties.md` largest rewrite

Per pre-execution verification, current sections present:
- § Property type catalog (line 45)
- § Relation scope (lines 236-259) → rename to § Relation target; vocabulary scrub
- § Dual relations (lines 262-287)
- § Creating a Relation property — guided flow (lines 289-306)
- § RelationChip rendering (line 459)

Apply per the Rewrite Rule:
- Rename § Relation scope → § Relation target throughout
- Scrub "scope" vocabulary → "target" everywhere
- Rewrite § Dual relations to include Agenda-as-target case
- Add new § Context-side linked-from picker (describes the stubbed-then-deferred LinkedFromDropdown surface)
- Add new § Agenda Tasks and Events as relation targets
- Add new § Built-in tier columns in Table views (rightmost; Project/Topic/Space order; reorderable)
- Remove the guided-flow mention that "context-tier omits reverse-name step" (the wizard hides context_tier, so the step never appears)
- Drop `allows_multiple` from all JSON examples
- Update all on-disk JSON examples to use array shape + `relation_target` key

- [ ] **Step 1: Apply all edits per the Rewrite Rule above**

- [ ] **Step 2: Verify no forbidden language**

```bash
grep -i -E "previously|now|updated|evolves|refines|next iteration|scaffolding|durable shape|revised|reversed|instead of|no longer|deprecated|the old|the new|moved to|we used to" .claude/Features/Properties.md
```

Expected: zero matches in doc body (heading anchors OK).

- [ ] **Step 3: Commit**

```bash
git commit -m "docs(properties): rewrite Properties.md for v1 Relations shape"
```

##### Task 21.4 — `Features/Domain-Model.md`

Per verification, tier rendering prose needs update. Add: tier values flow through PropertyEditorRow like any property; default-visible Table columns at rightmost positions.

- [ ] **Step 1: Rewrite tier sections in place**

- [ ] **Step 2: Commit**

```bash
git commit -m "docs(domain-model): update tier rendering prose for v1"
```

##### Task 21.5 — `Features/Contexts.md`

Add Linked-from section (descriptive — the future surface mentioned only); tier-relation dual surface specification.

- [ ] **Step 1: Apply rewrites + commit**

##### Task 21.6 — `Features/PageTypes.md`

JSON example cleanup (drop allows_multiple, rename relation_scope → relation_target, use array shape). Add pre-configured tier-column mention.

- [ ] **Step 1: Apply rewrites + commit**

##### Task 21.7 — `Features/Items.md`

Tier-row prose. Pre-configured tier-column mention.

- [ ] **Step 1: Apply rewrites + commit**

##### Task 21.8 — `Features/Agenda.md`

Add new § Agenda Tasks and Events as relation targets. Document the unified PropertyDefinition shape (so the file reads forward-only).

- [ ] **Step 1: Apply rewrites + commit**

##### Task 21.9 — `Features/Pages.md`

Add wikilink-vs-relation distinction (wikilinks are inline styled colored text in the body; relations are frontmatter property values rendered as chips in the property panel).

- [ ] **Step 1: Apply rewrites + commit**

##### Task 21.10 — `Features/PageEditor.md`

Per verification, actual wikilink content is at line 66 (not 69). Body-only wikilink statement.

- [ ] **Step 1: Apply rewrites + commit**

##### Task 21.11 — `Features/Homepage.md`

Widget rendering note: chips for relation values; inline-styled text for wikilinks inside embedded previews.

- [ ] **Step 1: Apply rewrites + commit**

##### Task 21.12 — `Features/Architecture.md`

Per verification, SQLite section content at line 13 (not 14). Add new § Context-side reverse-view query shape (describes `incomingRelations(targetID:)` against the `relations` table).

- [ ] **Step 1: Apply rewrites + commit**

##### Task 21.13 — `History.md`

Rewrite v0.3.0 Properties entry in place to describe v1 shape (per Rewrite Rule). Add v0.3.1.x entry with the one-line acknowledgment: "**Relations property layer rebuilt per the Relations Redesign plan.**"

- [ ] **Step 1: Apply rewrites + commit**

```bash
git commit -m "docs(history): rewrite v0.3.0 Properties entry; add v0.3.1.x Relations rebuilt entry"
```

##### Task 21.14 — `Guidelines/Paradigm-Decisions.md`

Per verification, 7 entries today. Entry #1 (line 44) describes `{"$rel": "<ULID>"}` tagged-object encoding — AMEND in place to describe array-wrapped shape. Add 5 new entries:
- #8: Chip-everywhere — RelationChip is the single rendering primitive for relation values
- #9: RelationTarget 4-case user-creatable + internal contextTier
- #10: Context-side reverse view is a settings-style dropdown (LinkedFromDropdown), not a property panel
- #11: Tier-as-property — Spaces/Topics/Projects are pre-configured relation properties merged via BuiltInRelationProperties
- #12: Tier label override resolution — per-Type sidecar override → TierConfig default → hardcoded fallback

- [ ] **Step 1: Apply rewrites + commit**

```bash
git commit -m "docs(paradigm): amend #1; add #8-#12 Relations v1 decisions"
```

##### Task 21.15 — `Handoff.md`

Additive update: Current state mentions Relations Redesign Plan execution complete; Next focuses absorbs any remaining Fix Log items; Fix Log entries that this work resolved get removed.

- [ ] **Step 1: Apply update + commit**

---

#### Phase 22 — Deferred items log

Document what defers to future plans so they don't get forgotten.

##### Task 22.1 — Extend `.claude/Features/Prospects.md` with deferred items

`Prospects.md` is Pommora's post-v1 features doc. Deferred Relations work belongs there alongside synced blocks, graph view, etc.

**Files:**
- Modify: `.claude/Features/Prospects.md`

- [ ] **Step 1: Append the deferred items as new entries in `Prospects.md`**

```markdown
### Relations Redesign — Deferred Items

Items deferred from the v1 Relations Redesign plan. Each carries enough context for a follow-on plan to pick up.

#### Deferred to future Context-views plan

- **LinkedFromDropdown** real implementation. Stub exists at `Pommora/Pommora/Detail/LinkedFromDropdown.swift`. Real surface is a dropdown button (modeled on NavDropdown + View Settings) that lists every operational entity whose tier1/2/3 array points at the Context. Powered by `IndexQuery.incomingRelations(targetID:)` (already shipped). Aggregate-view header uses TierConfig default label (since per-Type overrides diverge across contributing source Types).
- **`EntityStateRef.iconName`** extension wired to SettingsManager-resolved icon defaults.
- **`EntityKind.displayLabel`** extension wired to SettingsManager labels.
- **`EntityStateRef → SidebarSelection` resolver.** Required by LinkedFromDropdown navigation. The full entity (not just ID) is needed because `SidebarSelection.page(Page)` etc. take entities — requires content-manager lookups by ID.
- **`ContextDetailPlaceholder`** `@ViewBuilder footer:` slot OR inline rewrite at each `SidebarDetailView` Context branch (Space / Topic / Project). Recommend footer slot to preserve DRY.

#### Deferred to IconConfig effort

- **Tier property icon overrides** at the nexus-default level. Today `BuiltInRelationProperties` falls back from sidecar-override to hardcoded SF Symbol (building.2 / tag / briefcase). When IconConfig ships, the fallback chain extends to: sidecar override → IconConfig default → hardcoded fallback.

#### Deferred to a post-v1 picker redesign

- **Hierarchical value-assignment picker UI.** v1 uses flat `ChipDropdown` rows for every target. Hierarchical surfaces defer to a follow-on redesign:
  - Vault target: Collections expand to member Pages; root Pages render at top
  - Item Type target: Sets expand to member Items; root Items at top
  - Topics target: parent Topics + nested sub-Topics; multi-parent Topics render duplicated for navigation
  - Projects target: Projects nested under their parent Topic; tier-skipped Projects under their Space
- **Generic `HierarchicalEntityMenu` primitive** to power those surfaces (retired from v1 plan; resurface if the redesign confirms a tree picker is the right shape).
- **Sort/filter beyond alphabetical** on relation columns. v1 alphabetical-on-resolved-title is the floor; later redesign may surface relation-specific filter operators (`linked to`, `not linked to`, etc.).

#### Deferred per Pommora roadmap

- **Column reorder** (current Handoff Fix Log entry #3). Generic Table column reorder mechanism; tier columns inherit it once landed.
- **Relation sort/filter** wiring. `SavedView` has sort/filter/group stubs ready (lines 38-40); UI wiring + RelationTarget-aware sort comparator absent today.
- **Cleanup of `pageCollection` / `itemCollection` enum cases** from `RelationTarget`. Cases retained for legacy on-disk read-tolerance; remove after telemetry confirms zero observed instances.
- **Migration in-flight write locking.** Cross-Type concurrent writes during migration unprotected today; SchemaTransaction is per-Type atomic, but two Types migrating simultaneously have no inter-Type lock. Acceptable for v1 (migration happens once at nexus open with no other writers); revisit if multi-window writes during open become possible.
- **Polymorphic `relations` table FK enforcement.** Current plan handles deletion cascades at the application layer (Phase 18). DB-level FKs would require either per-target-kind tables or triggers; deferred indefinitely unless app-level cleanup proves insufficient.
```

- [ ] **Step 2: Commit**

```bash
git commit -m "docs(prospects): log items deferred from v1 Relations Redesign for follow-on plans"
```

---

#### Execution notes

**Pre-flight per task:** Pull latest, confirm working tree clean (per branch quirk #11, never revert unattributed changes — surface in report).

**Per-task verification:** Run targeted test via background Agent:
```
xcodebuild test -project Pommora/Pommora.xcodeproj -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/<TestFileName>
```
Never run xcodebuild in foreground (branch quirk #14).

**Per-phase commit hygiene:** Each task ends with its own commit. Don't batch.

**SourceKit caveat:** Trust `xcodebuild`, not IDE squiggles (branch quirk #3). Especially common during rename phases — `Cannot find type X` on rename-completed types often clears after a full build.

**Swift format:** Locked at v0.2.4. Invoke via `swift format format --in-place ...` and `swift format lint --strict --recursive ...` (subcommand form). Direct `swift-format` binary is NOT on PATH (branch quirk #12).

**Pbxproj noise:** SymbolPicker/Yams entries auto-reorder on every build (branch quirk #7). Revert any incidental pbxproj diffs before commit.

---

#### Verification protocol for plan execution

After each phase, the executing agent (or session) verifies:

1. **All tests for the phase PASS** via targeted background-Agent run.
2. **No regressions** in adjacent test suites (broader background-Agent run if uncertain).
3. **Working tree only contains intended changes** (`git status` review).
4. **Commits are tight + focused** (one logical change per commit; commit messages describe the "why").

At plan completion, full verification:
- Full PommoraTests sweep — PASS.
- Adoption preview opens cleanly on a v0.3.0 test nexus (legacy schema) and presents all migration events correctly.
- Adoption commit applies cleanly; post-migration nexus loads with tier values intact, relations table populated, schema sidecars at v2.
- Manual UI smoke: open a fresh test nexus, create a relation property via the wizard targeting each of the 4 target types, populate values via the picker, verify chip rendering in PropertyPanel + Table + Inspector.

---

#### Source references

- Brainstorming decisions: this plan's header decision table (locks every open item + late-stage clarification)
- Codebase verification: 8 parallel Explore agent runs (synthesis informed plan structure throughout)
- Pommora HARD RULES: `.claude//CLAUDE.md:21-27`
- Branch quirks: `.claude//CLAUDE.md:165-202`
- Paradigm decisions registry: `.claude//Guidelines//Paradigm-Decisions.md`
- Properties spec (pre-rewrite): `.claude//Features//Properties.md`
- Pages spec (pre-rewrite): `.claude//Features//Pages.md`
