### Pommora — Roadmap

Phased plan in chronological order; no calendar dates. Each version ships green standalone and produces a verifiable outcome. CRUD lands paired with paradigm at every minor version — a new entity type doesn't appear in code until its CRUD interface is functional end-to-end.

#### Vision

A Markdown-canonical, SQLite-indexed personal management platform combining Obsidian's local-first openness with Notion's database and view capabilities. **2-layer PARA-aligned domain model:**

- **Organization layer — Contexts** (Areas / Topics / Projects, 3 tiers) — composed-blocks surfaces
- **Operational layer:**
  - **Pages** — Page Collections → recursive Page Sets (Set at depth-1, Sub-Set deeper; any depth) → Pages (`.md`). UI labels default to "Collection" + "Set"
  - **Agenda** — Tasks (`.task.json`, EKReminder-aligned) + Events (`.event.json`, EKEvent-aligned)
- **Singleton — Homepage** (`.nexus/homepage.json`)
- **Settings scaffold** (`.nexus/settings.json`) — per-Nexus user-overridable UI labels + accent color

Mac-first for v1, always open-source. Domain spec → [[Domain-Model]].

#### Versioning

`major.minor.patch` semver. **Minor (`v0.X.0`)** = a completed feature cluster. **Patch (`v0.X.y`)** = touch-up or additive extension on top of a shipped feature. **Major (`vX.0.0`)** reserved for `v1.0.0` (stabilization) and onward.

---

#### Shipped versions (earliest → latest)

##### v0.0.0 — Shell opens
Toolchain proof on macOS 26+ (Tahoe). Three-pane shell (sidebar / main / pop-out inspector, inspector default closed) on SwiftUI's two-column `NavigationSplitView` + `.inspector(isPresented:)`. Both side panes drag-resizable; widths persist.

##### v0.1.0 — Nexus Foundation
Sandboxed folder picker, security-scoped bookmark persistence, `.nexus/` init flow, per-nexus App Support subdir keyed by ULID. Sidebar mirrors the picked folder. File menu → Open Nexus; Debug menu → Reset Bookmark.

##### v0.2.0 — Paradigm scaffolding + sidebar UX
Scaffolded the full locked paradigm: every entity CRUD-able end-to-end via sidebar + sheets + detail pane. Areas / Topics / Vaults sidebar sections with Pages disclosed under Vaults/Collections; Agenda in detail-pane Tables.

##### v0.2.1–v0.2.6 — Infrastructure baseline
Sidebar UX tweaks, GitHub Actions CI (`macos-26`), `swift-format` baseline + config + CI lint step, and the `.trash//` data foundation (disk-recoverable deletes; the in-app Trash window surface lands later).

##### v0.2.7.0 — Pages editor (TextKit 2)
Native NSTextView + Apple `swift-markdown` + the Pommora-owned `MarkdownPM` package. Writing Tools, Look Up, spell-check, IME, and dynamic system colors come free. One styler walks the cached AST once. `.md` is the architectural firewall — Pages survive any future editor swap. Spec → `// Features//PageEditor.md`.

##### v0.2.7.1 — Navigation
Liquid Glass dropdown navigation surface — Pinned + Recents tabs, single-click select / double-click open. `⌘T` opens; `⌘[` / `⌘]` walk Recents. Replaces the earlier tab-strip navigation model.

##### v0.2.7.2–v0.2.7.5 — Editor construct passes
HR, Lists, code blocks, and Blockquote rewritten through the dynamic-syntax architecture (markers shrink when the caret leaves the AST node, Bear/Notion pattern; on disk standard CommonMark). Bullet glyph substitution, task-list shorthand, bracket auto-pair, and arrow auto-format land alongside. Locked construct rules → `// Features//PageEditor.md`.

##### v0.2.8 — Sidebar drag-to-reorder
Order persistence (per-sidecar order fields) plus drag-to-reorder UX on the Pages-side and Contexts rows. Navigation Pinned reorder, cross-container drag, and detail-pane Table reorder remain queued.

##### v0.3.0 — Properties (data layer + SQLite + placeholder UI)
The data-layer chapter. Full property data layer (10 property types, stable-ULID definitions, atomic multi-file schema commits, an every-open ID migration with preview, schema CRUD on all schema-bearing managers, validation + drift defense, file attachments with size caps + cascade-delete, Settings auto-migration scaffold). A live end-to-end SQLite index (GRDB, per-nexus `index.db`, two-phase populate, wired into every manager, Notion-style filter/sort/broken-links; mid-session mutations propagate). Placeholder UI gives every interaction a working path. Full summary → [[History]].

