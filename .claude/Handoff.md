### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`; phased roadmap in `Framework.md`.

#### Current state (2026-05-25 — `v0.3.0-properties` synced with `main` after chrome-slice merge)

**v0.3.x View Settings chrome slice** shipped this session as the first patch of the v0.3.1.x Storage View Redesign series. Both branches in sync at the new tip; nothing ahead on either side after the merge + push.

**This session's ship:** static `slider.horizontal.3` toolbar button + empty Liquid-Glass popover (fixed 300×360pt) wired into ContentView's existing primary-action HStack — shares the Liquid-Glass capsule with NavDropdown + Inspector toggle. Popover content is `Color.clear` at this slice (chrome-only); future panes (Layout / Property Visibility / Sort / Filter / Group / Edit Properties) replace the body in subsequent v0.3.1.x patches. Scope-routing wiring locked: `ContentView.sidebarSelection` → `currentViewSettingsScope` computed → `ViewSettingsButton(scope:)` → `ViewSettingsPopover(scope:)`. Same button, every surface, content adapts.

**Files in the ship:**
- NEW `Pommora/Pommora/ViewSettings/ViewSettingsScope.swift` (10-case enum mirroring `SidebarSelection`)
- NEW `Pommora/Pommora/ViewSettings/ViewSettingsPopover.swift` (empty `Color.clear.frame(width: 300, height: 360)`)
- NEW `Pommora/Pommora/ViewSettings/ViewSettingsButton.swift` (Button + `.popover(arrowEdge:.top)`)
- NEW `Pommora/PommoraTests/ViewSettings/ViewSettingsScopeMappingTests.swift` (13 tests, all green)
- MODIFIED `Pommora/Pommora/ContentView.swift` — added `static func viewSettingsScope(for:)` + `private var currentViewSettingsScope` + inserted button as leading item in existing `.glassEffect()` HStack

**One bug found + fixed mid-session via systematic-debugging:** initial popover used `Button(role: .close) { dismiss() }` (no label). That role-only form only renders inside `.toolbar { ... }` context where SwiftUI synthesizes the X. Inside a popover body it asserted at first popover-content render — crash on button click. Replaced with `Button { dismiss() } label: { Image("xmark.circle.fill")... }.buttonStyle(.plain)` pattern. Then user requested empty placeholder; close button removed entirely (outside-click + ESC are the only dismiss paths now). Locked as new quirk #17.

#### What's next

**APPROVED plan ready to execute:** `.claude/Planning/View-Settings-edit-properties-plan.md` (also mirrored to `/Users/nathantaichman/The Nexus/Pommora/Planning/`). Approved 2026-05-26. **Use `superpowers:subagent-driven-development` to dispatch the 25 tasks across 9 phases — each phase ships green standalone per quirk #8.**

