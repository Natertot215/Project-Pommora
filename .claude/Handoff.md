### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`; phased roadmap in `Framework.md`.

#### Current state (2026-05-25 — 28 commits ahead of `origin/main` on `v0.3.0-properties`)

**v0.3.0 Properties FEATURE-COMPLETE + merged to main 2026-05-25 morning** (71 commits, tip `3d1bc19`). The `v0.3.0-properties` branch is now the **staging branch for v0.3.x patches**; today's session added 17 commits on top — 11 from the Items-Detail-Views plan (executor-driven) + 6 from interactive UX correctness work.

**Branch tip:** `88c9367` (pushed to `origin/v0.3.0-properties`).

**Today's session ships (chronological):**

| Cluster | Commits | Outcome |
|---|---|---|
| Items-Detail-Views plan (Tasks 1-11) | `adcb66c` → `55bf8c3` (11 commits) | All 4 storage detail views shipped with footer + drag-reorder; real NewItemSheet; columns no Kind |
| Disclosure pattern restore | `dd441f1` | Item Types fold (mirror Vaults); Sets render as flat leaves without chevrons. Fixed structural-asymmetry crash risk per quirk #9 |
| Items section label | `675e378` | Sidebar default `"Types"` → `"Items"` + Settings.migrate v1→v2 (preserves user customization) |
| Real stub-replacement sheets | `9a6aac0` | NewItemTypeSheet + NewItemCollectionSheet (Name + Icon forms) |
| Chip primitives + PommoraUIX | `cedb75b` | PropertyChip (2 variants × 13 colors in 2 tiers) + PropertyCheckbox + ChipDropdown + Cmd+Shift+D debug window. Pulldown removed from PageEditor |
| Crash fix | `c8b3cbc` | `ItemTypeManager` + `SettingsManager` injected into SidebarDetailView env (was EXC_BREAKPOINT in `_TaskValueModifier.Child.value.getter` on Item Type select) |
| Icon pipeline | `09e7a27` | `createItem` + `createPage` accept + persist `icon: String?`; NewPageSheet gains IconPickerField (was discarding selection) |
| Label sweep | `a8bd20b` | `"Name"` → `"Title"` everywhere (4 detail views + 8 sheet TextFields). `"Tier 1 (Spaces)"` → `"Spaces"` (drop Tier# prefix) in ItemWindow + RelationPropertyWizard |
| **SQLite FK fix** | `88c9367` | `PageTypeManager.loadAll` + `ItemTypeManager.loadAll` defensively upsert types + collections to index. Eliminates `INSERT OR REPLACE INTO pages... FK constraint failed` toast that hit when CRUD ran against entities loaded from disk that weren't in the DB (adoption / external-folder scenarios). 4 regression tests cover the invariant |

#### What's next

**Immediate:** smoke-test on real nexus (FK fix needs Cmd+R to verify the popup is gone).

**Active brainstorm — v0.3.1.x Storage View Redesign** (research done, spec not yet written). Design decisions locked:
- **Toolbar button** = `slider.horizontal.3` (Apple HIG: per-view configurator). Standard SwiftUI toolbar button sizing.
- **Popover** = `.popover(isPresented:)` with `NavigationStack` for submenu push/pop (WWDC25 #323 confirms Liquid Glass auto-applies in toolbar-anchored popovers).
- **Menu structure** mirrors Notion exactly:
  - Header: view icon + editable view name
  - View settings section: Layout / Property visibility / Filter / Sort / Group
  - Divider + "DATA SOURCE SETTINGS" subhead
  - Edit properties (schema CRUD, opens same surface as toolbar gear)
- **Property Visibility row** = click-to-toggle with **strikethrough** on muted (no eye icon)
- **Storage:** `views[]` array per sidecar (4 of them), single entry today, multi at v0.5.0
- **Delivery:** 4-5 patches v0.3.1 → v0.3.1.4 (user picked Approach B — patch-series drip)

**UIX rules locked this session:**
- **Tables have NO vertical column borders.** Only bottom border under headers. Notion-flat aesthetic (vs Finder's column-separated). Forward-applies to all storage detail views + v0.5.0 view types. SwiftUI Table needs NSViewRepresentable + cleared `gridStyleMask` to enforce (TBD implementation).
- **`"Title"` everywhere** (not `"Name"`) — column headers, form placeholders, rename dialogs.
- **Tier labels = `"Spaces"` / `"Topics"` / `"Projects"`** in property panels. No `"Tier N"` prefix.
- **Sidebar Items section = `"Items"`** (renameable; defaults to "Items" not "Types").
- **Item Types are disclosure-foldable** (mirror Vaults); Sets render as flat leaves WITHOUT chevrons (no further sidebar children to disclose).

**Research findings captured** at `.claude/Planning/View-Settings-research-notes.md` (Notion UX patterns + SwiftUI primitives — feed directly into the eventual spec).

**After v0.3.1.x cluster:** Per-item properties UX wiring (chip primitives → PropertyPanel / Item Window inspector / FrontmatterInspector — chips exist but aren't consumed anywhere except PommoraUIX) → Item Window redesign → PreviewWindow primitive → Page-wikilinks → file watcher → Trash UI → v0.5.0 non-Table view renderers.

Note: **v0.5.0 scope narrows** as v0.3.1.x lands. The per-view filter / sort / visible-properties + view-config storage that was scheduled for v0.5.0 ships at v0.3.1.x; v0.5.0 reduces to "non-Table renderers (board/list/cards/gallery)." Framework.md needs updating to reflect this (deferred — low priority).

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
10. **Settings carries `defaultsVersion: Int`** for forward-compat stale-default migration. `Settings.migrate(_:)` step-function. Bumped to v2 on 2026-05-25 (`"Types"` → `"Items"` label fix).
11. **Items + Pages are NOT renameable concepts** — only their containers are (Vault / Collection / Type / Set). `"New Item"` and `"New Page"` are fixed literals; no `settings.labels.item` or `.page` exists.

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
11. *(retired — parallel-session sidebar work landed at `2fada62`)*
12. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`). The direct `swift-format` binary is NOT on `$PATH`.
13. **Use `Agent run_in_background: true` for builder-subagent verification** — Nathan does not want xcodebuild grabbing window focus. Always builder via background Agent with `-only-testing:PommoraTests` to skip UI tests.
14. **GRDB `String` overload pollution in @ViewBuilder closures** — `SQLSpecificExpressible` conformance on String causes overload ambiguity for `==` and `contains` inside SwiftUI views. Workaround: isolate per-row rendering into private struct sub-views with plain value types; use `first(where:)` not `contains(_:)`. Pattern established in `RelationPicker.swift`.
15. **`loadAll` must sync in-memory parents to the SQLite index.** Established 2026-05-25 in `88c9367`. PageTypeManager.loadAll + ItemTypeManager.loadAll defensively upsert types + collections after disk load (INSERT OR REPLACE makes it idempotent; `try?` swallows failures since the index is regeneratable). The architecture's prior contract — "DB stays in sync via incremental CRUD upserts after IndexBuilder runs once" — breaks for entities arriving outside CRUD (adoption / external Finder folders / post-adoption state). Without this sync, any page/item CRUD into a non-CRUD-created vault triggers SQLite error 19 (FK constraint failed) toast. Regression-tested in `LoadAllIndexSyncTests.swift`. Future detail-view detail loaders (PageContent / ItemContent) inherit the same gap and may need similar sync if their FKs ever escalate.
16. **Every `@Environment(X.self)` declared on a detail view must be injected at `ContentView.detail`'s `.environment(...)` chain.** Locked 2026-05-25 via `c8b3cbc`. SwiftUI's `_TaskValueModifier` KeyPath-resolves env values when computing the `.task` closure; missing env asserts at runtime as EXC_BREAKPOINT — not a clean error. Symptom is "crash on first selection routing to that view." When adding a new env to a detail view, ALSO add it to the optional-unwrap chain at `ContentView.swift:237` AND the `.environment(...)` chain immediately after.

#### Pre-existing test state

All unit tests green at branch merge + today's tip. The 4 new `LoadAllIndexSyncTests` pass. The two flakes carried earlier in the branch (`NexusAdopterTests/applyNathansActualShape` + `PageEditorViewModelTests/debounceCoalescesRapidEdits`) remain resolved.

#### Document pointers

- **Roadmap (chronological)**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md`
- **PRD**: `.claude/PommoraPRD.md`
- **Properties spec (single source of truth)**: `.claude/Features/Properties.md`
- **Per-entity specs**: `.claude/Features/{Domain-Model, Contexts, PageTypes, Pages, Items, Agenda, Homepage, NavDropdown, Sidebar, PageEditor, Architecture, Prospects, PommoraUIX}.md`
- **Paradigm-decision rules**: `.claude/Guidelines/Paradigm-Decisions.md`
- **Active planning + research notes**: `.claude/Planning/`

#### Resume prompt for next session (verbatim)

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. v0.3.0 Properties merged to main; **today (2026-05-25) added 17 commits on `v0.3.0-properties` branch** — Items-Detail-Views plan complete + 6 UX/correctness fixes (env-injection crash, Items section label, real stub-replacement sheets, chip primitives, PommoraUIX debug window, icon pipeline, Name→Title, Tier# prefix removal, SQLite FK fix). Branch tip `88c9367` on `origin/v0.3.0-properties`. **Active brainstorm:** v0.3.1.x Storage View Redesign — toolbar `slider.horizontal.3` popover w/ NavigationStack submenus mirroring Notion's view-settings menu (Layout / Property Visibility / Filter / Sort / Group / Edit Properties); research notes at `.claude/Planning/View-Settings-research-notes.md`; spec NOT yet written. **UIX rules locked:** tables get NO vertical column borders (Notion-flat); 'Title' everywhere not 'Name'; 'Spaces'/'Topics'/'Projects' (no 'Tier #' prefix); Items section default 'Items'; Item Types fold like Vaults with Sets as flat leaves. **Quirks #15 + #16 are new** — loadAll syncs parents to index (regression-tested); every detail-view @Environment must be injected at ContentView.detail. Locked decisions + quirks in `Handoff.md`. Use `superpowers:subagent-driven-development` for execution; `builder` subagent with `run_in_background: true` for xcodebuild (quirk #13)."
