### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`; phased roadmap in `Framework.md`.

#### Current state (2026-05-25 — v0.3.0 Properties FEATURE-COMPLETE; merged to main)

**v0.3.0 Properties shipped end-to-end.** 71 commits on `v0.3.0-properties` merged into `main` as `3d1bc19` and pushed to `origin/main`. Branch `v0.3.0-properties` preserved on `origin/v0.3.0-properties`.

**All 11 phases A–K done.** See `History.md` for the full per-phase ship table. Headline:

- **Data layer (full):** 11 property types · stable ULID `id` identity · SchemaTransaction atomic multi-file commits · PropertyIDMigration runs every nexus open · schema CRUD on all 4 schema-bearing managers · 8-rule validator · SchemaConflictDialog drift defense · DualRelationCoordinator paired-relation lifecycle · `_status` built-in on AgendaTask + AgendaEvent · name-matched move-strip · file attachments (50/500 MB caps, cascade-delete) · Settings auto-migration scaffold.
- **SQLite index (live end-to-end):** GRDB · 12 tables · IndexBuilder filesystem walk · IndexUpdater wired into all 6 managers · IndexQuery Notion-style filter/sort/broken-links. Mid-session mutations propagate.
- **Placeholder UI (every interaction has a working path):** PropertyEditorRow dispatcher · StatusPicker · RelationPicker · FileAttachmentEditor · RelationPropertyWizard · PropertyTypePicker · VaultSettingsSheet + TypeSettingsSheet · MoveStripConfirmationDialog · PropertyPanel · PropertiesPulldown · FrontmatterInspector live editors · Item Window inspector toggle + pinned chips · column-header click-to-sort · CalendarDetailView + Calendar pin right-click create · UI labels threaded from `SettingsManager`.

#### What's next

**Immediate:** smoke-test v0.3.0 on Nathan's real nexus before release tagging. Launch app → exercise migration sheet → property panel → status picker → relation picker → attachment editor → schema editor sheet → calendar view → move-strip dialog. The unit suite is green but only an actual launch catches integration regressions across the 13 new UI surfaces.

**Next minor:** **v0.3.1 — Properties Pulldown + Property Panel polish (Figma-driven fast-follow).** Polishes the `PropertiesPulldown` lazy properties + "+ Add property" picker + auto-managed divider section, and the `PropertyPanel` SwiftUI component (host-agnostic; slots into any inspector). MultiSelectChips color refactor. SchemaEditorRouter for cross-surface right-click → "Edit options…" routing into Type Settings. Plan likely drafted into `.claude/Planning/v0.3.1-...md` once scoped.

**After that:** v0.3.x patches (Item Window redesign, Claude chat main-window inspector, PreviewWindow primitive — timing TBD) → v0.3.2 page-wikilinks → v0.3.3 file watcher + FTS5 + external-edit detection → v0.4.0 Trash UI → v0.5.0 view types. See `Framework.md` for the full chronological roadmap.

#### Locked decisions in force (v0.3.0)

1. **Status value on-disk encoding = `{"$status": value}` tagged-object form.** Matches the `{"$rel": id}` relation pattern. Pure shape-sniff at the Codable layer can't disambiguate `.status` from `.select`; tagged form is round-trip-stable + agent-legible.
2. **Move-strip matches by NAME, not ID.** Property IDs are globally unique per `property_definitions.id PRIMARY KEY`; ID-based cross-type matching is structurally impossible. Pages keep values where dest has a same-named property.
3. **Reserved property IDs:** `_id`, `_created_at`, `_modified_at`, `_status`, `_tier1/2/3`, `_wikilinks`. User-defined mint `prop_<ulid>`.
4. **`schema_version: 1` on every sidecar.** Legacy → 0 = needs migration. Index DB has its own `schema_version` in `meta`; mismatch triggers delete + rebuild.
5. **`PropertyIDMigration` runs on EVERY nexus open** — idempotent; preview shows per-Type counts before commit.
6. **tier1/2/3 are root-level frontmatter fields** (not under `properties:`). Edited via `ContextTierPicker`.
7. **AgendaTask + AgendaEvent default seed = single `_status` property.** Legacy `type` Select removed; load-path migration backfills via SchemaTransaction.
8. **`DualRelationCoordinator` owns paired-relation lifecycle.** Manager `addProperty`/`deleteProperty` route paired relations through it.
9. **`AttachmentManager` is the only path for file values.** Copy-on-attach into `<nexus>/.nexus/attachments/<entity-id>/`; cascade-delete to trash on entity delete.
10. **Settings carries `defaultsVersion: Int`** for forward-compat stale-default migration. `Settings.migrate(_:)` is the step-function scaffold.

