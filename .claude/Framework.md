### Pommora — Roadmap

Phased plan; no dates. Order is the only commitment.

> **Stack: SwiftUI.** Page editor = TextKit 2 + Apple `swift-markdown` + vendored `swift-markdown-engine` (shipped v0.2.7.0; full spec → `// Features//PageEditor.md`). Capability-level version descriptions below are written to survive any future editor-implementation swap.

#### Vision

A Markdown-canonical, SQLite-indexed personal management platform that combines Obsidian's local-first openness with Notion's database and view capabilities. Built around a **2-layer domain model** with PARA-aligned naming:

- **Organization layer — Contexts** (Spaces / Topics / Sub-topics) — categorical anchors that things relate *to*
- **Operational layer — Vaults + Agenda** — the data: Pages (`.md`) + Items (`.json`) inside Vaults; calendar-anchored items (`.agenda.json`) in Agenda with EventKit integration
- **Singleton — Homepage** — composed-blocks dashboard

Mac-first for v1, always open-source. Full domain spec → `// Features//Domain-Model.md`; complete implementation spec → `// Planning//Contexts-Vaults-spec.md`.

#### Phases

Versions use **`major.minor.patch` semver format**:
- **Minor (`v0.X.0`)** = a completed feature / capability cluster (Pages editor, NavDropdown, Properties, …).
- **Patch (`v0.X.y`)** = a touch-up or addition on top of an already-shipped feature (polish commit, infrastructure baseline, paradigm-doc hygiene, a small additive extension).
- **Major (`vX.0.0`)** reserved for `v1.0.0` (stabilization milestone) and onward.

Every release ships green standalone and produces a verifiable outcome you can run. **CRUD lands paired with paradigm** at every minor version per the locked spec — a new entity type doesn't appear in code until its CRUD interface is functional end-to-end.

##### v0.0.0 — Shell opens (shipped)

Toolchain proof. App launches on macOS 26+ (Tahoe) into a barebones three-pane shell — sidebar (default 240) / main (flex) / pop-out inspector (default 280, **hidden by default**) — built on SwiftUI's two-column `NavigationSplitView(sidebar:detail:)` with the inspector attached via `.inspector(isPresented:)`. Sidebar drag-resizable; widths persist. Window title suppressed (`.windowToolbarStyle(.unified(showsTitle: false))`). Default 1200×800; min 960×560.

##### v0.1.0 — Nexus Foundation (shipped)

Sandboxed picker, security-scoped bookmark persistence, `.nexus/` folder init flow, per-nexus subdirectory under Application Support keyed by ULID, sidebar tree mirroring picked folder with `.md` + `.json` shown. File menu → Open Nexus…; Debug menu → Reset Nexus Bookmark. 25 unit tests pass. (Formerly "v0.1a"; informal letter-suffix retired in favor of semver.)

##### Current Focus

**End of 2026-05-18 (Session 9 close — v0.2.7.0 SHIPPED + PUSHED):** The native TextKit-2 Page editor is **LIVE on `origin/main` at `9a0b383`**, **tagged `v0.2.7.0`**. Pommora uses Apple `swift-markdown 0.8.0` + a locally vendored `swift-markdown-engine` package (`External/MarkdownEngine/`, Apache 2.0). After an initial bad attempt with the Pallepadehat WKWebView fork that didn't deliver the Notion/Obsidian-native feel, the TextKit-2 pivot sealed it — Apple-native Writing Tools, Look Up / Translate, spell-check, IME, dynamic colors all show up free. Build green, **197/197 tests pass**, lint exit 0, engine builds standalone.

