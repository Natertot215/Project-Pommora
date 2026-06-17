### Pommora — Project Instructions

#### Overview

A simpler Notion that's also a more capable Obsidian. **2-layer PARA-aligned domain model** (locked 2026-05-16; ParadigmV2 2026-05-22; Contexts Decoupling — free-standing tiers + Space→Area rename — 2026-06-10):

- **Organization layer — Contexts** (3 tiers): Areas (1) / Topics (2) / **Projects** (3). Three **free-standing** tiers — no containment, no parents; each a folder with a config sidecar (`_area.json` / `_topic.json` / `_project.json`). Per-tier labels user-configurable per Nexus. (Context→context relations are a deferred design pass.)
- **Operational layer — Pages + Agenda**:
  - **Pages** — `.md` files (YAML frontmatter + body via `AtomicYAMLMarkdown`) inside Page Types; Page Collections organize within, optionally subdivided by Page Sets (schema-less; inherit everything from the Collection). UI labels: **"Vault"** + **"Collection"** + **"Set"** (renameable via Settings).
  - **Agenda** — split into Agenda Tasks (`.task.json`, EKReminder-shaped) and Agenda Events (`.event.json`, EKEvent-shaped). Data layer shipped; sidebar surfacing is consolidated into the Calendar pin entry (no separate Agenda sidebar heading).
- **Singleton — Homepage**: composed-blocks dashboard at `.nexus/homepage.json`.
- **Settings scaffold** (`.nexus/settings.json`): per-Nexus user-overridable UI labels + accent color (storage + label wiring shipped; full editing UI planned).

A second operational entity ("Items") existed until the 2026-06 PagesV2 collapse into Pages — see `History.md` + the `PommoraPRD.md` retrospective.

**Two builds, one app.** Project Pommora is the umbrella for the *same product* built two ways — the **Swift / SwiftUI** native app (repo root; this `.claude/`) and the **React + Electron** rebuild (sub-project under `React/`, with its own `React/.claude/`). Same PRD, domain model, and on-disk paradigm; only the implementation differs. Both live in **one repo on one `main`** — there is no separate React checkout. **When working on React, `React/.claude/` is authoritative** (start at `React/.claude/Handoff.md`); the root `.claude/` governs the Swift build + shared product truth.

#### Stack

Locked to **SwiftUI**. **Editor = TextKit 2 + Apple `swift-markdown` + the Pommora-owned `MarkdownPM` package** (originally vendored from `swift-markdown-engine`, folded in-tree + rebuilt 2026-06-03); full spec → `// Features//PageEditor.md`. React+Electron is preserved as a contingency path.

#### HARD RULES

- **Condensed, exhaustive control flow.** Model a finite set of states as an `enum` and branch with a `switch` (the compiler then enforces every case), rather than chains of `if/else` or loose booleans/strings. Favor the tightest structured form that stays legible.

- **DRY — one source of truth.** When the same logic, mapping, or rendering would live in two or more places, hoist it into a single function or type and reuse it; never copy-paste behavior across call sites.

- **Simplicity-first.** Don't add complexity that wasn't asked for. If it can be simplified, simplify it.

- **Versioning.** AVOID referencing specific versions in the framework as planned places for future features to be implemented. Feature-timing is fragile and declaring versioning of a feature before its worked on is a great way to compile confusion. Versioning should be exclusive to conversation and historical records / feature docs + Framework.  

- **Documentation altitude.** Docs describe to the durable decision, not the current instance. Keep design decisions, reusable guidelines, and canonical on-disk formats; cut component measurements, codebase verbatim, version stamps, and historical narrative. A spec reads as confident present tense — not a change-log. Over-specification manufactures its own drift.

- **Confirm paradigm-solidifying choices.** Before code locks an on-disk shape, wire encoding, identifier convention, or a default that becomes permanent once data exists, stop and surface the choice to Nathan with options + a recommendation; record the ratified decision in `History.md`.

- **`Handoff.md` is a lean snapshot maintained via `/handoff`.** Sections: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Never accumulate per-session work logs.

 - **Re-assess the plan between green commits.**  After each task ships green, read the active plan against what just landed. If the task surfaced wrong assumptions, missing prerequisites, scope drift, or shortened/expanded downstream tasks, rewrite the affected later tasks before dispatching the next one. The plan is the controller's live working theory of the work, not a fixed script — only green commits are facts.
 
#### Core Principles

- **Three load-bearing constraints:** (1) **conceptual portability of functionalities** — file formats, schemas, design values, UX patterns survive a stack rebuild; (2) **cross-nexus queryability + cloud sync compatibility** — the on-disk model maps cleanly to a cloud DB so sync arrives as additive translation; (3) **persistent immediate legibility for agents** — every entity is a file an external agent can read directly without tool-call round-trips. Full detail → `// Features//Architecture.md`.