**v0.3.1 scope (one plan, big):**
- **Phase A (Tasks 1-5b)** — Data layer: `DisplayVariant` enum (.box/.select/.chip, Status-only) + `ItemType.singular` + `SavedView` Codable upgrade (real fields: id, name, icon, type, visibleProperties, hiddenProperties + reserved stub sort/filter/group fields) + `views: [SavedView]` on PageCollection + ItemCollection + `PropertyDefinition.dateFormat` (6 cases incl. ISO 8601) + default-view migration on loadAll (quirk #15 pattern) + PropertyChipColor cleanup (drop .cyan/.mint; 12 cases total; 10-color 5×2 selection grid via new `OptionColorPicker`)
- **Phase B (Task 6)** — ViewSettingsScope associated values for 4 storage cases
- **Phase C (Task 7)** — Popover NavigationStack scaffold + storage-scope root menu (Edit Properties + Property Visibility both active; Layout/Filter/Sort/Group muted-placeholder)
- **Phase D (Task 8)** — PropertyEditor extraction: dedupe Select/Status/Number/File editors out of VaultSettingsSheet + TypeSettingsSheet into shared `Pommora/Properties/Editor/` module
- **Phase E (Tasks 9-11b)** — Edit Properties pane (Notion screenshot format: icon+title row + Type + Options with chevron-push + Duplicate/Delete footer) + + New property flow with type-aware routing (Select/Status/Multi auto-push to Edit Property pane after creation; simpler types pop back to list) + EditOptionPane (per-option edit pushed from option chevron) + `duplicateProperty` manager method
- **Phase F (Tasks 12-14)** — Property Visibility pane (drag-only reorder + click-to-toggle strikethrough) + new `updatePageProperty` / `updateItemProperty` single-property atomic manager methods
- **Phase G (Tasks 15-18)** — Dynamic Table columns: `PropertyColumnBuilder` produces TableColumn descriptors from `views[0].visibleProperties` + schema; `PropertyCellDisplay` per-type renderer (chips ONLY for Status/Select/Multi/Relation; pure text for Date/Link/Number; FileChip for files); wire into all 4 storage detail views
- **Phase H (Tasks 19-21)** — Click-to-edit cell popovers for all 11 types: `PropertyCellEditor` wrapper + per-type editor popovers reusing existing PropertyEditorRow editors + wire existing `RelationPicker` (J.15-shipped but unused) + `StatusPicker` + `FileAttachmentEditor` into PropertyEditorRow stubs
- **Phase I (Tasks 22-23)** — Doc sweep + Nexus mirror + commit + push + merge to main

**New chip primitives this plan adds (3):** `RelationChip.swift` (default-grey, RoundedRectangle cornerRadius 4, target entity icon + title) / `FileChip.swift` (quaternary fill, `link` SF Symbol, filename truncated 13 chars) / `LinkChip.swift` (accent-blue text, strips https:// prefix, truncates 15 chars) — all under `Pommora/Properties/Chips/`.

**Locked decisions in this plan (recorded for reference):**
- Empty cells: blank, full-area clickable (Notion-style)
- Header drag-reorder: deferred (Property Visibility pane is the only reorder surface at v0.3.1)
- Option sort: drag-only (no Sort picker in Edit Property pane; view-level Sort = v0.3.1.2 patch)
- DisplayVariant cases: `.box` / `.select` / `.chip` (was `.status` in earlier draft)
- Status group icons: hardcoded `"square.dashed"` placeholder; final per-group/per-option icons + Settings config deferred to pre-v1 cleanup
- New property defaults: schema-only write (no member files touched); option-requiring types auto-push to Edit Property pane after creation
- Reserved properties: lock badge in Properties pane; `_modified_at` always-visible read-only column
- Sheet path: VaultSettingsSheet + TypeSettingsSheet keep working; both backport extracted PropertyEditor

**Chrome plan retires to Superseded** at Task 22 of the edit-properties plan (once that ships).

**After v0.3.1 ships, follow-up plans queued:** v0.3.1.2 Sort pane / v0.3.1.3 Filter pane / v0.3.1.4 Group pane / v0.3.1.5 existing-property change-type + per-type-config edits / v0.5.0 non-Table view renderers (board/list/cards/gallery).

**UIX rules locked earlier this session (carry forward):** tables get NO vertical column borders (Notion-flat — `NSViewRepresentable` impl TBD); `"Title"` everywhere (not `"Name"`); `"Spaces"` / `"Topics"` / `"Projects"` in property panels (no `"Tier N"` prefix); Sidebar Items section defaults to `"Items"`; Item Types are disclosure-foldable, Sets are flat leaves.

**Parallel-session changes uncommitted in working tree** (NOT mine, per quirk #11 — surfaced not bundled):
- `Pommora/Pommora/Properties/TypeSettingsSheet.swift` (-4 lines — drops dynamic title from sheet header)
- `Pommora/Pommora/Sidebar/ItemTypeRow.swift` (-3 lines — context-menu label simplified to "Edit")

#### Locked decisions in force

1. **Status value on-disk encoding = `{"$status": value}` tagged-object form.** Matches `{"$rel": id}` relation pattern.
2. **Move-strip matches by NAME, not ID.** Property IDs are globally unique per `property_definitions.id PRIMARY KEY`.
3. **Reserved property IDs:** `_id`, `_created_at`, `_modified_at`, `_status`, `_tier1/2/3`, `_wikilinks`. User-defined mint `prop_<ulid>`.
4. **`schema_version: 1` on every sidecar.** Legacy → 0 = needs migration. Index DB has its own `schema_version` in `meta`; mismatch triggers delete + rebuild.
5. **`PropertyIDMigration` runs on EVERY nexus open** — idempotent; preview shows per-Type counts before commit.
6. **tier1/2/3 are root-level frontmatter fields** (not under `properties:`). Edited via `ContextTierPicker`.
7. **AgendaTask + AgendaEvent default seed = single `_status` property.**
8. **`DualRelationCoordinator` owns paired-relation lifecycle.**
9. **`AttachmentManager` is the only path for file values.** Copy-on-attach into `<nexus>/.nexus/attachments/<entity-id>/`.
10. **Settings carries `defaultsVersion: Int`** for forward-compat stale-default migration. `Settings.migrate(_:)` step-function. Bumped to v2 on 2026-05-25.
11. **Items + Pages are NOT renameable concepts** — only their containers are (Vault / Collection / Type / Set). `"New Item"` and `"New Page"` are fixed literals; no `settings.labels.item` or `.page` exists.
12. **View Settings button = single static instance at ContentView level inside the existing primary-action `.glassEffect()` HStack.** Order: `[ViewSettings] [NavDropdown] [InspectorToggle]`. NEVER per-detail-view. Popover content adapts via `scope: ViewSettingsScope` parameter derived from `sidebarSelection`. Source of truth: `.claude/Planning/View-Settings-button-chrome-plan.md`.

#### Active branch quirks (carry forward to every subagent dispatch)

1. **Test filter form uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`. Suite-name form silently no-ops with `** TEST SUCCEEDED **`. Visually verify count.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include; pbxproj usually doesn't need editing.
3. **Trust `xcodebuild`, not SourceKit squiggles.** "Cannot find type 'X'" and "No such module 'Testing'/'GRDB'" diagnostics are routinely stale post-edit; always builder-verify, never chase squiggles.
4. **`.claude/*` is included in commits.** Don't auto-bundle docs into Swift commits without explicit ask; explicit doc commits are fine.
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`. Snapshot pattern for `@Sendable` closures: hoist `let id = ULID.generate()` before building entity. For `@MainActor`-isolated `@Suite` test capture inside `dbQueue.read` (Sendable closure): hoist captured properties to local `let` before the closure.
6. *(retired)*
7. **Xcode auto-reorders SymbolPicker/Yams/GRDB entries in pbxproj on every build** — incidental noop diff. Revert before commit.
8. **Stub-and-progressively-replace** is the locked execution strategy for branch-spanning plans. Each task ships green standalone; later phases replace earlier stubs in-place.
9. **Section structure in SidebarView is load-bearing.** Don't break `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns. Also: don't mix flat-leaf and disclosure-style rows inside the same `Section` — `OutlineListCoordinator.recursivelyDiffRows` can crash on the asymmetry. Item Types + Sets must mirror Vaults + Page Collections uniformly.
10. **Sidebar selection chrome at row file level via `.listRowBackground(SelectionChrome(...))`.**
11. **Parallel-session caveat** — Nathan may have a separate session running small UI tweaks. `Pommora/*` working tree is NOT guaranteed clean between subagent dispatches. Never revert unattributed working-tree changes; surface in report rather than bundling or discarding.
12. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`). The direct `swift-format` binary is NOT on `$PATH`.
13. **Use `Agent run_in_background: true` for builder-subagent verification** — Nathan does not want xcodebuild grabbing window focus. Always builder via background Agent with `-only-testing:PommoraTests` to skip UI tests.
14. **GRDB `String` overload pollution in @ViewBuilder closures** — `SQLSpecificExpressible` conformance on String causes overload ambiguity for `==` and `contains` inside SwiftUI views. Workaround: isolate per-row rendering into private struct sub-views with plain value types; use `first(where:)` not `contains(_:)`. Pattern established in `RelationPicker.swift`.
15. **`loadAll` must sync in-memory parents to the SQLite index.** PageTypeManager.loadAll + ItemTypeManager.loadAll defensively upsert types + collections after disk load (INSERT OR REPLACE makes it idempotent; `try?` swallows failures since the index is regeneratable). Regression-tested in `LoadAllIndexSyncTests.swift`. Future detail-view detail loaders (PageContent / ItemContent) inherit the same gap and may need similar sync if their FKs ever escalate.
16. **Every `@Environment(X.self)` declared on a detail view must be injected at `ContentView.detail`'s `.environment(...)` chain.** SwiftUI's `_TaskValueModifier` KeyPath-resolves env values when computing the `.task` closure; missing env asserts at runtime as EXC_BREAKPOINT — not a clean error. Symptom is "crash on first selection routing to that view."
17. **`Button(role: .close) { dismiss() }` without an explicit `label:` closure crashes outside `.toolbar { ... }` context.** Apple only documents the role-only form inside a toolbar block where the system synthesizes the X icon from the role. Inside any other context (popover body, sheet body, regular VStack) it asserts at first render. For non-toolbar close affordances use the explicit `Button { ... } label: { Image(systemName: "xmark.circle.fill") ... }.buttonStyle(.plain)` form. Established this session in `ViewSettingsPopover.swift`.

#### Pre-existing test state

All unit tests green except 4 pre-existing failures unrelated to this slice — 3 label-spec drift in `SettingsTests` + `UILabelThreadingTests` (expect `"Types"` but defaults seed `"Items"` post-v2 migration; tests need updating) + 1 timing flake in `PageEditorViewModelTests/debounceCoalescesRapidEdits`. 13 new `ViewSettingsScopeMappingTests` all pass.

#### Document pointers

- **Roadmap (chronological)**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md`
- **PRD**: `.claude/PommoraPRD.md`
- **Properties spec (single source of truth)**: `.claude/Features/Properties.md`
- **Per-entity specs**: `.claude/Features/{Domain-Model, Contexts, PageTypes, Pages, Items, Agenda, Homepage, NavDropdown, Sidebar, PageEditor, Architecture, Prospects, PommoraUIX}.md`
- **Paradigm-decision rules**: `.claude/Guidelines/Paradigm-Decisions.md`
- **Active planning + research notes**: `.claude/Planning/` (chrome-slice plan + research notes for the panes work)

#### Resume prompt for next session (verbatim)

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. v0.3.x View Settings chrome slice shipped + merged to main 2026-05-25 PM (button + empty 300×360pt Liquid Glass popover at ContentView level inside the existing primary-action capsule with NavDropdown + Inspector toggle). Both branches in sync at `48316be`. **APPROVED PLAN ready to execute:** `.claude/Planning/View-Settings-edit-properties-plan.md` (25 tasks, 9 phases) — ships v0.3.1 properties end-to-end: schema CRUD via popover + dynamic property-value columns in all 4 storage detail-view Tables + click-to-edit popovers for all 11 property types + Property Visibility pane. Plan mirrored to `/Users/nathantaichman/The Nexus/Pommora/Planning/` for RC viewing. **First action: invoke `superpowers:subagent-driven-development`** to dispatch the 25 tasks; each phase ships green standalone per quirk #8. Use `builder` subagent with `run_in_background: true` for xcodebuild (quirk #13). **Phase A (Tasks 1-5b) is foundation:** data layer additions (`DisplayVariant` / `dateFormat` / `singular` / `SavedView` real fields / `views[]` on Collections / default-view migration / PropertyChipColor cleanup to 12 cases) — start there. Plan body has exact code snippets + bite-sized TDD steps for each task. **Decisions locked in this plan:** chips render ONLY for Status/Select/Multi/Relation; Dates/Links/Numbers = pure text; Files = quaternary chip with link icon; LinkChip strips https:// + truncates 15 chars; Option ordering is drag-only (no Sort picker — that's v0.3.1.2's view-level surface); 10-color 5×2 selection grid (Default + Accent excluded). Quirks #15 + #16 + #17 still apply throughout. Chrome plan retires to Superseded at Task 22 of edit-properties plan."
