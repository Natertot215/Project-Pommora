### Pommora — Project Instructions

#### Overview

A simpler Notion that's also a more capable Obsidian. **2-layer PARA-aligned domain model** (locked 2026-05-16; ParadigmV2 refactor 2026-05-22):

- **Organization layer — Contexts** (3 tiers): Spaces (1) / Topics (2) / **Projects** (3). All three are composed-blocks surfaces. Per-tier labels user-configurable per Nexus.
- **Operational layer — Items + Pages + Agenda**:
  - **Items** — `.json` files inside Item Types; Item Collections organize within. Items-side UI labels: **"Type"** + **"Set"**.
  - **Pages** — `.md` files inside Page Types; Page Collections organize within. Pages-side UI labels: **"Vault"** + **"Collection"**.
  - **Agenda** — split into Agenda Tasks (`.task.json`, EKReminder-shaped) and Agenda Events (`.event.json`, EKEvent-shaped). Data layer ships v0.3.0; sidebar surfacing is consolidated into the Calendar pin entry (no separate Agenda sidebar heading).
- **Singleton — Homepage**: composed-blocks dashboard at `.nexus/homepage.json`.
- **Settings scaffold** (`.nexus/settings.json`): per-Nexus user-overridable UI labels + accent color (Phase 7 — storage + label wiring; editing UI ships v0.6.0).

**Code layer is symmetric** (PageType / PageCollection / ItemType / ItemCollection — same shape, different content). **UI vocabulary diverges per side** — Pages get the distinctive "Vault" + generic "Collection"; Items get the generic "Type" + distinctive "Set". Each side has one signature word and one shared word. All UI labels renameable via Settings.

Items open in a popover-style **Item Window** (title + properties + 250-char description, not a full-frame surface); Pages open in the main detail pane. (Standalone-window previews are queued behind the cross-feature PreviewWindow primitive; not yet wired.) Per-tier multi-relations (`tier1` / `tier2` / `tier3`) connect operational entities to Contexts. SQLite indexes properties, links, and relations. Personal-first, Mac-first for v1, always open-source.

#### HARD RULES

- @Paradigm-Decisions carries more specific information.

- **The Component Library is the source of design.** Components and design come from the Component Library as reusable assets — stage them there and pull them into production; avoid one-off designs whenever possible.

- **Condensed, exhaustive control flow.** Model a finite set of states as an `enum` and branch with a `switch` (the compiler then enforces every case), rather than chains of `if/else` or loose booleans/strings. Favor the tightest structured form that stays legible.

- **DRY — one source of truth.** When the same logic, mapping, or rendering would live in two or more places, hoist it into a single function or type and reuse it; never copy-paste behavior across call sites.

- **`Handoff.md` is a lean snapshot maintained via `/handoff`.** Sections: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Never accumulate per-session work logs.

 - **Re-assess the plan between green commits.**  After each task ships green, read the active plan against what just landed. If the task surfaced wrong assumptions, missing prerequisites, scope drift, or shortened/expanded downstream tasks, rewrite the affected later tasks before dispatching the next one. The plan is the controller's live working theory of the work, not a fixed script — only green commits are facts. Pairs with #4 — #4 keeps the build green between tasks; #13 keeps the plan accurate between tasks.

#### Stack

Locked to **SwiftUI**. **Editor = TextKit 2 + Apple `swift-markdown` + vendored `swift-markdown-engine` & small Pommora-side customizations** (shipped v0.2.7.0; full spec → `// Features//PageEditor.md`). React+Electron is preserved as a contingency path — playbook + topic files at `// ReactInfo//`.

#### Core Principles

- **Three load-bearing constraints:** (1) **conceptual portability of functionalities** — file formats, schemas, design values, UX patterns survive a stack rebuild; (2) **cross-nexus queryability + cloud sync compatibility** — the on-disk model maps cleanly to a cloud DB so sync arrives as additive translation; (3) **persistent immediate legibility for agents** — every entity is a file an external agent can read directly without tool-call round-trips. Full detail → `// Features//Architecture.md`.

- **Simplicity-first.** Don't add complexity that wasn't asked for. If it can be simplified, simplify it.

