### Pommora — Roadmap

Phased plan in chronological order; no calendar dates. Each version ships green standalone and produces a verifiable outcome. CRUD lands paired with paradigm at every minor version — a new entity type doesn't appear in code until its CRUD interface is functional end-to-end.

#### Vision

A Markdown-canonical, SQLite-indexed personal management platform combining Obsidian's local-first openness with Notion's database and view capabilities. **2-layer PARA-aligned domain model:**

- **Organization layer — Contexts** (Spaces / Topics / Projects, 3 tiers) — composed-blocks surfaces
- **Operational layer:**
  - **Pages side** — Page Types → Page Collections → Pages (`.md`). UI labels default to "Vault" + "Collection"
  - **Items side** — Item Types → Item Collections → Items (`.json`). UI labels default to "Type" + "Set"
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
Single 69-commit branch that scaffolded the full locked paradigm. Every entity is CRUD-able end-to-end via sidebar + sheets + detail pane + Item Window. Spaces / Topics / Vaults sections in the sidebar with Pages disclosed under Vaults/Collections; Items + Agenda live in detail-pane Tables. 177 unit tests at merge.

##### v0.2.1–v0.2.6 — Infrastructure baseline
Parallel-session sidebar UX tweaks, CodeRabbit tightening, GitHub Actions CI (`runs-on: macos-26`), `swift-format` baseline + `.swift-format` config + CI lint step, `.trash//` data foundation (5 new APIs + 10 manager delete-site swaps; deletes recoverable from disk; in-app Trash window slot at v0.4.0).

##### v0.2.7.0 — Pages editor (TextKit 2)
Native NSTextView + Apple `swift-markdown` 0.8.0 + vendored `swift-markdown-engine` (Apache 2.0, `External/MarkdownEngine/`). Writing Tools (15.1+), Look Up, spell-check, IME, dynamic system colors free. Pommora-side `AppleASTSupplementalStyler` adds BlockQuote / Strikethrough / Table / ThematicBreak. `.md` is the architectural firewall — Pages survive any future editor swap.

##### v0.2.7.1 — NavDropdown
Liquid Glass dropdown navigation surface — Pinned + Recents tabs. Single-click select / double-click open in main detail pane. `⌘T` opens dropdown; `⌘[` / `⌘]` walk Recents. State in `<nexus>/.nexus/state.json`. Recents store cap 500; dropdown shows top 100. Replaces the earlier tab-strip navigation model.

##### v0.2.7.2 — Editor patches (partial)
HR + Lists rewritten via the dynamic-syntax architecture (markers shrink when caret leaves the AST node, Bear/Notion pattern). Blockquote + Tables deferred. Locked architecture rules for paragraph-level constructs at `Features/PageEditor.md`.

##### v0.2.7.4 — Editor polish bundle
HR jitter fix (layout-constant; only foreground color toggles). Bullet glyph substitution (`-` → `•`). Task-list shorthand `-[]` / `-[x]`. Bracket auto-pair guard. Arrow auto-format. Code-block colors via system semantics (`NSColor.systemRed.withAlphaComponent(0.85)` text / `NSColor.quaternaryLabelColor` background).

##### v0.2.7.5 — Blockquote
Always-show overlay; renderer-drawn rounded card with continuous vertical pill accent bar (Notion/Obsidian-style). Per-fragment corner-rounding for multi-line visual continuity. Activation `> ` (marker + space); plain Enter continues, Shift+Enter exits. `>` marker hidden in-editor; on disk standard CommonMark.

##### v0.2.8 — Sidebar drag-to-reorder
Phase 1 persistence shipped (`OrderResolver` + `OrderPersister` + per-sidecar order fields). Phase 2 UX shipped on Pages-side + Contexts rows (PageType / Topic / Space / Page / PageCollection / Project). Items-side rows + NavDropdown Pinned reorder + cross-container drag + detail-pane Table reorder remain queued.

