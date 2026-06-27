### Pommora Overview

A simpler Notion that's also a more capable Obsidian. 
**MUST READ BEFORE EVERY SESSION:** [[PommoraPRD]]

- **Organization layer —Contexts** (3 tiers): Areas (1) / Topics (2) / **Projects** (3). Three **free-standing** tiers — no containment, no parents; each a folder with a config sidecar (`_area.json` / `_topic.json` / `_project.json`). Per-tier labels user-configurable per Nexus. (Context→context relations are a deferred design pass.)
- **Operational layer — Pages + Agenda**:
  - **Pages** — `.md` files (YAML frontmatter + body via `AtomicYAMLMarkdown`) inside **Collections** — the schema-bearing top tier (`PageCollection`, `_pagecollection.json`). A Collection nests **Sets** to any depth: a recursive `PageSet` (`_pageset.json`) where the first level is a **Set** and deeper levels are **Sub-Sets**. Only depth-1 Sets carry their own views/sorting; deeper Sub-Sets are plain organizing folders. Schema lives only on the Collection; all Sets inherit it. Full spec → `// Features//PageCollections.md` + `// Features//PageSets.md`.
  - **Agenda** — the parent schema holding **Tasks** (`.task.json`, EKReminder-shaped) and **Events** (`.event.json`, EKEvent-shaped). Data layer shipped; sidebar surfacing is consolidated into the Calendar pin entry (no separate Agenda sidebar heading).
- **Singleton — Homepage**: composed-blocks dashboard at `.nexus/homepage.json`.
- **Settings scaffold** (`.nexus/settings.json`): per-Nexus user-overridable UI labels + accent color (storage + label wiring shipped; full editing UI planned).

A second operational entity ("Items") existed until the 2026-06 PagesV2 collapse into Pages — see `History.md` + the `PommoraPRD.md` retrospective.

**Two builds, one app.** Project Pommora is the umbrella for the *same product* built two ways — the **Swift / SwiftUI** native app (repo root; this `.claude/`) and the **React + Electron** rebuild (sub-project under `React/`, with its own `React/.claude/`). Same PRD, domain model, and on-disk paradigm; only the implementation differs. Both live in a single repo on a single main branch — there is no separate React checkout. **When working on React, React/.claude/ is authoritative** (start at React/.claude/Handoff.md); the root .claude/ governs the Swift build + shared product truth.

**If working in React, check into the `pommora-react` worktree first, then merge to `main` when done.**
#### Stack

