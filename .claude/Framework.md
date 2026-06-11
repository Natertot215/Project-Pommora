### Pommora — Roadmap

Phased plan in chronological order; no calendar dates. Each version ships green standalone and produces a verifiable outcome. CRUD lands paired with paradigm at every minor version — a new entity type doesn't appear in code until its CRUD interface is functional end-to-end.

#### Vision

A Markdown-canonical, SQLite-indexed personal management platform combining Obsidian's local-first openness with Notion's database and view capabilities. **2-layer PARA-aligned domain model:**

- **Organization layer — Contexts** (Areas / Topics / Projects, 3 tiers) — composed-blocks surfaces
- **Operational layer:**
  - **Pages** — Page Types → Page Collections → Pages (`.md`). UI labels default to "Vault" + "Collection"
  - **Agenda** — Agenda Tasks (`.task.json`, EKReminder-aligned) + Agenda Events (`.event.json`, EKEvent-aligned)
- **Singleton — Homepage** (`.nexus/homepage.json`)
- **Settings scaffold** (`.nexus/settings.json`) — per-Nexus user-overridable UI labels + accent color

Mac-first for v1, always open-source. Domain spec → [[Domain-Model]].

#### Versioning

`major.minor.patch` semver. **Minor (`v0.X.0`)** = a completed feature cluster. **Patch (`v0.X.y`)** = touch-up or additive extension on top of a shipped feature. **Major (`vX.0.0`)** reserved for `v1.0.0` (stabilization) and onward.

---

#### Shipped versions (earliest → latest)

##### v0.0.0 — Shell opens
Toolchain proof. macOS 26+ (Tahoe). Three-pane shell — sidebar (240) / main (flex) / pop-out inspector (280, default closed) — on SwiftUI's two-column `NavigationSplitView(sidebar:detail:)` with `.inspector(isPresented:)`. Both side panes drag-resizable; widths persist. Default 1200×800; min 960×560.

##### v0.1.0 — Nexus Foundation
Sandboxed picker, security-scoped bookmark persistence, `.nexus/` init flow, per-nexus App Support subdir keyed by ULID. Sidebar mirrors picked folder showing `.md` + `.json`. File menu → Open Nexus; Debug menu → Reset Bookmark. 25 unit tests pass.

##### v0.2.0 — Paradigm scaffolding + sidebar UX
Single 69-commit branch that scaffolded the full locked paradigm. Every entity is CRUD-able end-to-end via sidebar + sheets + detail pane. Areas / Topics / Vaults sections in the sidebar with Pages disclosed under Vaults/Collections; Agenda lives in detail-pane Tables. 177 unit tests at merge.

##### v0.2.1–v0.2.6 — Infrastructure baseline
Parallel-session sidebar UX tweaks, CodeRabbit tightening, GitHub Actions CI (`runs-on: macos-26`), `swift-format` baseline + `.swift-format` config + CI lint step, `.trash//` data foundation (5 new APIs + 10 manager delete-site swaps; deletes recoverable from disk; in-app Trash window slot at v0.4.0).

##### v0.2.7.0 — Pages editor (TextKit 2)
Native NSTextView + Apple `swift-markdown` 0.8.0 + the Pommora-owned `MarkdownPM` package (Apache 2.0, `External/MarkdownPM/`; originally vendored from `swift-markdown-engine`, now owned + maintained in-tree, rebuilt 2026-06-03). Writing Tools (15.1+), Look Up, spell-check, IME, dynamic system colors free. One owned `MarkdownPMStyler` walks the cached AST once; its `AppleASTSupplementalStyler` helper covers BlockQuote / Strikethrough / Table (HR is sole-written by the HR-visibility service, not the styler). `.md` is the architectural firewall — Pages survive any future editor swap.

##### v0.2.7.1 — NavDropdown
Liquid Glass dropdown navigation surface — Pinned + Recents tabs. Single-click select / double-click open in main detail pane. `⌘T` opens dropdown; `⌘[` / `⌘]` walk Recents. State in `<nexus>/.nexus/state.json`. Recents store cap 500; dropdown shows top 100. Replaces the earlier tab-strip navigation model.

##### v0.2.7.2 — Editor patches (partial)
HR + Lists rewritten via the dynamic-syntax architecture (markers shrink when caret leaves the AST node, Bear/Notion pattern). Blockquote + Tables deferred. Locked architecture rules for paragraph-level constructs at `Features/PageEditor.md`.