##### v0.3.0 — Properties (data layer + SQLite + placeholder UI)
The data-layer chapter. 71 commits across 11 phases A–K, merged to main 2026-05-25.
- **Data layer (full):** 11 property types · `PropertyDefinition` with stable ULID `id` · `SchemaTransaction` atomic multi-file commit · `PropertyIDMigration` runs every nexus open (preview before commit) · schema CRUD on all 4 schema-bearing managers · `PropertyDefinitionValidator` (8 rules) · `SchemaConflictDialog` drift defense · paired-relation lifecycle (`DualRelationCoordinator`) · `_status` built-in on AgendaTask + AgendaEvent · move-strip primitive (name-matched, since IDs are globally unique) · file attachments (copy-on-attach, 50/500 MB caps, cascade-delete) · Settings auto-migration scaffold (`defaultsVersion` + `Settings.migrate`).
- **SQLite index (live end-to-end):** GRDB.swift · per-nexus `<nexus>/.nexus/index.db` · 12-table schema · `IndexBuilder` two-phase populate · `IndexUpdater` wired into all 6 managers · `IndexQuery` Notion-style filter/sort/broken-links. Mid-session mutations propagate.
- **Placeholder UI (every interaction has a working path):** PropertyEditorRow dispatcher · StatusPicker · RelationPicker · FileAttachmentEditor · RelationPropertyWizard · PropertyTypePicker · VaultSettingsSheet + TypeSettingsSheet · MoveStripConfirmationDialog · PropertyPanel (eager) · PropertiesPulldown (lazy, mounted in PageEditorView) · FrontmatterInspector live editors · Item Window inspector toggle + pinned chips · column-header click-to-sort · CalendarDetailView + Calendar pin right-click create · UI labels threaded from `SettingsManager`.

Full ship summary → [[History]] § "v0.3.0 Properties — FEATURE-COMPLETE".

---

#### Upcoming versions (roadmap)

##### v0.3.1.x — Storage View Redesign (chrome shipped; properties-end-to-end approved)

- **v0.3.0.5 chrome slice** (shipped 2026-05-25 PM, merged to main as `48316be`) — static `slider.horizontal.3` toolbar button at ContentView level inside the existing primary-action Liquid Glass capsule (with NavDropdown + Inspector toggle). Empty 300×360pt popover scope-routed via `ViewSettingsScope` derived from `sidebarSelection`. Plan record at `.claude/Planning/View-Settings-button-chrome-plan.md`.
- **v0.3.1 Properties end-to-end** (APPROVED 2026-05-26, ready to execute) — 25 tasks across 9 phases at `.claude/Planning/View-Settings-edit-properties-plan.md`. Ships schema CRUD via popover (Edit Properties pane Notion-format with chevron-push option editing + Duplicate/Delete footer) + dynamic property-value columns in all 4 storage detail-view Tables + click-to-edit popovers for all 11 property types + Property Visibility pane (active) + Layout pane (Table active; Board/List/Cards/Gallery muted until v0.5.0). Includes data layer additions (`DisplayVariant` / `dateFormat` / `singular` / `SavedView` real fields / `views[]` on Collections / default-view migration / PropertyChipColor cleanup) and three new chip primitives (`RelationChip` / `FileChip` / `LinkChip`).
- **v0.3.1.2** — Sort pane (per-view; single criterion at v0.3.1.x; multi when saved views land)
- **v0.3.1.3** — Filter pane (equals / not-equals / contains / empty / not-empty; AND-grouped; wired to `IndexQuery`)
- **v0.3.1.4** — Group pane (optional; defer to v0.5.0 if Board view is closer)
- **v0.3.1.5** — existing-property change-type + per-type-config update gaps (`updateProperty(id:in:transform:)` manager method); relation cell edit if not landed in v0.3.1

Property Pulldown + Property Panel Figma polish moves to v0.3.x fast-follow after the storage redesign — properties-per-Page surface evolves independently of the storage configurator chrome.