#### Active branch quirks (carry forward to every subagent dispatch)

1. **Test filter form uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`. Suite-name form silently no-ops with `** TEST SUCCEEDED **`. Visually verify count.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include; pbxproj usually doesn't need editing.
3. **Trust `xcodebuild`, not SourceKit squiggles.** "Cannot find type 'X'" and "No such module 'Testing'/'GRDB'" diagnostics are routinely stale post-edit; always builder-verify, never chase squiggles.
4. **`.claude/*` is included in commits.** Don't auto-bundle docs into Swift commits without explicit ask; explicit doc commits are fine.
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`. Snapshot pattern for `@Sendable` closures: hoist `let id = ULID.generate()` before building entity.
6. *(retired)*
7. **Xcode auto-reorders SymbolPicker/Yams/GRDB entries in pbxproj on every build** — incidental noop diff. Revert before commit.
8. **Stub-and-progressively-replace** is the locked execution strategy for branch-spanning plans. Each task ships green standalone; later phases replace earlier stubs in-place.
9. **Section structure in SidebarView is load-bearing.** Don't break `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns.
10. **Sidebar selection chrome at row file level via `.listRowBackground(SelectionChrome(...))`.**
11. *(retired — parallel-session sidebar work landed at `2fada62`)*
12. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`). The direct `swift-format` binary is NOT on `$PATH`.
13. **Use `Agent run_in_background: true` for builder-subagent verification** — Nathan does not want xcodebuild grabbing window focus. Always builder via background Agent with `-only-testing:PommoraTests` to skip UI tests.
14. **GRDB `String` overload pollution in @ViewBuilder closures** — `SQLSpecificExpressible` conformance on String causes overload ambiguity for `==` and `contains` inside SwiftUI views. Workaround: isolate per-row rendering into private struct sub-views with plain value types; use `first(where:)` not `contains(_:)`. Pattern established in `RelationPicker.swift`.

#### Pre-existing test state

All unit tests green at branch merge. The two flakes carried earlier in the branch (`NexusAdopterTests/applyNathansActualShape` + `PageEditorViewModelTests/debounceCoalescesRapidEdits`) are now resolved or absorbed.

#### Document pointers

- **Roadmap (chronological)**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md` (v0.3.0 ship entry at top)
- **PRD**: `.claude/PommoraPRD.md`
- **Properties spec (single source of truth)**: `.claude/Features/Properties.md`
- **Per-entity specs**: `.claude/Features/{Domain-Model, Contexts, PageTypes, Pages, Items, Agenda, Homepage, NavDropdown, Sidebar, PageEditor, Architecture, Prospects}.md`
- **Paradigm-decision rules**: `.claude/Guidelines/Paradigm-Decisions.md`
- **Planning**: `.claude/Planning/README.md` (currently empty — no active plans)

#### Resume prompt for next session (verbatim)

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **v0.3.0 Properties FEATURE-COMPLETE** — 71 commits on `v0.3.0-properties` merged to `main` as `3d1bc19` (pushed). All 11 phases A–K shipped end-to-end: data layer + SQLite index live + full placeholder UI suite. Smoke test on Nathan's real nexus is the gate before release tagging. **Next:** v0.3.1 — Properties Pulldown + Property Panel Figma-driven polish (fast-follow on the placeholder UI shipped in J.13/J.11). Plan to be drafted into `.claude/Planning/` once scoped. Locked v0.3.0 decisions in `Handoff.md` § "Locked decisions in force." Use `superpowers:subagent-driven-development` for execution; `builder` subagent with `run_in_background: true` for xcodebuild (quirk #13). Quirks #1 FILENAME test filter; #3 SourceKit squiggles always stale post-edit; #14 GRDB String overload pollution in @ViewBuilder closures (private struct sub-view workaround). Properties.md is canonical spec; History.md is canonical ship log; Framework.md is chronological roadmap."
