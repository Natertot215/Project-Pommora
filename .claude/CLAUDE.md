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

- **Pages are Markdown, Contexts are blocks.** Pages are Markdown documents (one continuous Markdown stream) with two Pommora-specific rendering directives — `@Columns` (multi-column rendering of a section) and `:::callout` (outlined-box callout, distinct from blockquotes). Standard Markdown handles tables (GFM), blockquotes (standard `>` syntax, rendered with a filled background + left-side emphasis bar), dividers (`---`), and everything else. Headings are foldable by default (built-in UI, not a directive). **"Block-level features" as a project term belongs to Contexts only** — Contexts (Spaces / Topics / Sub-topics) are the page-like canvases with drag-and-drop blocks.

- **Wikilinks render as styled colored inline text** (Obsidian-style), not Notion-style chips.

- **Relations stored by ID, displayed by title.** Frontmatter relation properties hold the target's ID (rename-safe); the editor renders the target's current title as styled colored inline text. Per-tier multi-relations (`tier1` / `tier2` / `tier3`) on Items / Pages / Agenda items follow the same pattern.

- **Inline editing principle.** Every embedded view in a composed-blocks surface (Context, Homepage) is a live, fully-editable view of its source — never a read-only snapshot. Full inline editing of a referenced Page's body (Notion synced blocks) is post-v1.

- **Move-strip rule.** Moving a Page or Item across Vaults strips properties not in the destination schema — Notion-style; no quarantine. The user gets a simple confirmation warning listing which properties will be stripped. Within the same Vault (between Collection sub-folders), no strip — schema is shared.

- **Design system: SwiftUI primary + AppKit where needed + small Pommora-brand extensions.** Pommora uses SwiftUI semantic colors (`Color(.systemBackground)`, `.primary`, etc.), Materials (`Material.regular`, `.sidebar`), and Font scale (`.font(.body)`, `.font(.callout)`) wherever possible; AppKit is used directly via `NSViewRepresentable` where SwiftUI falls short (notably NSTextView/TextKit 2 for Option 1 editor, NSSplitView for splitter polish). Pommora-specific brand values (accent purple, code block colors, callout treatments) live in `// UI-UX//Design//Assets.xcassets` and `// Design//Color+Pommora.swift`. The full ~118-token Figma-built design system is React-flavored and lives in `// ReactInfo//Styling-Tokens.md` — only the WKWebView editor canvas (Option 2) uses CSS custom properties as tokens proper. Detail → `// UI-UX//UI-UX.md`.

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

##### Project root (outside `.claude//`)

- `// UI-UX//` — design system home. `Design//` holds `Assets.xcassets`, Pommora-brand Color/Font extensions, and design materials; `Components//` holds the SwiftUI component library. Guidelines: `UI-UX//UI-UX.md`, `UI-UX//Design//Design Guidelines.md`, `UI-UX//Components//Component Guidelines.md`.

#### Active Version

**v0.0.0 + v0.1.0 + v0.2.0 → v0.2.6 all shipped on `main`** (end of 2026-05-18 session, locally committed; NOT pushed yet). Implementation at [Pommora/Pommora/](Pommora/Pommora/). **186/186 unit tests pass**; `swift format lint --strict` exit 0; sandbox verified; 0 source warnings.