- **Files are canonical (≠ everything is Markdown).** Pages are `.md` (frontmatter + body); Agenda + all sidecars / Projects / Areas / Settings stay JSON. **Kind authority is the parent Type folder's sidecar, not the extension or any frontmatter field.** Foreign frontmatter is preserved by value on every write; SQLite is a regeneratable index (no user data trapped in it). Full on-disk spec → `// Features//Architecture.md` + `PommoraPRD.md`.

- **Filename = title** everywhere. No `title` field. Renaming in the UI renames the file. Independent UI titles are a Prospect.

- **Pages are Markdown, Contexts are blocks.** Pages are Markdown documents with some Pommora-specific rendering directives; Contexts are live, fully-editable block-like pages of views and queries— never a read-only snapshot. 

- Per-tier multi-relations (`tier1` / `tier2` / `tier3`) connect operational entities to Contexts. SQLite indexes properties, links, and relations. Personal-first, Mac-first for v1, always open-source.

- **Connections render as styled colored inline text** (Obsidian wikilink-style), not Notion-style chips.

- **Context-tier links stored by ID.** `tier1` / `tier2` / `tier3` hold **bare ULID string arrays at the frontmatter root** (always multi-value, rename-safe), and are the sole relation-type connection. The `$rel`-tagged shape is **only** for user relation properties inside `properties` (and Agenda properties), never the tier root fields. Rendering + full catalog → `// Features//Contexts.md` + `// Features//Properties.md`.

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
- `History.md` — locked decisions + version history; brief (not a session work-log).
- `Framework.md` — phased roadmap to v1.0 (CRUD paired with paradigm at every phase)
- `Resources.md` — external resources catalog. 
- `// Features//` — Feature specs; consult the relevant doc before claiming functionality, and cross-check with code before treating docs as factual. Most files are topic-named; two aren't obvious — `Connections.md` (canonical wikilink/connection-system spec) and `PommoraUIX.md` (debug component-explorer spec).
- `// Guidelines//` — Domain-specific guidelines; add relevant entries when feedback is given about behavior you must not repeat when both cause and fix are identified. You MUST reference the relevant file before planning around a topic to which the guidelines relate.
- `// Planning//` — active plans + `Superseded/` archive; index at `// Planning//README.md`

##### Active branch quirks (carry forward to every subagent dispatch)

