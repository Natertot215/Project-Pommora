### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history in `History.md`; phased roadmap in `Framework.md`.

#### Current state (2026-05-27)

**Folders feature reverted in full this cycle** (see `History.md` → "Folders — tried and reverted"). The third Pages-side tier (`PageType → PageCollection → Folder → Page`) was built end-to-end then removed: it duplicated Collections' rigid-grouping role and conflicted with the still-unbuilt view-organization system (Board / group-by / saved views, v0.6.0) — you can't group-by-property while displaying a fixed container hierarchy in the same view, and that primitive doesn't exist yet to prove folders were even needed. Removed before more features piled onto the third tier.

**Kept from the effort:**
- **F.0** (commit `68caf96`) — system-wide stub-and-inline-rename CRUD (`CreateWithInlineEdit` + `DefaultTitleResolver`; manager `create*` return new entity via `@discardableResult`; 9 `New*Sheet.swift` deleted).
- **Sidebar context-menu tweaks** — "New Vault" removed from the PageType row menu (the Pages-section "+" header is the sole vault-creation path); plain "New X" labels (dropped the "(in This …)" suffixes).
- **`NexusAdopter.autoTagMissingSidecars`** for Types + Collections — drag a folder structure into a Nexus via Finder and it's recognized on launch (two-tier; folder depth-3 stripped).

**Mechanics of the revert:** 26 files reverted to the pre-folders baseline (`68caf96`), 9 folder files deleted, surgical folder-strip on `NexusAdopter` + `AdoptionPreviewView` + `NexusAdopterAutoTagTests` (auto-tagger kept two-tier). Build verified green — **304 tests pass across 16 regression suites**; parallel Properties/ViewSettings working-tree code compiles clean. Removal plan: `.claude/Planning/2026-05-27-folders-removal-plan.md`. Beyond-folders cleanup backlog: `.claude/Planning/2026-05-27-codebase-health-log.md`.

**Pending: commit + push.** `origin/main` is at `e2a5dc0` (folders shipped); the revert commit backs that out. Both sessions share `main` — **`git pull origin main` at session start** once the revert lands.

#### Side-channel: parallel v0.3.1 Properties UX rebuild — in-flight in working tree

Nathan has separate in-progress edits to the property editor surfaces (`Properties/Editor/SelectOptionsEditor.swift`, `Properties/Editor/StatusGroupsEditor.swift`, `Properties/Chips/PropertyChipColor.swift`, `Properties/PropertyTypePicker.swift`, `ViewSettings/EditOptionPane.swift`, `ViewSettings/EditPropertyPane.swift`, `ViewSettings/PropertiesListPane.swift`, `ViewSettings/PropertyTypePickerPane.swift`, `ViewSettings/PropertyVisibilityPane.swift`, plus new files `ViewSettings/PropertyEditorErrorMessage.swift` + `Properties/Editor/OptionEditPopover.swift`). These are NOT in the F.0 / F.1 commits — they sit in working tree as a coherent parallel-session unit.