##### v0.3.1 — Properties end-to-end (View Settings editor)
The View Settings popover goes live: schema CRUD through an Edit Properties pane, dynamic property-value columns in detail-view Tables, click-to-edit cell popovers per property type, and a Property Visibility pane. Adds saved-view fields + a default-view migration and the chip-color palette. Full record → [[History]].

##### v0.3.2 — View Settings editor rebuild + nav/detail fixes
The per-property editor rebuilt to the Figma; popover-family UIX lessons folded into `// Guidelines//Design.md` (standalone `UIX-Baseline.md` retired). A Pages-side Folders tier was built and **reverted the same cycle** — it duplicated Collections' role — keeping only its stub-and-inline-rename CRUD primitives and sidebar tweaks. Nav/detail bug fixes landed alongside.

##### v0.3.4 — Relations made real + manager de-dup + Pages stats footer
The big consolidation release (**v0.3.3 skipped** — relations folded forward).
- **Relations unified (since superseded — see Contextv2 below).** Tiers and relation properties shared one pipeline with a single reverse-lookup path; context-delete cascades the tier reference out of every operational entity.
- **Native IconPicker.** Pommora's own SF Symbols picker over the full catalog replaces the third-party dependency, behind one icon-edit modifier.
- **Manager de-dup.** The duplicated schema-mutation methods collapsed behind two shared `@MainActor` services, fully behavior-preserving.
- **Vault-table display-only + creation-order.** Type detail tables are display-only for row order (mirror the sidebar); empty-state default order changed alphabetical → creation order. The full per-view ordering system ships later.
- **Pages stats footer + editor polish.** Live line / word / character counts (toggle) + a plain-text breadcrumb; code-block and bullet rendering refinements.

##### v0.3.5 — Connections (page-level) + Contextv2 + MarkdownPM perf
- **Connections page-level.** `[[Page Title]]` syntax, inline render as styled colored text, Liquid Glass autocomplete, click navigation, atomic rename cascade, nexus-wide title uniqueness, a live-refresh bus, and a `connections` index table. Spec → `// Features//Connections.md`.
- **Contextv2.** User-creatable relation properties retired; the three tiers are now the sole relation connection. The paired-relation coordinator was deleted; all `Relation*` symbols renamed `Context*`; the substrate kept.
- **MarkdownPM performance.** Heading / HR / blockquote / bullet reads served from token/construct caches; scroll lag eliminated.
- **Index hardening + page icon.** Conflict-safe parent upserts, a lenient launch scan with file-level exclusions, and an in-editor page-header icon with an "Add Icon" hover affordance (toggle, default off).

Full ship detail → [[History]].

##### v0.4.0 — Pages unification + PagePreview window
The second operational side deleted, not migrated — Page is the only operational entity beside Agenda. `[[` is the sole connection syntax; per-vault `open_in` routes page-taps to **PagePreview** (a real `NSPanel` — AppKit is required for no-dim child-window behavior with no traffic-light / Dock / Window-menu presence, child-attached above the main window, mounting the shared inspector at compact scale) or the main detail pane. User-creatable sidebar sections group Vaults (navigation-only). Launch/state hardening alongside. Full record → [[History]].

##### v0.4.1 — Sets
The original third operational tier: Vault → Collection → **Set** (optional) → Pages — a schema-less folder, strict three levels. **Superseded** by the Collections/Sets rename + infinite nesting — the three tiers collapsed to a **Collection** nesting recursive **Sets** (depth-1 "Set", deeper "Sub-Set") → [[History]]; current spec → [[PageCollections]] + [[PageSets]].

---

#### Upcoming versions (roadmap)

> **Version buckets + priority follow Nathan's own [[Pommora Tasks]] doc** (the working intent ledger); Framework keeps the implementation detail under each. Entries Framework tracks that the Tasks doc doesn't name are *folded into their nearest bucket* and marked **(infra)** / **(folded)**. **The view system ships incrementally** — UIX fixes at **v0.4.2**, Gallery + Layout settings at **v0.4.3**, feature-complete (with the Sort / Filter / Group panes + multi-saved-view config) at **v0.5.0**.

##### v0.4.2 — Views UIX fixes (in progress)
Cross-view polish on the Vault + Collection views: the toolbar **Views dropdown** (create / switch / type-switch — done); the detail **header + container banners** (a title overlaying an edge-to-edge banner); and the shared **menus + toolbar** behavior. Open item: the macOS 26 toolbar `»`-overflow. Active plan → `// Planning//06-13-Views-UIX-Fixes.md`.