1. **Test filter matches the `@Suite`/type name, NOT the source filename.** `-only-testing:PommoraTests/<SuiteOrTypeName>` works only when a `@Suite`/struct in the file is *named* that. A file whose suites are named differently (e.g. `TierValueAdapterTests.swift` holding `TierValueAdapterPageFrontmatterTests`) silently no-ops to `** TEST SUCCEEDED **` with 0 tests. Fixes: match the real suite name, or run the whole `-only-testing:PommoraTests` target. ALWAYS visually verify a non-zero executed count.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include; pbxproj usually doesn't need editing.
3. **Trust `xcodebuild`, not SourceKit squiggles** — IDE diagnostics frequently stale (especially `Cannot find type X` / `Cannot find 'PUI'` for same-module types, `Collection` shadow with `Swift.Collection`, `No such module 'X'` for a resolved SPM dep, `No such module 'Testing'` in test files).
4. **`.claude/*` is included in commits.** Don't auto-bundle docs into Swift commits without explicit ask, but explicit doc commits are fine — commit accumulated docs to the active branch so branch switches don't make them "disappear" from the working view.
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`. NexusContext closure tests: hoist `let id = ULID.generate()` before building entity to avoid `@Sendable` capture errors. `@MainActor @escaping () -> NexusContext` is the locked parameter pattern on TopicManager / PageContentManager; the snapshot-closure trick in `NexusEnvironment.init` is the in-body solution for capturing manager state into validator closures.
6. **Xcode auto-reorders SPM package entries (Yams / GRDB) in pbxproj on every build** — incidental noop diff. Revert before commit to keep diffs limited to intended files.
7. **Stub-and-progressively-replace** — each task ships as a green commit; when an earlier task's file references a type built in a later task, inline a throwaway stub and replace it in place when the real type lands. Rejected: batch-commit all tasks at branch end.
8. **Section structure in SidebarView is load-bearing.** Changes to `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns or to the `SectionHeader`/`SelectableRow`/`SelectionChrome` shape risk regressing a launch crash (the in-content `.background` workaround tried during the polish series broke `OutlineListCoordinator.recursivelyDiffRows`, a SwiftUI-internal symbol). Verify via `xcodebuild test` (tests must actually bootstrap, not just compile). ALSO: keep every `Section`'s rows homogeneous — don't mix flat-leaf and disclosure-style rows inside the same outer `Section` (`OutlineListCoordinator.recursivelyDiffRows` can crash on the asymmetry). This includes user vault sections: each renders the identical `Section { PageTypeRow… } header:` shape as the default Vaults section, and an empty user section renders header-only — never a placeholder leaf.
9. **Sidebar selection chrome lives at row file level via `.listRowBackground(SelectionChrome(...))`**, not in-content `.background`. Locked spec at `// Features//Sidebar.md`. Row files derive `isSelected` from `SelectionTag.X(entity.id).matches(selection)`. SelectableRow itself is pure content — no chrome. ALSO: an untagged row inside a tagged container (e.g. a row nested in a tagged DisclosureGroup) INHERITS the container's `.tag` — "no tag" does not mean non-selectable. A non-selectable row needs its own distinct tag (one that resolves to no selection) plus `.selectionDisabled(true)` on its label row (not the container — traits propagate to generated child rows). Established by the v0.4.1 set-row selection-bleed fix.
10. **Parallel-session caveat** — Nathan may have a separate session running small UI tweaks. Pommora/* working tree is NOT guaranteed clean between subagent dispatches. Never revert unattributed working-tree changes; surface in report rather than bundling or discarding. Assume documentation changes in parallel sessions are safe to commmit in parallel unless individually asessed otherwise.
11. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`) via Xcode 26's bundled toolchain. The direct `swift-format` binary is NOT on `$PATH` on this machine.
12. **GRDB `String` overload pollution in @ViewBuilder closures** — `SQLSpecificExpressible` conformance on String causes overload ambiguity for `==` and `contains` inside SwiftUI views. Workaround: isolate per-row rendering into private struct sub-views with plain value types; use `first(where:)` not `contains(_:)`. Pattern established in `ContextPicker.swift`.
13. **Use `Agent run_in_background: true` for builder-subagent verification** — Nathan does not want xcodebuild grabbing window focus. Always builder via background Agent with `-only-testing:PommoraTests` to skip UI tests.
14. **`loadAll` must sync in-memory parents to the SQLite index.** Established 2026-05-25 in `88c9367`. PageTypeManager.loadAll defensively upserts types + collections after disk load (INSERT OR REPLACE makes it idempotent; `try?` swallows failures since the index is regeneratable). The architecture's prior contract — "DB stays in sync via incremental CRUD upserts after IndexBuilder runs once" — breaks for entities arriving outside CRUD (adoption / external Finder folders / post-adoption state). Without this sync, any page CRUD into a non-CRUD-created vault triggers SQLite error 19 (FK constraint failed) toast. Regression-tested in `LoadAllIndexSyncTests.swift`.
15. **Per-Nexus managers are owned + injected by one `NexusEnvironment` (single source).** Every manager/resolver is a stored property on `NexusEnvironment` (`Nexus/NexusEnvironment.swift`), injected by the single `.injectNexusEnvironment(_:)` modifier — adding a manager = one stored property + one `.environment(...)` line there, co-located and compiler-checked. Why it matters: SwiftUI's `_TaskValueModifier` KeyPath-resolves `@Environment(X.self)` when computing a view's `.task`, so a manager a view declares but nobody injects asserts at runtime as `EXC_BREAKPOINT` (SIGTRAP) on first selection — not a clean error. Centralizing injection removed the old scattered-inject footgun; a new `@Environment(X.self)` on any view just needs its manager added to that one modifier.
16. **The unit-test host app must not trigger launch modals (XCTest guard).** `xcodebuild test` launches `Pommora.app` as the test host; its `ContentView.task` → `NexusManager.loadOnLaunch()` resolves a security-scoped bookmark (macOS folder-grant prompt) or opens `NSOpenPanel` — both modal, which **blocks the test runner from connecting** (`** TEST FAILED **` with "test runner hung before establishing connection", 0 tests run) AND interrupts the user with permission prompts. Guard added `1d48c41`: `loadOnLaunch()` early-returns when `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`. Any future launch-time code that touches system permissions or shows a modal MUST apply the same XCTest guard.
17. **Layer-confusion check — confirm the data before blaming it.** A wrong, empty, or "(missing)" UI surface does **not** mean the data layer is broken. The symptom sits at the *end* of a chain (store → query → load → render), and a UI fault mimics a data fault perfectly. Before touching the store, **verify the data directly** — query the SQLite index, read the on-disk file, or run the exact query the view runs — to split two distinct failures: **data is wrong** (fix the index / rebuild / file) vs. **data is correct but the view can't read or render it** (fix the UI: env injection, load timing, popover/layout sizing, live-refresh). Name the confirmed layer before proposing a fix; "the picker is empty" and "the index is empty" are different claims — prove which is true. 
