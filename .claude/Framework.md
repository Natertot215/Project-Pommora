### Pommora — Roadmap

Phased plan; no dates. Order is the only commitment.

> **Stack: SwiftUI.** Page editor = TextKit 2 + Apple `swift-markdown` + vendored `swift-markdown-engine` (shipped v0.2.7.0; full spec → `// Features//PageEditor.md`). Capability-level version descriptions below are written to survive any future editor-implementation swap.

#### Vision

A Markdown-canonical, SQLite-indexed personal management platform that combines Obsidian's local-first openness with Notion's database and view capabilities. Built around a **2-layer domain model** with PARA-aligned naming (ParadigmV2 refactor 2026-05-22):

- **Organization layer — Contexts** (Spaces / Topics / **Projects**) — categorical anchors that things relate *to*
- **Operational layer — symmetric Pages + Items + Agenda**:
  - **Pages side:** Page Types → Page Collections → Pages (`.md`). UI labels default to "Vault" + "Collection".
  - **Items side:** Item Types → Item Collections → Items (`.json`). UI labels default to "Type" + "Set".
  - **Agenda:** split into Agenda Tasks (`.task.json`, EKReminder-aligned) and Agenda Events (`.event.json`, EKEvent-aligned) inside their respective singleton folders at the nexus root (the folder carrying `_taskconfig.json` is the Tasks singleton; the folder carrying `_eventconfig.json` is the Events singleton). EventKit integration. No sidebar section — surfaces via Calendar pin.
- **Singleton — Homepage** — composed-blocks dashboard
- **Settings scaffold** — `.nexus/settings.json` carrying user-overridable UI labels + accent color (ships v0.3.0; editing UI ships v0.6.0)

Mac-first for v1, always open-source. Full domain spec → `// Features//Domain-Model.md`.

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

