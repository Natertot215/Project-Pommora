### Pommora — Roadmap

Phased plan; no dates. Order is the only commitment.

> **Stack: SwiftUI.** Capability-level version descriptions below survive an editor-implementation pivot inside the SwiftUI path (Option 1 native vs Option 2 WKWebView).

#### Vision

A Markdown-canonical, SQLite-indexed personal management platform that combines Obsidian's local-first openness with Notion's database and view capabilities. Built around a **2-layer domain model** with PARA-aligned naming:

- **Organization layer — Contexts** (Spaces / Topics / Sub-topics) — categorical anchors that things relate *to*
- **Operational layer — Vaults + Agenda** — the data: Pages (`.md`) + Items (`.json`) inside Vaults; calendar-anchored items (`.agenda.json`) in Agenda with EventKit integration
- **Singleton — Homepage** — composed-blocks dashboard

Mac-first for v1, always open-source. Full domain spec → `// Features//Domain-Model.md`; complete implementation spec → `// Planning//Contexts-Vaults-spec.md`.

#### Phases

Versions use **`major.minor.patch` semver format**:
- **Minor (`v0.X.0`)** = a completed feature / capability cluster (Pages editor, Tabs, Properties, …).
- **Patch (`v0.X.y`)** = a touch-up or addition on top of an already-shipped feature (polish commit, infrastructure baseline, paradigm-doc hygiene, a small additive extension).
- **Major (`vX.0.0`)** reserved for `v1.0.0` (stabilization milestone) and onward.

Every release ships green standalone and produces a verifiable outcome you can run. **CRUD lands paired with paradigm** at every minor version per the locked spec — a new entity type doesn't appear in code until its CRUD interface is functional end-to-end.

##### v0.0.0 — Shell opens (shipped)

Toolchain proof. App launches on macOS 26+ (Tahoe) into a barebones three-pane shell — sidebar (default 240) / main (flex) / pop-out inspector (default 280, **hidden by default**) — built on SwiftUI's two-column `NavigationSplitView(sidebar:detail:)` with the inspector attached via `.inspector(isPresented:)`. Sidebar drag-resizable; widths persist. Window title suppressed (`.windowToolbarStyle(.unified(showsTitle: false))`). Default 1200×800; min 960×560.

##### v0.1.0 — Nexus Foundation (shipped)

Sandboxed picker, security-scoped bookmark persistence, `.nexus/` folder init flow, per-nexus subdirectory under Application Support keyed by ULID, sidebar tree mirroring picked folder with `.md` + `.json` shown. File menu → Open Nexus…; Debug menu → Reset Nexus Bookmark. 25 unit tests pass. (Formerly "v0.1a"; informal letter-suffix retired in favor of semver.)

##### Current Focus

**End of 2026-05-18 (Session 9 — v0.2.7 shipped, Phase 3 deferred):** The native TextKit-2 Page editor is **LIVE on `main` at `b7a2535`**. Pommora now uses the vendored `swift-markdown-engine` (local Swift Package at `External/MarkdownEngine/`) as its body editor. Build green, **197/197 tests pass**, lint exit 0. Apple `swift-markdown 0.8.0` SPM dep wired as engine groundwork (currently unused; powers the deferred Phase 3 AST rewrite).

**Shipped this session (5 commits, `1c6e270` → `b7a2535`):**
- ✅ **Phase 0** (`h.0`) — docs repair reconciling Session-8 engine-swap decision
- ✅ **Phase 1** (`h.1`) — Pallepadehat fork stripped (6 pbxproj entries + Package.resolved pin + `network.client` entitlement + External/PageEditorMD/ clone)
- ✅ **Phase 2** (`h.2`) — engine vendored as local SPM at `External/MarkdownEngine/` (Apache 2.0, 46 files, Swift 5.9 mode); Apple swift-markdown 0.8.0 added as Pommora SPM dep
- ✅ **Phase 4** (`h.3`) — `PageEditorView` body swapped to `NativeTextViewWrapper(text: $viewModel.body, configuration: .default, fontName: "SF Pro Text", fontSize: 15, documentId: viewModel.page.id)`; editable title TextField preserved exactly; swift-markdown 0.8.0 also added as engine-side dep
- ✅ **Phase 4.5 basic** (`h.4`) — character-pair auto-pair `**`/`__`/`[[`/`` `` `` with caret-between; suppressed inside code blocks + when next char is close marker