##### v0.2.7.4 — Editor polish bundle
HR jitter fix (layout-constant; only foreground color toggles). Bullet glyph substitution (`-` → `•`). Task-list shorthand `-[]` / `-[x]`. Bracket auto-pair guard. Arrow auto-format. Code-block colors via system semantics (`NSColor.systemRed.withAlphaComponent(0.85)` text / `NSColor.quaternaryLabelColor` background).

##### v0.2.7.5 — Blockquote
Always-show overlay; renderer-drawn rounded card with continuous vertical pill accent bar (Notion/Obsidian-style). Per-fragment corner-rounding for multi-line visual continuity. Activation `> ` (marker + space); plain Enter continues, Shift+Enter exits. `>` marker hidden in-editor; on disk standard CommonMark.

##### v0.2.8 — Sidebar drag-to-reorder
Phase 1 persistence shipped (`OrderResolver` + `OrderPersister` + per-sidecar order fields). Phase 2 UX shipped on Pages-side + Contexts rows (PageType / Topic / Area / Page / PageCollection / Project). NavDropdown Pinned reorder + cross-container drag + detail-pane Table reorder remain queued.

##### v0.3.0 — Properties (data layer + SQLite + placeholder UI)
The data-layer chapter. 71 commits across 11 phases A–K, merged to main 2026-05-25.
- **Data layer (full):** 10 property types · `PropertyDefinition` with stable ULID `id` · `SchemaTransaction` atomic multi-file commit · `PropertyIDMigration` runs every nexus open (preview before commit) · schema CRUD on all 4 schema-bearing managers · `PropertyDefinitionValidator` (8 rules) · `SchemaConflictDialog` drift defense · paired-relation lifecycle (`DualRelationCoordinator`) · `_status` built-in on AgendaTask + AgendaEvent · move-strip primitive (name-matched, since IDs are globally unique) · file attachments (copy-on-attach, 50/500 MB caps, cascade-delete) · Settings auto-migration scaffold (`defaultsVersion` + `Settings.migrate`).
- **SQLite index (live end-to-end):** GRDB.swift · per-nexus `<nexus>/.nexus/index.db` · 12-table schema · `IndexBuilder` two-phase populate · `IndexUpdater` wired into all 6 managers · `IndexQuery` Notion-style filter/sort/broken-links. Mid-session mutations propagate.
- **Placeholder UI (every interaction has a working path):** PropertyEditorRow dispatcher · StatusPicker · ContextPicker · FileAttachmentEditor · RelationPropertyWizard · PropertyTypePicker · VaultSettingsSheet · MoveStripConfirmationDialog · PropertyPanel (eager) · PropertiesPulldown (lazy, mounted in PageEditorView) · FrontmatterInspector live editors · column-header click-to-sort · CalendarDetailView + Calendar pin right-click create · UI labels threaded from `SettingsManager`.

Full ship summary → [[History]] § "v0.3.0 Properties — FEATURE-COMPLETE".

##### v0.3.1 — Properties end-to-end (View Settings editor)
21 commits (`627e972`→`0d5aa16`, 2026-05-26). The `slider.horizontal.3` View Settings popover goes live. Schema CRUD through the Edit Properties pane (Notion-format, per-type editors, Duplicate/Delete footer); dynamic property-value columns in the storage detail-view Tables; click-to-edit cell popovers for every property type; Property Visibility pane. Data-layer additions: `DisplayVariant` + `DateFormat` enums · real `SavedView` fields + `views[]` on Collections + default-view migration · flat 12-case `PropertyChipColor`. Three chip primitives — `ContextChip` / `FileChip` / `LinkChip`. Full record → [[History]].

##### v0.3.2 — View Settings editor rebuild + nav/detail fixes
Tagged 2026-05-27. The per-property editor rebuilt to the Figma — PaneDivider rail standard, pinned destructive footers, Subheadline / Callout type ramp, plain-`Menu` inline selectors; the popover-family UIX lessons folded into `Guidelines/Design.md` (standalone `UIX-Baseline.md` retired). A Pages-side third tier (Folders) was built and **reverted the same cycle** — it duplicated Collections' role and collided with the planned view-organization system; kept its system-wide stub-and-inline-rename CRUD (`CreateWithInlineEdit` + `DefaultTitleResolver`), the sidebar menu tweaks, and `NexusAdopter.autoTagMissingSidecars`. Nav/detail bug fixes landed alongside.


