### Pommora — Roadmap

Phased plan in chronological order; no calendar dates. Each version ships green standalone and produces a verifiable outcome. CRUD lands paired with paradigm at every minor version — a new entity type doesn't appear in code until its CRUD interface is functional end-to-end.

#### Vision

A Markdown-canonical, SQLite-indexed personal management platform combining Obsidian's local-first openness with Notion's database and view capabilities. **2-layer PARA-aligned domain model:**

- **Organization layer — Contexts** (Spaces / Topics / Projects, 3 tiers) — composed-blocks surfaces
- **Operational layer:**
  - **Pages side** — Page Types → Page Collections → Pages (`.md`). UI labels default to "Vault" + "Collection"
  - **Items side** — Item Types → Item Collections → Items (`.md`). UI labels default to "Type" + "Set"
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
Phase 1 persistence shipped (`OrderResolver` + `OrderPersister` + per-sidecar order fields). Phase 2 UX shipped on Pages-side + Contexts rows (PageType / Topic / Space / Page / PageCollection / Project). Items-side rows + NavDropdown Pinned reorder + cross-container drag + detail-pane Table reorder remain queued.

##### v0.3.0 — Properties (data layer + SQLite + placeholder UI)
The data-layer chapter. 71 commits across 11 phases A–K, merged to main 2026-05-25.
- **Data layer (full):** 10 property types · `PropertyDefinition` with stable ULID `id` · `SchemaTransaction` atomic multi-file commit · `PropertyIDMigration` runs every nexus open (preview before commit) · schema CRUD on all 4 schema-bearing managers · `PropertyDefinitionValidator` (8 rules) · `SchemaConflictDialog` drift defense · paired-relation lifecycle (`DualRelationCoordinator`) · `_status` built-in on AgendaTask + AgendaEvent · move-strip primitive (name-matched, since IDs are globally unique) · file attachments (copy-on-attach, 50/500 MB caps, cascade-delete) · Settings auto-migration scaffold (`defaultsVersion` + `Settings.migrate`).
- **SQLite index (live end-to-end):** GRDB.swift · per-nexus `<nexus>/.nexus/index.db` · 12-table schema · `IndexBuilder` two-phase populate · `IndexUpdater` wired into all 6 managers · `IndexQuery` Notion-style filter/sort/broken-links. Mid-session mutations propagate.
- **Placeholder UI (every interaction has a working path):** PropertyEditorRow dispatcher · StatusPicker · ContextPicker · FileAttachmentEditor · RelationPropertyWizard · PropertyTypePicker · VaultSettingsSheet + TypeSettingsSheet · MoveStripConfirmationDialog · PropertyPanel (eager) · PropertiesPulldown (lazy, mounted in PageEditorView) · FrontmatterInspector live editors · Item Window inspector toggle + pinned chips · column-header click-to-sort · CalendarDetailView + Calendar pin right-click create · UI labels threaded from `SettingsManager`.

Full ship summary → [[History]] § "v0.3.0 Properties — FEATURE-COMPLETE".

##### v0.3.1 — Properties end-to-end (View Settings editor)
21 commits (`627e972`→`0d5aa16`, 2026-05-26). The `slider.horizontal.3` View Settings popover goes live. Schema CRUD through the Edit Properties pane (Notion-format, per-type editors, Duplicate/Delete footer); dynamic property-value columns in all 4 storage detail-view Tables; click-to-edit cell popovers for every property type; Property Visibility pane. Data-layer additions: `DisplayVariant` + `DateFormat` enums · `ItemType.singular` · real `SavedView` fields + `views[]` on Collections + default-view migration · flat 12-case `PropertyChipColor`. Three chip primitives — `ContextChip` / `FileChip` / `LinkChip`. In-window Item property editing deferred (its surface is slated for a rebuild). Full record → [[History]].

##### v0.3.2 — View Settings editor rebuild + nav/detail fixes
Tagged 2026-05-27. The per-property editor rebuilt to the Figma — PaneDivider rail standard, pinned destructive footers, Subheadline / Callout type ramp, plain-`Menu` inline selectors; the popover-family UIX lessons folded into `Guidelines/Design.md` (standalone `UIX-Baseline.md` retired). A Pages-side third tier (Folders) was built and **reverted the same cycle** — it duplicated Collections' role and collided with the planned view-organization system; kept its system-wide stub-and-inline-rename CRUD (`CreateWithInlineEdit` + `DefaultTitleResolver`), the sidebar menu tweaks, and `NexusAdopter.autoTagMissingSidecars`. Nav/detail bug fixes landed alongside.

