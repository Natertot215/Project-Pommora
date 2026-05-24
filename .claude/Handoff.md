### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`.

#### Current state (2026-05-24 EOD)

Today was a **Properties discovery + direction-shift + merge session** — no code shipped. Phase-1/2/3 exploration of the v0.3.0 Properties surface surfaced architectural gaps + Claude-side assumptions in the existing spec. Nathan locked the direction shifts inline, then the prior split-doc structure (`Planning/v0.3.0-Properties-spec.md` + `Planning/v0.3.0-Properties-plan.md`) was merged into a single PRD-style **`Features/Properties.md`** and the two old docs deleted. **Next session writes a fresh implementation plan from scratch against `Features/Properties.md`.**

##### Locked direction shifts (2026-05-24)

1. **File / Attachment is the 11th property type** (catalog grows from 10 → 11). Copy-on-attach into `<nexus>/.nexus/attachments/<entity-id>/<original-filename>`; property value stores nexus-relative paths. Multi-file by default; optional `accept` MIME-type whitelist config. Especially load-bearing for Items (no Markdown body to drop files into).
2. **Entity identity ≠ title.** Every entity carries a stable ULID (`id` in frontmatter / JSON) — identity used by every cross-reference. Filename = renameable display title. Cross-references resolve via ULID, never basename. Duplicate titles allowed in same container; filesystem may auto-disambiguate (`(2)`) but displayed title stays user-typed. Wikilink disk format: `[[Title|ULID]]`. (Earlier "filename = title" was misread by prior Claude sessions as "filename = ID" — corrected.)
3. **Cross-side relations ARE supported** (Item ↔ Page). Unified picker; no side-locking. Validator's cross-side guard removed. (Earlier "cross-side NOT supported" framing was a Claude assumption, not a Nathan decision.) Cross-side *promotion* stays a Prospect — different concept.
4. **Property surface render modes are PER-SURFACE, not universal.** Pages Pulldown is **lazy** (populated-only + "+ Add property" picker); Inspectors (Page Preview, Item Window) are **eager** (full schema visible, void-or-fill inline). The earlier "lazy properties unifying model" was a Claude misframing — Nathan never said inspectors should be lazy.
5. **Status built-in on AgendaEvent too** (not just AgendaTask). Same 3 EventKit-aligned groups. User-set (decoupled from start_at / end_at date math) — tracks the user's engagement with the event. EventKit mapping for events ships v0.6.0.
6. **Rollups + Formulas confirmed OUT of v1 scope.** Pommora's catalog stays at 11 types. Post-v1 Prospects if revisited.
7. **SQLite scaffolding pulled forward into v0.3.0** (was v0.3.3). Adds GRDB.swift dependency + new `Pommora/Pommora/Index/` folder + per-nexus `index.db`. Powers relation pickers + sort/filter at scale + move-strip "affected count" from day one. v0.3.3 re-purposed to file watcher + FTS5 wiring + external-edit detection.
8. **Description stays 250-char capped on Items** (early Claude misread tried to lift the cap — Nathan corrected; cap stays). Description IS Items' body field (always was) — the framing change is just clarifying that "main body" still means "short body."

##### Reinforcements (Nathan said + Claude needed to lock more explicitly)

R1. **Relation VALUES bind to specific entities, always.** Scope (Vault / Collection / Context tier) is the picker constraint; value is always a specific Page / Item / Context ULID. Notion-model exactly. (Doc-language clarification — implementation always intended this; spec language was misleading.)

R2. **Relation property = "relationship to Collection Y"; relation value = "Page ID: 01HXYZ..."** Same as Notion's database-property points-at-a-database, page-property-value-is-a-specific-page model.

##### Surface architecture (updated table)

| Surface | Property home | Render mode | Timing |
|---|---|---|---|
| **Page in main window** | NavDropdown-style pulldown at top of content | **Lazy** (populated-only + "+ Add property" picker over schema) | Real UI v0.3.1 |
| **Page Preview** (standalone window) | Property panel in window inspector (toggle, default closed) | **Eager** (full schema; void-or-fill inline) | When PreviewWindow ships |
| **Item Window** (popover) | Property panel in popover inspector (toggle, default closed) + pinned-property chips above title (Item Collection-level) | **Eager** (full schema; void-or-fill inline) | When Item Window redesign ships |
| **Context Preview** (window) | Inspector reserved for TBD purpose; Contexts have no properties | n/a | n/a |
| **Main window inspector** | Claude chat (CLI subprocess bridge). Properties NEVER live here. | n/a | Ships independently |