##### v0.4.3 — Gallery + Layout settings
The **Gallery** renderer (cards over the per-container `SavedView` storage) and the View Settings **Layout** pane rework (format-dependent Table/Gallery options + per-view Open-In + type dual-write). The grouping + sorting UIX rework lands in this window.

##### v0.5.0 — Views complete + Symbols + Trash
- **Views feature-complete.** With Table + Gallery, the Views dropdown, page **covers** + container **banners**, and the full per-view config — **order, sort, Group By, column selection** + **tier-link sort + filter** (`linked to` / `not linked to` relation operators) — all polished, the view system is done (Board / List / Cards stay enum-carried for post-v0.5 UI — Board = kanban, cards grouped by a property's options). Includes the deferred per-view **reorder engine** on the macOS 26 drag-session APIs (until now, Type detail tables are display-only and mirror the sidebar). Spec → `// Features//Views.md`.
- **Standardized Symbols.** In-app Symbol Settings surface over the `// Guidelines//Symbols.md` registry — user-remappable Application ↔ SF Symbol assignments, replacing hardcoded glyphs with a configurable table.
- **Archive / Trash.** In-app Trash window (SwiftUI surface over the v0.2.5 `.trash//` data layer) with restore + permanent-delete + Empty Trash; cascade-delete reporting with exact counts (Page Type → N Collections + M Pages).
- **(infra)** **FTS5 tables wired** (schema only — the `⌘K` search UI ships v0.7.0); broken-link warning surface for connections.

##### v0.6.0 — EventKit + Agenda UIX + Calendar
EventKit bridge (sandbox entitlement + Info.plist + modern `requestFullAccessTo*` APIs; opt-in via Settings; bidirectional mirroring). Task / Event compact panels (title + properties + description; hosting surface decided here). Calendar view over Agenda; the Saved-section Calendar fills in with the EventKit mirror.

##### v0.7.0 — Settings + Quick Capture + LLM Interface + global search
- **Settings Panel.** Full Settings editing UI — accent color picker (swatch grid + custom well, live preview), label rename forms (Collection / Set / Task / Event + section + tier labels), and tier-config consolidation (folds `.nexus/tier-config.json` into the same surface). Replaces hand-editing `.nexus/settings.json`.
- **Quick Capture.** Global `⌘⇧N` / menu-bar popover creating Pages / Tasks / Events from anywhere in the OS; defaults to a configured inbox Collection; optional Tier / Collection override fields; Enter submits, Esc dismisses.
- **LLM Interface.** The main-window inspector slot becomes the Claude chat (CLI subprocess bridge — frontend to Nathan's local CLI, not API integration). Properties never live in the main-window inspector under the locked direction.
- **(folded) Global search.** `⌘K` command palette + FTS5 search over Page bodies, Agenda titles, and frontmatter / properties (over the FTS5 tables wired at v0.5.0). Natural pairing with Quick Capture — both are global invocation surfaces.
- **(folded) Recents full-frame view.** The Saved-section `Recents` pin opens a full-frame view of the Recents store (up to 500, with sort + filter) — the same data the Navigation shows as its top 100.

##### v0.8.0 — Contexts + Homepage editor
- **Contexts + Homepage block editor.** The composed-blocks surface (Areas / Topics / Projects / Homepage) gets its editor — paragraph, headings, lists, callout, code, image, columns, **embedded-collection-view** (inline-editable per the locked principle, not snapshots — renderers shipped v0.5.0), linked-pages widget, link-list widget, mini-calendar widget; drag-and-drop reorder + slash-menu insertion.
- **Context Linked-from surface.** The real `LinkedFromDropdown` (not yet stubbed): a dropdown listing every operational entity whose `tier1/2/3` points at the Context. The reverse query it builds on, `IndexQuery.incomingContextLinks(targetID:)`, is shipped. Supporting bits: `EntityStateRef.iconName`, `EntityKind.displayLabel`, an `EntityStateRef → SidebarSelection` navigation resolver, and a host slot.

##### v1.0.0 — Stabilization
No new features. Polish, performance, bug-fix across everything from v0.0.0 through v0.8.0. Final accent / typography pass. Release-readiness checklist (Sparkle integration if non-MAS, TestFlight if MAS).

#### Post-v1
No specific phase commitments. Catalog at [[Prospects]] — additional view types, synced blocks (full inline Page-body editing), graph view, collaborative simultaneous editing (out of scope indefinitely), sync (Supabase), mobile/iPad, plugin system, plus the Pages-editor wishlist from [[Pommora Tasks]] (H1→H6 styling, page-nav dropdown, connection aliases, page notes/description, page banners).