##### v0.3.4 — Relations made real + manager de-dup + Pages stats footer
Tagged 2026-05-31; the big consolidation release (**v0.3.3 was skipped** — the relations work folded forward into this tag). Marketing version bumped `0.2.6` → `0.3.4` at release.
- **Relations unified (since superseded — see Contextv2 below).** `tier1/2/3` and relation properties shared a single pipeline; the `tier_links` table retired (one reverse-lookup path). Relations are always-multi (`[{"$rel": "<ULID>"}]`); a single-pane editor set home side + reverse name + reverse icon. Context-delete cascades the tier reference out of every Page / Item / Agenda entry. Entity `icon` denormalized into the SQLite index. Index resilience hardened (per-row insert, version-stamp-after-populate) + `MemberFileStrip.forEach` tolerates frontmatter-less member files.
- **Native IconPicker.** Pommora's own SF Symbols 6 picker (`IconCatalog`, 6,195 names + `IconFavorites`) replaces the third-party `SymbolPicker`; one `.iconPickerPopover` modifier at every icon-edit entry.
- **Manager de-dup.** The 5 schema-mutation methods across all 4 managers collapsed behind two shared `@MainActor` services — `PerTypeSchemaService` (Page/Item) + `SingletonSchemaService` (Agenda); `ItemTypeManager.typesByID` removed so the two type managers are symmetric. ~590 lines of copy-paste removed, fully behavior-preserving.
- **Vault-table display-only + creation-order.** Page/Item *Type* detail tables are display-only for row order (mirror the sidebar live); Collection/Set tables keep flat reorder; empty-state default order changed alphabetical → **creation order** (ULID-id ascending). The full per-view ordering system is deferred to the v0.7.0 view work.
- **Pages stats footer + editor polish.** Footer with live line / word / character counts (toggle) + plain-text Finder-style breadcrumb (the clickable `NSPathControl` variant was tried and reverted). Code-block syntax-hide now ignores inline code spans and fires inside headings; bullet gap / indent tuning; `-[]` / `-[x]` checkbox shorthand continues + toggles on Enter.

---

#### Upcoming versions (roadmap)

> **Version buckets + priority follow Nathan's own [[Pommora Tasks]] doc** (the working intent ledger); Framework keeps the implementation detail under each. Items Framework tracks that the Tasks doc doesn't name are *folded into their nearest bucket* and marked **(infra)** / **(folded)**. The Sort / Filter / Group panes muted in v0.3.1 + multi-saved-view tabs land with the view system at **v0.7.0**.

##### v0.3.x — Contextv2: Drop Relations → Contexts (SHIPPED 2026-06-04)
User-creatable relation properties removed; context tiers (`tier1`/`tier2`/`tier3`) are now the only relation-type connection. SQLite table `relations`→`context_links` (`idx_relations_*`→`idx_context_links_*`); all `Relation*` symbols renamed `Context*` (`RelationChip`→`ContextChip`, `RelationValueEditor`→`ContextValueEditor`, `RelationPicker`→`ContextPicker`, `RelationDisplayResolver`→`ContextDisplayResolver`, `BuiltInRelationProperties`→`BuiltInContextLinkProperties`, `incomingRelations`→`incomingContextLinks`). `Project.linked_relations`→`project_links` (dual-key tolerant decode). Orphaned `$rel` member values cleared during the migration walk; legacy Collection→Type migration deleted as dead-after-filter. Substrate kept: `$rel` token, `PropertyValue.relation`, `RelationTarget.contextTier`, `TierRelationCarrying`, `PropertyType.relation` (tier-only). **v0.4.0:** a separate connection-model layer (per-shape tables, weight-at-query, contexts-as-cores) is planned but not yet built. Plan → `Planning/Contextv2.md`; registry decision #16 in `Paradigm-Decisions.md`.

##### v0.3.x — Items as Markdown (serialization unification) (near-term, timing TBD)
The accidental Items-vs-Pages serialization fork collapses: Items become plain `.md` (YAML frontmatter + capped Markdown body) on the same `AtomicYAMLMarkdown` pipeline Pages use — the capped description *is* the body (Shape A, one source of truth). Folder sidecar is the kind authority; a non-authoritative `Class` frontmatter stamp marks the form and self-heals (disagreement / homeless file → hidden `.unsorted` inbox). Foreign frontmatter is preserved by value on every Item AND Page write path. A mandatory one-shot launch migration normalizes legacy `.json` Items → `.md`. **This is where save-time `ItemValidator` validation is introduced for the first time** (the "Phase-6 rider" — body-length cap at 1000 source chars, provisional, validated not clamped, across all 6 Item CRUD entry points). Agenda stays JSON (`.task.json` / `.event.json`); sidecars / Projects / Spaces / Settings stay JSON — only Item *content* files changed. SHIPPED 2026-06-02. Plan → `Planning/Superseded/2026-06-01-Items-as-Markdown-Plan.md`.

##### v0.3.x — Item Window redesign + PreviewWindow primitive (near-term, timing TBD)
Polish on the already-shipped Item Window: reshape it around the Property Panel + inspector toggle + pinned chips per Nathan's WIP sketch. Eventually a `WindowGroup(for: ItemRef.self)` standalone window once the cross-feature PreviewWindow primitive ships. AgendaTask + AgendaEvent reuse the same UX pattern. (Per-Page Property Pulldown + Property Panel Figma polish is the parallel fast-follow on the Pages surface.)