| SHA | Version | Description |
|---|---|---|
| `e3daedb` | v0.2.0 | Paradigm scaffolding + sidebar UX polish (merge commit, 83 underlying preserved) |
| `3bcf328` | v0.2.1 | Parallel-session Swift UX tweaks + page selection wiring |
| `2e140ed` | v0.2.2 | CodeRabbit tightening (ItemWindow refetch + ContentManagerTests filesystem) |
| `56efd68` | v0.2.3 | CI baseline (GitHub Actions workflow) |
| `60e2ef6` | v0.2.4 | swift-format baseline (config + formatter pass + CI lint step) |
| `9f56fbe` | v0.2.5 | `.trash//` data foundation (`Filesystem.moveToTrash` + 10 manager swaps + 4 new tests) |
| `25de7c6` | v0.2.5.1 | Trash cleanup (UUID-discriminated timestamp + tighter test pattern) |
| `7b17d1d` | v0.2.6 | Spec catch-up (5 stale version strings + Pages.md + Sidebar.md doc passes) |
| `ca33210` → `1989fac` | v0.2.7-a → v0.2.7-g.2 | Phase A-G of v0.2.7 (Pallepadehat fork CodeMirror editor + Apple typography polish). 198/198 tests pass. **Superseded by Session-9 engine swap.** See Handoff for full commit table. |
| `152609c` | docs Session 7 | Milkdown decision documentation (superseded by Session-8 engine-swap decision; commit stays in history) |
| `1c6e270` → `9a0b383` | v0.2.7-h.0 → v0.2.7-h.10 | Session-9 engine swap **SHIPPED + PUSHED + TAGGED `v0.2.7.0`** on origin (10 commits): docs repair → Pallepadehat strip → vendor swift-markdown-engine as local SPM at `External/MarkdownEngine/` + Apple swift-markdown 0.8.0 SPM dep → wire `PageEditorView` to `NativeTextViewWrapper` → character-pair auto-pair (`**`/`__`/`[[`/`` `` ``) → docs ship-out → UX polish (title-body padding + 24pt body textInsets + auto-unpair on backspace) → Apple-AST supplemental styler (BlockQuote/Strikethrough/Table/ThematicBreak) + expanded right-click menu → HR-as-real-line via custom NSTextLayoutFragment draw + table pipes/separator-row hidden + Enter→body focus shift → HR draw-detection fix (enumerateAttribute scan) + title @FocusState + H5/H6 removed. **197/197 tests pass.** Full editor spec at `// Features//PageEditor.md`. v0.2.7.x patch sequence next: `.1` blockquote+HR Apple-Notes polish, `.2` NavDropdown, `.3` Tables custom grid, `.4` sidebar reorder+drag. |
| `fa51430` → `b13f9a5` | v0.2.7.2 | Session-10 NavDropdown first-attempt **TAGGED `v0.2.7.2`** on `main` (22 commits). Functional but UIX-iterated (standalone preview window + hover-heart favorites + chrome iteration Nathan was unhappy with). **Superseded by v0.2.7.1 simplification later same day.** Tag stays in history for archaeological reference. |
| `4def823` → (final) | v0.2.7.1 | Session-10 NavDropdown **SHIPPED + TAGGED `v0.2.7.1`** on `main` (8 commits): stripped standalone-window machinery (`EntityRef` + `EntityWindowHost` + WindowGroup scene deleted, 406 lines gone) → Favorites → Pinned rename top-to-bottom (class, file, JSON key with backward-compat decode, +2 NexusStateTests) → EntityRow hover-accent + right-click Pin/Unpin context menu → click model (single = select, double = open in main detail pane) → Page + Item context menus in `VaultDetailView` + `CollectionDetailView` (Rename + Pin + Delete) → bugfix `.simultaneousGesture(TapGesture(count: 2))` + lazy-load fallback → bugfix wire `.collection` case + bypass MainWindowRouter via direct closure from ContentView. **226 unit tests pass.** GitHub CI removed (`.github/workflows/ci.yml` — failure-email noise). New rule at `Guidelines/CRUD-Patterns.md → Preview-window prerequisite`: PreviewWindow primitive ships per kind before any "open in preview" UI for that kind is wired. Four follow-ups tracked in `Features/NavDropdown.md → Future implementation`: (1) wire preview when primitive lands, (2) fix Pinned drag-to-reorder, (3) remove type chip in favor of kind-icon, (4) segmented picker polish. **v0.2.7.1 supersedes v0.2.7.2 as canonical NavDropdown.** The originally-planned v0.2.7.1 Page-editor-touch-ups slot shifts to a later patch number. |

