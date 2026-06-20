## Codebase Audit & Reorganization Scoping (Swift build)

Full harsh audit of the Swift Pommora codebase (excludes MarkdownPM + the React build). Produced by a 28-agent workflow: 23 area agents mapped + cleaned + analyzed disjoint directories, reporting findings back to the controller for the recommendations below. Build verified green at audit time (`** BUILD SUCCEEDED **`, 1,272 tests / 0 fail).

This is a `// Planning` scoping doc — it cites `file:line` evidence deliberately (an audit is a snapshot for action). Consume it into work, then remove it per the `// Planning` convention.

### Executive Summary

**The codebase is structurally healthy, well-tested, and conscientiously commented.** Observation/`@Observable` is already adopted throughout, the data layer is well-separated from the views, the on-disk paradigm is consistently honored, and 1,272 tests pass. This is not a rescue — it is a debt-reduction pass on a sound foundation.

**The debt is concentrated in three patterns, not in architecture:**

1. **Parallel-family duplication** — types are triplicated/twinned across Pommora's parallel families (Area/Topic/Project, Task/Event, the 9 validators, the 4 SavedView panes, Pinned/Recents). *Ratified caveat:* the per-type Context + Agenda **managers** are kept separate **on purpose** — headroom for features that will diverge per type — so the DRY target is the *non-divergent* duplication (panes, the filename-safety rule, CRUD scopes, index emitters) and the shared *mechanism*, never a manager merge. See §3.1.
2. **God-files** — a handful of files carry 3+ separable concerns (NexusAdopter 1,147 loc, GroupingPane 775, ViewSurface 747, PageTypeManager 1,077, IndexQuery 706, SidebarView 667).
3. **Manual boilerplate** — hand-rolled `Codable`, per-call `DateFormatter` allocation, and magic numbers that bypass the existing `PUI` token system.

**LOC baseline (code only, comments excluded):**

| Scope | Files | **Code** | Comments | Blank |
|---|---|---|---|---|
| App source (`Pommora/Pommora`) | 275 | **36,707** | 8,867 | 4,063 |
| Tests (`PommoraTests` + UITests) | 213 | **21,611** | 3,110 | 4,311 |
| **Total** | **488** | **58,318** | 11,977 | 8,374 |

**Findings:** 133 (21 high / 53 medium / 59 low) · by lens: complexity 34, DRY 33, outdated-swift 29, organization 21, repetition 16 · plus 63 Claude-defaults and 72 stress-test targets.

#### Top priorities (ROI-ranked)