##### v0.3.4 — Relations made real + manager de-dup + Pages stats footer
Tagged 2026-05-31; the big consolidation release (**v0.3.3 was skipped** — the relations work folded forward into this tag). Marketing version bumped `0.2.6` → `0.3.4` at release.
- **Relations unified (since superseded — see Contextv2 below).** `tier1/2/3` and relation properties shared a single pipeline; the `tier_links` table retired (one reverse-lookup path). Relations are always-multi (`[{"$rel": "<ULID>"}]`); a single-pane editor set home side + reverse name + reverse icon. Context-delete cascades the tier reference out of every operational entity. Entity `icon` denormalized into the SQLite index. Index resilience hardened (per-row insert, version-stamp-after-populate) + `MemberFileStrip.forEach` tolerates frontmatter-less member files.
- **Native IconPicker.** Pommora's own SF Symbols 6 picker (`IconCatalog`, 6,195 names + `IconFavorites`) replaces the third-party `SymbolPicker`; one `.iconPickerPopover` modifier at every icon-edit entry.
- **Manager de-dup.** The 5 schema-mutation methods duplicated across the schema-bearing managers collapsed behind two shared `@MainActor` services — `PerTypeSchemaService` + `SingletonSchemaService` (Agenda). ~590 lines of copy-paste removed, fully behavior-preserving.
- **Vault-table display-only + creation-order.** *Type* detail tables are display-only for row order (mirror the sidebar live); Collection tables keep flat reorder; empty-state default order changed alphabetical → **creation order** (ULID-id ascending). The full per-view ordering system ships v0.5.0.
- **Pages stats footer + editor polish.** Footer with live line / word / character counts (toggle) + plain-text Finder-style breadcrumb (the clickable `NSPathControl` variant was tried and reverted). Code-block syntax-hide now ignores inline code spans and fires inside headings; bullet gap / indent tuning; `-[]` / `-[x]` checkbox shorthand continues + toggles on Enter.

##### v0.3.5 — Connections (page-level) + Contextv2 + MarkdownPM perf
Tagged 2026-06-07. 231 commits since v0.3.4.

- **Connections page-level.** `[[Page Title]]` syntax, inline render (styled colored text), Liquid Glass autocomplete popup, click navigation, atomic rename cascade, nexus-wide title uniqueness, `connectionsChanged` live-refresh bus, `connections` SQLite table (schema v8+). Spec → `Features/Connections.md`.
- **Contextv2.** User-creatable relation properties retired; `tier1`/`tier2`/`tier3` are now the sole relation connection. `DualRelationCoordinator` deleted (~1.4k LOC). All `Relation*` symbols renamed `Context*`; `relations` → `context_links` table. Substrate (`$rel`, `PropertyValue.relation`, `RelationTarget.contextTier`, `PropertyType.relation`) kept.
- **MarkdownPM performance.** `constructLineStarts` precomputed; heading/HR/blockquote/bullet reads from token/construct caches; `blockCodeTokens` DRY. Scroll lag eliminated.
- **Index hardening.** Parent upserts use `ON CONFLICT DO UPDATE`; launch scan lenient + `excluded_folders` at file level; schema 9 → 10.
- **Page icon.** In-editor page-header icon + "Add Icon" hover affordance; `showPageIcon` toggle (default OFF).

Full ship detail → [[History]] § "Connections — page-level complete".

##### v0.4.0 — Pages unification + PagePreview window (2026-06-09/10)
The second operational side deleted, not migrated — Page is the only operational entity beside Agenda. `[[` is the sole connection syntax; per-vault `open_in` (`compact` | `window`) routes page-taps to **PagePreview** — a real `WindowGroup` window restricted to never act as its own app window (no traffic lights / Dock / Window-menu presence; child-attached above the main window; mounts the shared `FrontmatterInspector` at a compact scale) — or the main detail pane; user-creatable sidebar sections group Vaults (navigation-only); index schema v10 → v11 (legacy tables dropped, delete-and-rebuild). Launch/state hardening: XCTest app-state isolation, launch-panel abort retry. Full record + retrospective pointers → [[History]] § "v0.4.0" + § "PagesV2".

---

#### Upcoming versions (roadmap)

> **Version buckets + priority follow Nathan's own [[Pommora Tasks]] doc** (the working intent ledger); Framework keeps the implementation detail under each. Entries Framework tracks that the Tasks doc doesn't name are *folded into their nearest bucket* and marked **(infra)** / **(folded)**. The Sort / Filter / Group panes muted in v0.3.1 + multi-saved-view tabs land with the view system at **v0.5.0**.