##### v0.4.0 — Symbols + Trash + Wikilinks
- **Standardized Symbols.** In-app Symbol Settings surface over the `Guidelines/Symbols.md` registry — user-remappable Application ↔ SF Symbol assignments, replacing hardcoded glyphs with a configurable table.
- **Archive / Trash.** In-app Trash window (SwiftUI surface over the v0.2.5 `.trash//` data layer) with restore + permanent-delete + Empty Trash; cascade-delete reporting with exact counts (Page Type → N Collections + M Pages). External-edit detection extended to all entity kinds.
- **Wikilinks.** Body-text `[[Title]]` with autocomplete + click routing + rename cascade. Derived `wikilinks: [<id>, ...]` frontmatter mirror auto-maintained on save. Routing — Page / Context → detail pane; Item → ItemWindow popover. Indexed via the v0.3.0 SQLite layer.
- **(infra)** FSEventStream **file watcher** — external changes update SQLite + sidebar live, per-file reconcile on touch, lost-update protection on mtime drift; **FTS5 tables wired** (schema only — the `⌘K` search UI ships v0.6.0); broken-link warning surface for wikilinks.

##### v0.5.0 — EventKit + Agenda UIX + Calendar
EventKit bridge (sandbox entitlement + Info.plist + modern `requestFullAccessTo*` APIs; opt-in via Settings; bidirectional mirroring). Agenda Task / Agenda Event Windows (popover with inspector toggle + Property Panel + pinned chips — reusing the Item Window pattern). Calendar view over Agenda; the Saved-section Calendar fills in with the EventKit mirror.

##### v0.6.0 — Settings + Quick Capture + LLM Interface + global search
- **Settings Panel.** Full Settings editing UI — accent color picker (swatch grid + custom well, live preview), label rename forms (Vault / Collection / Type / Set / Task / Event + section + tier labels), and tier-config consolidation (folds `.nexus/tier-config.json` into the same surface). Replaces hand-editing `.nexus/settings.json`.
- **Quick Capture.** Global `⌘⇧N` / menu-bar popover creating Items / Pages / Agenda Tasks / Agenda Events from anywhere in the OS; defaults to a configured inbox Type per kind; optional Tier / Type override fields; Enter submits, Esc dismisses.
- **LLM Interface.** The main-window inspector slot becomes the Claude chat (CLI subprocess bridge — frontend to Nathan's local CLI, not API integration). Properties never live in the main-window inspector under the locked direction.
- **(folded) Global search.** `⌘K` command palette + FTS5 search over Page bodies, Item descriptions, Agenda titles, and frontmatter / properties (over the FTS5 tables wired at v0.4.0). Natural pairing with Quick Capture — both are global invocation surfaces.
- **(folded) Recents full-frame view.** The Saved-section `Recents` pin opens a full-frame view of the Recents store (up to 500, with sort + filter) — the same data the NavDropdown shows as its top 100.

##### v0.7.0 — Views: operational renderers + Contexts / Homepage editor
- **Vault + Collection / Item + Set views.** The four non-Table renderers (Board / List / Cards / Gallery) over the per-container `SavedView` storage already in place; multi-saved-view tabs beneath the detail title; the full per-view config family — per-view **order, sort, Group By, column selection** — plus **tier-link sort + filter** (context-link-aware operators like `linked to` / `not linked to`, sortable in the per-view pipeline). Board = kanban (cards grouped by a property's options; editing via card UI). This is also where the deferred per-view **reorder engine** lands — until now, Type detail tables are display-only and mirror the sidebar (SwiftUI's macOS `Table` can't combine collapsible grouping with reliable nested reorder).
- **(folded) Contexts + Homepage block editor.** The composed-blocks surface (Spaces / Topics / Projects / Homepage) gets its editor — paragraph, headings, lists, callout, code, image, columns, **embedded-collection-view** (inline-editable per the locked principle, not snapshots — works because the renderers ship in this same version), linked-pages widget, link-list widget, mini-calendar widget; drag-and-drop reorder + slash-menu insertion.
- **(folded) Context Linked-from surface.** The real `LinkedFromDropdown` (stub today at `Detail/LinkedFromDropdown.swift`): a dropdown listing every operational entity whose `tier1/2/3` points at the Context, via `IndexQuery.incomingContextLinks(targetID:)` (shipped). Supporting bits: `EntityStateRef.iconName`, `EntityKind.displayLabel`, an `EntityStateRef → SidebarSelection` navigation resolver, and a host slot.

##### v1.0.0 — Stabilization
No new features. Polish, performance, bug-fix across everything from v0.0.0 through v0.7.0. Final accent / typography pass. Release-readiness checklist (Sparkle integration if non-MAS, TestFlight if MAS).

#### Post-v1
No specific phase commitments. Catalog at [[Prospects]] — additional view types, synced blocks (full inline Page-body editing), graph view, collaborative simultaneous editing (out of scope indefinitely), sync (Supabase), mobile/iPad, plugin system, plus the Pages-editor wishlist from [[Pommora Tasks]] (H1→H6 styling, page-nav dropdown, wikilink aliases, page notes/description, page banners).