Canonical reference: `.claude/Features/Properties.md` § "Where Properties Live" + § "Property surface rendering modes".

#### v0.3.x sub-sequence (re-sequenced 2026-05-24 — SQLite pulled forward)

```
v0.3.0 — Properties data layer + SQLite scaffolding + minimum-viable placeholder UI
v0.3.1 — Properties Pulldown + Panel UI (Figma-driven fast-follow)
v0.3.2 — Page-wikilinks (indexed from day one — SQLite already shipped at v0.3.0)
v0.3.3 — File watcher + FTS5 wiring + external-edit detection
```

**Independent v0.3.x patches (TBD timing):** Item Window redesign with pinned chips at Item Collection level; Claude chat as main-window inspector; PreviewWindow primitive (Page / Context Preview windows). Each ships when designed.

#### Verbatim resume prompt

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. 2026-05-24 was a Properties discovery + direction-shift session — no code shipped. 8 directional shifts + 2 reinforcements locked: (1) File/Attachment is the 11th property type with copy-on-attach into `.nexus/attachments/<entity-id>/`; (2) Entity identity ≠ title — every entity has a stable ULID; filename is renameable display label; duplicate titles allowed; wikilink format `[[Title|ULID]]`; (3) Cross-side relations supported; cross-side guard removed; (4) Render modes are PER-SURFACE — Pulldown lazy, Inspectors eager; (5) Status built-in on AgendaEvent too; (6) Rollups + Formulas out of v1; (7) SQLite scaffolding pulled into v0.3.0 (was v0.3.3) — adds GRDB.swift; (8) Description stays 250-char capped on Items (Claude misread initially tried to lift; Nathan corrected). Reinforcements: relation VALUES bind to specific entities always; scope is picker constraint, value is always specific Page/Item ULID. **Next session task:** surface every contradiction between `.claude/Planning/v0.3.0-Properties-spec.md` and `.claude/Features/Properties.md`, get Nathan's clarification on each, then merge spec INTO Features/Properties.md as the single source of truth, delete the old `v0.3.0-Properties-plan.md` (we'll write a new one from scratch), mirror to Nexus. Then: write a NEW implementation plan from scratch against the merged Properties.md. Build green at start of day (366 tests passing, no code shipped). Builder subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1). Parallel session may have editor / wireframe work in working tree — never bundle into commits (quirk #11)."

#### Open questions still queued (some from 2026-05-23, some new)

Conceptual gaps Nathan hasn't decided yet — flag at the merge-clarification pass tomorrow:

1. **Multi-window state.** When a Page is open in the main window AND a Page Preview window simultaneously, how do property edits propagate? Conflict resolution? Live update both?
2. **Pinned chip overflow.** Item Collection-level pinned set with more chips than fit. Wrap to second row? Scroll? Hide overflow with "+N more"?
3. **Per-property icon vs per-Type icon distinction.** Both use SF Symbols. Visual distinction or contextual-only?
4. **Move-strip + dual relation interaction.** Page moves to a new PageType that ALSO has a same-named relation property with the same target. Transfer value or strip-and-orphan-target-side?
5. **Number format storage shape.** Schema says `number_format: currency`. User enters "$100.50". Stored as `100.50` raw + format applied at render? Or `"$100.50"` formatted string? (Round-trip implications.)
6. **Status property — move option between groups.** Spec says data-semantic (changes EventKit mapping at v0.6.0). UX: confirmation dialog needed? What does it list?
7. **Properties Pulldown default state.** Open or closed on page load? Affects discoverability.
8. **AgendaTask + AgendaEvent placeholder UI entry point.** Locked: reuse Item Window UX pattern, separate code per entity. But WHERE does the user open these from at v0.3.0? Calendar pin → list → click → window?
9. **Settings scaffold migration story.** Nathan's settings.json was stale (pre-defaults change). For future users, should `SettingsManager.loadOrCreate()` migrate stale `sidebar_sections` values to new defaults automatically? Or stays user-managed?
10. **Validation on dual relations.** Both sides must succeed atomically. What's the UI feedback when one side fails (e.g., target Type's reverse-property name conflicts)?
11. **Lazy/eager default for Pages Pulldown — per-Type toggle in Type Settings.** Locked as lazy. Per-Type toggle would let users override per Type — small cost, big UX flexibility. Decide before plan write.
12. **Move-strip undo / quarantine.** Notion-parity pain rescue. Recommended: `_stripped: {...}` sibling field on the moved file, allow one-shot restore, drop on next save.

#### v0.3.0 code-audit findings — must-fix during implementation plan

