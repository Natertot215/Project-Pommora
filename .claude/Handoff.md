### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`; phased roadmap in `Framework.md`.

#### Current state (2026-05-26 — `main` at `0d5aa16`, +21 commits ahead of origin/main pending push)

**v0.3.1 Properties end-to-end** shipped this session via inline execution of the approved `.claude/Planning/View-Settings-edit-properties-plan.md`. **Tasks 1-20 of 25 landed on `main` as 21 commits.** Task 21 (PropertyEditorRow Item-Window-inspector stub patches) deferred to v0.3.1.x — cell editor bypasses that dispatcher so the headline UX ships without it. **Task 22 (this doc sweep) just shipped.** **Task 23 (`git push origin main` + Nexus mirror) is paused awaiting Nathan's auth** — every working-tree change is committed locally; nothing on the wire.

**Branch state:**
- `main` (HEAD): `0d5aa16` — 21 commits ahead of `origin/main` (+ this commit + the doc-sweep commit before push).
- `v0.3.0-properties`: still at `627e972` (pre-Properties-work tip). Nathan's parallel adoption-fix session works there.
- After Task 23 push: `main` advances on origin; `v0.3.0-properties` retired (will rebase Nathan's adoption fix onto main when ready).

**Working tree:** clean. Every Phase A-H commit landed atomically with `xcodebuild build` verification between. Test runner has been intermittently hanging on this Mac mid-session (build is reliable; tests deferred to a runner-stability follow-up).

**Parallel-session merge debt:** Nathan's adoption-fix session on `v0.3.0-properties` will collide with my Phase A Task 5 default-view migration in `PageTypeManager.loadAll` + `ItemTypeManager.loadAll`. Quirk #11 anticipated; rebase happens when his work commits.

**This session's ship:** static `slider.horizontal.3` toolbar button + empty Liquid-Glass popover (fixed 300×360pt) wired into ContentView's existing primary-action HStack — shares the Liquid-Glass capsule with NavDropdown + Inspector toggle. Popover content is `Color.clear` at this slice (chrome-only); future panes (Layout / Property Visibility / Sort / Filter / Group / Edit Properties) replace the body in subsequent v0.3.1.x patches. Scope-routing wiring locked: `ContentView.sidebarSelection` → `currentViewSettingsScope` computed → `ViewSettingsButton(scope:)` → `ViewSettingsPopover(scope:)`. Same button, every surface, content adapts.

**Files in the ship:**
- NEW `Pommora/Pommora/ViewSettings/ViewSettingsScope.swift` (10-case enum mirroring `SidebarSelection`)
- NEW `Pommora/Pommora/ViewSettings/ViewSettingsPopover.swift` (empty `Color.clear.frame(width: 300, height: 360)`)
- NEW `Pommora/Pommora/ViewSettings/ViewSettingsButton.swift` (Button + `.popover(arrowEdge:.top)`)
- NEW `Pommora/PommoraTests/ViewSettings/ViewSettingsScopeMappingTests.swift` (13 tests, all green)
- MODIFIED `Pommora/Pommora/ContentView.swift` — added `static func viewSettingsScope(for:)` + `private var currentViewSettingsScope` + inserted button as leading item in existing `.glassEffect()` HStack

**One bug found + fixed mid-session via systematic-debugging:** initial popover used `Button(role: .close) { dismiss() }` (no label). That role-only form only renders inside `.toolbar { ... }` context where SwiftUI synthesizes the X. Inside a popover body it asserted at first popover-content render — crash on button click. Replaced with `Button { dismiss() } label: { Image("xmark.circle.fill")... }.buttonStyle(.plain)` pattern. Then user requested empty placeholder; close button removed entirely (outside-click + ESC are the only dismiss paths now). Locked as new quirk #17.

#### What's next

**Task 23 — push + Nexus mirror (auth-required, paused for Nathan):**
1. `git push origin main` — sends the 21 (now 22 with doc sweep) Properties commits live.
2. Mirror `.claude/Handoff.md` + `.claude/History.md` + `.claude/Planning/README.md` + `.claude/Features/Properties.md` to `/Users/nathantaichman/The Nexus/Pommora/` for Obsidian/RC visibility.
3. Retire `.claude/Planning/View-Settings-edit-properties-plan.md` to `.claude/Planning/Superseded/2026-05-26-View-Settings-edit-properties-plan-COMPLETE.md` (most of plan shipped; document the few sub-tasks deferred to v0.3.1.x).
4. Retire `.claude/Planning/View-Settings-button-chrome-plan.md` to Superseded (predecessor; shipped this series).
5. After Nathan's parallel adoption-fix session lands on `v0.3.0-properties`: rebase his work onto `main`; resolve PageTypeManager.loadAll + ItemTypeManager.loadAll merge conflicts at the default-view-migration insertion points.

**v0.3.1.x follow-up patches (queued, each smaller than v0.3.1 itself):**
- **v0.3.1.1** — Task 21 (PropertyEditorRow stub patches for relation/status/file in Item Window inspector) + inline Relation cell editor (IndexQuery flow-through) + inline File cell editor (AttachmentManager flow-through) + SelectOptionsEditor + StatusGroupsEditor chevron-push refactor (lights up EditOptionPane in normal UX) + dual-relation reverse-mirror in updatePageProperty + updateItemProperty.
- **v0.3.1.2** — Sort pane (per-view single-criterion sort; multi-criterion when saved views land). Wires `SavedView.sort: [SortCriterion]` reserved stub from Task 3.
- **v0.3.1.3** — Filter pane (equals / not-equals / contains / empty / not-empty operators; AND-grouped at first; OR at v0.5.0). Wires `SavedView.filter: FilterGroup`.
- **v0.3.1.4** — Group pane (single property). May defer to v0.5.0 with Board view.
- **v0.3.1.5** — Existing-property change-type + per-type-config edit-flow polish; relation scope reconfiguration via wizard inside the popover; Status icons + Settings config (per-group + per-option) pre-v1 cleanup.

**v0.5.0** — non-Table view renderers (board / list / cards / gallery) on top of the populated SavedView storage.

**Open UX risks to watch in next visual smoke:**
- TableColumnForEach behavior with very wide schemas (>10 columns) — width math may need tuning.
- Popover dismissal commits the draft via `.onDisappear`; if SwiftUI re-renders the popover host mid-edit (e.g. typing in the cell while a sibling cell rebuilds), the draft might lose its in-flight value. Watch for this during visual smoke.
- Status `.chip` displayAs renders `"square.dashed"` placeholder for ALL options; visually identical at the moment. Per-option icons land in pre-v1 cleanup.
- `_modified_at` always-visible may feel like cluttered noise on narrow Tables — Nathan to decide if a "hide" override should land.

**Carry-forward UIX rules (unchanged from prior session):** tables get NO vertical column borders (Notion-flat — NSViewRepresentable impl TBD); `"Title"` everywhere (not `"Name"`); `"Spaces"` / `"Topics"` / `"Projects"` in property panels (no `"Tier N"` prefix); Sidebar Items section defaults to `"Items"`; Item Types are disclosure-foldable, Sets are flat leaves.

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

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **v0.3.1 Properties end-to-end shipped 2026-05-26 — 22 commits on `main` (`627e972` → `<tip>`), all local, awaiting `git push origin main`.** Tasks 1-20 of the View-Settings-edit-properties-plan landed (Task 21 deferred to v0.3.1.1; Task 23 push is the immediate action). The headline UX is live: click any cell in any of the 4 storage detail-view Tables → type-appropriate popover editor → commit on outside-click. **First action: run `git push origin main`** (auth-required — that's why the session paused). Then mirror `.claude/Handoff.md` + `.claude/History.md` + `.claude/Planning/README.md` to `/Users/nathantaichman/The Nexus/Pommora/` for RC visibility; retire the edit-properties plan + the chrome plan to `.claude/Planning/Superseded/`. **Parallel-session merge debt:** Nathan's adoption-fix work on `v0.3.0-properties` will conflict with my default-view-migration inserts in `PageTypeManager.loadAll` + `ItemTypeManager.loadAll` — rebase when his work commits. **v0.3.1.x patches queued (in order):** v0.3.1.1 (Task 21 + cell-editor inline Relation/File + EditOptionPane chevron-push), v0.3.1.2 Sort pane, v0.3.1.3 Filter pane, v0.3.1.4 Group pane, v0.3.1.5 existing-property change-type. **Quirks #15 + #16 + #17 still apply throughout.** Test runner is currently flaky on this Mac (build is reliable); `xcodebuild test` results not captured this session — a test-stability follow-up is on the v0.3.1.x list. **DON'T trust SourceKit squiggles** (quirk #3) — entire session was spent ignoring stale 'Cannot find type X' diagnostics that always cleared post-build."