**`flatlayout` SHIPPED + post-ship hardening cluster landed** (tag `flatlayout` at `049df19`, between `paradigmV2` and v0.3.0). On-disk layout is flat — Types live at the nexus root + six per-kind sidecars (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`); Agenda Tasks + Events are sidecar-driven singletons at root. `NexusAdopter` handles four input shapes (fresh / legacy v0.2 / paradigmV2-wrapper / already-flat) with legacy-orphan + co-located sidecar cleanup. Five post-ship hardening commits on `main`: adoption-preview gate (non-Pommora folders stay invisible), drag-to-reorder Phase 2 UX (v0.2.8), `lookupVault` folder-name fallback + diagnostics, co-located per-kind sidecar orphan cleanup, and a cosmetic `var` → `let`. Build green, **366 tests passing**. Nathan's real-nexus migration is complete.

**Next: v0.3.0 Properties** begins on the flat-layout foundation — implementation plan at `// Planning//v0.3.0-Properties-plan.md` (5 phases A–E; `ItemTypeSettingsSheet` ships at v0.3.0). Detailed ship log in `History.md`.

##### v0.2.7.x — Page editor patch family

Post-Pages-editor capability iterations on top of the v0.2.7.0 TextKit-2 baseline.

- ✅ **v0.2.7.0** — Page editor (native TextKit-2 + Apple `swift-markdown` 0.8.0 + vendored `swift-markdown-engine`)
- ✅ **v0.2.7.1** — NavDropdown (Liquid Glass dropdown nav — Pinned + Recents tabs; single-click select / double-click open)
- 🟡 **v0.2.7.2** — Page editor fixes — HR / divider + Lists rewritten via dynamic-syntax architecture (shipped); Blockquote + Tables deferred. Locked architecture for paragraph-level constructs at `Features/PageEditor.md → Dynamic-syntax pattern`.
- ✅ **v0.2.7.4** — Editor polish bundle — HR jitter fix, bullet glyph substitution (`-` → `•`), task shorthand `-[]` / `-[x]`, bracket auto-pair guard, arrow auto-format, code-block colors.
- ✅ **v0.2.7.5** — Blockquote chrome (always-show overlay; renderer-drawn rounded card + vertical pill bar). One visual TBD (horizontal positioning) in Handoff.
- **Remaining page editor fixes** — code & quote `Enter}` auto-completion; code block → red text bug.
- **Tables** (queued — ~10-15h realistic estimate; spec at `// Features//PageEditor.md → Tables — to be implemented`) — Core Graphics inline grid overlay + drag-resize columns + `pommora_table_widths` frontmatter persistence + double-click popover editor + right-click structural context menu. NSTextTable explicitly rejected.
- ✅ **Sidebar drag-to-reorder Phase 2 — v0.2.8** — Phase 1 persistence shipped `5a264f0`; Phase 2 UX shipped `9cd8cd1` (Pages-side + Contexts rows: PageType / Topic / Space / Page / PageCollection / Project). Still queued in `Planning/v0.2.8-Drag-Reorder.md`: Items-side rows (ParadigmV2 stubs), NavDropdown Pinned reorder, cross-container drag (out-of-scope v1), detail-pane Table reorder (Phase 4).
- **PreviewWindow primitive** (queued) — cross-feature standalone-window surface. Project-wide contract at `Guidelines/CRUD-Patterns.md → Preview-window prerequisite`.
- **Directives + heading fold + slash menu** (formerly v0.2.9) — unscheduled; page editor is functional without them.

After v0.2.7.x: v0.3.0 Properties begins the data-layer chapter.

##### v0.2.0 — Paradigm scaffolding + sidebar UX polish (shipped)

Single-branch effort that scaffolded the entire locked paradigm in one pass (`paradigm-scaffolding`, 69 commits, merged to `main` 2026-05-18). End state: every entity is CRUD-able end-to-end via sidebar + sheets + detail pane + Item Window; Spaces / Topics / Vaults sections in the sidebar with Pages disclosed under Vaults/Collections; Items/Agenda live in detail-pane Tables only. 177 unit tests passing at merge. Full session breakdown in `History.md`.

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

- 🔒 **v0.2.7.2 — Page editor fixes (plan LOCKED 2026-05-20).** Three-phase patch covering Blockquote (Apple Calendar event-card chrome — grey rounded card + 3pt vertical accent bar inside; per-fragment corner-rounding for multi-line visual continuity), HR (auto-transform on 3rd dash + cursor-atom behavior + right-click `\n\n---\n\n` insert + container-minus-insets width + raw `NSColor.separatorColor`), and Tables (Core Graphics inline grid overlay + drag-resize columns + `pommora_table_widths` frontmatter persistence + double-click NSPopover SwiftUI cell editor + right-click structural add-row/add-column context menu). NSTextTable explicitly rejected after Round-5 verification: Apple's own TextEdit silently downgrades to TextKit 1 when a table is inserted (Krzyzanowski Aug 2025 "TextKit 2: The Promised Land"); Apple Notes uses a custom protobuf document model, not the AppKit text system. Core Graphics overlay drawn in `MarkdownTextLayoutFragment.draw` IS the 2026 Apple-native path; preserves the TextKit-2-native Writing Tools / Look Up / dynamic-color wins from Session 9. ~7.5h across 3 phases / 4 stages. Full implementation spec at `// Features//PageEditor.md → Tables — to be implemented`.
- **v0.2.9 — Directives + heading fold + slash menu (UNSCHEDULED, re-homing TBD)** — `:::callout` / `@Columns` directives, heading-fold chevrons, `/` slash menu. Removed from the active v0.2.x patch sequence at RC-2026-05-19; page editor is functional without them. Re-homes to a later v0.2.x patch, or post-v0.3.x, when Nathan decides.
- **v0.2.10 — Wikilinks** — **moved to v0.3.2** (RC-2026-05-19). Couples with SQLite at v0.3.3 so the autocomplete + rename cascade ship indexed from day one. Full scope under v0.3.2 in the v0.3.x sub-sequence below.

End of v0.2.x: `main` has formatter + trash + a fully usable Pages editor with NavDropdown navigation history (Pinned + Recents). Directives + wikilinks no longer land inside v0.2.x — directives are unscheduled; wikilinks moved to v0.3.2. GitHub CI was removed at v0.2.7.1 (lint-only locally + via `swift format` subcommand). **"Pommora is writable" milestone is complete** — long-form notes editable, NavDropdown navigation history, right-click context menus for Page + Item CRUD. v0.3.0 begins the data-model side (Properties).

##### v0.3.x — Properties + Items pane + Wikilinks + SQLite (data-layer chapter)

The other half of the data model — until v0.3.0, Pages and Items load + save their property frontmatter but have no UI for editing it. The four-patch sub-sequence at v0.3.x closes the data layer entirely, ending at indexed cross-document linking + queryable storage. **Sub-sequence refined 2026-05-23 brainstorm:**

```
v0.3.0 — Properties data layer + minimum-viable placeholder UI
v0.3.1 — Properties Pulldown + Panel UI (Figma-driven fast-follow)
v0.3.2 — Page-wikilinks
v0.3.3 — SQLite + querying
```

Item Window redesign, Claude chat main-window inspector, and PreviewWindow primitive are separate v0.3.x patches with TBD timing — independent of the 4-patch sequence above.

Conceptual spec → `// Planning//v0.3.0-Properties-spec.md`; implementation plan → `// Planning//v0.3.0-Properties-plan.md`.

###### v0.3.0 — Properties (data layer + placeholder UI)

**Scope split (locked 2026-05-23):** v0.3.0 ships the **data layer + minimum-viable placeholder UI** to verify the data layer works. Real Properties Pulldown + Property Panel ships in a fast-follow patch (alongside v0.3.0 or v0.3.1, Figma-driven). Broader inspector architecture (Claude chat main-window inspector, PreviewWindow primitive, Item Window redesign w/ pinned chips) ships in later v0.3.x patches whenever designed.

- **Data layer (full ship):** PropertyType extensions (`lastEditedTime`, `status`), PropertyValue (`.status`), PropertyDefinition (discriminated `RelationScope`, `dual_property`, `statusGroups`, `icon`, `allowsMultiple`), AgendaTaskSchema + AgendaEventSchema Property struct parity. SchemaTransaction primitive (compound mode for dual relations). Manager schema CRUD on all 4 managers. StatusOptionMutations helper (kind-agnostic). A.7.5 load-path migrations (AgendaTask Status injection + `type` removal, RelationScope decode shim, `.status` decode promotion). PropertyDefinitionValidator + ItemValidator rewire. `default_sort` field on all 4 sidecars. Move-strip primitive + cross-Type move methods.
- **Placeholder UI (disposable):** Extend existing `FrontmatterInspector` (Pages-side) and `ItemWindow`'s `PropertyEditorRow` (Items-side) to handle all 10 property types. Minimum-viable Type Settings sheet (Edit Properties + Sort sections only) on both sides. Native SwiftUI move-strip confirmation dialog. **No design polish** — gets replaced when the real Property Panel SwiftUI component ships in the fast-follow patch.

End of v0.3.0: data layer correct end-to-end; placeholder UI exercises every property type so users can verify Pages + Items + Agenda Tasks + Agenda Events all read/write properties correctly.

###### v0.3.1 — Properties Pulldown + Property Panel (Figma-driven fast-follow)

Real property UI ships right after v0.3.0:
- **Properties Pulldown** for Pages in the main window (NavDropdown-style; populated-only; "+ Add property" picker; lazy properties; auto-managed at bottom in divider-separated section; title excluded). Full spec in `// Features//Pages.md` § "Properties Pulldown — to-be-implemented".
- **Property Panel** SwiftUI component — host-agnostic, slots into any inspector container. Used by the future Page Preview inspector + Item Window inspector. MultiSelectChips color refactor + caller-site sweep. SchemaEditorRouter for cross-surface routing (right-click → "Edit options…" jumps to Type Settings).

###### v0.3.x — Item Window redesign + PreviewWindow primitive (timing TBD)

Reshape the Item Window around the Property Panel + add inspector toggle + pinned chips per Nathan's WIP sketch (`// Features//Items.md` § "Inspector Panel + Pinned Chips"):
- Inspector toggle in popover top-right (default closed); reveals Property Panel as a panel to the right of the body
- Pinned-property chips above title; saved at Item Collection level (`_itemcollection.json.pinned_properties: [String]`)
- Eventually a true `WindowGroup(for: ItemRef.self)` standalone window (depends on cross-feature PreviewWindow primitive)
- Same window doubles as create + edit by passing mode
- AgendaTask + AgendaEvent reuse the Item Window UX pattern (separate code per entity); ship alongside the Item Window redesign

###### v0.3.x — Claude chat as main-window inspector (timing TBD)

Main-window inspector slot becomes the Claude chat (CLI subprocess bridge — frontend to Nathan's local CLI, not API integration). Properties never live in the main-window inspector under the locked direction — they live in the Pulldown / Page Preview inspector / Item Window inspector instead.

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

Smaller version — SQLite + Watcher absorbed into v0.3.3; cross-Type move-strip absorbed into v0.3.0.

- **In-app Trash window** — `.trash//` data layer already shipped at v0.2.5; v0.4.0 adds the SwiftUI surface listing entries with restore + permanent-delete + Empty Trash actions.
- **Cascade-delete reporting refinements** — exact counts in confirmation dialogs (Page Type → N Page Collections + M Pages; Item Type → N Item Collections + K Items).
- **External-edit detection on Item / Agenda Task / Agenda Event save** — extends v0.3.3's Page-save detection to other entity types as needed.

End of v0.4.0: deletes recoverable via UI. The "infrastructure" base layer is complete.

##### v0.5.0 — Type view types (table / board / list / cards / gallery)

The five view types over Page Type / Item Type Content. Inline cell editing in Table view; Board view ships as visual kanban (cards grouped by a property's options; editing a card via the card UI moves it visually). Drag-to-rewrite-frontmatter on kanban is a post-v1.0 follow-up. Per-view filter / sort / group / shown-properties controls (powered by v0.3.3's SQLite + `json_extract` queries). Saved view configurations stored inside each Type's per-kind sidecar (`_pagetype.json.views[]` / `_itemtype.json.views[]`).

End of v0.5.0: Page Types + Item Types stop being just "lists of files in a folder" and become real database views — Pommora's Notion-like value proposition is now visible to the user.

##### v0.6.0 — EventKit + Agenda UI + Hardening + accessibility + performance + onboarding

The "polish + integration" version. Agenda's full UI ships **hand-in-hand with EventKit** (Nathan-locked: they go together — see Paradigm-Decisions.md). Combines previously-scattered concerns:

- **Agenda Task / Agenda Event Windows** — reuse the Item Window UX pattern (popover with inspector toggle + Property Panel + pinned chips), but **separate code per entity** (different EventKit semantics, different built-in fields). Time-field handling: AgendaTask single "When?" input when due / start collapse; AgendaEvent always shows start + end. Per-side schema property panel reading from `AgendaTaskSchema` / `AgendaEventSchema` (same `PropertyEditorRow` dispatch as Items).
- **Agenda creation surfacing** — sidebar context-menu entries; menu-bar Quick Capture for fast event entry.
- **Calendar view over Agenda** — date-anchored grid replacing the placeholder Saved → Calendar entry; can be embedded in Contexts/Homepage post-v0.7.0.
- **EventKit bridge** — Sandbox entitlement (`com.apple.security.personal-information.calendars`) + Info.plist usage description keys + modern `requestFullAccessTo*` APIs. **Opt-in via Settings.** Bidirectional mirroring (`EKEvent` for items with `start_at` + `end_at`; `EKReminder` for items with `due_at` or unscheduled).
- **Settings scene scaffold** (`⌘,`) — Tier-config editor (per-tier singular + plural labels; `tagging_style`; `exposed` toggle); Saved-section labels editor (Homepage / Calendar / Recents renaming); EventKit sync opt-in toggle; **accent color + font size customization** (was previously a standalone v0.12.0 — folded in here since this is the natural home for user-overridable surface).
- **Accessibility checkpoint** — VoiceOver labels + focus order + Dynamic Type respect verified across all v0.2.0-v0.5.0 surfaces.
- **Performance budgets verified** — "open a Page in <X ms," "render N-row sidebar without jank," "Page Type / Item Type Table view with 1000 rows scrolls smoothly." Sets a baseline before v0.7.0 stacks more on top.
- **First-launch UX** — empty-state copy across sidebar sections + detail pane; nexus-picker flow polish; menu-bar `+ New` Quick Capture entry as the discoverable counterpart to right-click-only creation.
- **Saved section content fills in** — Recents (full-frame view backed by NavDropdown's `RecentsManager`, sharing the v0.2.7.1 store); Calendar (with EventKit mirror visible if opt-in).
- ✅ **Pending-error toast surface** — already shipped in v0.2.0 (`2d707a0`). v0.6.0 extends observation to AgendaTaskManager / AgendaEventManager / HomepageManager / TierConfigManager / SettingsManager if user-driven CRUD lands for those.

End of v0.6.0: Pommora is integration-complete with system Calendar/Reminders, accessible, performant, and onboards new users without surprises.

##### v0.7.0 — Composed-blocks editor for Contexts + Homepage

The composed-blocks surface used by Spaces / Topics / Projects / Homepage gets its editor. Block types: paragraph, headings, lists, callout, code, image, columns, **embedded-collection-view** (with **inline editing per the locked principle** — not snapshots; works because Type views shipped at v0.5.0), linked-pages widget, link-list widget. Drag-and-drop reordering; slash-menu insertion.

End of v0.7.0: Contexts stop being "labeled buckets with an icon" and become real composed dashboards. The organization layer becomes substantive.

##### v0.8.0 — Global search + rich blocks

- **Global FTS5 search** over Page bodies, Item descriptions, Agenda titles, and frontmatter / properties (powered by v0.4.0's SQLite + FTS5 tables). `⌘K` command palette.
- **Mini-calendar widget** showing Agenda items inline (in Contexts/Homepage composed surfaces).
- **Additional block types** as needed once the basics are exercised.

##### v1.0.0 — Stabilization

No new features. Polish, performance, bug-fix across everything from v0.0.0 through v0.8.0. Final accent / typography pass. Release-readiness checklist (Sparkle integration if non-MAS, TestFlight if MAS).

##### Post-v1

No specific phase commitments yet. Catalog at `// Features//Prospects.md` — additional view types, synced blocks (full inline Page-body editing), graph view (currently a Prospect), collaborative simultaneous editing (out of scope indefinitely), sync (Supabase), mobile/iPad, plugin system, etc.