- **Files are canonical (≠ everything is Markdown).** Pages = `.md`, Items = `.json` — inside their Type folder (sidecar `_pagetype.json` / `_itemtype.json`), optionally within a Collection sub-folder; Agenda = `.task.json` / `.event.json`; Projects = `.project.json`; Settings = `.nexus/settings.json`. Operational containers live at the nexus root (no wrapper folders); SQLite is a regeneratable index — no user data trapped in it. Full on-disk spec → `PommoraPRD.md` + `// Features//Architecture.md`.

- **Filename = title** everywhere. No `title` field; no `name` field on Items. Renaming in the UI renames the file. Independent UI titles are a Prospect.

- **Pages are Markdown, Contexts are blocks.** Pages are Markdown documents (one continuous Markdown stream) with two Pommora-specific rendering directives — `@Columns` (multi-column rendering of a section) and `:::callout` (outlined-box callout, distinct from blockquotes).

- **Wikilinks render as styled colored inline text** (Obsidian-style), not Notion-style chips.

- **Relations stored by ID, displayed by icon + title.** Relation properties are always multi-value — frontmatter holds an array of the targets' IDs (rename-safe; `[{"$rel": "<ULID>"}]`); each value renders as the target's current icon + title in styled colored text (the single `RelationChip` primitive — a dedicated chip visual is a future design). Tiers are relations: `tier1` / `tier2` / `tier3` on Items / Pages / Agenda are pre-configured relation properties (merged via `BuiltInRelationProperties`), stored at frontmatter root, edited inline like any relation.

- **Inline editing principle.** Every embedded view in a composed-blocks surface (Context, Homepage) is a live, fully-editable view of its source — never a read-only snapshot. Full inline editing of a referenced Page's body (Notion synced blocks) is post-v1.

- **"Pommora" prohibited in on-disk schemas + Swift namespace qualifications.** Brand name reserved for the module name (`Pommora` Swift module), app branding, and documentation. NOT allowed in:
  - On-disk JSON field names (no `pommora_*` keys)
  - Swift type qualifications used as a discriminator pattern (no `Pommora.X` workarounds for stdlib collisions; use side-prefixed names like `AgendaTask` instead of `Pommora.Task`)

  Existing `pommora_table_widths` (page editor) is grandfathered for v0.3.0; rename when Tables ship.

- **Design system: SwiftUI primary + AppKit where needed**
 Pommora uses SwiftUI semantic colors (`Color(.systemBackground)`, `.primary`, etc.), Materials (`Material.regular`, `.sidebar`), and Font scale (`.font(.body)`, `.font(.callout)`) wherever possible; AppKit is used directly via `NSViewRepresentable` where SwiftUI falls short (notably NSTextView / TextKit 2 for the Page editor, NSSplitView for splitter polish). 

- **The local file is the spec, not the render.** In-line views and computed values are referenced by directive, not inlined.

#### Document Map

- `PommoraPRD.md` — high-level product requirements + architecture; storage model + SQLite schema
- `Handoff.md` — current state and near-term priorities (read first at session start)
- `History.md` — locked decisions, brief
- `Framework.md` — phased roadmap to v1.0 (CRUD paired with paradigm at every phase)
- `Resources.md` — external resources catalog (Swift-baseline; React-side at `// ReactInfo//Resources.md`)
- `// Features//`
  - `Domain-Model.md` — 2-layer model overview, PARA mapping, linking model, sidebar shape
  - `Contexts.md` — Spaces / Topics / Projects tier system; per-tier rules, validation, tier-config (renamable labels)
  - `PageTypes.md` — Page Types + Page Collections + Pages; shared schema, view types, move-strip (was `Vaults.md` pre-ParadigmV2)
  - `Agenda.md` — Agenda Tasks + Agenda Events (split entities, EKReminder + EKEvent shaped), EventKit integration, sandbox permissions
  - `Homepage.md` — singleton composed-blocks dashboard
  - `Pages.md` — on-disk shape, Markdown features + two rendering directives, opening behavior, wikilinks, tier1/2/3
  - `PageEditor.md` — editor implementation spec: library (swift-markdown + vendored swift-markdown-engine), shipped v0.2.7.0 features, v0.2.7.x deferred patches, save pipeline, hot-swap surface
  - `Items.md` — Item Types + Item Collections + Items (`.json` row entries); Item Window UI; tier1/2/3
  - `Properties.md` — property type catalog (per-Type via per-kind sidecar — `_pagetype.json` / `_itemtype.json` / `_taskconfig.json` / `_eventconfig.json`; shared across Pages, Items, Agenda Tasks, Agenda Events)
  - `NavDropdown.md` — Liquid Glass dropdown navigation surface (Pinned + Recents); shipped v0.2.7.1 — supersedes the earlier tab-strip navigation model
  - `Sidebar.md` — five-section sidebar (Pinned / Spaces / Topics / Items / Pages — no Agenda section); selection language, indentation mechanisms
  - `Architecture.md` — what survives a stack rebuild (conceptual portability)
  - `Prospects.md` — post-v1 features (incl. synced blocks, collection-local schemas, graph view, Item ↔ Page promotion, Item Templates, full Settings UI)
  - `Spaces.md` — STUB: redirects to `Contexts.md` (Spaces are tier-1 Contexts)
  - `Collections.md` — STUB: redirects to `PageTypes.md` + `Items.md` (Page Collections + Item Collections are sub-folders inside Types)