**Shipped this session (10 commits, `1c6e270` → `9a0b383`):** Full commit table at the top of `Handoff.md`. Highlights: Pallepadehat fork stripped (`h.1`); engine vendored as local SPM + Apple swift-markdown 0.8.0 added (`h.2`); `PageEditorView` wired to `NativeTextViewWrapper` (`h.3`); character-pair auto-pair (`h.4`); UX polish — title-body padding + body 24pt textInsets + auto-unpair-on-backspace (`h.7`); Apple-AST supplemental styler for BlockQuote/Strikethrough/Table/ThematicBreak + expanded right-click menu Format/Heading/Lists/Block (`h.8`); HR-as-real-line via custom NSTextLayoutFragment drawing + table pipes/separator-row hidden + Enter→body focus shift (`h.9`); HR draw-detection fix + title @FocusState + H5/H6 removed (`h.10`).

**Plan deviation that paid off:** the original plan called for raw source vendoring at `Pommora/Pommora/PageEditor/Engine/`. We pivoted to a local Swift Package at `External/MarkdownEngine/` because Pommora's Swift 6 strict-concurrency + ExistentialAny clashed with the engine's Swift 5.9 idioms. The package boundary isolated the engine's concurrency contract, avoiding cascading `@MainActor` annotations across 46 files. Engine remains fully Pommora-editable.

##### Roadmap reorders locked Session 9 close

