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

Items open in a popover-style **Item Window** (title + properties + 250-char description, not a full-frame surface); Pages open in the main detail pane. (Standalone-window previews are queued behind the cross-feature PreviewWindow primitive; not yet wired.) Per-tier multi-relations (`tier1` / `tier2` / `tier3`) connect operational entities to Contexts. SQLite indexes properties, links, and relations. Personal-first, Mac-first for v1, always open-source. Pommora's stack is **SwiftUI**; React+Electron is preserved as the contingency path.

#### Working with Nathan

- Non-coder, first agentic project. Nathan directs, Claude implements. Nathan does not write code.
- Mac user, always Mac. Lives in the Apple ecosystem.
- Values cohesion and simplicity over ecosystem reach or feature ceilings.
- Push back honestly when direction is unclear or a mistake is forming.
- Vocabulary may be imprecise — clarify before assuming.
- Studio-resident project; the Studio CLAUDE.md global rules and Nathan's NathanOS rules apply.

#### Stack

Locked to **SwiftUI**. **Editor = TextKit 2 + Apple `swift-markdown` + vendored `swift-markdown-engine` & small Pommora-side customizations** (shipped v0.2.7.0; full spec → `// Features//PageEditor.md`). React+Electron is preserved as the contingency path — translation methodology lives at `// ReactInfo//Contingency.md`; topic-based React reference at `// ReactInfo//` folder.

#### Core Principles

- **Three load-bearing constraints:** (1) **conceptual portability of functionalities** — file formats, schemas, design values, UX patterns survive a stack rebuild; (2) **cross-nexus queryability + cloud sync compatibility** — the on-disk model maps cleanly to a cloud DB so sync arrives as additive translation; (3) **persistent immediate legibility for agents** — every entity is a file an external agent can read directly without tool-call round-trips. Full detail → `// Features//Architecture.md`.

- **Simplicity-first.** Don't add complexity that wasn't asked for. If it can be simplified, simplify it.

- **Files are canonical (≠ everything is Markdown).** Pages = `.md` (inside a Page Type's Page Collection sub-folder, or directly in a Page Type). Items = `.json` (inside an Item Type's Item Collection sub-folder, or directly in an Item Type). Page Type = folder + `_pagetype.json`; Item Type = folder + `_itemtype.json`. Page Collection = sub-folder + `_pagecollection.json`; Item Collection = sub-folder + `_itemcollection.json` (carries id + type_id + ordering). Agenda Tasks = `.task.json` files inside the Tasks singleton folder (root folder carrying `_taskconfig.json`). Agenda Events = `.event.json` files inside the Events singleton folder (root folder carrying `_eventconfig.json`). All operational containers live at the nexus root — no wrapper folders. Projects (tier-3 Contexts) = `.project.json` inside `.nexus/topics/<TopicFolder>/`. Settings = `.nexus/settings.json` (Phase 7). SQLite is regeneratable index — no user data trapped in it.

- **Filename = title** everywhere. No `title` field; no `name` field on Items. Renaming in the UI renames the file. Independent UI titles are a Prospect.

- **Pages are Markdown, Contexts are blocks.** Pages are Markdown documents (one continuous Markdown stream) with two Pommora-specific rendering directives — `@Columns` (multi-column rendering of a section) and `:::callout` (outlined-box callout, distinct from blockquotes).

- **Wikilinks render as styled colored inline text** (Obsidian-style), not Notion-style chips.

- **Relations stored by ID, displayed by title.** Frontmatter relation properties hold the target's ID (rename-safe); the editor renders the target's current title as styled colored inline text. Per-tier multi-relations (`tier1` / `tier2` / `tier3`) on Items / Pages / Agenda items follow the same pattern.

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
4. **`.claude/*` is included in commits.** Don't auto-bundle docs into Swift commits without explicit ask, but explicit doc commits are fine — commit accumulated docs to the active branch so branch switches don't make them "disappear" from the working view.
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`. NexusContext closure tests: hoist `let id = ULID.generate()` before building entity to avoid `@Sendable` capture errors. `@MainActor @escaping () -> NexusContext` is the locked parameter pattern on TopicManager / ContentManager; snapshot-closure trick at `ContentView.constructManagers` is the in-body solution for capturing manager state into validator closures.
6. *(retired in ParadigmV2 — was `Pommora.Collection` qualification rule; superseded by the `PageCollection` / `ItemCollection` renames. Slot kept so #7–#12 references stay valid.)*
7. **Xcode auto-reorders SymbolPicker/Yams entries in pbxproj on every build** — incidental noop diff. Revert before commit to keep diffs limited to intended files.
8. **Stub-and-progressively-replace is the locked execution strategy** for branch-spanning plans with forward task dependencies (paradigm decision #4 in `// Guidelines//Paradigm-Decisions.md`). Each task ships green standalone; later tasks replace earlier stubs in-place. Supersedes spec batch-commit-at-end approach.
9. **Section structure in SidebarView is load-bearing.** Changes to `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns or to the `SectionHeader`/`SelectableRow`/`SelectionChrome` shape risk regressing a launch crash (the in-content `.background` workaround tried during the polish series broke `OutlineListCoordinator.recursivelyDiffRows`). Verify via `xcodebuild test` (tests must actually bootstrap, not just compile).
10. **Sidebar selection chrome lives at row file level via `.listRowBackground(SelectionChrome(...))`**, not in-content `.background`. Locked spec at `// Features//Sidebar.md` "Selection language" + paradigm decision #6. Row files derive `isSelected` from `SelectionTag.X(entity.id).matches(selection)`. SelectableRow itself is pure content — no chrome.
11. **Parallel-session caveat** — Nathan may have a separate session running small UI tweaks. Pommora/* working tree is NOT guaranteed clean between subagent dispatches. Never revert unattributed working-tree changes; surface in report rather than bundling or discarding.
12. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`, `swift format lint --strict --recursive ...`) via Xcode 26's bundled toolchain. The direct `swift-format` binary is NOT on `$PATH` on this machine. CI uses the same subcommand form. Locked at v0.2.4 (`.swift-format` config + CI lint step).
