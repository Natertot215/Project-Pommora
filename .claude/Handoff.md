### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`.

#### Current state (2026-05-25 — v0.3.0 Properties FEATURE-COMPLETE; merge to main + smoke test pending)

**Branch:** `v0.3.0-properties` (off `main`). **44 commits** ahead of main. Tip: `71ce2da` (Phase G validator regression fix). Build green; full unit suite passing except 2 known pre-existing failures (`NexusAdopterTests/applyNathansActualShape` — broken by parallel-session NexusAdopter working-tree change; `PageEditorViewModelTests/debounceCoalescesRapidEdits` — timing flake under full-suite load, passes in isolation).

##### Phases complete

- ✅ **A** Foundation types (PropertyType 11 cases · PropertyValue + FileRef · ReservedPropertyID · 5-case RelationScope · PropertyDefinition with stored ULID `id` · StatusGroup/Option/ID · DualPropertyConfig)
- ✅ **B** SchemaTransaction atomic multi-file commit primitive
- ✅ **C** Migration suite (PageFrontmatter.modifiedAt · schema_version: 1 on every sidecar · PropertyIDMigration two-phase scan/apply runs every nexus open · AdoptionPreviewView surfaces counts before commit)
- ✅ **D** Schema CRUD on all 4 schema-bearing managers + PropertyDefinitionValidator 8 rules + schemaByID rewire + drop duplicateTitle + default_sort on every sidecar + SchemaConflictDialog (EC4 drift defense)
- ✅ **E** SQLite index live end-to-end (GRDB.swift · 12-table schema · IndexBuilder filesystem walk · IndexUpdater wired into all 6 managers · IndexQuery Notion-style filter+sort+broken-links · NexusManager opens/rebuilds · ContentView plumbs IndexUpdater so mid-session mutations propagate)
- ✅ **F** File attachments (AttachmentManager copy-on-attach + 50 MB warn / 500 MB hard cap + MIME accept-list with wildcard · cascade-delete to trash on entity delete)
- ✅ **G** Status seed (`_status` injected in AgendaTask + AgendaEvent default seeds + load-path backfill for legacy schemas) + DualRelationCoordinator (create/value-mirror/rename/delete paired relations atomically via SchemaTransaction) + wired into PageTypeManager + ItemTypeManager

##### Phases remaining for v0.3.0 ship

- **H** Move-strip primitive + cross-Type move methods on PageContentManager + ItemContentManager (the IndexQuery.moveStripCount preview shipped in E.6; H wires the actual file move + value strip via SchemaTransaction).
- **I** Settings scaffold (`.nexus/settings.json` + `SettingsManager.loadOrCreate` with auto-migration of stale defaults). Cmd+, stub scene.
- **J** Placeholder UI suite (~15 sub-tasks): PropertyEditorRow dispatchers for all 11 types · Pulldown · PropertyPanel · VaultSettingsSheet · TypeSettingsSheet · StatusPicker · RelationPicker · FileAttachmentEditor · RelationPropertyWizard · PropertyTypePicker · pinned-property chips · MoveStripConfirmationDialog · column-header sort · live red-border validation.
- **K** Calendar placeholder UI (pinned list view + Calendar pin right-click create).

After H + I + J + K land, v0.3.0 is shippable end-to-end.

#### Locked decisions on this branch

1. **Status value on-disk encoding = `{"$status": value}` tagged-object form.** Matches `{"$rel": id}` pattern. Pure shape-sniff can't disambiguate `.status` from `.select`; tagged form is round-trip-stable + agent-legible.
2. **Move-strip matches by NAME not ID.** Property IDs are globally unique per `property_definitions.id PRIMARY KEY` — ID-based cross-type matching was structurally impossible. `IndexQuery.moveStripCount` filters by name; Pages keep values where dest has a same-named property.
3. **Reserved property IDs:** `_id`, `_created_at`, `_modified_at`, `_status`, `_tier1/2/3`, `_wikilinks`. User-defined mint `prop_<ulid>`.
4. **`schema_version: 1`** on every sidecar (legacy → 0 = needs migration). Index DB has its own `schema_version` in `meta` table; mismatch triggers delete + rebuild via IndexBuilder.
5. **`PropertyIDMigration` runs on every nexus open** — idempotent. Preview sheet shows per-Type counts before commit.
6. **tier1/2/3 are root-level frontmatter fields**, not nested under `properties:`. Reserved IDs block user collisions.
7. **AgendaTask + AgendaEvent default seed = single `_status` property.** Legacy `type` Select removed; load-path migration injects on existing schemas via SchemaTransaction.
8. **DualRelationCoordinator is the lifecycle owner of paired relations.** PageTypeManager + ItemTypeManager `addProperty`/`deleteProperty` route paired relations through it; container-scoped relations get atomic dual creation, value mirroring on set/clear, atomic delete-with-value-cascade.

