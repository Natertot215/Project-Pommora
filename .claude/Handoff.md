### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`.

#### Current state (2026-05-24 late session — v0.3.0 implementation underway)

**Branch:** `v0.3.0-properties` (created from `main` this session). **8 commits shipped.** Build green; full unit suite ~206 unique tests passing with only the 2 known pre-existing failures (`NexusAdopterTests/applyNathansActualShape` from parallel-session work + `PageEditorViewModelTests/debounceCoalescesRapidEdits` flaky timing).

The earlier session in the same calendar day was a planning pass: spec direction-shifts locked, `Features/Properties.md` consolidated as single source of truth, implementation plan written at `// Planning//v0.3.0-Properties-plan.md` via the `superpowers:writing-plans` skill. That doc commit (`0dc47f4`) opens this session. The session then started executing the plan task-by-task per `superpowers:subagent-driven-development`.

##### Shipped on `v0.3.0-properties` (in order)

| SHA | Phase | Scope |
|---|---|---|
| `0dc47f4` | docs | v0.3.0 spec finalization + locked plan (11 phases A–K) |
| `cd61ed4` | A.1 | `PropertyType` 8 → 11 cases (adds `.status`, `.lastEditedTime`, `.file`) |
| `953ba39` | A.2 | `PropertyValue` parity + `FileRef` struct |
| `8358ebf` | A.3 | `ReservedPropertyID` enum + `mintUserPropertyID()` helper |
| `23a2aa5` | A.4 | `RelationScope` 2 → 5 cases (tagged-object on-disk shape) |
| `1f85548` | A.5+6 | `PropertyDefinition` stored `id` + config fields + `StatusGroup` / `StatusOption` / `StatusGroupID` / `DualPropertyConfig` nested types |
| `f31bda0` | B.1 | `SchemaTransaction` atomic multi-file commit primitive (`Pommora/Pommora/AtomicIO/SchemaTransaction.swift`) |
| `d69fd97` | C.1 | `PageFrontmatter.modifiedAt` field (optional; legacy decode yields nil) |

##### Phases complete

- ✅ **Phase A — Foundation types + reserved-ID prefixes** (all 6 sub-tasks shipped). Full property catalog (11 types), `RelationScope` 5 cases, `PropertyDefinition` with stored ULID `id` + all spec config fields, Status types, dual-relation config type.
- ✅ **Phase B — `SchemaTransaction` primitive** (1 task shipped). Atomic multi-file commit with two-phase commit + idempotent stale-temp cleanup. Used by Phase C/D/G/H.
- 🟡 **Phase C — Migration** (1 of 5 sub-tasks shipped). Only C.1 (`PageFrontmatter.modifiedAt`) landed. **C.3 (NexusAdopter property-ID rewrite migration) + C.4 (schema_version field on all 6 sidecars) + C.5 (AdoptionPreview migration counts) are the next session's first tasks** — they ship together because schema_version is the "this needs migration" signal C.3 reads, and AdoptionPreview surface needs C.3's count output.

##### Phases pending

- **Phase D — Schema CRUD on all 4 managers + validators + drift defense** — `addProperty / renameProperty / changeType / deleteProperty / reorderProperty` on PageType, ItemType, AgendaTask, AgendaEvent managers. New `PropertyDefinitionValidator` with 8 rules. Drop `duplicateTitle` validation. `SchemaConflictDialog` for EC4 schema-drift defense.
- **Phase E — SQLite indexer** (GRDB.swift SPM dep) + full Notion-style filter query API. 7 sub-tasks.
- **Phase F — File attachments** copy-on-attach + size cap (warn 50 MB / hard 500 MB).
- **Phase G — Status seed on AgendaTask/AgendaEvent + dual-relation lifecycle.**
- **Phase H — Move-strip primitive** + cross-Type move methods on PageContentManager + ItemContentManager.
- **Phase I — Settings scaffold** with auto-migration of stale defaults.
- **Phase J — Placeholder UI suite** (15 sub-tasks: PropertyEditorRow extension, Pulldown, PropertyPanel, schema editor sheets, Status/Relation/File pickers, pinned chips, move-strip dialog, column-header sort).
- **Phase K — Calendar placeholder UI** (pinned list view).