Locked to **SwiftUI**. **Editor = TextKit 2 + Apple `swift-markdown` + the Pommora-owned `MarkdownPM` package** (originally vendored from `swift-markdown-engine`; full spec → `// Features//PageEditor.md`. 

#### HARD RULES

- **Condensed, exhaustive control flow.** Model a finite set of states as an `enum` and branch with a `switch` (the compiler then enforces every case), rather than chains of `if/else` or loose booleans/strings. Favor the tightest structured form that stays legible.

- **DRY — one source of truth.** When the same logic, mapping, or rendering would live in two or more places, hoist it into a single function or type and reuse it; never copy-paste behavior across call sites.

- **Versioning.** AVOID referencing specific versions in the framework as planned places for future features to be implemented. Feature-timing is fragile and declaring versioning of a feature before its worked on is a great way to compile confusion. Versioning should be exclusive to conversation and historical records / feature docs + Framework.  

- **Documentation altitude.** Docs describe to the durable decision, not the current instance. Keep design decisions, reusable guidelines, and canonical on-disk formats; cut component measurements, codebase verbatim, version stamps, and historical narrative. A spec reads as confident present tense — not a change-log. Over-specification manufactures its own drift.

- **Confirm paradigm-solidifying choices.** Before code locks an on-disk shape, wire encoding, identifier convention, or a default that becomes permanent once data exists, stop and surface the choice to Nathan with options + a recommendation; record the ratified decision in `History.md`

- **`Handoff.md` is a lean snapshot maintained via `/handoff`.** Sections: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Never accumulate per-session work logs.

 - **Re-assess the plan between green commits.**  After each task ships green, read the active plan against what just landed. If the task surfaced wrong assumptions, missing prerequisites, scope drift, or shortened/expanded downstream tasks, rewrite the affected later tasks before dispatching the next one. The plan is the controller's live working theory of the work, not a fixed script — only green commits are facts.
 
#### Core Principles

- **Three load-bearing constraints:** (1) **conceptual portability of functionalities** — file formats, schemas, design values, UX patterns survive a stack rebuild; (2) **cross-nexus queryability + cloud sync compatibility** — the on-disk model maps cleanly to a cloud DB so sync arrives as additive translation; (3) **persistent, convention-aware legibility for agents** — every entity is a plain text-readable file any agent that has learned the system's conventions can read directly (a `[[wikilink]]` abstracts a lookup yet stays legible once you know the convention). We strongly prefer formats readable without Pommora's running code; relaxing that for a genuine need is a tradeoff to raise, not a violation — but the firm line holds: no user data trapped in a binary blob or held only in the regeneratable index. Full detail → `//Features//Architecture.md`.


- **Files are canonical (≠ everything is Markdown).** Pages are `.md` (frontmatter + body); Agenda + all sidecars / Projects / Areas / Settings stay JSON. **Kind authority is the parent Type folder's sidecar, not the extension or any frontmatter field.** Foreign frontmatter is preserved by value on every write; SQLite is a regeneratable index (no user data trapped in it). Full on-disk spec → `// Features//Architecture.md` + `PommoraPRD.md`.

- **Filename = title** everywhere. No `title` field. Renaming in the UI renames the file. Independent UI titles are a Prospect.

- **Pages are Markdown, Contexts are blocks.** Pages are Markdown documents with some Pommora-specific rendering directives; Contexts are live, fully-editable block-like pages of views and queries— never a read-only snapshot. 

- Per-tier multi-relations (`tier1` / `tier2` / `tier3`) connect operational entities to Contexts. SQLite indexes properties, links, and relations. Personal-first, Mac-first for v1, always open-source.

- **Connections render as styled colored inline text** (Obsidian wikilink-style), not Notion-style chips.

- **Context-tier links stored by ID.** `tier1` / `tier2` / `tier3` hold **bare ULID string arrays at the frontmatter root** (always multi-value, rename-safe), and are the sole relation-type connection. The `$rel`-tagged shape is **only** for user relation properties inside `properties` (and Agenda properties), never the tier root fields. Rendering + full catalog → `// Features//Contexts.md` + `// Features//Properties.md`.

- **"Pommora" prohibited in on-disk schemas + Swift namespace qualifications.** Brand name reserved for the module name (`Pommora` Swift module), app branding, and documentation. NOT allowed in:
  - On-disk JSON field names (no `pommora_*` keys)
  - Swift type qualifications used as a discriminator pattern (no `Pommora.X` workarounds for stdlib collisions; use side-prefixed names like `AgendaTask` instead of `Pommora.Task`). The canonical entity names are **Task** and **Event**; `AgendaTask` / `AgendaEvent` are the collision-safe code-type forms only (the `Agenda` prefix dodges Swift's `Task`) — never the product name.

- **Design system: SwiftUI primary + AppKit where needed**
 Pommora uses SwiftUI semantic colors (`Color(.systemBackground)`, `.primary`, etc.), Materials (`Material.regular`, `.sidebar`), and Font scale (`.font(.body)`, `.font(.callout)`) wherever possible; AppKit is used directly via `NSViewRepresentable` where SwiftUI falls short (notably NSTextView / TextKit 2 for the Page editor, NSSplitView for splitter polish). 

- **The local file is the spec, not the render.** In-line views and computed values are referenced by directive, not inlined.


#### Document Map

- `PommoraPRD.md` — high-level product requirements + architecture; storage model + SQLite schema
- `Handoff.md` — current state and near-term priorities
- `History.md` — locked decisions + version history; brief (not a session work-log).
- `Framework.md` — phased roadmap to v1.0 (CRUD paired with paradigm at every phase)
- `Resources.md` — external resources catalog. 
- `// Features//` — Feature specs; consult the relevant doc before claiming functionality, and cross-check with code before treating docs as factual. Most files are topic-named; two aren't obvious — `Connections.md` (canonical wikilink/connection-system spec) and `PommoraUIX.md` (debug component-explorer spec).
- `// Guidelines//` — Domain-specific guidelines; add relevant entries when feedback is given about behavior you must not repeat when both cause and fix are identified. You MUST reference the relevant file before planning around a topic to which the guidelines relate.
- `// Planning//` — active plans + `Superseded/` archive; index at `// Planning//README.md`

##### Active branch quirks (carry forward to every subagent dispatch)

1. **Test filter matches the struct TYPE name, not the `@Suite` display label.** `-only-testing:PommoraTests/<Name>` keys on the test struct's type name (e.g. `SettingsManagerTests`), NOT the `@Suite("…")` display string (e.g. `"SettingsManager"`) — when they differ, the display-label form silently reports `** TEST SUCCEEDED **` with 0 tests executed. Always verify a non-zero executed count via the `.xcresult` (`totalTestCount`), never trust the success banner.
2. **Xcode tooling.** New files auto-include (pbxproj rarely needs editing); trust `xcodebuild` over SourceKit squiggles (stale for same-module types, SPM deps, `Testing` imports). Xcode reorders Yams/GRDB in pbxproj on every build — revert before committing.
3. **`.claude/*` in commits.** Commit docs explicitly to the active branch — don't auto-bundle into Swift commits; don't let them disappear on branch switches.
4. **Swift 6 + ExistentialAny.** Codable: `init(from decoder: any Decoder)` / `encode(to encoder: any Encoder)`; errors: `(any Error)?`; hoist `let id = ULID.generate()` in closure tests to avoid `@Sendable` captures. `@MainActor @escaping () -> NexusContext` is the locked manager parameter pattern.
5. **Stub forward-references inline** when an earlier task needs a type from a later one; replace in-place when the real type lands. Each task ships as a green commit — don't batch.
6. **SidebarView Section structure is crash-sensitive.** Don't modify the `Section(isExpanded:)/SectionHeader/SelectableRow/SelectionChrome` pattern — `.background` workarounds break `OutlineListCoordinator.recursivelyDiffRows`. Keep rows homogeneous within each Section (never mix flat-leaf + disclosure); verify with `xcodebuild test`.
7. **Selection chrome at row level** via `.listRowBackground(SelectionChrome(...))`, never in-content `.background`. Untagged rows inside a tagged container inherit the tag — non-selectable rows need an explicit non-matching tag + `.selectionDisabled(true)` on the label row.
8. **`swift format` is a subcommand** (`swift format format --in-place`, `swift format lint --strict`) — `swift-format` binary isn't on `$PATH`.
9. **GRDB `String` overload in `@ViewBuilder`** — `SQLSpecificExpressible` causes `==`/`contains` ambiguity; isolate per-row logic into private struct sub-views with plain values; use `first(where:)` not `contains(_:)`.
10. **`PageCollectionManager.loadAll` upserts collections + sets to SQLite** after disk load — without it, CRUD into externally-adopted Collections triggers FK constraint error 19. Regression-tested in `LoadAllIndexSyncTests.swift`.
11. **All managers owned by `NexusEnvironment`, injected via `.injectNexusEnvironment(_:)`.** A forgotten inject causes `EXC_BREAKPOINT` (SIGTRAP) on first selection — new managers need one stored property + one `.environment(...)` line there.
12. **Launch-time modals block the test runner.** Any code touching permissions or showing a panel must early-return on `ProcessInfo.isRunningXCTests` — a modal causes "test runner hung before establishing connection", 0 tests run.