Audit run today against the locked direction in `Features/Properties.md`. The current Swift code passes on entity-identity (D1) and Items description cap (D11), and the queued-but-absent areas (wikilink resolver D4, SQLite indexer D9, file attachments D10) are correctly absent and become net-new implementation work. Six areas need actual code changes during the implementation plan:

1. **Property identity = ID, not name** (D2 — CRITICAL).
   - `Pommora/Pommora/Vaults/PropertyDefinition.swift:8` — `name` doubles as property key (`var id: String { name }` on line 17). PropertyDefinition needs a stable `id: String` (ULID) as a load-bearing field independent of `name`.
   - `Pommora/Pommora/Vaults/PropertyDefinition.swift:18-24` — `SelectOption.id` derives from `value`; stays as-is (option identity is the `value` field by design) — flag only because it's a similar pattern.
   - `Pommora/Pommora/Validation/PageValidator.swift:52-54` + `Pommora/Pommora/Validation/ItemValidator.swift:61-63` — `schemaByName = Dictionary(...vault.properties.map { ($0.name, $0) })`. Validators must look up properties by ID, not name.
   - `Pommora/Pommora/Content/Item.swift:13` + `Pommora/Pommora/Content/PageFrontmatter.swift:12` — `properties: [String: PropertyValue]` is keyed by property name today. Must be keyed by property ID. Migration: synthesize IDs for existing nexuses on load, then rewrite frontmatter keys.

2. **Duplicate titles allowed — drop `duplicateTitle` validation** (D3 — CRITICAL).
   - `Pommora/Pommora/Validation/PageValidator.swift:37-40` — `conflict` check that throws `ValidationError.duplicateTitle`. Drop. Filesystem auto-disambiguates filenames with `(2)` suffix; displayed title stays user-typed.
   - `Pommora/Pommora/Validation/ItemValidator.swift:34-37` — same `duplicateTitle` rejection. Drop.

3. **RelationScope incomplete** (D5 — HIGH).
   - `Pommora/Pommora/Vaults/PropertyDefinition.swift:35-38` — `RelationScope` enum only has `sameVault` and `anywhere` cases. Must be expanded to the 5 cases: `pageType(String)`, `itemType(String)`, `pageCollection(String)`, `itemCollection(String)`, `contextTier(Int)`. Plus the cross-side picker logic in the schema editor needs to drop side-locking.

4. **Status built-in seed missing** (D6 — CRITICAL).
   - `Pommora/Pommora/Agenda/AgendaEventSchema.swift:34-54` — `defaultSeed()` seeds a `type` Select; does NOT seed Status. Must seed `_status` Status property with 3 fixed groups (Upcoming / In Progress / Done) as required, non-deletable.
   - `Pommora/Pommora/Agenda/AgendaTaskSchema.swift:34-55` — same pattern. Status seeding marked as deferred to "Phase 9.2"; that gate is now resolved — must seed Status. Existing `type` Select gets removed via load-path migration.
   - `PropertyDefinition.StatusGroup` + `PropertyDefinition.StatusOption` + `PropertyDefinition.StatusGroupID` types don't exist yet; must be added before Status seeding can compile.

5. **Property catalog gaps** (D7 — CRITICAL).
   - `Pommora/Pommora/Vaults/PropertyType.swift:5-14` — 8 cases today (`number`, `checkbox`, `date`, `datetime`, `select`, `multiSelect`, `relation`, `url`). Missing 3: `status`, `lastEditedTime`, `file`.
   - `Pommora/Pommora/Vaults/PropertyValue.swift:20-29` — corresponding 8 cases. Add `.status(String)`, `.lastEditedTime` (virtual; not stored), `.file([FileRef])`.
   - PropertyDefinition needs new config fields: `statusGroups: [StatusGroup]?` (for Status), `accept: [String]?` (file MIME-type whitelist), `dualProperty: DualPropertyConfig?` (paired relation), `icon: String?` (already exists?), `allowsMultiple: Bool` (single vs multi-relation).

6. **`pinned_properties` field missing on ItemCollection** (D8 — HIGH).
   - `Pommora/Pommora/Items/ItemCollection.swift:10-62` — struct carries `id`, `typeID`, `modifiedAt`, `itemOrder`; missing `pinned_properties: [String]` (property ID array). Add field + migration for existing nexuses.

**Net-new implementation areas (no current code; must be built):**