| #   | Move                                                                                          | Effort                    | Payoff                                                          | Risk                                    |
| --- | --------------------------------------------------------------------------------------------- | ------------------------- | --------------------------------------------------------------- | --------------------------------------- |
| 1   | **Fix the 5 latent bugs** hiding in the Claude-defaults                                       | 1 session                 | Correctness                                                     | Low                                     |
| 2   | **DRY the non-divergent families** (panes, filename rule, CRUD scopes, index emitters) — keep per-type managers separate (§3.1) | 2–3 sessions | Removes mechanical duplication without blocking per-type divergence | Med — load-bearing UI/CRUD; TDD-gated |
| 3   | **Extract the shared-primitives layer** (the folder reorg)                                    | 2–3 sessions, incremental | Kills cross-folder coupling; enables DRY for views/styling      | Low–med                                 |
| 4   | **Break up the god-files**                                                                    | 2–3 sessions              | Cohesion, testability, fewer merge crashes                      | Med (quirks #8/#9)                      |
| 5   | **Replace manual `Codable` with synthesized + minimal-custom**                                | 2 sessions                | −~1,000 loc of lockstep-fragile boilerplate                     | Med — TDD legacy keys                   |
| 6   | **Modernize concurrency/formatters/throws** (`Task{@MainActor}`, `FormatStyle`, typed throws) | 2 sessions                | Idiom + fixes formatter drift bug                               | Low                                     |
| 7   | **Extract `PommoraTestSupport`** + close boundary/concurrency coverage gaps                   | 2 sessions                | Test maintainability + stress coverage                          | Low                                     |

> **Honest scope note on "aggressive modernization":** SwiftData / `@Model` is **excluded** — it would move data into a binary store and break the three load-bearing constraints (files-are-canonical, cross-nexus queryability, agent-legibility). Likewise the AppKit bridges (`NSOutlineView`, TextKit 2, `NSViewRepresentable` shims) are **intentional** where SwiftUI falls short and are not "modernization" targets. The modern wins below are the ones that respect those constraints.

---

### 1 · Codebase Map

The 275 app files resolve into six layers. (Per-area detail with key types lives in the workflow output; this is the structural skeleton.)

**Data substrate** — atomic file I/O + index + pure value types
- `AtomicIO/` — `AtomicJSON`, `AtomicYAMLMarkdown` (foreign-key-preserving merge), `Filesystem`, `NexusPaths`, `SchemaTransaction` (two-phase multi-file commit), `FolderFilter`.
- `Index/` — `PommoraIndex` (GRDB, schema v14), `IndexSchema` (DDL), `IndexBuilder` (cold rebuild), `IndexUpdater` (incremental), `IndexQuery` (read facade).
- `Validation/` — 9 pure validators + `NexusContext` + `NameCollisionValidator`.

**Domain entities + managers** — folder+sidecar CRUD
- `Vaults/` — `PageType`/`PageCollection`/`PageSet` + their managers + schema value types (`PropertyDefinition`, `PropertyValue`, `SavedView`).
- `Contexts/` — `Area`/`Topic`/`Project` + three managers + tier config.
- `Agenda/` — `AgendaTask`/`AgendaEvent` + managers + schemas + `Recurrence`.
- `Content/` — `PageContentManager` (+CRUD), `PageFile`/`PageFrontmatter`/`PageMeta`/`PageParent`.
- `Nexus/` — `NexusManager`, `NexusEnvironment` (single injector, quirk #15), `NexusAdopter`, `PropertyIDMigration`.

**View pipeline** (pure, testable) — `Detail/ViewPipeline/` (`GroupResolver`, `FilterEvaluator`, `SortComparator`), `Detail/Table/TableColumnResolver`, `VisiblePropertyOrder`.

**View surfaces** — `Detail/` (`ViewSurface`, `ViewOutlineTable`, `GalleryView`), `ViewSettings/` (5 panes), `Sidebar/`, `Pages/` (editor), `Homepage/`, `Properties/` (editors).

**Shared primitives (today scattered — see §4)** — `DesignSystem/PUI` + modifiers, `Properties/Chips/*`, `Ordering/`, `CRUD/`, `Connections/`.

**Shell** — `PommoraApp`, `ContentView`, `NavDropdown/`, `ComponentLibrary/` (DEBUG-only).

---

### 2 · The Five Lenses

#### 2.1 Organization
- **God-files** (high): `NexusAdopter.swift` (1,147 loc — model + classifier + disk-mutation), `GroupingPane.swift` (775 — 12 view types + 2 enums + 3 extensions), `ViewSurface.swift` (747 — render + pipeline + drag + cover + rename + delete + menus), `PageTypeManager.swift` (1,077 — Type CRUD + Collection CRUD + View CRUD + Schema CRUD), `SidebarView.swift` (667 — 5 top-level types; shared `SelectableRow`/`SelectionChrome`/`SectionHeader` buried at the bottom), `IndexQuery.swift` (706 — `FilterBuilder` + ~12 DTOs).
- **Misplaced types**: `SavedConfig` (sidebar-label config) sits in `Contexts/`; `ReservedTypeID` (Agenda singletons) sits in `Vaults/`; `FlowLayout` (general layout) buried in `Properties/Chips/MultiSelectChips.swift` yet consumed by `Detail/`; a generic `FlowingHStack: Layout` trapped in the DEBUG-only `ComponentLibraryView.swift`.
- **Single-file folders** fragment the tree: `CRUD/`, `Ordering/`, `Components/`, `Filesystem/` each hold 1–2 tiny files.

#### 2.2 DRY (the dominant lens)
The headline is **parallel-family duplication** — see §3.1. Beyond it:
- **ViewSettings panes**: the `scope→typeID` switch is copy-pasted **6 times** (`PropertiesListPane:93`, `EditPropertyPane:531`, `LayoutPane:250`, `SortPane:146`, `FilterPane:290`, `PropertyTypePickerPane:78`); `currentView()`, the "No view configured" empty-state, and the commit-error banner are each duplicated across all 4 SavedView panes.
- **PUI bypass**: `PropertyCellDisplay.swift` inlines 9 raw font sizes + paddings/radii while its sibling `ViewTableCells.swift` correctly uses `PUI.Spacing` — `PUI.swift:25-26` explicitly forbids the magic numbers.
- **Per-call formatters**: `PropertyValue.swift` re-instantiates two `DateFormatter`/`ISO8601DateFormatter` at **four** sites (init + encode); the Index layer holds three more with **divergent options** (a real bug, §6).
- **Hand-shared utilities re-implemented**: `AtomicJSON` reimplemented inline in `AppState` + `NexusIdentity`; the Crockford ULID alphabet hardcoded in both `ULID` and `ULIDValidator`; the XCTest modal-guard (quirk #16) duplicated across 4 files.

#### 2.3 Un-needed complication
- **Dead code**: `Sidebar/Sheets/IconPickerField.swift` (entire file, zero call sites); `MultiSelectChips` "add option by typing" path (contradicts the locked Properties spec; sole caller passes `false`); `PropertiesPulldown`'s entire VM + `showAddPicker` state (re-declared as private View copies); `OrderResolver.titleKeyPath` (vestigial, threaded through ~30 call sites, author already flagged it removable); `NexusAdopter` `skipped`/`contentSniff` scaffolding.
- **Over-built**: `PropertyValue.init(from:)` runs **five speculative `try?` decodes** in a precise order (decodes `[FileRef]` twice); `ViewSurface.columns` mutates a copy of the active view to force-show, with the same status-grouping rule re-applied in a second computed.

#### 2.4 Repetition across files
Captured in §3.1 (families) and §2.2. Notable additional: the inline-rename row wiring (`RenameableRow` + commit + clearEditing) is duplicated across all **6** entity rows; the stub-and-edit `createX()` flow is reimplemented **~10 times**; the atomic-rename-with-rollback block appears **4 times** verbatim in the Vaults managers.

#### 2.5 Outdated Swift (modernization map — constraints-respecting)
| Theme | Where | Modern form |
|---|---|---|
| **Manual `Codable`** (largest) | `PageType`, `PageCollection`, `PageSet`, `SavedView`, `PropertyDefinition`, `Area/Topic/Project`, `AgendaTask/Event`, `AppState` | Synthesized + `decodeIfPresent` defaults; custom **only** for legacy-key fallbacks |
| **`DispatchQueue.main.async`** inside `@MainActor` | `ContentView:282`, `RenameableRow:91`, `SidebarView:469`, `OptionEditPopover:63`, `WindowToolbarConfigurator` | `Task { @MainActor in … }` |
| **Per-call formatters** | `PropertyValue`, Index layer, `TimeFormat`/`DateFormat`/`FilterPane` | `static let` + `FormatStyle` / `.ISO8601` |
| **`try! NSRegularExpression`** | `ConnectionScanner:11` | Swift `Regex` |
| **Untyped `throws`** | every `Validation/*` (pure, total, one error enum each) | `throws(ValidationError)` typed throws |
| **Hand-rolled comparators** | `SortComparator`, `GroupResolver` stable-sort | `SortComparator` / `sorted(using:)` |
| **`if(condition:)` View ext** | `GroupingOptionsList:81` | always-apply + gated drop |
| **`@State var vm?` + `onAppear` init** | `FileAttachmentEditor`, `FrontmatterInspector` | `@State` init or `.task` (no first-render-nil) |
| **XCTest** (mixed with Swift Testing) | numerous suites | finish Swift Testing migration |

---

### 3 · Where DRY Pays Off Most

#### 3.1 What to DRY — and what to keep separate

**Keep separate (Nathan-ratified headroom, *not* debt):** the **per-type Context managers** (`AreaManager`/`TopicManager`/`ProjectManager`) and **Agenda managers** (`AgendaTaskManager`/`AgendaEventManager`) stay distinct concrete types — their entities are expected to grow *different features*, and a generic merge would block that divergence. Their structs/schemas stay separate too (the manual-`Codable` boilerplate inside them is trimmed in place by §5 item 3, no merge). If the copy-paste in the shared CRUD *mechanism* ever grates, a `protocol` with default implementations removes it while leaving every type independent — optional, your call, not a debt item.

**Still worth collapsing (no divergence rationale — purely mechanical):**

| Target | Duplication | Collapse to |
|---|---|---|
| **Filename-safety rule** | title-shape block copy-pasted in **9** validators; invalid-char set hardcoded 8× (+ `NexusManager.renameRoot`'s own variant) | One shared rule; per-entity validators stay thin separate wrappers |
| **SavedView panes** | Layout/Sort/Filter/Grouping share `currentView()` / empty-state / error-banner / the scope→typeID switch (6 copies) | A shared pane scaffold + computed props on `ViewSettingsScope` |
| **Page CRUD scopes** | Collection/Set/Type-root triplicated 70-loc blocks in `PageContentManager+CRUD` | One scope-parameterized CRUD path (same op, different bucket) |
| **Index emitters** | `upsertContext` ×3 SQL; tier context-links emitted in both `IndexBuilder` + `IndexUpdater` | One `upsertContext(id,tier,title,icon)` + one tier-link emitter (index layer — no entity merge) |
| **NavDropdown stores** | `PinnedManager`/`RecentsManager` byte-identical `updateTitle` + load/save skeleton | A `StateJSONStore` base — *unless* you want these kept separate too (same headroom logic; your call) |

> ⚠️ The pane/CRUD collapses touch load-bearing paths. Do them **TDD-first, one at a time, behind the 1,272-test net**, per stub-and-progressively-replace. Not a big-bang.

#### 3.2 Other high-value hoists
- `schemaOptionOrder`/`optionOrderIndex` (must stay in lockstep) → one `schemaOptionValues(_:)`.
- Tier context-link emission duplicated across `IndexBuilder` + `IndexUpdater` → one shared emitter.
- Security-scoped image-import + size-cap + collision-name implemented 3× (`CoverAssetStore`, `AttachmentManager`, `NexusHeaderBanner` inline) → one asset-import service.
- Hover-fill rounded-rect idiom repeated 4× in DateTimePicker (and wanted elsewhere) → a project-wide `.hoverFill()` `ViewModifier`.

---

### 4 · Folder Reorganization Guide

**Two principles, both yours:** **(a)** split **Components** (design assets — reusable, themeable, *no business logic*) from **Features** (full user-facing capabilities); **(b)** give the *emergent shared layer* — today scattered inside feature folders (`Detail` → `Properties/Chips/FlowLayout`, `DateTimePicker` → `Properties/Chips/ChipDropdownPanel`) — a real home so DRY for views/styling/design becomes the path of least resistance. The React build already organizes exactly this way (a `Components/` layer feeding the `Sidebar/`+`Detail/` features), so this is a proven shape.

**Proposed top-level structure** (move, don't rewrite):

```
Pommora/
  Core/                     ← pure substrate, no SwiftUI, no feature logic
    IO/                       AtomicJSON, AtomicYAMLMarkdown, Filesystem, NexusPaths, SchemaTransaction
    Index/                    PommoraIndex, IndexSchema, IndexBuilder, IndexUpdater, IndexQuery
    Validation/               shared filename-safety rule + thin per-entity validators
    Model/                    PropertyDefinition, PropertyValue, SavedView, ULID (+ ULIDValidator)
    Ordering/                 OrderResolver, OrderPersister  (absorb the 1-file folders)
    Formatters/               shared static DateFormatter/FormatStyle (kills the §6 drift bug)
  Components/               ← DESIGN ASSETS only: reusable, themeable, showcase-able, no feature logic
    Tokens/                   PUI (single source of spacing/type/radius/fill)
    Modifiers/                fieldBackground, toolbarGlyph, hoverFill (new), SelectionChrome
    Layout/                   FlowLayout, FlowingHStack  (pulled out of Properties + the DEBUG file)
    Chips/                    PropertyChip, ChipDropdown, ContextChip, StatusCheckbox, …
    Row/                      a unified Row primitive — slots (icon · label · trailing · drag-handle ·
                              drop-indicator) + typed selection/rename state; subsumes SelectableRow +
                              RenameableRow + the 6 per-entity rows  (the React Row lesson, §9)
    Inputs/                   the inline-edit field primitive (one source for rename + banner editing)
    DateTimePicker/           (unchanged)
  Domain/                   ← entities + their (separate) managers
    Contexts/ Vaults/ Agenda/ Pages/      ← per-type managers stay distinct (§3.1)
  Features/                 ← FULL FEATURES: complete user-facing surfaces
    Sidebar/ Detail/ ViewSettings/ Editor/ Homepage/ NavDropdown/
  App/                      PommoraApp, ContentView, NexusEnvironment
  Debug/                    ComponentLibrary (the showcase OF the Components layer)
```

**The Components/Features line:** it's a **Component** if it has no business logic and could sit in the showcase (a chip, a button, the Row, a modifier, a token); it's a **Feature** if it's a complete capability a user invokes (the sidebar, the table/gallery detail, view settings, the editor). `ComponentLibrary` is the *showcase of* Components — the same relationship as the React design-system showcase.

**Highest-value moves first (each independently shippable):**
1. `Properties/Chips/*` → `Components/Chips/` (removes the most cross-folder coupling).
2. Build the **`Row` primitive** in `Components/Row/` and re-skin the sidebar onto it (**rewrite, don't amend**) — the React build's #1 component lesson: the 6-way duplicated inline-rename wiring *and* the drag-ghost color patch both dissolve into one `Row` with typed state + a real drag-handle/drop-indicator slot (§9).
3. `FlowLayout` + `FlowingHStack` → `Components/Layout/`.
4. Shared formatters → `Core/Formatters/` (consolidating fixes the §6 drift bug).
5. Move misplaced singletons: `SavedConfig` out of `Contexts/`, `ReservedTypeID` to `Agenda/`.

> Both targets use `PBXFileSystemSynchronizedRootGroup` (quirk #2), so folder moves auto-track — but verify the build per move and keep the `Section`/`SelectionChrome` shapes intact (quirks #8/#9).

---

### 5 · Prioritized Refactor Backlog

1. **Quick-win bug + dead-code sweep** *(1 session, low risk)* — fix §6 latent bugs; delete the 5 dead-code items in §2.3. Pure subtraction, immediate clarity.
2. **Shared-primitives extraction** *(2–3 sessions, incremental)* — the §4 moves 1–4. Each is a self-contained green commit.
3. **Manual `Codable` → synthesized** *(2 sessions)* — default values + `decodeIfPresent`; keep custom only for the genuine legacy keys (`vault_id`, `visible_properties`, `relation_scope`, favorites→pinned). TDD the legacy-key + foreign-frontmatter preservation paths first.
4. **DRY the non-divergent families** *(2–3 sessions, TDD-gated)* — §3.1: the filename-safety rule, the SavedView pane scaffold, the Page-CRUD scope path, the index emitters. **Per-type Context + Agenda managers stay separate** (ratified — headroom for divergent features).
5. **God-file breakups** *(2–3 sessions)* — `NexusAdopter` (model/classifier/mutation), `GroupingPane` (extract the reusable rows + label catalogs), `ViewSurface` (extract rename/delete/cover), `PageTypeManager` (split Collection + Schema CRUD), `IndexQuery` (`FilterBuilder` → own file).
6. **Concurrency + formatter + typed-throws modernization** *(2 sessions)* — `DispatchQueue→Task{@MainActor}` sweep, shared `FormatStyle`, typed throws on validators, Swift `Regex`.
7. **Test-support module + coverage** *(2 sessions)* — §7.
8. **PUI enforcement** *(1–2 sessions)* — route the scattered magic numbers through tokens; add `.hoverFill()`.

---

### 6 · Claude-Decisions to Revisit (D6)

These were almost certainly *Claude* choices made for expedience, not *Nathan* decisions. Triaged by stakes.

#### 🔴 Latent bugs (fix in §5 item 1)
| Bug | Where | Effect |
|---|---|---|
| `schema_version` hardcoded `1` instead of the entity field | `IndexUpdater.swift:98` (`upsertPageCollection`) | Index disagrees with the entity; every sibling upsert passes the real value |
| Datetime filter formatter omits `.withFractionalSeconds` | `IndexQuery.swift:540-547` vs index-write paths | A datetime-property filter **silently never matches** stored timestamps |
| `created_at` strict-decode falls back to the **1970 epoch** | `PageFrontmatter.swift:80` | A page missing `created_at` sorts/shows as 1970-01-01 |
| Corrupt `state.json` silently replaced with defaults | `OrderPersister.swift:97` (`?? NexusState()`) | Drops **all** pins / recents / active-views / order on next write |
| Property-group drop onto a non-select property writes `.select(bucket)` | `GroupDropPlanner.swift:108` | Wrong on-disk value if a date/number group ever accepts a drop |

#### 🟠 On-disk defaults that hardened by accident (ratify before data accrues — this is the "confirm paradigm-solidifying choices" HARD RULE)
- Adopted-Page id = `SHA256(path)[:16]` with `adopted-` prefix — digest/length/prefix unratified (`PageFile.swift:60`).
- Option-value minting differs by type: Status `opt_<ULID>` vs Select bare `ULID.generate()` (`VaultSettingsSheet.swift:498-508`).
- `context_links.id` uses `UUID` in `IndexBuilder` but `ULID` in `IndexUpdater` (regeneratable, but inconsistent).
- `schemaVersion` "current" constants scattered as bare literals (`2` for PageType, `1` for Collection/Set) with no shared source.
- `loadAll` mints + rewrites sidecars on the **read** path (heal-on-read silently writes user files on first open).

#### 🟡 Versioning-rule violations (HARD RULE: no version stamps in code/copy)
- `StatusGroupsEditor.swift:73` ships "surfaces in a future v0.3.1.x patch" to the **user**.
- `PommoraApp.swift:67` comments "until … v0.6.0 (Task 7.6)".
- `PageType.swift:13,23` field comments stamp "v0.2".

#### 🟡 Other notables
- `AreaColor.blue` maps to the same `Color` as `AreaColor.accent` — two enum cases render identically; saved "blue" vs "accent" are indistinguishable.
- `SidebarConfirmation` hardcodes entity-kind words ("Vault", "Collection", "Set", tier names) despite those labels being user-renameable via Settings.
- ~40 magic numbers bypass `PUI` (font sizes, paddings, panel dimensions, opacity haircuts) — low-risk individually, but exactly the drift `PUI` exists to prevent.
- Multiple bare `catch {}` on async move/rewrite/delete/cover paths swallow errors silently.

---

### 7 · Stress-Test Targets (D7)

The 1,272 tests are strong on happy-path round-trips and weak on **boundaries, concurrency, malformed input, and 3+ multiplicity.** Highest-value gaps:

**Fragile logic that is thinly covered**
- **NSOutlineView teardown invariants** (documented prior crashes): never-remove-`Title`, the reload-vs-collapse jank guard, status-grouping forced-first column (`ViewOutlineTable.swift:217-260, 291-318`).
- **Hand-rolled drag-drop index math** everywhere — zone-boundary clamps, cross-group multi-select drags, virtualized-card append, the `src<dst ? -1 : 0` shift (recurs in `PropertyIDReorder`, `ChipDropdown`, both option editors, two-zone row reorder).
- **`PropertyValue` 5-probe speculative decode** — a string that is both URL-and-date, or a 1-element array that is both `FileRef` and multiSelect.
- **One-shot destructive adoption/migration** — ParadigmV2 unwrap when a user folder is literally named `Pages`/`Agenda`; `rekey()` skipping any property whose name starts with `_`/`prop_`.
- **Atomic-rename double-failure rollback** + `moveSet`'s divergent throw-ordering vs the three renames.
- **`ViewSettingsButton` popover when `AppGlobals.current` is nil** → SIGTRAP via missing env injection (quirk #15).

**Missing coverage to add** (concrete): exact-boundary cap values (50 MB / 500 MB / `end_at == start_at`); concurrency (two managers / two `IndexUpdater`s on one `dbQueue`; racing `updatePage`); folder-name collision on rename; corrupt/BOM/CRLF file decode; Unicode/emoji/whitespace/reserved-char titles; 3+ duplicate-heal and 3+ connection multiplicity; self-connection rejection.

**Missing test-support module (DRY for tests):** `TempNexus.make()` + the `makePageType/makePageCollection/makePageSet/writePage` fixtures + `makeIndex(at:)` + the 15-arg `AgendaTask/Event` literals are re-inlined across ~50+ suites. Extract a `PommoraTestSupport` target and collapse the three parallel `Area/Topic/Project` manager-test suites — this closes gaps and shrinks the 21,611 test-loc materially.

---

### 8 · Comment-Cleanup Report

The in-pass cleanup ran against all 488 files. **It came back deliberately conservative:**

| | Lines removed | Rewritten (verbose→tight "why") | Kept as load-bearing |
|---|---|---|---|
| App | 61 | 9 | 1,261 |
| Tests | 98 | 10 | 410 |

Git ground-truth: **49 files changed, ~199 deletions / 33 insertions** (net ~−166 lines).

**Why so little came out:** the agents evaluated ~1,671 comments and judged the overwhelming majority genuine "why" — the high 24% comment ratio is mostly **legitimate density**, not bloat. The code documents real gotchas (NSOutlineView teardown crashes, GRDB overload hygiene, drag-type UTI registration, Swift-6 concurrency requirements, on-disk format decisions). The keep-on-doubt rubric (a wrongly-removed "why" costs more than a kept borderline "how") plus that genuine density is why the cut is small.

**This pass's only code-touch (not comment-only):** `Index/PommoraIndex.swift:139` — an agent removed an empty `} else {}` shell after stripping its only comment. Behavior-preserving, **compiles, all 1,272 tests pass** — kept. (Flagged because it technically breached "comments only.")

**Not from this pass — a parallel session:** `Sidebar/SidebarView.swift` carries a `labelColor` (`.white`) change with its own drag-ghost rationale comment. This is Nathan's concurrent sidebar-polish work that landed in the shared working tree; surfaced per quirk #10, untouched. `SidebarView.swift`'s diff is *purely* that change (no comment edits from this pass), so it is cleanly separable by path from the cleanup.

**Decision point for Nathan:** if you want a heavier cut, I can run a second, more aggressive pass with a "remove unless clearly load-bearing" rubric (inverts the bias). My recommendation is **not** to — the data says the comments are mostly earning their place, and aggressive removal would start cutting genuine value.

---

### 9 · React Build — Cross-Applicable Lessons

The React rebuild (same PRD, same paradigm) has already hit and solved problems the Swift build is about to face. The transferable ones (React-specific Electron / vanilla-extract traps omitted):

- **The `Row` primitive is the sidebar-duplication fix.** React's recon concluded its bad drag UX "is a `Row` problem, not 'no components' broadly," and built one `Row` (slots: drag-handle + drop-indicator, tokenized indent/height, **typed state union**) that subsumed leaf + disclosure rows. Swift's mirror: the 6-way duplicated inline-rename wiring + `SelectableRow`/`RenameableRow` collapse into one `Components/Row` (§4 move 2).
- **The drag ghost should render the real Row, not a bare label.** React explicitly fixed "the drag ghost re-implements the row as a bare label" by rendering the same `Row`. That is the *deeper* version of the parallel session's `SidebarView.labelColor` patch (which fixes the ghost's *color*): once a real `Row` exists, the ghost renders it and the color special-case disappears.
- **Components-first, and "rewrite don't amend."** React sequences the component library *before* re-skinning surfaces, and rewrites each surface onto the new component rather than patching it. Same discipline for the Swift `Components/` extraction.
- **Swift already has the tokens React is still building.** React's open gap is "spacing + radius are ad-hoc literals — tokenize first." Swift is *ahead* (`PUI` exists), so the Swift task is **enforcement** — route the ~40 magic numbers through `PUI` (§6) — not authoring. Don't let the existing token system rot into the ad-hoc state React is climbing out of.
- **Fresh-filename-per-save for assets (convention watch-item).** React learned "a stable asset filename behind glass is a stale-image trap" and writes a fresh `banner-<token>.<ext>` per save so the URL always changes. Swift's `CoverAssetStore` instead uses collision-safe naming off the *source* filename — it mostly dodges the trap (a replaced image gets a new name → new URL) but it's a weaker guarantee. Worth aligning to the fresh-token convention when the asset-import service is consolidated (§3.2), especially as the parallel session is touching `NexusHeaderBanner`'s inline store.
- **Operational: path-limited commits under parallel sessions.** React's standing rule is `git commit -- <paths>` so a concurrent session's staging can't leak in. That is exactly how I'll land the cleanup once your sidebar work commits — cleanup files + this doc, **excluding** `SidebarView.swift`.

---

### Method & Caveats
- 23 area agents (disjoint dirs) + 5 cross-cutting lenses. **The 5 lenses failed on a transient API rate-limit**, so the cross-cutting synthesis above is the controller's, built directly from the 23 area inventories (which is the requested division: agents find, controller recommends).
- All work is on branch **`audit-comment-cleanup`** (off `nexus-header`), **uncommitted** — the comment edits and this doc are there for review.
- Build + tests verified green at audit time. Nothing here changes runtime behavior except the one `PommoraIndex` simplification.