##### v0.5.0 — Views + Symbols + Trash
- **Vault + Collection views.** The four non-Table renderers (Board / List / Cards / Gallery) over the per-container `SavedView` storage already in place; multi-saved-view tabs beneath the detail title; full per-view config — **order, sort, Group By, column selection** — plus **tier-link sort + filter** (context-link-aware operators like `linked to` / `not linked to`). Board = kanban (cards grouped by a property's options; editing via card UI). Also ships the deferred per-view **reorder engine** — until now, Type detail tables are display-only and mirror the sidebar (SwiftUI's macOS `Table` can't combine collapsible grouping with reliable nested reorder).
- **Standardized Symbols.** In-app Symbol Settings surface over the `Guidelines/Symbols.md` registry — user-remappable Application ↔ SF Symbol assignments, replacing hardcoded glyphs with a configurable table.
- **Archive / Trash.** In-app Trash window (SwiftUI surface over the v0.2.5 `.trash//` data layer) with restore + permanent-delete + Empty Trash; cascade-delete reporting with exact counts (Page Type → N Collections + M Pages). External-edit detection extended to all entity kinds.
- **(infra)** FSEventStream **file watcher** — external changes update SQLite + sidebar live, per-file reconcile on touch, lost-update protection on mtime drift; **FTS5 tables wired** (schema only — the `⌘K` search UI ships v0.7.0); broken-link warning surface for connections.

##### v0.6.0 — EventKit + Agenda UIX + Calendar
EventKit bridge (sandbox entitlement + Info.plist + modern `requestFullAccessTo*` APIs; opt-in via Settings; bidirectional mirroring). Agenda Task / Agenda Event compact panels (title + properties + description; hosting surface decided here). Calendar view over Agenda; the Saved-section Calendar fills in with the EventKit mirror.

##### v0.7.0 — Settings + Quick Capture + LLM Interface + global search
- **Settings Panel.** Full Settings editing UI — accent color picker (swatch grid + custom well, live preview), label rename forms (Vault / Collection / Task / Event + section + tier labels), and tier-config consolidation (folds `.nexus/tier-config.json` into the same surface). Replaces hand-editing `.nexus/settings.json`.
- **Quick Capture.** Global `⌘⇧N` / menu-bar popover creating Pages / Agenda Tasks / Agenda Events from anywhere in the OS; defaults to a configured inbox Vault; optional Tier / Vault override fields; Enter submits, Esc dismisses.
- **LLM Interface.** The main-window inspector slot becomes the Claude chat (CLI subprocess bridge — frontend to Nathan's local CLI, not API integration). Properties never live in the main-window inspector under the locked direction.
- **(folded) Global search.** `⌘K` command palette + FTS5 search over Page bodies, Agenda titles, and frontmatter / properties (over the FTS5 tables wired at v0.5.0). Natural pairing with Quick Capture — both are global invocation surfaces.
- **(folded) Recents full-frame view.** The Saved-section `Recents` pin opens a full-frame view of the Recents store (up to 500, with sort + filter) — the same data the NavDropdown shows as its top 100.

##### v0.8.0 — Contexts + Homepage editor
- **Contexts + Homepage block editor.** The composed-blocks surface (Areas / Topics / Projects / Homepage) gets its editor — paragraph, headings, lists, callout, code, image, columns, **embedded-collection-view** (inline-editable per the locked principle, not snapshots — renderers shipped v0.5.0), linked-pages widget, link-list widget, mini-calendar widget; drag-and-drop reorder + slash-menu insertion.
- **Context Linked-from surface.** The real `LinkedFromDropdown` (stub today at `Detail/LinkedFromDropdown.swift`): a dropdown listing every operational entity whose `tier1/2/3` points at the Context, via `IndexQuery.incomingContextLinks(targetID:)` (shipped). Supporting bits: `EntityStateRef.iconName`, `EntityKind.displayLabel`, an `EntityStateRef → SidebarSelection` navigation resolver, and a host slot.

##### v1.0.0 — Stabilization
No new features. Polish, performance, bug-fix across everything from v0.0.0 through v0.8.0. Final accent / typography pass. Release-readiness checklist (Sparkle integration if non-MAS, TestFlight if MAS).

#### Post-v1
No specific phase commitments. Catalog at [[Prospects]] — additional view types, synced blocks (full inline Page-body editing), graph view, collaborative simultaneous editing (out of scope indefinitely), sync (Supabase), mobile/iPad, plugin system, plus the Pages-editor wishlist from [[Pommora Tasks]] (H1→H6 styling, page-nav dropdown, connection aliases, page notes/description, page banners).