- **D4 — Wikilink ID-keyed resolver.** Disk format `[[Title|ULID]]`. PommoraWikiLinkResolver doesn't exist; engine doesn't have ID-keyed resolution. Ships v0.3.2.
- **D9 — SQLite indexer.** Per-nexus DB at `<nexus>/.nexus/index.db`; GRDB.swift dependency; `Pommora/Pommora/Index/` folder (PommoraIndex, IndexBuilder, IndexUpdater, IndexQuery). Powers relation pickers + sort/filter + move-strip "affected count." Ships at v0.3.0 as part of Properties scaffolding.
- **D10 — File attachment property type + copy-on-attach pipeline** into `<nexus>/.nexus/attachments/<entity-id>/`. Ships at v0.3.0.

#### Outstanding follow-ups

##### Known outstanding state

- **Sidebar drag-to-reorder REGRESSION (introduced 2026-05-23 by `fb6d581`).** Today's disclosure-click fix moved `.reorderable(...)` from the outer DisclosureGroup modifier to inside the `label:` closure on PageTypeRow / PageCollectionRow / TopicRow. This restored chevron-click toggling but shrunk the drag/drop hit zone to label area only AND broke `rowHeight` measurement (label height ≠ full row height → above/below drop position calc is off). Drag may feel non-functional or land in wrong positions. **Fix direction:** split drag source from drop destination — keep `.draggable` scoped to label only (so chevron click stays free), but apply `.dropDestination` to the full row (so users can drop anywhere). Requires refactoring `ReorderableRowModifier` to support split application, OR adding a separate `.dropTarget` modifier alongside `.reorderable`. Queue before v0.3.0 starts.
- **Collision-suffixed singleton folders on Nathan's nexus.** `Tasks.20260523-224558-760F/` and `Events.20260523-224558-46F1/` sit at `/Users/nathantaichman/The Nexus/` root — inert artifacts of the original adoption-pass folder-name collision. Authoritative `Tasks/` + `Events/` singletons are in place. Nathan can `rm -rf` the timestamped siblings manually.
- **Settings.json `sidebar_sections` migration debt.** Today's fix was direct file edit on Nathan's nexus. A SettingsManager migration shim that detects stale-default values and updates in place is queued (see Open Question #9 above).

##### Known debt (not blocking next focus)

- **Blockquote horizontal-positioning visual** (v0.2.7.5 carryover) — card highlight starts at body text rather than extending into the hidden `>` syntax gap.
- **NavDropdown Pinned drag-to-reorder** — queued behind v0.2.8 Phase 2.
- **Drag-to-reorder — Items-side rows** — queued (Items rows are stubs).
- **Drag-to-reorder — cross-container drag** — out of scope for v1.
- **Drag-to-reorder — detail-pane Tables** — Phase 4 of v0.2.8 plan; not started.
- **NavDropdown polish** — type chip removal, segmented picker opacity/contrast.
- **In-app Trash window** — `.trash/` data layer shipped v0.2.5; UI surface at v0.4.0.
- **`do { try await … } catch { … }` rewrap** in SidebarView.swift + IconPickerSheet.swift — cosmetic.
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.3.2 dependency.

#### Parallel session

The concurrent editor session shipping collapsible-heading work + em/en dash syntax in `External/MarkdownEngine/` continues to land commits on `main` interleaved with this work. Today's commits include the foldable-headings toggle fix (works correctly now) + em/en dash syntax. Working tree at this snapshot carries unattributed edits to `External/MarkdownEngine/Sources/MarkdownEngine/...` + `Pommora/Pommora/ContentView.swift` + `Pommora/Pommora/Pages/PageEditorView.swift` — never bundled into property-scope commits per quirk #11.

#### Document pointers

- **Roadmap**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md`
- **Editor feature spec**: `.claude/Features/PageEditor.md`
- **Editor implementation rules**: `.claude/Guidelines/Markdown.md`
- **NavDropdown feature spec**: `.claude/Features/NavDropdown.md`
- **Sidebar feature spec**: `.claude/Features/Sidebar.md`
- **Pages data model**: `.claude/Features/Pages.md`
- **Properties — singular PRD-style spec**: `.claude/Features/Properties.md` — the source of truth for what Properties are + how they behave. The prior split (`Planning/v0.3.0-Properties-spec.md` + `Planning/v0.3.0-Properties-plan.md`) was merged into this file then both deleted today. **Next session writes a fresh implementation plan from scratch against this doc.**
- **Engine vendor docs**: `External/MarkdownEngine/NOTICE.md`
- **Session transcripts**: `.claude/Transcripts/`
- **Paradigm-decision rules**: `.claude/Guidelines/Paradigm-Decisions.md`