**v0.2.7.x patch sequence** (post-NavDropdown ship; ordering not pinned to specific patch numbers — pick what's next at session time):

- ✅ **v0.2.7.0** — Page editor (native TextKit-2 via vendored swift-markdown-engine; SHIPPED Session 9)
- ✅ **v0.2.7.2** — NavDropdown first attempt (functional + standalone preview window + hover-heart favorites; TAGGED but **superseded by v0.2.7.1**)
- ✅ **v0.2.7.1** — NavDropdown simplification (standalone window removed, Favorites → Pinned + right-click context menu, single-click select / double-click open, detail-view context menus on Page + Item rows; SHIPPED end of 2026-05-19) — canonical NavDropdown
- 🟡 **v0.2.7.2 — Page editor fixes (PARTIAL SHIP 2026-05-20, Sessions 12 + 13)** — **HR / divider SHIPPED** Session 12 via Obsidian-style dynamic syntax (full architecture at `Features/PageEditor.md → Dynamic-syntax pattern`). Established the locked architecture for paragraph-level dynamic-syntax constructs: AST-backed detection in renderer + caret-awareness service as sole writer + styler emits nothing for the construct. Session-12 changes: `MarkdownTextLayoutFragment.swift` + `AppleASTSupplementalStyler.swift` + `NativeTextViewCoordinator+HRVisibility.swift` (new) + legacy `MarkdownListHandler` HR expansion removed. **Lists SHIPPED** Session 13 via rewrite of `MarkdownListHandler.swift`: space styles immediately (styler-driven, no source mutation), Enter continues with next marker via Case 4, Shift+Enter exits via modifier-flag check at top of `\n` block (NOT `doCommandBy` — that selector only fires on Ctrl+\), bare `-` / `1.` + Enter initializes list via Case 1, edge guard fixes the "voids the line at caret-line-start" regression. Portable CommonMark source on disk (`- item` / `* item` / `+ item` / `1. item`) instead of pre-v0.2.7.2 `\t• ` engine-only syntax. Visual indent restored via `firstLineHeadIndent = indentPerLevel + depthIndent`. `bulletListPattern` broadened from `[-•]` to `[-*+•]`. ContextMenu cleanup: "Insert bullet list" writes `- ` not `\t• `; `isSelectionList` detects CommonMark + legacy; `applyList` strips any known prefix before re-adding. Pre-existing typo fix at `MarkdownTextLayoutFragment.swift:534`. **Bullet glyph substitution (`-` → `•` visually) attempted + reverted** (overlay produced invisible bullets — deferred as a known cosmetic caveat). **Blockquote DEFERRED** (next session — Apple-Calendar-event-card chrome via dynamic-syntax pattern). **Tables DEFERRED** (~10-15h realistic estimate). Right-click "Insert HR" out of scope.
- **Remaining page editor fixes** (next session — full list in Handoff) — Bullet glyph substitution (`-` → `•`); Blockquote rendering (Apple-Calendar-event-card chrome); Code & Quote `Enter}` auto-completion; Code block → red text bug; Auto-format `←` / `↔` (the `->` works but `<-` / `<->` don't transform on typed input — paste works fine).
- **Tables** (queued — ASAP but realistic estimate 10-15h after divider iteration experience) — Full spec preserved at `// Planning//Page-Editor-Plan.md → Phase 3` (CG inline grid overlay + drag-resize column dividers + `pommora_table_widths` frontmatter persistence + double-click NSPopover hosting SwiftUI Grid with editable TextField cells + right-click structural context menu via `TableStructureRewriter` AST splice). NSTextTable explicitly rejected; Core Graphics overlay IS the 2026 Apple-native path.
- **Sidebar + Vault/Collection drag-to-reorder** (queued) — drag Pages between Collections; reorder Spaces/Topics/Sub-topics; reorder Pinned in NavDropdown (covers the v0.2.7.1 follow-up #2); persist order via new `_order: [<id>]` overlay on parent JSON sidecars.
- **PreviewWindow primitive** (queued) — cross-feature standalone-window surface for Pages / Vaults / Collections / Spaces / Topics / Sub-topics / Items / Agenda items. Once any kind has a wired PreviewWindow, NavDropdown's open-in-preview can be lit up per kind (covers v0.2.7.1 follow-up #1). See `Guidelines/CRUD-Patterns.md → Preview-window prerequisite` for the project-wide contract.

After v0.2.7.x: **v0.3.0 (Properties)** begins the data-layer chapter (v0.3.x sub-sequence locked RC-2026-05-19; see "Roadmap reorders" below). **Wikilinks moved from v0.2.10 → v0.3.2** (couples with SQLite at v0.3.3, indexed from day one). **Directives + heading fold + slash menu** (formerly v0.2.9) are unscheduled — page editor is functional without them; they re-home to a future v0.2.x or post-v0.3.x patch as decided.

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

##### v0.2.x — Path from v0.2.0 to v0.3.0 (touch-ups + infrastructure + Pages + NavDropdown)

Each patch ships green standalone. The infrastructure patches (.1 – .5) should land before the writable-Pommora patches (Pages + NavDropdown + their additions). **Order between Pages and NavDropdown is interchangeable** (Nathan locked 2026-05-17: "Pages or Tabs could land in any patch; just have to get done before v0.3.0 is started" — quote pre-dates the 2026-05-18 Tabs → NavDropdown pivot but the ordering principle holds). Directives + wikilinks are Pages-editor additions and naturally come after Pages itself.

**Shipped on `main` (end of 2026-05-18):**

- **v0.2.1 — Parallel-session sidebar UX tweaks** ✅ (`3bcf328`) — 16 Swift files (Detail / Sidebar / Sheet polish from Nathan's other session) + page selection wiring (`case page(PageMeta)` + placeholder `PageDetailView` text in `SidebarDetailView`). The substrate v0.2.7 plugs into.
- **v0.2.2 — CodeRabbit tightening** ✅ (`2e140ed`) — `ItemWindow.swift` refetch-after-rename recovery (`loadAll(for: coll)` + `dismiss()` on still-missing-after-reload) + 2 `ContentManagerTests` filesystem assertions.
- **v0.2.3 — CI baseline** ✅ (`56efd68`) — `.github/workflows/ci.yml` running `xcodebuild build` + `xcodebuild test -only-testing:PommoraTests` on `runs-on: macos-26`, triggered by push to any branch + PRs targeting `main`.
- **v0.2.4 — `swift-format` baseline** ✅ (`60e2ef6`) — `.swift-format` config at repo root (lineLength 120 / 4-space indent / `respectsExistingLineBreaks: true` / `OrderedImports: true` / `NeverForceUnwrap: false` to honor project's deliberate `try!` use) + one-time formatter pass across 97 Swift files (`+593/-422` mechanical whitespace + import-ordering only) + CI `swift format lint --strict` step in `ci.yml` after "Show toolchain" (fail-fast). Also fixed two pre-existing `OneCasePerLine` violations in `Recurrence.swift` since the formatter can't auto-fix that rule.
- **v0.2.5 — `.trash//` data foundation** ✅ (`9f56fbe`) — 5 new APIs (`NexusPaths.trashDir(in:)`, `Filesystem.moveToTrash(_:in:)`, private `suffixedWithTimestamp(_:)`, `FilesystemError.sourceNotInNexus`, file-private `String.removingPrefix(_:)`) + 10 manager delete-site swaps (SpaceManager.delete / TopicManager.deleteTopic + deleteSubtopic / VaultManager.deleteVault + deleteCollection / ContentManager+CRUD.deletePage×2 + deleteItem×2 / AgendaManager.deleteItem) + 4 new `FilesystemTrashTests` (movesFile / movesFolder / collisionAddsTimestampSuffix / rejectsExternalSource) + extended v0.2.2's `ContentManagerTests.deletes` + `VaultManagerTests.deleteVault`/`deleteCollection` assertions to ALSO check trash-side existence. Deletes are now recoverable from disk; in-app Trash UI window lands at v0.4.0.
- **v0.2.5.1 — Trash cleanup** ✅ (`25de7c6`) — `suffixedWithTimestamp` now appends a 4-char hex discriminator (UUID prefix) after the UTC timestamp — guarantees uniqueness for same-second collisions without loop ceremony (`Notes.20260518-093215-A3F2.md` shape). `rejectsExternalSource` test tightened to pattern-match the specific `FilesystemError.sourceNotInNexus` case. UTC documentation folded into the suffix function's docstring.
- **v0.2.6 — Spec catch-up** ✅ (`7b17d1d`) — 5 Swift literal version strings updated to align with the Framework reorder: `ItemWindow.swift` & `PropertyEditorRow.swift` "coming v0.5" → "v0.3.0" (Properties); `ContextDetailPlaceholder.swift` "coming v0.9" → "v0.7.0" (Composed view); `SidebarDetailView.swift` "Saved view coming v0.5" → "v0.6.0" (Calendar with EventKit); `SidebarDetailView.swift` "Page editor coming v0.6" → "v0.2.7". Doc passes: `// Features//Pages.md` softened from "Tiptap LOCKED" to "leading candidate; final pick reopens at v0.2.7 prep" with a structured candidate list and stack-agnostic architecture restated; `// Features//Sidebar.md` updated the right-click table's Page row entry to reference v0.2.7 and replaced the "discoverability deferred to quick-capture" section with a "hover-icon `+` complement + quick-capture" section acknowledging the hover-only `+` buttons that actually shipped in v0.2.0.

**Planned (next sessions):**

- 🔒 **v0.2.7.2 — Page editor fixes (plan LOCKED 2026-05-20).** Three-phase patch covering Blockquote (Apple Calendar event-card chrome — grey rounded card + 3pt vertical accent bar inside; per-fragment corner-rounding for multi-line visual continuity), HR (auto-transform on 3rd dash + cursor-atom behavior + right-click `\n\n---\n\n` insert + container-minus-insets width + raw `NSColor.separatorColor`), and Tables (Core Graphics inline grid overlay + drag-resize columns + `pommora_table_widths` frontmatter persistence + double-click NSPopover SwiftUI cell editor + right-click structural add-row/add-column context menu). NSTextTable explicitly rejected after Round-5 verification: Apple's own TextEdit silently downgrades to TextKit 1 when a table is inserted (Krzyzanowski Aug 2025 "TextKit 2: The Promised Land"); Apple Notes uses a custom protobuf document model, not the AppKit text system. Core Graphics overlay drawn in `MarkdownTextLayoutFragment.draw` IS the 2026 Apple-native path; preserves the TextKit-2-native Writing Tools / Look Up / dynamic-color wins from Session 9. ~7.5h across 3 phases / 4 stages. Full implementation spec at `// Planning//Page-Editor-Plan.md`.
- **v0.2.9 — Directives + heading fold + slash menu (UNSCHEDULED, re-homing TBD)** — `:::callout` / `@Columns` directives, heading-fold chevrons, `/` slash menu. Removed from the active v0.2.x patch sequence at RC-2026-05-19; page editor is functional without them. Re-homes to a later v0.2.x patch, or post-v0.3.x, when Nathan decides.
- **v0.2.10 — Wikilinks** — **moved to v0.3.2** (RC-2026-05-19). Couples with SQLite at v0.3.3 so the autocomplete + rename cascade ship indexed from day one. Full scope under v0.3.2 in the v0.3.x sub-sequence below.

End of v0.2.x: `main` has formatter + trash + a fully usable Pages editor with NavDropdown navigation history (Pinned + Recents). Directives + wikilinks no longer land inside v0.2.x — directives are unscheduled; wikilinks moved to v0.3.2. GitHub CI was removed at v0.2.7.1 (lint-only locally + via `swift format` subcommand). **"Pommora is writable" milestone is complete** — long-form notes editable, NavDropdown navigation history, right-click context menus for Page + Item CRUD. v0.3.0 begins the data-model side (Properties).

##### v0.3.x — Properties + Items pane + Wikilinks + SQLite (data-layer chapter)

The other half of the data model — until v0.3.0, Pages and Items load + save their property frontmatter but have no UI for editing it. The four-patch sub-sequence at v0.3.x closes the data layer entirely, ending at indexed cross-document linking + queryable storage. **Sub-sequence locked RC-2026-05-19**:

```
v0.3.0 — Properties
v0.3.1 — Items pane (Item Window redesign)
v0.3.2 — Page-wikilinks
v0.3.3 — SQLite + querying
```

Full implementation spec → `// Planning//v0.3.0-Properties-implementation.md`.

###### v0.3.0 — Properties

- **Property panel UI** — separate SwiftUI surface (in the Pages inspector pane + Item Window) showing each property in the parent Vault's schema, dispatched to per-type controls (TextField / Toggle / DatePicker / Picker / `MultiSelectChips` — most already wired from v0.2.0's `PropertyEditorRow`). 7 of 8 property types already wired; v0.3.0 adds the Relation editor (currently stubbed at `PropertyEditorRow.swift:33`) + scope-aware pickers (Vault / Collection / Context-tier).
- **Last Edited Time property type** — promoted from collapsed `modified_at` footer to first-class sortable property; v0.3.0 default sort on Vault Table views is descending.
- **`tier1` / `tier2` / `tier3` multi-select chip relation editor** — type-to-search relation pickers backed by Space / Topic / Sub-topic managers (shared `ContextTierPicker` component).
- **Vault property-schema editor** — `NewPropertySheet` opened from the Vault Table view's rightmost "+ Property" column header (Notion pattern) + Vault row right-click → "Edit Schema…". Name + type picker → per-type config (options for Select, scope for Relation, dual toggle for Relation, etc.). Edits `_vault.json.properties[]` atomically via `SchemaTransaction` (new two-phase commit infrastructure in `AtomicIO//`).
- **Schema mutations** — add / rename / type-change (lossless only) / delete / reorder; cross-member rewrite for renames using `SchemaTransaction`.
- **Dual relations** — Notion-parity: setting a dual Relation on Vault A pointing at Vault B auto-creates a reverse property on B; values mirror automatically. Context-tier scopes are inherently one-way (Contexts don't have a per-tier `properties[]`); UI grays out the dual toggle for those.
- **Cross-Vault move-strip** — pulled forward from v0.4.0; tightly coupled to property schema. Move dialog lists props that'll be stripped before commit.
- **Item creation surfacing** — Item creation paths expand from "only `CollectionDetailView` footer" to: `VaultDetailView` footer `+ New Item`, Collection row right-click → `New Item (in This Collection)`, Vault row right-click → `New Item`. `Sidebar.md` right-click menu table updated.
- **Sort by property** in Vault Table views — type-aware comparators (Select option-order, Date chronological, Last Edited Time descending default, etc.). Per-Vault default-sort persists in `_vault.json.default_sort` (new field). Full per-view sort + saved configurations land at v0.6.0.

End of v0.3.0: Items paradigm closes. Pages + Items both have body + properties + tier relations editable in-app.

###### v0.3.1 — Items pane (Item Window redesign)

Reshape the Item Window around the now-filled property panel per Nathan's WIP sketch (`// Features//Items.md` "Item window — design evolution"):
- Modal `WindowGroup(for: ItemRef.self)` — standalone window, side-by-side editing possible
- Two-column body: description left (60%), properties right (40%)
- Delete (red, edit-mode-only) + Save footer
- Same view doubles as create + edit by passing mode

###### v0.3.2 — Page-wikilinks

Body-text wikilinks (`[[Title]]`) with autocomplete + click routing + rename cascade:
- **Autocomplete popover** triggered by typing `[[`, queries Pages/Items/Contexts via managers (naive scan until v0.3.3)
- **Click routing** — Page → opens in detail pane; Context → detail pane; Item → ItemWindow popover
- **Rename cascade** — renaming a target Page rewrites all `[[oldTitle]]` references via naive body scan
- **Derived `wikilinks: [<id>, ...]` frontmatter mirror** — auto-maintained from body scan on save; queryable via index at v0.3.3
- **NOT a creatable property type** — schema editor doesn't offer Wikilink

###### v0.3.3 — SQLite + querying

Indexed lookup swaps in transparently behind the existing manager APIs:
- **SQLite indexer (GRDB.swift v7.5+)** — rebuilt from files on launch; six-table schema from PRD (`pages` / `items` / `agenda` / `vaults` / `tiers` / `links`). Per-nexus DB at `~/Library/Application Support/Pommora/nexuses/<nexus-id>/nexus.db`.
- **File watcher (FSEventStream)** — external changes update SQLite + sidebar live
- **Wikilink rename cascade upgrade** — v0.3.2's naive body-scan rewrite gets replaced with indexed lookup
- **Relation picker performance** — naive manager scan replaced with indexed query
- **External-edit detection on Page save** — prompt before overwriting drifted mtime
- **FTS5 tables wired** — schema only, no UI; ⌘K palette ships at v0.8.0

End of v0.3.x: data layer is complete. Pages editable + Items paradigm closed + cross-document linking live + storage indexed.

##### v0.4.0 — Trash UI + cascade-delete refinements

Smaller version — SQLite + Watcher absorbed into v0.3.3; cross-Vault move-strip absorbed into v0.3.0.

- **In-app Trash window** — `.trash//` data layer already shipped at v0.2.5; v0.4.0 adds the SwiftUI surface listing entries with restore + permanent-delete + Empty Trash actions.
- **Cascade-delete reporting refinements** — exact counts in confirmation dialogs (Vault → N Collections + M Pages + K Items).
- **External-edit detection on Item / Agenda save** — extends v0.3.3's Page-save detection to other entity types as needed.

End of v0.4.0: deletes recoverable via UI. The "infrastructure" base layer is complete.

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
- **Saved section content fills in** — Recents (full-frame view backed by NavDropdown's `RecentsManager`, sharing the v0.2.7.1 store); Calendar (with EventKit mirror visible if opt-in).
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

1. **Pages + NavDropdown ship as v0.2.x patches before v0.3.0.** Initially structured as v0.3.0 = Pages, v0.4.0 = Tabs. Locked to: both ship as patches inside v0.2.x (specifically v0.2.7 Pages + v0.2.7.2 NavDropdown, originally assigned v0.2.8 before Session-9 resequencing, plus v0.2.9 directives + v0.2.10 wikilinks → later unscheduled and moved). v0.3.0 becomes Properties — the next substantial feature after Pommora becomes writable. (NavDropdown originally scoped as 'Tabs'; pivot to a Liquid Glass dropdown locked 2026-05-18 — see `// Features//NavDropdown.md`.)
2. **Editor library narrowed to three options (end-of-5-18).** Tiptap was previously locked, then demoted to "leading candidate." End-of-5-18 research replaced the candidate list with three honest options inventoried at `// Planning//Page-Editor-Plan.md`: (1) Native Swift (`swift-markdown` + TextKit 2; optional `nodes-app/swift-markdown-engine` wrapper), (2) JS editor library + macOS shell we build (Tiptap / Milkdown / BlockNote), (3) Fork `Pallepadehat/MarkdownEditor` (CodeMirror 6 + WKWebView; ours after fork). `.md` file format is the firewall — user data portable across all three. Nathan picks at v0.2.7 start; recommendation is Option 3 for cheapest first experiment with high reversibility.
3. **Agenda UI ships hand-in-hand with EventKit at v0.6.0.** Previously considered as a v0.5.0 split-from-EventKit. Locked end of 5-17: they go together. Calendar view in Saved section also ships at v0.6.0.
4. **SQLite + Watcher at v0.4.0** (was v0.8.0 in original plan). Earlier indexing pays back across Properties (v0.3.0), Vault views (v0.5.0), and Contexts embedded views (v0.7.0).
5. **Vault views at v0.5.0** (was v0.10.0). Resolves the dependency contradiction where v0.7.0 Contexts editor embeds views.
6. **v0.6.0 consolidates accessibility + performance + onboarding + Settings + EventKit + Agenda UI** as the "polish + integration" pass. v0.12 customization folded into Settings scaffold.
7. **`.trash//` data foundation at v0.2.5**, in-app Trash window at v0.4.0. Originally unscoped; pulled forward because deletes need to be recoverable before Pages have months of content.

**Net result:** 7 minor versions remaining to v1.0.0 (v0.3.0 through v0.8.0 + v1.0.0). v0.11/v0.12 dissolved. v0.2.x is the long "infrastructure + Pages + NavDropdown" patch family.

**2026-05-19 RC-session (v0.3.x sub-sequence locked):** The v0.3.x patch family was explicit at: `v0.3.0 = Properties` / `v0.3.1 = Items pane` / `v0.3.2 = Page-wikilinks` / `v0.3.3 = SQLite + querying`. SQLite + Watcher absorbed from v0.4.0 → v0.3.3 (data-layer chapter completes in one minor). Cross-Vault move-strip absorbed from v0.4.0 → v0.3.0 (tightly coupled to property schema). Wikilinks moved from v0.2.10 → v0.3.2 (depends on derived `wikilinks: []` frontmatter mirror which is naturally part of the data-layer chapter). v0.4.0 reduced to Trash UI + cascade-delete refinements. Full v0.3.0 implementation spec at `// Planning//v0.3.0-Properties-implementation.md`.

**2026-05-20 (v0.2.7.2 slot assigned + plan locked):** The post-NavDropdown v0.2.7.x patch slot is now planned for page editor fixes (Blockquote Apple-Calendar-event-card chrome + HR auto-transform/cursor-atom + Tables Core-Graphics grid + popover edit + structural context menu). Tables custom grid (previously sketched as a separate v0.2.7.3 patch) is absorbed into v0.2.7.2 Phase 3. NSTextTable rejected as a viable Apple-native alternative — Round-5 research confirmed Apple's own TextEdit downgrades to TextKit 1 to use it, and Apple Notes uses a custom protobuf model. ~7.5h estimate across 3 phases / 4 stages. Full implementation spec at `// Planning//Page-Editor-Plan.md`.