**Deferred to v0.2.7.1 patch:**
- **Phase 3 substantive** — rewrite engine's `MarkdownTokenizer.parseTokens(in:)` body to walk `Document(parsing: text)` AST + emit `[MarkdownToken]` shims; same for `MarkdownStyler.styleAttributes`; delete `MarkdownTokenizer+Emphasis.swift` + 6 `MarkdownStyler+*` extensions. Adds Table / BlockQuote / ThematicBreak / Strikethrough support.
- **Phase 4.5 polish** — selection-wrap (typing `*` with selected text → `*text*`) + auto-exit-on-whitespace + the 11-test auto-pair test suite.
- **Phase 6** — `.claude/Features/Pages.md` split into new `Features/PageEditor.md` covering editor-UX content.

**Plan deviation: engine location.** Plan specified `Pommora/Pommora/PageEditor/Engine/` (raw source vendoring). Shipped at `External/MarkdownEngine/` (local Swift Package). Rationale: Pommora's Swift 6 strict-concurrency + ExistentialAny clashed with the engine's Swift 5.9 idioms — the package boundary isolates the engine's concurrency contract, avoiding cascading `@MainActor` annotations across 46 files. Engine remains fully editable (we own the vendored copy in External/).

**Next session priorities** (verbatim resume prompt at top of `Handoff.md`): land v0.2.7.1 patch with the deferred Phase 3 + Phase 4.5 polish work. After v0.2.7.1: **v0.2.8 Tabs**, then v0.2.9 directives (`:::callout`/`@Columns` via Apple `BlockDirective`) + v0.2.10 wikilinks (autocomplete + click routing + rename cascade; extends engine's `WikiLinkService` two-form storage transform). v0.3.0 (Properties) follows the v0.2.x writable-Pommora milestone.

##### v0.2.0 — Paradigm scaffolding + sidebar UX polish (shipped on `paradigm-scaffolding`; merged to `main` 2026-05-18)

Single-branch effort that scaffolds the entire locked paradigm in one pass — Phases 0 → 6 of the implementation spec. Tracked task-by-task in `// Planning//Paradigm-Scaffolding-Tasks.md` (65 tasks).

**Shipped on `paradigm-scaffolding` (69 commits, sessions 2026-05-16 + 2026-05-17):**
- ✅ Swift 6 strict concurrency + ExistentialAny upcoming feature flipped on; Yams 5.4.0 + xnth97/SymbolPicker 1.6.2 SPM deps added
- ✅ Atomic-write helpers (`AtomicJSON`, `AtomicYAMLMarkdown`, `Filesystem`, `NexusPaths`)
- ✅ Codable for every entity: Space / Topic / Sub-topic / Vault / Collection (Codable + `_collection.json` sidecar) / Item / Page (frontmatter + composite) / AgendaItem / AgendaSchema / Recurrence / Homepage / TierConfig / SavedConfig / PropertyType / PropertyDefinition / PropertyValue (tagged `{$rel: ...}` relation encoding) / ContextBlock / VaultView / SpaceColor
- ✅ Validators for every entity + ULIDValidator + NexusContext provider pattern
- ✅ `@MainActor @Observable` managers for every entity (Space / Topic+Subtopic / Vault+Collection / Content (Pages+Items) / Agenda / Homepage / TierConfig / SavedConfig)
- ✅ Sidebar tier — `SidebarSelection` / `SelectionTag` / `SidebarSheet` / `SidebarConfirmation` enums; `SidebarView` four-section layout (Saved / Spaces / Topics / Vaults); 5 row views (`SpaceRow` / `TopicRow` / `SubtopicRow` / `VaultRow` / `CollectionRow`) + `ParentSpaceTags` helper; updated `SelectableRow`
- ✅ Sheets tier — `NewSpaceSheet` / `NewTopicSheet` / `NewSubtopicSheet` / `NewVaultSheet` / `NewCollectionSheet` / `NewPageSheet` / `NewItemSheet` / `EditTopicParentsSheet` / `SpaceColorPicker` + `ColorPickerSheet` / `IconPickerSheet` (wrapping SymbolPicker); confirmation dialogs with Topic-delete promote-vs-cascade
- ✅ Detail pane tier — `ContentItem` + `DetailRow` value types + `ContextDetailPlaceholder` (Spaces/Topics/Sub-topics until v0.9.0 composed-blocks editor); `VaultDetailView` + `CollectionDetailView` using native SwiftUI `Table(_:children:)`; `SidebarDetailView` dispatcher
- ✅ Item Window tier — `MultiSelectChips` + `FlowLayout` primitives; `PropertyEditorRow` per-PropertyType dispatch; `ItemWindow` popover with editable title + icon + description (250-char counter) + per-property editors + read-only tier1/2/3 (relation editor deferred to v0.5.0)
- ✅ ContentView full 8-manager wiring with real `contextProvider` closures via in-body snapshot-capture trick; preserves SidebarSearchField + inspector-internal toolbar layout from main
- ✅ 177 unit tests, 0 failures, 0 source warnings, sandbox entitlements verified

**Cleanup + UX polish shipped (13 commits this session — full list in `History.md` session 3 entry):**
1. ✅ Dead-code purge (`1343e50`) — `SheetStubView` + v0.1a folder-tree trio
2. ✅ Sidebar UX restructure (`c8dbac6`) — right-click context menus replace 5 "+ New" buttons; rename draft-loss fix; vault-root Page case added
3. ✅ Pages-under-Vaults/Collections sidebar disclosure (`02da8ff`) — `PageRow` leaf + vault-root content support in ContentManager
4. ✅ Sidebar regressions fix (`1a84a5f`) — full-row click + section disclosure chevrons + secondary headers + custom `SectionHeader` with `+` button
5. ✅ Sidebar polish (`64e6cd8`) — hover-only `+`; selection chrome on disclosure rows; `SelectableRow<Trailing>` generic
6. ✅ Sidebar fixes batch (`9971a35`) — SF Symbol picker in Create sheets via `IconPickerField`; `SpaceColor.accent`; renamingRow keeps icon; click-off cancels rename
7. ✅ Atomicity rollback + `pendingError` + 8 small fixes + 4 carryovers (`2d707a0`) — `RenameAtomicityError`, sidebar toast, `ContentManager+CRUD` split, validator rename, etc.
8. ✅ Launch crash fix (`3657cad`) — missing `.environment(contentMgr)` in ContentView sidebar branch
9. ✅ Accent rainbow swatch + 5x2 grid (`838b063`)
10. ✅ Detail-pane fixes (`8fe91d7`) — "+ New Collection" works; vault-root content in Table; Saved padding
11. ✅ Restore `.listRowBackground` for selection chrome (`ae8280d`) — covers chevron + matches search width + taller rows
12. ✅ Sidebar geometry consistency (`576d933`) — HStack spacing 8; icon 16x16 centered with 14pt glyph; renamingRow matches SelectableRow
13. ✅ Symmetric chrome for disclosure rows (`8cc492b`)
14. ✅ Selection polish (`0bc4c8d`) — chrome opacity 0.10, text brightness 0.10

**End of v0.2.0:** every entity in the locked paradigm is CRUD-able end-to-end via sidebar + sheets + detail pane + Item Window. Sidebar shows real Spaces / Topics / Vaults sections (plus heading-less Saved at top); Pages appear under Vaults/Collections; Items/Agenda live only in detail-pane Tables. No editor yet (that's v0.3.0). No tabs yet (that's v0.4.0). No property panel yet (that's v0.5.0).

##### v0.2.x — Path from v0.2.0 to v0.3.0 (touch-ups + infrastructure + Pages + Tabs)

Each patch ships green standalone. The infrastructure patches (.1 – .5) should land before the writable-Pommora patches (Pages + Tabs + their additions). **Order between Pages and Tabs is interchangeable** (Nathan locked 2026-05-17: "Pages or Tabs could land in any patch; just have to get done before v0.3.0 is started"). Directives + wikilinks are Pages-editor additions and naturally come after Pages itself.

**Shipped on `main` (end of 2026-05-18):**

- **v0.2.1 — Parallel-session sidebar UX tweaks** ✅ (`3bcf328`) — 16 Swift files (Detail / Sidebar / Sheet polish from Nathan's other session) + page selection wiring (`case page(PageMeta)` + placeholder `PageDetailView` text in `SidebarDetailView`). The substrate v0.2.7 plugs into.
- **v0.2.2 — CodeRabbit tightening** ✅ (`2e140ed`) — `ItemWindow.swift` refetch-after-rename recovery (`loadAll(for: coll)` + `dismiss()` on still-missing-after-reload) + 2 `ContentManagerTests` filesystem assertions.
- **v0.2.3 — CI baseline** ✅ (`56efd68`) — `.github/workflows/ci.yml` running `xcodebuild build` + `xcodebuild test -only-testing:PommoraTests` on `runs-on: macos-26`, triggered by push to any branch + PRs targeting `main`.
- **v0.2.4 — `swift-format` baseline** ✅ (`60e2ef6`) — `.swift-format` config at repo root (lineLength 120 / 4-space indent / `respectsExistingLineBreaks: true` / `OrderedImports: true` / `NeverForceUnwrap: false` to honor project's deliberate `try!` use) + one-time formatter pass across 97 Swift files (`+593/-422` mechanical whitespace + import-ordering only) + CI `swift format lint --strict` step in `ci.yml` after "Show toolchain" (fail-fast). Also fixed two pre-existing `OneCasePerLine` violations in `Recurrence.swift` since the formatter can't auto-fix that rule.
- **v0.2.5 — `.trash//` data foundation** ✅ (`9f56fbe`) — 5 new APIs (`NexusPaths.trashDir(in:)`, `Filesystem.moveToTrash(_:in:)`, private `suffixedWithTimestamp(_:)`, `FilesystemError.sourceNotInNexus`, file-private `String.removingPrefix(_:)`) + 10 manager delete-site swaps (SpaceManager.delete / TopicManager.deleteTopic + deleteSubtopic / VaultManager.deleteVault + deleteCollection / ContentManager+CRUD.deletePage×2 + deleteItem×2 / AgendaManager.deleteItem) + 4 new `FilesystemTrashTests` (movesFile / movesFolder / collisionAddsTimestampSuffix / rejectsExternalSource) + extended v0.2.2's `ContentManagerTests.deletes` + `VaultManagerTests.deleteVault`/`deleteCollection` assertions to ALSO check trash-side existence. Deletes are now recoverable from disk; in-app Trash UI window lands at v0.4.0.
- **v0.2.5.1 — Trash cleanup** ✅ (`25de7c6`) — `suffixedWithTimestamp` now appends a 4-char hex discriminator (UUID prefix) after the UTC timestamp — guarantees uniqueness for same-second collisions without loop ceremony (`Notes.20260518-093215-A3F2.md` shape). `rejectsExternalSource` test tightened to pattern-match the specific `FilesystemError.sourceNotInNexus` case. UTC documentation folded into the suffix function's docstring.
- **v0.2.6 — Spec catch-up** ✅ (`7b17d1d`) — 5 Swift literal version strings updated to align with the Framework reorder: `ItemWindow.swift` & `PropertyEditorRow.swift` "coming v0.5" → "v0.3.0" (Properties); `ContextDetailPlaceholder.swift` "coming v0.9" → "v0.7.0" (Composed view); `SidebarDetailView.swift` "Saved view coming v0.5" → "v0.6.0" (Calendar with EventKit); `SidebarDetailView.swift` "Page editor coming v0.6" → "v0.2.7". Doc passes: `// Features//Pages.md` softened from "Tiptap LOCKED" to "leading candidate; final pick reopens at v0.2.7 prep" with a structured candidate list and stack-agnostic architecture restated; `// Features//Sidebar.md` updated the right-click table's Page row entry to reference v0.2.7 and replaced the "discoverability deferred to quick-capture" section with a "hover-icon `+` complement + quick-capture" section acknowledging the hover-only `+` buttons that actually shipped in v0.2.0.

**Planned (next sessions):**

- **v0.2.7 — Pages editor (prose + standard Markdown).** Editor library decision narrowed to **three options** at end-of-5-18, fully documented at `// Planning//Page-Editor-Plan.md`: (1) Native Swift (`swift-markdown` + TextKit 2; optionally wrapping `nodes-app/swift-markdown-engine`); (2) JS editor library + macOS shell we build (Tiptap / Milkdown / BlockNote); (3) Fork `Pallepadehat/MarkdownEditor` (CodeMirror 6 + WKWebView, ours after fork). Nathan picks one at session start; implementation immediate. Recommendation: Option 3. Common to all options — `ContentManager.updatePage(_:in:vault:)` + `(_:inVaultRoot:)` lands first (mirrors `updateItem` shape; atomicity rollback + `pendingError` CRUD pattern from v0.2.0). Detail-pane dispatch routes `.page(PageMeta)` selection to `PageEditorView` (replaces v0.2.1/v0.2.6 placeholder). Standalone window via `WindowGroup(for: PageRef.self)` + `⌥⌘O`. Scope: prose editing (paragraphs, headings H1–H5, lists, code blocks, blockquotes, hr, links, inline marks). GFM tables parsed in all options; visually grid-rendered in Option 2 only at v0.2.7 (Options 1 + 3 show as source until later widget work). Bubble menu on selection. Markdown round-trips edge-to-edge.
- **v0.2.8 — Tabs.** Multi-tab interface in the navigation toolbar. Clicking a sidebar entry opens it as a tab; multiple Pages open simultaneously. Standard `+` / `×` / `⌘T` / `⌘W` chrome + `⌃Tab` / `⌃Shift+Tab` cycle. Vault + Collection detail views also tab-able (not just Pages). Persistence via `.nexus/state.json` (open tabs + active tab survive quit/relaunch). Standalone-window path from v0.2.7 continues to work in parallel. **Order with v0.2.7 is interchangeable** — whichever ships first is `.7`, the other `.8`.
- **v0.2.9 — Directives + heading fold + slash menu** (Pages-editor addition). `:::callout` node (outlined box), `@Columns` / `:::columns` node (CSS Grid), heading-fold chevrons, slash menu (`/`) for inserting directives + block types.
- **v0.2.10 — Wikilinks + rename cascade** (Pages-editor addition). `[[Title]]` autocomplete via popover (queries Swift via the `query` bridge), `Wikilink` inline node rendered as styled colored inline text, click routing (Page → opens in new tab / Context → detail pane / Item → ItemWindow popover), body-scan rename rewrite across all Pages containing `[[<oldTitle>]]`. (If v0.4.0 SQLite has landed by the time v0.2.10 ships, use the indexed lookup directly.)

End of v0.2.x: `main` has CI + formatter + trash + a fully usable Pages editor with tabs, directives, and wikilinks. **"Pommora is writable + multi-instance" milestone is complete** — long-form notes, multiple Pages open at once, wikilink-driven navigation, fenced callout + multi-column directives, foldable headings. v0.3.0 begins the data-model side (Properties).

##### v0.3.0 — Properties + Item creation surfacing + Item Window redesign

The other half of the data model — until now, Pages and Items load + save their property frontmatter but have no UI for editing it. v0.5.0 lands all of that, plus the Item story finally surfaces cohesively (deferred from v0.2.0 since Items without Properties are paradigm-hollow):

- **Property panel UI** — separate SwiftUI surface (in the inspector pane) showing each property in the parent Vault's schema, dispatched to per-type controls (TextField / Toggle / DatePicker / Picker / `MultiSelectChips` — most of these already exist from v0.2.0's `PropertyEditorRow`). Active for Pages and Items. Agenda items use the same panel once v0.8.0 ships Agenda UI.
- **`tier1` / `tier2` / `tier3` multi-select chip relation editor** — type-to-search relation pickers backed by Space / Topic / Sub-topic managers.
- **Vault property-schema editor** — `+ Add property` button → name + type picker → per-type config (options for Select, scope for Relation, etc.). Edits `_vault.json.properties[]` atomically. Currently empty in v0.2.0; this is where the schema actually fills up.
- **Schema mutations** — rename / type-change (lossless only) / delete; cross-member rewrite for renames using the same atomic-transaction pattern as wikilink renames.
- **Item creation surfacing** — Item creation paths expand from "only `CollectionDetailView` footer" to: `VaultDetailView` footer `+ New Item`, Collection row right-click → `New Item (in This Collection)`, Vault row right-click → `New Item`. Sidebar.md right-click menu table updated. `.newItem(...)` sheet routing already wired from v0.2.
- **Item Window redesign per Nathan's WIP sketch** — modal `WindowGroup(for: ItemRef.self)`, two-column body (description left, properties right), Delete/Save footer. Full spec at `// Features//Items.md` "Item window — design evolution".

End of v0.5.0: Pages + Items are structurally complete — body content + properties + Context relations all editable in-app, and the Item paradigm has a discoverable creation story. Agenda layer still dormant in-UI until v0.8.0 ships its UI hand-in-hand with EventKit.

##### v0.4.0 — SQLite + Watcher + cross-Vault move-strip + .trash UI

Infrastructure version. SQLite + watcher pulled forward (was v0.8.0 in the original plan) so the index is live for v0.3.0 Properties relation search and v0.5.0 Vault views from day one rather than building each against naive filesystem scans then rewriting:

- **SQLite indexer (GRDB.swift v7.5+)** — rebuilt from files on launch; six-table schema from PRD (`pages` / `items` / `agenda` / `vaults` / `tiers` / `links`). Per-nexus DB at `~/Library/Application Support/Pommora/nexuses/<nexus-id>/nexus.db` (kept outside the nexus to avoid iCloud-sync locking pathologies).
- **File watcher (FSEventStream)** — external changes update SQLite + sidebar live; atomic-write detection (debounce + outbound mtime tracking to ignore Pommora's own writes).
- **Wikilink rename cascade upgrade** — v0.2.10's naive body-scan rewrite gets replaced with SQLite-indexed lookup.
- **Cross-Vault move-strip rule** — Notion-style; moving a Page/Item across Vaults strips properties not in destination schema with confirm dialog listing affected props.
- **Cascade-delete reporting refinements** — exact counts in confirmation dialogs (Vault → N Collections + M Pages + K Items).
- **External-edit detection on Page save** — when v0.2.7 Pages editor saves a Page whose mtime has drifted since editor mount, prompt before overwriting.
- **In-app Trash window** — `.trash//` data layer already shipped at v0.2.5; v0.4.0 adds the SwiftUI surface listing entries with restore + permanent-delete + Empty Trash actions.

End of v0.4.0: live sync between disk and SQLite, external edits reflected in-app, deletes recoverable via UI, cross-Vault moves predictable. The "infrastructure" base layer is complete.

##### v0.5.0 — Vault view types (table / board / list / cards / gallery)

The five view types over Vault Content. Inline cell editing in Table view; Board view ships as visual kanban (cards grouped by a property's options; editing a card via the card UI moves it visually). Drag-to-rewrite-frontmatter on kanban is a post-v1.0 follow-up. Per-view filter / sort / group / shown-properties controls (powered by v0.4.0's SQLite + `json_extract` queries). Saved view configurations stored inside `_vault.json`. Vault `views` field becomes populated and editable.

End of v0.5.0: Vaults stop being just "lists of files in a folder" and become real database views — Pommora's Notion-like value proposition is now visible to the user.

##### v0.6.0 — EventKit + Agenda UI + Hardening + accessibility + performance + onboarding

The "polish + integration" version. Agenda's full UI ships **hand-in-hand with EventKit** (Nathan-locked: they go together — see Paradigm-Decisions.md). Combines previously-scattered concerns:

- **Agenda Item Window** — parallel to Item Window; time-field handling (single "When?" input when `start_at == due_at`; expands when divergent); per-Vault-schema property panel (same `PropertyEditorRow` dispatch as Items).
- **Agenda creation surfacing** — sidebar context-menu entries; menu-bar Quick Capture for fast event entry.
- **Calendar view over Agenda** — date-anchored grid replacing the placeholder Saved → Calendar entry; can be embedded in Contexts/Homepage post-v0.7.0.
- **EventKit bridge** — Sandbox entitlement (`com.apple.security.personal-information.calendars`) + Info.plist usage description keys + modern `requestFullAccessTo*` APIs. **Opt-in via Settings.** Bidirectional mirroring (`EKEvent` for items with `start_at` + `end_at`; `EKReminder` for items with `due_at` or unscheduled).
- **Settings scene scaffold** (`⌘,`) — Tier-config editor (per-tier singular + plural labels; `tagging_style`; `exposed` toggle); Saved-section labels editor (Homepage / Calendar / Recents renaming); EventKit sync opt-in toggle; **accent color + font size customization** (was previously a standalone v0.12.0 — folded in here since this is the natural home for user-overridable surface).
- **Accessibility checkpoint** — VoiceOver labels + focus order + Dynamic Type respect verified across all v0.2.0-v0.5.0 surfaces.
- **Performance budgets verified** — "open a Page in <X ms," "render N-row sidebar without jank," "Vault view with 1000 rows scrolls smoothly." Sets a baseline before v0.7.0 stacks more on top.
- **First-launch UX** — empty-state copy across sidebar sections + detail pane; nexus-picker flow polish; menu-bar `+ New` Quick Capture entry as the discoverable counterpart to right-click-only creation.
- **Saved section content fills in** — Recents (with tabs from v0.2.8 hooked up); Calendar (with EventKit mirror visible if opt-in).
- ✅ **Pending-error toast surface** — already shipped in v0.2.0 (`2d707a0`). v0.6.0 extends observation to AgendaManager / HomepageManager / TierConfigManager if user-driven CRUD lands for those.

End of v0.6.0: Pommora is integration-complete with system Calendar/Reminders, accessible, performant, and onboards new users without surprises.

##### v0.7.0 — Composed-blocks editor for Contexts + Homepage

The composed-blocks surface used by Spaces / Topics / Sub-topics / Homepage gets its editor. Block types: paragraph, headings, lists, callout, code, image, columns, **embedded-collection-view** (with **inline editing per the locked principle** — not snapshots; works because Vault views shipped at v0.5.0), linked-pages widget, link-list widget. Drag-and-drop reordering; slash-menu insertion.

End of v0.7.0: Contexts stop being "labeled buckets with an icon" and become real composed dashboards. The organization layer becomes substantive.

##### v0.8.0 — Global search + rich blocks

- **Global FTS5 search** over Page bodies, Item descriptions, Agenda titles, and frontmatter / properties (powered by v0.4.0's SQLite + FTS5 tables). `⌘K` command palette.
- **Mini-calendar widget** showing Agenda items inline (in Contexts/Homepage composed surfaces).
- **Additional block types** as needed once the basics are exercised.

##### v1.0.0 — Stabilization

No new features. Polish, performance, bug-fix across everything from v0.0.0 through v0.8.0. Final accent / typography pass. Release-readiness checklist (Sparkle integration if non-MAS, TestFlight if MAS).

##### Post-v1

No specific phase commitments yet. Catalog at `// Features//Prospects.md` — additional view types, synced blocks (full inline Page-body editing), graph view (currently a Prospect), collaborative simultaneous editing (out of scope indefinitely), sync (Supabase), mobile/iPad, plugin system, etc.

#### Roadmap reorders (cumulative history)

**2026-05-17 (Pages-first reorder):** previously the plan was v0.3.0 Hardening → v0.4.0 Agenda+EventKit → v0.5.0 Watcher → v0.6.0+ Page editor. Reordered to lead with the writable-Pommora milestone before infrastructure cycles.

**2026-05-17 end-of-session (final structural locks):**

1. **Pages + Tabs ship as v0.2.x patches before v0.3.0.** Initially structured as v0.3.0 = Pages, v0.4.0 = Tabs. Locked to: both ship as patches inside v0.2.x (specifically v0.2.7 Pages + v0.2.8 Tabs in either order, plus v0.2.9 directives + v0.2.10 wikilinks). v0.3.0 becomes Properties — the next substantial feature after Pommora becomes writable.
2. **Editor library narrowed to three options (end-of-5-18).** Tiptap was previously locked, then demoted to "leading candidate." End-of-5-18 research replaced the candidate list with three honest options inventoried at `// Planning//Page-Editor-Plan.md`: (1) Native Swift (`swift-markdown` + TextKit 2; optional `nodes-app/swift-markdown-engine` wrapper), (2) JS editor library + macOS shell we build (Tiptap / Milkdown / BlockNote), (3) Fork `Pallepadehat/MarkdownEditor` (CodeMirror 6 + WKWebView; ours after fork). `.md` file format is the firewall — user data portable across all three. Nathan picks at v0.2.7 start; recommendation is Option 3 for cheapest first experiment with high reversibility.
3. **Agenda UI ships hand-in-hand with EventKit at v0.6.0.** Previously considered as a v0.5.0 split-from-EventKit. Locked end of 5-17: they go together. Calendar view in Saved section also ships at v0.6.0.
4. **SQLite + Watcher at v0.4.0** (was v0.8.0 in original plan). Earlier indexing pays back across Properties (v0.3.0), Vault views (v0.5.0), and Contexts embedded views (v0.7.0).
5. **Vault views at v0.5.0** (was v0.10.0). Resolves the dependency contradiction where v0.7.0 Contexts editor embeds views.
6. **v0.6.0 consolidates accessibility + performance + onboarding + Settings + EventKit + Agenda UI** as the "polish + integration" pass. v0.12 customization folded into Settings scaffold.
7. **`.trash//` data foundation at v0.2.5**, in-app Trash window at v0.4.0. Originally unscoped; pulled forward because deletes need to be recoverable before Pages have months of content.

**Net result:** 7 minor versions remaining to v1.0.0 (v0.3.0 through v0.8.0 + v1.0.0). v0.11/v0.12 dissolved. v0.2.x is the long "infrastructure + Pages + Tabs" patch family.