#### Active branch quirks (carry forward to every subagent dispatch)

1. **Test filter form uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`. Suite-name form silently no-ops with `** TEST SUCCEEDED **`. Visually verify count.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include; pbxproj usually doesn't need editing.
3. **Trust `xcodebuild`, not SourceKit squiggles.** "Cannot find type 'X'" and "No such module 'Testing'/'GRDB'" diagnostics are routinely stale post-edit; always builder-verify, never chase squiggles.
4. **`.claude/*` is included in commits.** Don't auto-bundle docs into Swift commits without explicit ask; explicit doc commits are fine.
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`. Snapshot pattern: hoist `let id = ULID.generate()` before building entity to avoid `@Sendable` capture errors.
6. *(retired)*
7. **Xcode auto-reorders SymbolPicker/Yams/GRDB entries in pbxproj on every build** — incidental noop diff. Revert before commit.
8. **Stub-and-progressively-replace** is the locked execution strategy for branch-spanning plans. Each task ships green standalone; later phases replace earlier stubs in-place.
9. **Section structure in SidebarView is load-bearing.** Don't break `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns.
10. **Sidebar selection chrome at row file level via `.listRowBackground(SelectionChrome(...))`.**
11. **Parallel-session caveat — STILL ACTIVE.** Working tree carries ~15 sidebar/manager edits + 1 untracked `Sidebar/NSTableSelectionStyleSuppressor.swift` + 1 untracked plan doc from an ongoing parallel-session sidebar-color iteration. Per Nathan: parallel is purely sidebar coloring/visuals — no manager logic in flight. SAFE to read manager files; **NEVER commit, revert, or include those parallel-session edits in any Swift commit.**
12. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`). The direct `swift-format` binary is NOT on `$PATH`.
13. **Use `Agent run_in_background: true` for builder-subagent verification** — Nathan does not want xcodebuild grabbing window focus. Always builder via background Agent with `-only-testing:PommoraTests` (excludes UI test target which DOES launch the app window). Pattern proven across all 44 Phase A–G commits.

#### Pre-existing test failures (known; not blocking)

- `NexusAdopterTests/applyNathansActualShape` — broken by `guard !moves.isEmpty else { return }` in parallel-session NexusAdopter working-tree diff. Will resolve when parallel session commits the rest of their work.
- `PageEditorViewModelTests/debounceCoalescesRapidEdits` — timing flake; passes in isolation.

#### Resume prompt for tomorrow (verbatim)

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. On branch `v0.3.0-properties` — **Phases A–G complete, 44 commits shipped**. Tip: `71ce2da` (G.1–G.2 validator regression fix). Resume at **Phase H — move-strip primitive + cross-Type move methods on PageContentManager + ItemContentManager**, using SchemaTransaction for atomic file move + property-value strip. IndexQuery.moveStripCount preview surface already shipped in E.6 (matches by name; ID-based was structurally impossible because `property_definitions.id` is globally unique). Then Phase I (settings scaffold + auto-migration), J (placeholder UI suite ~15 sub-tasks), K (Calendar pinned list view). Plan at `.claude/Planning/v0.3.0-Properties-plan.md`. Locked decisions: `{$status: value}` tagged encoding; move-strip matches by NAME; tier1/2/3 root-level frontmatter; reserved IDs `_id`/`_status`/`_tier1/2/3`/`_wikilinks`/`_created_at`/`_modified_at`; user-defined mint `prop_<ulid>`; `schema_version: 1` on every sidecar; PropertyIDMigration runs every nexus open; AgendaTask/AgendaEvent seed `_status` single property + load-path backfill; DualRelationCoordinator owns paired-relation lifecycle. Parallel-session caveat (quirk #11) still active — ~15 sidebar/manager edits in working tree from continuing sidebar-color iteration; SAFE to read manager files; NEVER commit those parallel edits. Quirks #1 FILENAME-form test filter; #3 SourceKit squiggles always stale post-edit; #13 background builder subagent with `-only-testing:PommoraTests` for xcodebuild. Pre-existing test failures: NexusAdopterTests/applyNathansActualShape (parallel) + PageEditorViewModelTests/debounceCoalescesRapidEdits (flake). Use `superpowers:subagent-driven-development`."

#### Document pointers

- **Roadmap**: `.claude/Framework.md` (Current Focus reflects Phase A–G shipped + H/I/J/K remaining)
- **Session history**: `.claude/History.md` (new 2026-05-24 entry at top covers A–G)
- **PRD**: `.claude/PommoraPRD.md`
- **Properties spec (single source of truth)**: `.claude/Features/Properties.md`
- **Properties implementation plan**: `.claude/Planning/v0.3.0-Properties-plan.md` (11 phases A–K)
- **Paradigm-decision rules**: `.claude/Guidelines/Paradigm-Decisions.md`