**Currently working toward v0.3.0 Properties.** Full implementation spec at `// Planning//v0.3.0-Properties-implementation.md`; companion uncertainty log at `// Planning//v0.3.0-Properties-uncertainty-log.md`. **v0.3.x sub-sequence locked RC-2026-05-19:** .0 Properties / .1 Items pane / .2 Page-wikilinks / .3 SQLite + querying. v0.2.7.x patch sequence (post-NavDropdown ship): page editor touch-ups (blockquote real chrome + HR auto-lock + Phase 4.5 auto-pair polish + Phase 3 engine AST rewrite), Tables custom grid, sidebar + Vault/Collection drag-to-reorder (also fixes NavDropdown's Pinned drag-to-reorder follow-up). No specific patch number assignments — pick what's next at session time.

**Editor library — SHIPPED Session 9 (end-of-2026-05-18): vendored `swift-markdown-engine` as local Swift Package at `External/MarkdownEngine/` (Apache 2.0, 46 files, Swift 5.9 mode).** Native TextKit 2 via `NativeTextViewWrapper` — gives Pommora Writing Tools (15.1+), Look Up / Translate / spell-check, IME, dynamic system colors, drag-select natively. Apple `swift-markdown 0.8.0` is wired as an engine SPM dep (currently unused; powers the deferred Phase 3 AST tokenizer/styler rewrite). Pallepadehat fork at `Natertot215/PageEditorMD@addaa23` removed from build; stays in fork history for archaeological reference.

**Plan deviations from `// Planning//v0.2.7-engine-swap.md`:**
1. **Engine location**: `External/MarkdownEngine/` (local SPM) instead of `Pommora/Pommora/PageEditor/Engine/` (raw source). Package boundary isolates engine's Swift 5.9 / minimal-concurrency contract from Pommora's Swift 6 strict + ExistentialAny — avoids cascading `@MainActor` annotations across 46 files.
2. **Phase 3 deferred to v0.2.7.1**: regex-based tokenizer/styler ships for v0.2.7. Apple-AST body swap of `MarkdownTokenizer.parseTokens(in:)` + `MarkdownStyler.styleAttributes` (which adds Table / BlockQuote / ThematicBreak / Strikethrough support) deferred. swift-markdown SPM dep already wired as groundwork.
3. **Phase 4.5 trimmed**: basic character-pair auto-pair ships (`**`/`__`/`[[`/`` `` ``). Selection-wrap + auto-exit-on-whitespace + 11-test suite deferred to v0.2.7.1.

**All v0.2.7 domain wiring intact:** PageEditorViewModel (300ms debounce), PageEditorHost (page-switch flush), AppGlobals (lifecycle observers), AppState.pageInspectorOpen, inspector + sidebar wiring, atomic-write contract, frontmatter preservation rule, editable title TextField — **survive unchanged**.

**Reference plan:** `// Planning//v0.2.7-engine-swap.md` — Phases 0/1/2/4/4.5-basic shipped; Phases 3/4.5-polish/6 deferred to a future page-editor patch (no longer pinned to v0.2.7.1 since that slot is now NavDropdown's ship version). **Engine vendor docs:** `External/MarkdownEngine/NOTICE.md`.

**Next session opens with the v0.2.7.1-ship verbatim resume prompt** at the top of `Handoff.md` — pick from (a) page editor touch-ups, (b) sidebar+vault drag-reorder, (c) v0.3.0 Properties, (d) PreviewWindow primitive.

**New project-wide rule (v0.2.7.1, locked):** `Guidelines/CRUD-Patterns.md → Preview-window prerequisite` — the PreviewWindow primitive for an entity kind ships **before** any "open in preview" UI for that kind is wired. CRUD on entities may land independently. The deleted v0.2.7.2 EntityWindowHost is the cautionary tale.

**Framework reorder locked end-of-2026-05-17** (see `Framework.md` "Roadmap reorders" + `Handoff.md`): Pages + NavDropdown ship as v0.2.7 + v0.2.7.1 patches — NOT as v0.3.0/v0.4.0 minors. (NavDropdown supersedes the original v0.2.8 'Tabs' scope; pivot locked 2026-05-18.) Editor library NOT solidified — Tiptap leading candidate, final pick at v0.2.7 prep. Properties → v0.3.0. SQLite + Watcher → v0.4.0. Vault views → v0.5.0. EventKit + Agenda UI ship together at v0.6.0 (hand-in-hand). v0.6.0 consolidates a11y + perf + onboarding + Settings + accent customization. `.trash//` data layer → v0.2.5; UI window → v0.4.0.

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
