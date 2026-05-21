### Pommora — Project Instructions

#### Overview

A simpler Notion that's also a more capable Obsidian. **2-layer PARA-aligned domain model** (locked 2026-05-16):

- **Organization layer — Contexts** (3 tiers): Spaces (1, broad life domains) / Topics (2, subject areas) / Sub-topics (3, specifics within a Topic). All three are composed-blocks surfaces. Per-tier labels user-configurable per Nexus.
- **Operational layer — Vaults + Agenda**: Vaults (folder + `_vault.json` with shared schema) contain Collections (sub-folders sharing the Vault's schema in v1) which contain Pages (`.md`) and Items (`.json`). Agenda is a sibling of Vaults at `<nexus>/Agenda/` for calendar-anchored items with EventKit integration.
- **Singleton — Homepage**: composed-blocks dashboard at `.nexus/homepage.json`.

Items open in a popover-style **Item Window** (title + properties + 250-char description, not a full-frame surface); Pages open in the main detail pane (or in a standalone window via NavDropdown's preview gate or `⌥⌘O`). Per-tier multi-relations (`tier1` / `tier2` / `tier3`) connect operational entities to Contexts. SQLite indexes properties, links, and relations. Personal-first, Mac-first for v1, always open-source. Pommora's stack is **SwiftUI**; React+Electron is preserved as the contingency path.

#### Working with Nathan

- Non-coder, first agentic project. Nathan directs, Claude implements. Nathan does not write code.
- Mac user, always Mac. Lives in the Apple ecosystem.
- Values cohesion and simplicity over ecosystem reach or feature ceilings.
- Push back honestly when direction is unclear or a mistake is forming.
- Vocabulary may be imprecise — clarify before assuming.
- Studio-resident project; the Studio CLAUDE.md global rules and Nathan's NathanOS rules apply.

#### Stack

Locked to **SwiftUI**. Option 2 (WKWebView hosting Tiptap / Milkdown / BlockNote) is the likely direction for the Pages editor; Option 1 (native NSTextView + `swift-markdown` + TextKit 2; Clearly available as a fork-reference) is the more ambitious alternative. React+Electron is preserved as the contingency path — translation methodology lives at `// ReactInfo//Contingency.md`; topic-based React reference at `// ReactInfo//` folder.

#### Core Principles

- **Three load-bearing constraints:** (1) **conceptual portability of functionalities** — file formats, schemas, design values, UX patterns survive a stack rebuild; (2) **cross-nexus queryability + cloud sync compatibility** — the on-disk model maps cleanly to a cloud DB so sync arrives as additive translation; (3) **persistent immediate legibility for agents** — every entity is a file an external agent can read directly without tool-call round-trips. Full detail → `// Features//Architecture.md`.

- **Simplicity-first.** Don't add complexity that wasn't asked for. If it can be simplified, simplify it.

- **Files are canonical (≠ everything is Markdown).** Pages = `.md` (inside a Vault Collection sub-folder, or directly in a Vault). Items = `.json` (same locations as Pages). Vaults = folder + `_vault.json` with shared schema; Collections = sub-folders inside Vaults sharing the Vault's schema. Agenda items = `.agenda.json` at `<nexus>/Agenda/`. Contexts (Spaces / Topics / Sub-topics) = `.space.json` / `_topic.json` / `.subtopic.json` files under `.nexus/spaces/` and `.nexus/topics/`. Homepage = `.nexus/homepage.json` (singleton). SQLite is regeneratable index — no user data trapped in it.

- **Filename = title** everywhere. No `title` field; no `name` field on Items. Renaming in the UI renames the file. Independent UI titles are a Prospect.

- **Pages are Markdown, Contexts are blocks.** Pages are Markdown documents (one continuous Markdown stream) with two Pommora-specific rendering directives — `@Columns` (multi-column rendering of a section) and `:::callout` (outlined-box callout, distinct from blockquotes).

- **Wikilinks render as styled colored inline text** (Obsidian-style), not Notion-style chips.

- **Relations stored by ID, displayed by title.** Frontmatter relation properties hold the target's ID (rename-safe); the editor renders the target's current title as styled colored inline text. Per-tier multi-relations (`tier1` / `tier2` / `tier3`) on Items / Pages / Agenda items follow the same pattern.

- **Inline editing principle.** Every embedded view in a composed-blocks surface (Context, Homepage) is a live, fully-editable view of its source — never a read-only snapshot. Full inline editing of a referenced Page's body (Notion synced blocks) is post-v1.

- **Move-strip rule.** Moving a Page or Item across Vaults strips properties not in the destination schema — Notion-style; no quarantine. The user gets a simple confirmation warning listing which properties will be stripped. Within the same Vault (between Collection sub-folders), no strip — schema is shared.

- **Design system: SwiftUI primary + AppKit where needed**
 Pommora uses SwiftUI semantic colors (`Color(.systemBackground)`, `.primary`, etc.), Materials (`Material.regular`, `.sidebar`), and Font scale (`.font(.body)`, `.font(.callout)`) wherever possible; AppKit is used directly via `NSViewRepresentable` where SwiftUI falls short (notably NSTextView/TextKit 2 for Option 1 editor, NSSplitView for splitter polish). 

- **The local file is the spec, not the render.** In-line views and computed values are referenced by directive, not inlined.

- **React pairing.** When meaningful Swift implementation work lands — something big OR something with an obvious React-side equivalent worth recording — add a paired note in the relevant `// ReactInfo// <topic>.md` file. Skip for trivial work. See `// ReactInfo//Contingency.md` for translation patterns.

#### Document Map

- `PommoraPRD.md` — high-level product requirements + architecture; storage model + SQLite schema
- `Handoff.md` — current state and near-term priorities (read first at session start)
- `History.md` — locked decisions, brief
- `Framework.md` — phased roadmap to v1.0 (CRUD paired with paradigm at every phase)
- `Resources.md` — external resources catalog (Swift-baseline; React-side at `// ReactInfo//Resources.md`)
- `// Features//`
  - `Domain-Model.md` — 2-layer model overview, PARA mapping, linking model, sidebar shape
  - `Contexts.md` — Spaces / Topics / Sub-topics tier system; per-tier rules, validation, tier-config (renamable labels)
  - `Vaults.md` — Vaults + Collections + Content (Pages + Items); shared schema, view types, move-strip
  - `Agenda.md` — Agenda entity, EventKit integration, sandbox permissions, time-field collapse UI
  - `Homepage.md` — singleton composed-blocks dashboard
  - `Pages.md` — on-disk shape, Markdown features + two rendering directives, opening behavior, wikilinks, tier1/2/3
  - `PageEditor.md` — editor implementation spec: library (swift-markdown + vendored swift-markdown-engine), shipped v0.2.7.0 features, v0.2.7.x deferred patches, save pipeline, hot-swap surface
  - `Items.md` — row-shaped `.json` entries; Item Window UI; tier1/2/3
  - `Properties.md` — property type catalog (Vault-wide v1; shared across Pages, Items, Agenda)
  - `NavDropdown.md` — Liquid Glass dropdown navigation surface (Recents + Favorites); v0.2.7.2 — supersedes the old `Navigation-Bar.md` tab-strip model
  - `Sidebar.md` — four-section sidebar (Saved / Spaces / Topics / Vaults); selection language, indentation mechanisms
  - `Architecture.md` — what survives a stack rebuild (conceptual portability)
  - `Prospects.md` — post-v1 features (incl. synced blocks, collection-local schemas, graph view, Item ↔ Page promotion)
  - `Spaces.md` — STUB: redirects to `Contexts.md` (Spaces are now tier-1 Contexts)
  - `Collections.md` — STUB: redirects to `Vaults.md` (Collections are now sub-folders inside Vaults)
- `// Guidelines//`
  - `UIX-Guide.md` — SwiftUI-native design philosophy, component conventions, AppKit interop
  - `CRUD-Patterns.md` — SwiftUI patterns for per-entity CRUD UI, atomic-write discipline, manager pattern
- `// Planning//`
  - `Contexts-Vaults-spec.md` — complete implementation spec for the locked 2-layer model (file schemas, validation, CRUD scope, 11-phase plan, SwiftUI research, EventKit details, day-1 plan)
  - `v0.1-nexus-foundation-design.md` — v0.1a implementation design + Findings (shipped)
- `// ReactInfo//` — React+Electron contingency reference
  - `Contingency.md` — translation methodology and the update-obligation pattern
  - `ReactInfo.md` — folder index + preserved verified-findings appendix
  - `Editor.md`, `Spaces-DnD.md`, `Styling-Tokens.md`, `StateData.md`, `MacIntegration.md`, `Distribution.md` — topic files
  - `Symbols-guide.md` — React-side semantic-role icon indirection
  - `Resources.md` — React-side library catalog
  - `v0.0.md` — preserved React+Electron-locked v0.0.0 spec

> **Note:** ReactInfo docs predate the RC-session domain-model revision and still describe the older 3-entity model. Sync to the new 2-layer model is deferred; the Swift-side docs are canonical. ReactInfo translation will catch up if the contingency path is ever activated.


Read `Handoff.md` first at session start.

The React+Electron-locked predecessor spec for v0.0.0 is preserved at `// ReactInfo//v0.0.md`.

##### Active branch quirks (carry forward to every subagent dispatch)

1. **Test filter form uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`. Suite-name form silently no-ops with `** TEST SUCCEEDED **`. Visually verify count.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include; pbxproj usually doesn't need editing.
3. **Trust `xcodebuild`, not SourceKit squiggles** — IDE diagnostics frequently stale (especially `Cannot find type X` for same-module types, `Collection` shadow with `Swift.Collection`, `No such module 'SymbolPicker'` after SPM dep landed).
4. **`.claude/*` IS included in commits** (corrected end-of-2026-05-17). The prior "DO NOT stage `.claude/*` unless explicitly asked" rule prevents unilateral doc bundling into Swift commits, but does NOT preclude explicit doc commits. Commit accumulated docs to the active branch so branch switches don't make them "disappear" from the working view. Still: don't auto-bundle docs into Swift commits without explicit ask.
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`. NexusContext closure tests: hoist `let id = ULID.generate()` before building entity to avoid `@Sendable` capture errors. `@MainActor @escaping () -> NexusContext` is the locked parameter pattern on TopicManager / ContentManager; snapshot-closure trick at `ContentView.constructManagers` is the in-body solution for capturing manager state into validator closures.
6. **`Pommora.Collection` qualification** required in field declarations + type signatures involving `Collection` — bare name shadows with `Swift.Collection` protocol (fix at commit `2b54123`, repeated several times since).
7. **Xcode auto-reorders SymbolPicker/Yams entries in pbxproj on every build** — incidental noop diff. Revert before commit to keep diffs limited to intended files.
8. **Stub-and-progressively-replace is the locked execution strategy** for branch-spanning plans with forward task dependencies (paradigm decision #4 in `// Guidelines//Paradigm-Decisions.md`). Each task ships green standalone; later tasks replace earlier stubs in-place. Supersedes spec batch-commit-at-end approach.
9. **Section structure in SidebarView is load-bearing.** Changes to `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns or to the `SectionHeader`/`SelectableRow`/`SelectionChrome` shape risk regressing a launch crash (the in-content `.background` workaround tried during the polish series broke `OutlineListCoordinator.recursivelyDiffRows`). Verify via `xcodebuild test` (tests must actually bootstrap, not just compile).
10. **Sidebar selection chrome lives at row file level via `.listRowBackground(SelectionChrome(...))`**, not in-content `.background`. Locked spec at `// Features//Sidebar.md` "Selection language" + paradigm decision #6. Row files derive `isSelected` from `SelectionTag.X(entity.id).matches(selection)`. SelectableRow itself is pure content — no chrome.
11. **Parallel-session caveat** — Nathan may have a separate session running small UI tweaks. Pommora/* working tree is NOT guaranteed clean between subagent dispatches. Never revert unattributed working-tree changes; surface in report rather than bundling or discarding.
12. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`) via Xcode 26's bundled toolchain. The direct `swift-format` binary is NOT on `$PATH` on this machine. CI uses the same subcommand form. Locked at v0.2.4 (`.swift-format` config + CI lint step).