##### Decisions locked this session (in addition to plan-doc locks)

- **Status value encoding is `{"$status": value}` tagged-object form**, matching the existing `{"$rel": id}` pattern for relations. Properties.md illustrates Status values as bare strings, but pure shape-sniff at the Codable layer cannot disambiguate `.status` from `.select` (both single strings). Tagged form is round-trip-stable AND more agent-legible (load-bearing constraint #3). **If Nathan wants bare-string on-disk, the manager layer would need schema-aware encode/decode** — flag for review at next session start before Phase D wires manager value writes.
- **7 test-fixture call sites patched with `id: ""` prefix** when Phase A.5+6's PropertyDefinition init gained the required `id` parameter (stub-and-progressively-replace per paradigm decision #4). The `id: ""` empty values get backfilled to minted ULIDs by Phase C.3's adoption-scan migration.

#### Active branch quirks (all still in force)

Carry forward to every subagent dispatch — unchanged from prior session:

1. **Test filter form uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`. Suite-name form silently no-ops with `** TEST SUCCEEDED **`. Visually verify count.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include; pbxproj usually doesn't need editing.
3. **Trust `xcodebuild`, not SourceKit squiggles** — IDE diagnostics frequently stale. Every Phase A/B/C task hit `Cannot find type 'X'` and `No such module 'Testing'` squiggles that vanished on real build. **Always builder-subagent verify; never trust SourceKit alone.**
4. **`.claude/*` is included in commits.** Don't auto-bundle docs into Swift commits without explicit ask, but explicit doc commits are fine.
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. New types added this session follow that pattern.
6. *(retired)*
7. **Xcode auto-reorders SymbolPicker/Yams entries in pbxproj on every build** — incidental noop diff. Revert before commit. (Will also apply to GRDB.swift once Phase E.1 lands.)
8. **Stub-and-progressively-replace** is the locked execution strategy. Each task ships green standalone; later phases replace earlier stubs in-place.
9. **Section structure in SidebarView is load-bearing.** Don't break the `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns.
10. **Sidebar selection chrome at row file level via `.listRowBackground(SelectionChrome(...))`.**
11. **Parallel-session caveat — STILL ACTIVE.** Working tree carries 4 unattributed Swift edits from a parallel session: `Pommora/Pommora/Detail/PageCollectionDetailView.swift`, `Pommora/Pommora/Items/ItemTypeManager.swift`, `Pommora/Pommora/Nexus/NexusAdopter.swift`, `Pommora/Pommora/Vaults/PageTypeManager.swift`. **Never bundle into Properties commits; never revert.** These showed up in `git status` before this session started and remained untouched throughout.
12. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`). The direct `swift-format` binary is NOT on `$PATH`.

##### New quirk this session

13. **Use background `Agent` calls with `run_in_background: true` for builder-subagent verification** — Nathan asked not to have xcodebuild runs grab window focus (auto-mode classifier blocks raw xcodebuild calls anyway). Always dispatch builder via background Agent with `-only-testing:PommoraTests` (excludes UI test target which DOES launch the app window). Pattern proven across A.5+6, B.1, C.1.

#### v0.3.x sub-sequence (unchanged from prior plan)

```
v0.3.0 — Properties data layer + SQLite scaffolding + minimum-viable placeholder UI (in progress)
v0.3.1 — Properties Pulldown + Panel UI (Figma-driven fast-follow)
v0.3.2 — Page-wikilinks (indexed from day one — SQLite already shipped at v0.3.0)
v0.3.3 — File watcher + FTS5 wiring + external-edit detection
```

#### Verbatim resume prompt

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. On branch `v0.3.0-properties` — 8 commits shipped this session (`0dc47f4` docs + `cd61ed4` A.1 + `953ba39` A.2 + `8358ebf` A.3 + `23a2aa5` A.4 + `1f85548` A.5+6 + `f31bda0` B.1 + `d69fd97` C.1 + this Handoff commit). Phase A foundation types done (11-case PropertyType + PropertyValue + FileRef + ReservedPropertyID + 5-case RelationScope + PropertyDefinition with stored id + StatusGroup/StatusOption/StatusGroupID/DualPropertyConfig). Phase B SchemaTransaction primitive done. Phase C.1 modified_at on PageFrontmatter done. **Resume at Phase C.3 + C.4 + C.5 (migration suite — they ship together):** C.4 adds `schema_version: 1` to all 6 sidecar Codable types (PageType, PageCollection, ItemType, ItemCollection, AgendaTaskSchema, AgendaEventSchema — legacy decode defaults to 0); C.3 extends NexusAdopter with `migratePropertyIDsIfNeeded` that walks every schema sidecar (mints `prop_<ulid>` for empty `id`s), then walks every member file (rekeys `properties:` from name to ID via the per-Type name→id map), commits per-Type via SchemaTransaction; C.5 surfaces migration counts in AdoptionPreviewView. Then Phase D (Schema CRUD on managers + validators + EC4 drift defense). Plan at `.claude/Planning/v0.3.0-Properties-plan.md`. Critical context: quirk #11 parallel-session 4-file working-tree mods MUST stay untouched; quirk #3 SourceKit squiggles are stale (every session task hits them) — always builder-verify; new quirk #13 use `Agent run_in_background: true` for builder verifications (Nathan doesn't want xcodebuild focus-grab); test-fixture call sites with empty `id: \"\"` get backfilled by Phase C.3 migration. **Open decision flagged for review:** Status PropertyValue encoding chose `{\"$status\": value}` tagged form (matches `$rel` pattern) over Properties.md's illustrative bare-string shape — disambiguates `.status` from `.select` at Codable layer. If Nathan wants bare-string on disk, manager layer needs schema-aware encode/decode."

#### Open questions still queued

Most were answered during this session's plan-mode brainstorming pass (12 Q-decisions + 4 EC-decisions + 25 L-locks documented in the plan file). Remaining items for next-session check-in:

1. **Status PropertyValue on-disk shape** — tagged-object `{"$status": value}` (chosen + committed in A.2) vs bare-string `"value"` (Properties.md illustrative example). Flag for review before Phase D manager value writes.
2. **Schema sidecar concurrent-write contention** (L19) — column-header sort persistence will write `default_sort` outside the schema sheet. Single-writer routing through manager keeps this safe; verify Phase D wires sort persistence through manager too.
3. **Status group `label` rename uniqueness (L10)** — labels NOT required unique; group `id` is load-bearing. Wire this into PropertyDefinitionValidator so the validator doesn't accidentally reject distinct labels with the same casing.

#### v0.3.0 code-audit findings — STATUS UPDATE

Of the 6 must-fix areas + 3 net-new areas the prior session's audit flagged, this session resolved:

| Audit item | Status |
|---|---|
| **1. Property identity = ID not name** (D2 CRITICAL) | ✅ DONE via Phase A.5 — stored `id` field; legacy decode synthesises empty; Phase C.3 migration backfills |
| **2. Drop `duplicateTitle` validation** (D3 CRITICAL) | ⏳ Phase D.6 — drops `PageValidator.swift:37-40` + `ItemValidator.swift:34-37` |
| **3. RelationScope incomplete** (D5 HIGH) | ✅ DONE via Phase A.4 — 5 cases, custom Codable |
| **4. Status built-in seed missing** (D6 CRITICAL) | ⏳ Phase G.1+G.2 — `defaultSeed()` injects `_status` on AgendaTask/AgendaEvent schemas |
| **5. Property catalog gaps** (D7 CRITICAL) | ✅ DONE via Phase A.1+A.2+A.5 — `.status`, `.file`, `.lastEditedTime` cases + StatusGroup config field on PropertyDefinition |
| **6. pinned_properties missing on ItemCollection** (D8 HIGH) | ⏳ Phase J.2 — adds field + Collection-only pinning per EC1 |
| **Net-new: D4 Wikilink ID-keyed resolver** | ⏳ v0.3.2 (out of v0.3.0 scope) |
| **Net-new: D9 SQLite indexer** | ⏳ Phase E.1-7 — GRDB.swift dep, `Pommora/Pommora/Index/` folder, full filter query API |
| **Net-new: D10 File attachment + copy-on-attach** | ⏳ Phase F.1 |
| **Bonus: PageFrontmatter `modified_at`** (found during audit) | ✅ DONE via Phase C.1 |

#### Outstanding follow-ups

##### Known outstanding state

- **Sidebar drag-to-reorder REGRESSION (from `fb6d581`).** Still queued before v0.3.0 starts shipping UI work — Phase J touches sidebar context menus + may collide. Carryover from prior session.
- **Collision-suffixed singleton folders on Nathan's nexus.** `Tasks.20260523-224558-760F/` and `Events.20260523-224558-46F1/` sit at nexus root — inert artifacts. Nathan can `rm -rf` manually.
- **Settings.json `sidebar_sections` migration debt.** Phase I.2 (`SettingsManager.loadOrCreate` auto-migration) is the locked fix.
- **Parallel-session working tree changes still uncommitted** at session end (the 4 Swift files in quirk #11). The other session author should commit them on their own branch / workflow.

##### Known debt (not blocking next focus)

- **Blockquote horizontal-positioning visual** (v0.2.7.5 carryover).
- **NavDropdown Pinned drag-to-reorder** — queued behind v0.2.8 Phase 2.
- **Drag-to-reorder — Items-side rows** — queued.
- **Drag-to-reorder — cross-container drag** — out of scope for v1.
- **Drag-to-reorder — detail-pane Tables** — Phase 4 of v0.2.8 plan; not started.
- **NavDropdown polish** — type chip removal, segmented picker opacity/contrast.
- **In-app Trash window** — UI surface at v0.4.0.
- **`do { try await … } catch { … }` rewrap** in SidebarView.swift + IconPickerSheet.swift — cosmetic.
- **PommoraWikiLinkResolver** — v0.3.2 dependency.
- **PropertyEditorRow placeholder polish** — Phase A.1 added a single combined `case .status, .lastEditedTime, .file:` placeholder Text; Phase J.1 replaces with real dispatchers. Code-quality review at A.1 noted the placeholder text could be more grep-distinguishable from the `.relation` placeholder — not blocking.
- **`@Suite("DisplayName")` test-suite naming convention** — Phase A.1's `PropertyTypeTests` uses bare `@Suite`; all Phase A.3+ test files use `@Suite("...")` form. Backfill A.1 in a doc/polish pass when convenient.

#### Document pointers

- **Roadmap**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md`
- **Editor feature spec**: `.claude/Features/PageEditor.md`
- **Editor implementation rules**: `.claude/Guidelines/Markdown.md`
- **NavDropdown feature spec**: `.claude/Features/NavDropdown.md`
- **Sidebar feature spec**: `.claude/Features/Sidebar.md`
- **Pages data model**: `.claude/Features/Pages.md`
- **Properties — singular PRD-style spec**: `.claude/Features/Properties.md` — source of truth.
- **Properties — implementation plan**: `.claude/Planning/v0.3.0-Properties-plan.md` — 11 phases A–K with bite-sized TDD tasks. Phases A + B + C.1 marked complete in commit history; C.3/C.4/C.5 next.
- **Engine vendor docs**: `External/MarkdownEngine/NOTICE.md`
- **Session transcripts**: `.claude/Transcripts/`
- **Paradigm-decision rules**: `.claude/Guidelines/Paradigm-Decisions.md`