##### v0.3.x — Item Window redesign + PreviewWindow primitive (timing TBD)
Reshape the Item Window around the Property Panel + inspector toggle + pinned chips per Nathan's WIP sketch. Eventually a `WindowGroup(for: ItemRef.self)` standalone window once the cross-feature PreviewWindow primitive ships. AgendaTask + AgendaEvent reuse the same UX pattern.

##### v0.3.x — Claude chat main-window inspector (timing TBD)
Main-window inspector slot becomes the Claude chat (CLI subprocess bridge — frontend to Nathan's local CLI, not API integration). Properties never live in the main-window inspector under the locked direction — they live in the Pulldown / Page Preview inspector / Item Window inspector instead.

##### v0.3.2 — Page-wikilinks
Body-text wikilinks (`[[Title]]`) with autocomplete + click routing + rename cascade. Derived `wikilinks: [<id>, ...]` frontmatter mirror auto-maintained on save. Click routing — Page → detail pane; Context → detail pane; Item → ItemWindow popover. Indexed via the v0.3.0 SQLite layer from day one.

##### v0.3.3 — File watcher + FTS5 + external-edit detection
FSEventStream — external changes update SQLite + sidebar live; reconciles per-file on touch. Lost-update protection on Page / Item / AgendaTask / AgendaEvent save when external mtime drifts. FTS5 tables wired (schema only; ⌘K palette ships v0.8.0). Broken-link warning surface for wikilinks + per-Type Page-wikilink count UI.

##### v0.4.0 — Trash UI + cascade-delete refinements
In-app Trash window (SwiftUI surface over the v0.2.5 `.trash//` data layer) with restore + permanent-delete + Empty Trash actions. Cascade-delete reporting refinements with exact counts (Page Type → N Page Collections + M Pages). External-edit detection extended to all entity kinds.

##### v0.5.0 — Non-Table view renderers (board / list / cards / gallery)
v0.5.0 ships the four remaining renderer types over the single per-container `SavedView` storage already in place. Board = visual kanban (cards grouped by a property's options; editing via card UI); List / Cards / Gallery render the same underlying entities differently.

##### v0.6.0 — Saved views + EventKit + Agenda UI + hardening + accessibility + perf + onboarding
Multi-saved-view support (tabs row beneath the detail-view title) plus the per-view-config family that becomes per-view once multiple views exist — per-view sort, Group By, and detail-pane column selection. Agenda Task / Agenda Event Windows (popover with inspector toggle + Property Panel + pinned chips). Calendar view over Agenda. EventKit bridge (sandbox entitlement + Info.plist + modern `requestFullAccessTo*` APIs; opt-in via Settings; bidirectional mirroring). Full Settings editing UI (accent color picker, label rename forms, tier-config consolidation). Accessibility checkpoint. Performance budgets verified. First-launch UX polish. Saved-section content fills in (Recents full-frame, Calendar with EventKit mirror).

##### v0.7.0 — Composed-blocks editor for Contexts + Homepage
The composed-blocks surface used by Spaces / Topics / Projects / Homepage gets its editor. Block types: paragraph, headings, lists, callout, code, image, columns, **embedded-collection-view** (with inline editing per the locked principle — not snapshots; works because view types shipped at v0.5.0), linked-pages widget, link-list widget. Drag-and-drop reorder; slash-menu insertion.

##### v0.8.0 — Global search + rich blocks
Global FTS5 search over Page bodies, Item descriptions, Agenda titles, and frontmatter / properties (powered by v0.3.3's SQLite + FTS5 tables). `⌘K` command palette. Mini-calendar widget inline in Contexts/Homepage composed surfaces. Additional block types as needed.

##### v1.0.0 — Stabilization
No new features. Polish, performance, bug-fix across everything from v0.0.0 through v0.8.0. Final accent / typography pass. Release-readiness checklist (Sparkle integration if non-MAS, TestFlight if MAS).

#### Post-v1
No specific phase commitments. Catalog at [[Prospects]] — additional view types, synced blocks (full inline Page-body editing), graph view, collaborative simultaneous editing (out of scope indefinitely), sync (Supabase), mobile/iPad, plugin system, etc.