- `// Guidelines//`
  - `Design.md` — SwiftUI-native design philosophy, brand-value placement, component conventions, AppKit interop
  - `Symbols.md` — SF Symbol registry (Application ↔ Symbol table); spec for the future in-app Symbol Settings surface
  - `CRUD-Patterns.md` — SwiftUI patterns for per-entity CRUD UI, atomic-write discipline, manager pattern
  - `Paradigm-Decisions.md` — Confirmation protocol + registry of paradigm-solidifying decisions
- `// Planning//` — active plans + `Superseded/` archive; index at `// Planning//README.md`
- `// ReactInfo//` — React+Electron contingency reference (translation methodology + topic files + preserved v0.0 spec)


Read `Handoff.md` first at session start.

##### Active branch quirks (carry forward to every subagent dispatch)

1. **Test filter form uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`. Suite-name form silently no-ops with `** TEST SUCCEEDED **`. Visually verify count.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include; pbxproj usually doesn't need editing.
3. **Trust `xcodebuild`, not SourceKit squiggles** — IDE diagnostics frequently stale (especially `Cannot find type X` / `Cannot find 'PUI'` for same-module types, `Collection` shadow with `Swift.Collection`, `No such module 'X'` for a resolved SPM dep, `No such module 'Testing'` in test files).
4. **`.claude/*` is included in commits.** Don't auto-bundle docs into Swift commits without explicit ask, but explicit doc commits are fine — commit accumulated docs to the active branch so branch switches don't make them "disappear" from the working view.
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`. NexusContext closure tests: hoist `let id = ULID.generate()` before building entity to avoid `@Sendable` capture errors. `@MainActor @escaping () -> NexusContext` is the locked parameter pattern on TopicManager / PageContentManager / ItemContentManager; snapshot-closure trick at `ContentView.constructManagers` is the in-body solution for capturing manager state into validator closures.
6. **Xcode auto-reorders SPM package entries (Yams / GRDB) in pbxproj on every build** — incidental noop diff. Revert before commit to keep diffs limited to intended files.
7. **Stub-and-progressively-replace** — each task ships as a green commit; when an earlier task's file references a type built in a later task, inline a throwaway stub and replace it in place when the real type lands (paradigm decision #4 in `// Guidelines//Paradigm-Decisions.md`). Rejected: batch-commit all tasks at branch end.
8. **Section structure in SidebarView is load-bearing.** Changes to `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns or to the `SectionHeader`/`SelectableRow`/`SelectionChrome` shape risk regressing a launch crash (the in-content `.background` workaround tried during the polish series broke `OutlineListCoordinator.recursivelyDiffRows`). Verify via `xcodebuild test` (tests must actually bootstrap, not just compile). ALSO: don't mix flat-leaf and disclosure-style rows inside the same outer `Section` — `OutlineListCoordinator.recursivelyDiffRows` can crash on the asymmetry. Item Types + Sets MUST mirror Vaults + Page Collections uniformly (both disclosure parents with leaf children).
9. **Sidebar selection chrome lives at row file level via `.listRowBackground(SelectionChrome(...))`**, not in-content `.background`. Locked spec at `// Features//Sidebar.md` "Selection language" + paradigm decision #6. Row files derive `isSelected` from `SelectionTag.X(entity.id).matches(selection)`. SelectableRow itself is pure content — no chrome.
10. **Parallel-session caveat** — Nathan may have a separate session running small UI tweaks. Pommora/* working tree is NOT guaranteed clean between subagent dispatches. Never revert unattributed working-tree changes; surface in report rather than bundling or discarding.
11. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`) via Xcode 26's bundled toolchain. The direct `swift-format` binary is NOT on `$PATH` on this machine. CI uses the same subcommand form. Locked at v0.2.4 (`.swift-format` config + CI lint step).
12. **GRDB `String` overload pollution in @ViewBuilder closures** — `SQLSpecificExpressible` conformance on String causes overload ambiguity for `==` and `contains` inside SwiftUI views. Workaround: isolate per-row rendering into private struct sub-views with plain value types; use `first(where:)` not `contains(_:)`. Pattern established in `RelationPicker.swift`.
13. **Use `Agent run_in_background: true` for builder-subagent verification** — Nathan does not want xcodebuild grabbing window focus. Always builder via background Agent with `-only-testing:PommoraTests` to skip UI tests.
14. **`loadAll` must sync in-memory parents to the SQLite index.** Established 2026-05-25 in `88c9367`. PageTypeManager.loadAll + ItemTypeManager.loadAll defensively upsert types + collections after disk load (INSERT OR REPLACE makes it idempotent; `try?` swallows failures since the index is regeneratable). The architecture's prior contract — "DB stays in sync via incremental CRUD upserts after IndexBuilder runs once" — breaks for entities arriving outside CRUD (adoption / external Finder folders / post-adoption state). Without this sync, any page/item CRUD into a non-CRUD-created vault triggers SQLite error 19 (FK constraint failed) toast. Regression-tested in `LoadAllIndexSyncTests.swift`.
15. **Every `@Environment(X.self)` declared on a detail view must be injected at `ContentView.detail`'s `.environment(...)` chain.** Locked 2026-05-25 via `c8b3cbc`. SwiftUI's `_TaskValueModifier` KeyPath-resolves env values when computing the `.task` closure; missing env asserts at runtime as `EXC_BREAKPOINT` (SIGTRAP) — not a clean error. Symptom is "crash on first selection routing to that view." When adding a new env to a detail view, ALSO add it to the optional-unwrap chain at the top of `ContentView.detail` (`ContentView.swift:330`) AND the `.environment(...)` chain immediately after (`:344-350`).
16. **The unit-test host app must not trigger launch modals (XCTest guard).** `xcodebuild test` launches `Pommora.app` as the test host; its `ContentView.task` → `NexusManager.loadOnLaunch()` resolves a security-scoped bookmark (macOS folder-grant prompt) or opens `NSOpenPanel` — both modal, which **blocks the test runner from connecting** (`** TEST FAILED **` with "test runner hung before establishing connection", 0 tests run) AND interrupts the user with permission prompts. Guard added `1d48c41`: `loadOnLaunch()` early-returns when `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`. Any future launch-time code that touches system permissions or shows a modal MUST apply the same XCTest guard.
17. **Swift Testing `-only-testing` filters match the `@Suite`/type name, not the source filename.** Refinement of quirk #1: `-only-testing:PommoraTests/<FilenameWithTests>` only works when a struct/`@Suite` in that file is *named* `<FilenameWithTests>`. A file with differently-named suites (e.g. `TierValueAdapterTests.swift` holding `TierValueAdapterPageFrontmatterTests` etc.) silently no-ops to `** TEST SUCCEEDED **` with 0 tests. Fixes: name the primary test struct to match the filename, OR filter by the real struct/suite name, OR run the whole `-only-testing:PommoraTests` target. ALWAYS visually verify a non-zero executed count.
18. - **Layer-confusion check — confirm the data before blaming it.** A wrong, empty, or "(missing)" UI surface does **not** mean the data layer is broken. The symptom sits at the *end* of a chain (store → query → load → render), and a UI fault mimics a data fault perfectly. Before touching the store, **verify the data directly** — query the SQLite index, read the on-disk file, or run the exact query the view runs — to split two distinct failures: **data is wrong** (fix the index / rebuild / file) vs. **data is correct but the view can't read or render it** (fix the UI: env injection, load timing, popover/layout sizing, live-refresh). Name the confirmed layer before proposing a fix; "the picker is empty" and "the index is empty" are different claims — prove which is true. 