**API shape iterated mid-session.** `SelectOptionsEditor` / `StatusGroupsEditor` signatures changed from 1-arg `(options:)` to 4-arg `(options:propertyID:path:onAddOption:)` and then back to 2-arg `(options:onAddOption:)`. My commits never touched these editor files; my F.0 reconciled call-site patches to `Properties/TypeSettingsSheet.swift` + `Properties/VaultSettingsSheet.swift` are LIVE in working tree against the current 2-arg shape but were not committed (they pair with parallel-session work, not with F.0's intent). When Nathan ships the v0.3.1 properties work, those Settings-sheet patches should ride along.

#### Properties polish session — paused 2026-05-26 (pending Nathan review)

> Slice 1 popover iteration in working tree. **Improved but unverified.** Every theme below is provisional until Nathan smokes it.

**State:** uncommitted in working tree, compile-clean per last build. Sits in working tree as its own coherent unit — commit independently when ready.

**Files touched:** `Properties/Editor/{SelectOptionsEditor,StatusGroupsEditor,OptionEditPopover (NEW)}.swift`, `Properties/{PropertyTypePicker, Chips/PropertyChipColor}.swift`, `ViewSettings/{EditPropertyPane, StorageMenuRoot, PropertiesListPane, PropertyVisibilityPane, PropertyTypePickerPane, EditOptionPane, PropertyEditorErrorMessage (NEW)}.swift`, `DesignSystem/PUI.swift`. Settings-sheet patches in `Properties/{VaultSettingsSheet,TypeSettingsSheet}.swift` ride along.

**Themes (provisional — pending smoke):**

- Inline `OptionEditPopover` (double-click on chip) replaces chevron-push for option editing.
- Pill backgrounds on title TextFields + icon Buttons via `Color.primary.opacity(0.06)`.
- Bare `Menu` (`.menuStyle(.borderlessButton)`) replaces `.pickerStyle(.menu)` for inline selectors.
- Delete + Duplicate moved INSIDE the EditPropertyPane scroll body; dividers inset.
- Snapshot→live binding refactor in `PropertiesListPane` + `PropertyVisibilityPane`.
- Section labels at `.headline`; `PUI.Icon.header` at `.title3` / frame 28pt.
- SymbolPicker constrained to 540×460 popover (both pane + sheet entry points).

**Slice 2/3 backlog — NOT started:**

1. **Doubled "Done" in cell editor.** Render `Menu` directly from Status/Select/MultiSelect Table cells; skip `PropertyCellEditor`'s popover wrapper. File: `Detail/Columns/PropertyCellEditor.swift`.
2. **Column drag-reorder.** macOS 14+ `TableColumnCustomization` + `.customizationID(...)` per column in all four detail views; persist to `view.visibleProperties` via `updateView()`. Confirm public order accessor; ship session-only first if API gates persistence.
3. **Snapshot→live for `userPropertyColumns`** in all four detail views — re-query manager by stable type ID instead of reading from the `pageType` snapshot.

**Why paused:** `OptionEditPopover` alignment loop ate time. Paused for focus + documentation before detail-view work.

**Open UIX questions (smoke-needed):** popover rail alignment at sub-pixel level, `StorageMenuRoot` vs `EditPropertyPane` pill parity, SymbolPicker 540×460 visual feel, `.headline` section labels relative to chip text, `+ Add` row tap-target size.

**Discipline (continues, unchanged):** STOP-and-ASK on uncertainty • audit by reading actual files before claiming complete • in-line code only for frontend (background `building-apple-platform-products` agent for build verify) • Auto Mode OFF • match design references exactly • derive measurements from math.

**Reference:** principles captured in `.claude/Guidelines/Design.md` (Liquid Glass continuity + Context-aware padding sections).

**Resume:** continue Slice 2/3 backlog with same discipline. (The folders work that previously shared `Pommora/Vaults/`, `Pommora/Index/`, `Pommora/Nexus/`, `Pommora/Content/` has been reverted, so the prior coordination caveat no longer applies.)

#### Locked decisions this session (F.0 paradigm-affecting)

1. **Esc on a freshly-stubbed entity leaves it created.** Sidecar literally named "New Collection" / "New Collection 2" / etc. stays on disk until user renames or deletes via context menu. No delete-on-cancel.
2. **TextField select-all-on-fresh-stub only.** When a row enters rename mode because it was just stub-created (`justCreatedID == entity.id`), the entire default title is pre-selected so first keystroke replaces it. Existing rename-from-context-menu keeps cursor-at-end.
3. **`isCreating` flag guards rapid double-clicks** at every trigger site. Disabling the button/menu item while a create Task is in flight prevents collision toasts from the default-title disambiguator.
4. **Context-tier in scope of F.0** (Space / Topic / Project) — plan's "every New X" prose interpreted as system-wide; explicit list expanded to 9 entities total.
5. **Detail-view footer "+" buttons drive sidebar rename mode** by sharing `editingID` + `justCreatedID` bindings via ContentView (lifted from SidebarView's local @State).
6. **Manager `create*` methods return their new entity** via `@discardableResult` — backward-compatible with existing call sites; coordinator reads the new id for the editingID flip.

#### Parallel-session coordination note

**The v0.3.1 Properties UX rebuild work in `Pommora/Properties/Editor/*`, `Pommora/Properties/Chips/*`, `Pommora/Properties/PropertyTypePicker.swift`, and `Pommora/ViewSettings/*` is uncommitted in working tree** as of session end. The settings-sheet call-site patches I wrote to keep the build green (matching whatever editor signature is current) are also uncommitted. When Nathan finishes the Properties rebuild, those patches need to ride along with that commit (not with the folders-revert commit).

#### Resume prompt for next session (verbatim)

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **Folders feature was reverted in full** (see History.md "Folders — tried and reverted"); kept F.0 stub-and-inline-rename CRUD, the sidebar menu tweaks, and the Types/Collections auto-tagger. The revert is verified green (304 tests / 16 suites). **First: `git pull origin main`** — confirm the folders-revert commit landed and the parallel Properties session is synced. Then resume the actual next priority: **build the view-organization system** (Board / group-by / sort / filter / saved views) — that's the primitive that defines how Pommora organizes, and the reason folders were premature. **DO NOT touch** `Pommora/Properties/*` or `Pommora/ViewSettings/*` (parallel v0.3.1 Properties work in working tree). Codebase-health backlog for opportunistic cleanup: `.claude/Planning/2026-05-27-codebase-health-log.md`."

#### Locked rules from the Properties rebuild (durable — schema, correctness, workflow)

> UIX-specific design choices that may change (type picker layout, drag affordances, gesture canonicalization, design-tool workflow) have been removed from this list. They live in the active plan + working code until smoke-verified and locked.

1. **Property Visibility shows ONLY user properties + `_modified_at`.** Reserved IDs (`_id`, `_created_at`, `_status`, `_tier1/2/3`, `_wikilinks`) do not appear in the user-facing visibility list. Schema-level decision.
2. **Error display uses user-friendly sentences.** Raw enum descriptions (`String(describing: error)`) banned. Errors clear on every fresh user input.
3. **All popover-side surfaces MUST read live from the manager via stable IDs.** Never from captured `ViewSettingsScope` payloads. Property-pane equivalent of quirk #16 (env re-injection).
4. **STOP-and-ASK on uncertainty.** Any uncertainty about interaction model, UX flow, design specifics, gesture behavior, error-state copy, drop-target affordances, or animation behavior → stop and ask Nathan. No guessing.

#### Locked decisions in force (carry forward from prior sessions)

1. **Status value on-disk encoding = `{"$status": value}` tagged-object form.**
2. **Move-strip matches by NAME, not ID.** Property IDs are globally unique per `property_definitions.id PRIMARY KEY`.
3. **Reserved property IDs:** `_id`, `_created_at`, `_modified_at`, `_status`, `_tier1/2/3`, `_wikilinks`. User-defined mint `prop_<ulid>`.
4. **`schema_version: 1` on every sidecar.**
5. **`PropertyIDMigration` runs on EVERY nexus open** — idempotent.
6. **tier1/2/3 are root-level frontmatter fields** (not under `properties:`).
7. **AgendaTask + AgendaEvent default seed = single `_status` property.**
8. **`DualRelationCoordinator` owns paired-relation lifecycle.**
9. **`AttachmentManager` is the only path for file values.**
10. **Settings carries `defaultsVersion: Int`** bumped to v2 on 2026-05-25.
11. **Items + Pages are NOT renameable concepts** — only containers are (Vault / Collection / Type / Set).
12. **View Settings button = single static instance at ContentView level inside the existing primary-action `.glassEffect()` HStack.**
13. **`PUI` design tokens** — single source of truth for paddings / spacings / icons / fonts / radii. Forbidden in new code: magic-number padding. Extend `Pommora/Pommora/DesignSystem/PUI.swift` rather than inlining raw values.
14. **`PaneHeader` is the chrome for every View Settings sub-pane** — no `.navigationTitle(_:)` allowed on pushed panes.
15. **`SidebarSelection` no longer reads `AppGlobals`** — all selection resolution goes through `SidebarLookupBundle`. AppGlobals is forbidden as a selection-resolution source.
16. **Popover-side surfaces read live from the manager via stable IDs.** `PropertiesListPane`, `EditPropertyPane`, `PropertyVisibilityPane`, `EditOptionPane` must NEVER read state from captured `ViewSettingsScope` payloads — always look up via type ID / property ID / option value from the live manager. View-state propagation equivalent of quirk #16 (env re-injection).
17. **Visibility lists show ONLY user properties + `_modified_at`.** Reserved IDs are filtered out — they have no place in a user-facing visibility list.

#### Active branch quirks (carry forward to every subagent dispatch)

1. **Test filter form uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`. Suite-name form silently no-ops.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include.
3. **Trust `xcodebuild`, not SourceKit squiggles.**
4. **`.claude/*` is included in commits.**
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`.
6. *(retired in ParadigmV2)*
7. **Xcode auto-reorders SymbolPicker/Yams/GRDB entries in pbxproj on every build** — incidental noop diff. Revert before commit.
8. **Stub-and-progressively-replace** is the locked execution strategy.
9. **Section structure in SidebarView is load-bearing.** Don't break `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns.
10. **Sidebar selection chrome at row file level via `.listRowBackground(SelectionChrome(...))`.**
11. **Parallel-session caveat** — Nathan may have a separate session running small UI tweaks.
12. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`).
13. **Use `Agent run_in_background: true` for builder-subagent verification** — Nathan does not want xcodebuild grabbing window focus. **This session reaffirmed: code-writing in-line by Claude; xcodebuild verification via background Agent.**
14. **GRDB `String` overload pollution in @ViewBuilder closures** — isolate per-row rendering into private struct sub-views.
15. **`loadAll` must sync in-memory parents to the SQLite index.** Defensive INSERT OR REPLACE upserts after disk load (PageTypeManager + ItemTypeManager).
16. **Every `@Environment(X.self)` declared on a detail view OR popover-hosted view must be explicitly re-injected at the boundary** — every env a detail view declares must also be in `ContentView.detail`'s `.environment(...)` chain (~line 237).
17. **`Button(role: .close) { dismiss() }` without an explicit `label:` closure crashes outside `.toolbar { ... }` context.**
18. **(NEW this session)** **STOP-and-ASK on uncertainty.** Any uncertainty about interaction model, UX flow, design specifics, gesture behavior, error-state copy, drop-target affordances, or animation behavior → stop implementing and ask Nathan. No guessing, no "I'll pick something reasonable." Lesson from the v0.3.1 slice-execution drift.
19. **(NEW this session)** **Zero subagents for any frontend-touching work.** All SwiftUI / view-layer code is written in-line by Claude. Applies across Slices 1, 2, AND 3 of the Properties rebuild — every step touching the View Settings popover, EditPropertyPane, EditOptionPane, options editors, PropertyVisibilityPane, PropertyTypePicker, detail-view Table columns, cell editor popovers, or any other UI surface. Permitted carve-outs: read-only Explore agents for code-survey; `building-apple-platform-products` background xcodebuild runs per #14 (verification only, no code-writing).

#### Properties rebuild scope summary

Beyond Slice 1 (above), the rebuild plan covers:

- **Slice 2 — v0.3.1.1 "Dynamic columns in detail views."** Build `updatePageProperty(...)` + `updateItemProperty(...)` atomic single-property writes. Build `PropertyColumnBuilder` + `PropertyCellDisplay` using existing chip primitives. Wire all 4 detail views.
- **Slice 3 — v0.3.1.2 "Click-to-edit cell popovers."** Build `PropertyCellEditor` wrapper. Wire 11 per-type editor popovers (reuse PropertyEditorRow dispatcher). Patch PropertyEditorRow relation / status / file stubs to real editors.

Items NOT in the three-slice scope (still queued for follow-up):

- Simple-type inline anchored popover split (Number / URL / Checkbox / File) — may not be needed if Slice 3's universal popover model proves clean.
- Date & Time consolidation (drop `.date`, keep only `.dateTime`).
- Relation editor full redesign (searchable target picker + Show on [target] toggle + mirror name + Limit) — after Slice 3 ships.
- StorageMenuRoot 8-row redesign (inline-edit Vault/View title rows) — only after Slice 3, with Figma in the loop.
- `@FocusState` click-outside-commits — small fix; can piggyback on any slice.
- Sidebar / detail-view chrome PUI migration — separate concern, not blocking property work.

All deferred items get their own focused plan documents after Slice 3 ships green.

#### Document pointers

- **Active plan (Properties rebuild)**: `.claude/Planning/2026-05-26-v0.3.1-properties-rebuild-plan.md`
- **Folders revert record**: `.claude/Planning/2026-05-27-folders-removal-plan.md` (feature tried + reverted)
- **Codebase health backlog**: `.claude/Planning/2026-05-27-codebase-health-log.md`
- **Superseded plan (v0.3.1 original)**: `.claude/Planning/Superseded/2026-05-26-View-Settings-edit-properties-plan-COMPLETE.md` — referenced by the rebuild plan for UIX detail recovery
- **Roadmap (chronological)**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md`
- **PRD**: `.claude/PommoraPRD.md`
- **Properties spec (single source of truth)**: `.claude/Features/Properties.md`
- **Per-entity specs**: `.claude/Features/{Domain-Model, Contexts, PageTypes, Pages, Items, Agenda, Homepage, NavDropdown, Sidebar, PageEditor, Architecture, Prospects}.md`
- **CRUD pattern**: `.claude/Guidelines/CRUD-Patterns.md`
- **Paradigm-decision registry**: `.claude/Guidelines/Paradigm-Decisions.md`
- **Figma source for property editor**: `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`

