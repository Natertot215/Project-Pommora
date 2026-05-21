### Pommora — Product Requirements Document

> Living document. Captures the vision, scope, and key architectural decisions for Pommora.

---

#### Vision

Personal management platform combining Obsidian's customization + local-first ethos with Notion's database and view capabilities. Pages are Markdown files; **Vaults** are folder-based database entities holding property schemas + saved views (with **Collections** as sub-folders sharing the Vault's schema); **Contexts** (Spaces / Topics / Sub-topics — 3-tier) are composed-blocks dashboard surfaces. A simpler Notion that's also a more capable Obsidian — without the trade-offs that push users to bounce between the two.

#### Why

- **Obsidian** gives UI-level customization + a transparent local-first file model, but its Markdown core can't express columns, side-by-side callouts, or in-line filtered views without heavy plugins.
- **Notion's** in-line database views (filtered, sorted, regrouped per page without altering source) are its defining feature; Obsidian's file-as-document architecture can't match this natively.
- Obsidian shines until you need real task management or cross-page coordination. Notion shines until you hit an interface decision you can't change.

Pommora's bet: a Markdown-canonical foundation with SQLite as the property + query engine, and clean separation between content (Pages), data (Items), structure (Collections), and interface (Spaces), delivers Notion's most-loved features without giving up Obsidian's open, hackable, local-first nature.

#### Audience and Posture

- Personal-first, single-user, Mac-first for v1. Linux/Windows aren't on the v1 path (would need a React rebuild). iOS/iPad is long-term intent (SwiftUI ships there for free).
- Always open-source.
- Architected so future cross-device + cloud sync remain viable, but not v1 concerns. Multi-user collaboration + plugin system are out of scope indefinitely.

---

#### Domain Model

Two layers, PARA-aligned:

- **Organization — Contexts** (3 tiers): Spaces (tier 1, broad life domains) / Topics (tier 2, subject areas) / Sub-topics (tier 3). All composed-blocks surfaces under `.nexus/spaces/` and `.nexus/topics/`. Per-tier labels user-configurable per-Nexus.
- **Operational — Vaults + Agenda:** Vaults (folder + `_vault.json` shared schema) contain Collections (sub-folders sharing Vault schema in v1) which contain Pages (`.md`) + Items (`.json`); Vaults are kind-agnostic. Agenda (`<nexus>/Agenda/` + `_agenda.json`) holds calendar-anchored `.agenda.json` items (tasks / events / to-dos / phases) with EventKit integration; sibling of Vaults, not nested.
- **Singleton — Homepage** (`.nexus/homepage.json`) — composed-blocks dashboard, one per Nexus.

Full definitions, on-disk shapes, linking model → `// Features//Domain-Model.md` + per-entity files (`Contexts.md`, `Vaults.md`, `Pages.md`, `Items.md`, `Agenda.md`, `Homepage.md`). Implementation spec → `// Planning//Contexts-Vaults-spec.md`.

---

#### Core Architectural Decisions

##### Stack

Pommora's stack is SwiftUI. **The Pages editor shipped at v0.2.7.0 on native NSTextView + Apple `swift-markdown` 0.8.0 + TextKit 2 + vendored `swift-markdown-engine`** (Apache 2.0, at `External/MarkdownEngine/`). The native TextKit-2 pivot (after a WKWebView fork attempt) gave Pommora Writing Tools (15.1+), Look Up / Translate, spell-check, IME, and dynamic system colors for free. Full editor spec → `// Features//PageEditor.md`.

| Layer | SwiftUI |
|---|---|
| Desktop shell | SwiftUI on macOS Tahoe (26+) |
| UI framework | SwiftUI primary + AppKit interop where needed (NSTextView/TextKit 2, NSSplitView, NSItemProvider) |
| Styling | SwiftUI native semantic colors / Materials / Font scale + small Pommora-brand `Color` / `Font` extensions (accent + code + callout) |
| Editor (Pages) | Shipped v0.2.7.0: native NSTextView + `swift-markdown` 0.8.0 + TextKit 2 + vendored `swift-markdown-engine` (`External/MarkdownEngine/`). Pommora-side `AppleASTSupplementalStyler` adds BlockQuote / Strikethrough / Table / ThematicBreak on top of the engine's regex tokenizer. `MarkdownTextLayoutFragment.draw` overrides are the extension point for HR (Phase 1) + v0.2.7.2 Blockquote + Tables work. |
| Spaces composer | SwiftUI `.draggable` / `.dropDestination` + `Codable` block enum; candidate libs (`visfitness/reorderable`, `stevengharris/SplitView`) evaluated at build time |
| Backend layer | Pure Swift |
| Database | SQLite via GRDB.swift v7.5+ (FTS5 + `ValueObservation`) |
| Markdown parser | `apple/swift-markdown` (parse only; hand-rolled writer for save path) |
| File watcher | FSEventStream via Swift wrapper |
| Icons | SF Symbols via `Image(systemName:)` |

> If pivoting to React, see `// ReactInfo//Contingency.md` + `// ReactInfo//ReactInfo.md`.

##### Three load-bearing constraints

1. **Stack portability of functionalities.** File formats, SQLite schema, domain model, property catalog, directive syntax, wikilink behavior, view directives, design values, UX patterns survive a stack rebuild — the codebase doesn't. No enforced layer separation; portability comes from documented decisions. Detail → `// Features//Architecture.md`.

2. **Cross-nexus queryability + cloud sync compatibility.** Collections aren't isolated — any Page or Space can query/link/embed any Collection regardless of folder location. On-disk model maps cleanly to a cloud DB: shared `pages` table with `collection_id` + `properties` JSONB; parallel `items` table; one `collections` row per `_collection.json`; one `spaces` row per `.space.json`. Sync arrives as additive translation. V1 gets device-to-device sync free via nexus in iCloud/Dropbox/any synced folder. **Reference convention:** relations stored by ID (rename-safe); body wikilinks use names (rewritten on rename).

3. **Persistent immediate legibility for agents.** External agents (Claude, MCP clients, any tool with filesystem access) read Pommora's entire structured graph — Pages, Items, Collection schemas, Spaces, relations, properties — directly from files without tool-call round-trips. SQLite is performance scaffolding, not source of truth. Differentiator from Notion-via-MCP (tool-mediated, opaque) and Obsidian (locally legible but unstructured). Choices that trade file-canonical legibility for app-internal convenience violate this constraint.

##### Storage Model

**Nexus location:** user-pickable on first launch; default `~//PommoraNexus//`. Can sit in iCloud Drive / Dropbox / any synced folder for free device-to-device sync. Path persisted via security-scoped bookmark in app-level state; sandbox enabled from v0.1a (forward-compatible with MAS).

**On disk:**

```
<picked nexus folder>//                    ← canonical content lives here, syncs with cloud
  Planner//                                 ← Vault (folder + _vault.json)
    _vault.json                             ← shared schema for all Content inside
    Tasks-archive//                         ← Collection (sub-folder; shares Vault schema)
      Old-task.json                         ← Item
    Goals//                                 ← Collection
      Q1-goals.json
    Events-notes//                          ← Collection
      Conference-summary.md                 ← Page (Vaults are kind-agnostic)

  Materials//                               ← Vault
    _vault.json
    Pages//                                 ← Collection
      Attention-is-all-you-need.md          ← Page
    Documents//
      Annual-report.json                    ← Item
    Reports//
      Research-summary.md                   ← Page

  Agenda//                                  ← Operational-layer sibling of Vaults
    _agenda.json                            ← built-in `type` Select + user-extensible
    Buy-groceries.agenda.json               ← Agenda item (kind inferred from time fields)
    Team-standup.agenda.json
    Submit-report.agenda.json

  .nexus//                                  ← app-internal config (nexus-portable, syncs)
    nexus.json                              ← v0.1a: ULID + createdAt
    state.json                              ← v0.2+: open tabs, sidebar UI state
    tier-config.json                        ← Contexts tier labels (singular + plural)
    saved-config.json                       ← Saved-section item labels
    homepage.json                           ← singleton Homepage entity (composed blocks)
    spaces//                                ← tier-1 Contexts (flat files)
      Personal.space.json
      Academics.space.json
      Work.space.json
    topics//                                ← tier-2 Contexts (each Topic is a folder)
      Academics//
        _topic.json                         ← parents: [Academics-space-id]
        CS-161.subtopic.json                ← tier-3, file-structural parent = this folder
        Linear-Algebra.subtopic.json
      Productivity//
        _topic.json                         ← parents: [Personal-id, Work-id] (multi-Space)
        GTD-method.subtopic.json

  .trash//                                  ← Deleted entities (nexus-local trash; v1+)
    Planner//Tasks-archive//
      Old-cancelled-task.json               ← Preserves original relative path

~//Library//Application Support//com.nathantaichman.Pommora//   ← machine-specific, never syncs
  state.json                                ← Codable AppState: bookmark + future recent-nexuses
  nexuses//
    <nexus-id>//                            ← keyed by ULID from .nexus/nexus.json
      nexus.db                              ← SQLite index (v0.2+); regeneratable
      cache//                               ← future
```

A folder is a **Vault** iff it contains `_vault.json`. Sub-folders inside a Vault (no own `_vault.json`) are Collections sharing the Vault's schema. Nexus-root folders without `_vault.json` are cosmetic — but `Agenda/` is reserved. App-internal config sits in `.nexus//` (hidden, matches `.obsidian` convention) and holds Contexts + Homepage singleton + tier/saved config. Deletes go to `.trash//` at the nexus root, preserving original relative path.

**Why the SQLite index lives outside the nexus:** `nexus.db` inside an iCloud/Dropbox-synced vault risks file-conflict-driven corruption (SQLite's locking assumes single-host filesystem semantics). The Application Support per-nexus subdir is keyed by ULID (survives vault rename/move) and marked `isExcludedFromBackupKey` so iCloud Backup skips the regeneratable index.

##### Pages

`.md` file with YAML frontmatter (`id` ULID, `icon`, per-tier multi-relations `tier1`/`tier2`/`tier3`, property values from parent Vault's schema; no `vault` or `title` field — filename = title) + Markdown body. Pages conform to the Vault's schema; ad-hoc page-local properties are out of v1 (Prospect).

Pages are Markdown documents, not block surfaces — one continuous stream. Standard Markdown (headings H1–H5, lists, code blocks + inline code (SF Mono; `code//` tokens), images, GFM tables, blockquotes, HRs) plus two Pommora rendering directives: **`@Columns`** (`:::columns` fenced section; renders N equidistant horizontal columns; layout-only, content inside is standard Markdown) and **`:::callout`** (outlined-box, distinct from blockquotes' left-side emphasis bar; border binds to `callout//` token).

Both directives resolve to inert text + standard Markdown for external tools (Notion's Markdown export principle). Headings are foldable by default (chevron collapses until next equal-or-higher heading); no `:::toggle` construct, no on-disk syntax. Blocks belong to Spaces only. `@View` in-line embeds in Page bodies are out of v1 (TextKit 2 layout-attachment complexity); embedded views remain available inside Spaces. Full detail → `// Features//Pages.md`.

##### Vaults

Folder + `_vault.json` sidecar (`id`, `icon`, `properties[]` shared schema, `views[]`). Title = folder name. Vaults are **kind-agnostic** (Pages + Items coexist under shared schema). **Collections** are pure sub-folders inheriting the Vault's schema (no own metadata file in v1; Collection-local overrides are post-v1 Prospect). Vaults have no text-editor surface — pure database viewers (table / board / list / cards / gallery). Full detail → `// Features//Vaults.md`.

##### Contexts (Spaces / Topics / Sub-topics)

Three-tier organization layer; all three are composed-blocks surfaces. Tier-1 Spaces: `.nexus/spaces/<Title>.space.json` (carries `color`, tier-1 only). Tier-2 Topics: `.nexus/topics/<Title>/_topic.json` (multi-parent across Spaces). Tier-3 Sub-topics: `.nexus/topics/<TopicFolder>/<Title>.subtopic.json` (single file-structural parent + `linked_relations` typed property). Tier labels user-configurable per-Nexus (Capacities-style singular + plural). Same `blocks` shape as Homepage. Full detail → `// Features//Contexts.md`.

##### Agenda

Calendar-anchored items (events, tasks, to-dos, phases) at `<nexus>/Agenda/*.agenda.json`. Single unified entity; `properties.type` Select (defaults Task / To-Do / Phase / Event; user-extensible). EventKit mapping is data-driven: `start_at`+`end_at` → `EKEvent`; `due_at` only → `EKReminder`; neither → unscheduled `EKReminder`. Requires `com.apple.security.personal-information.calendars` entitlement + `NSCalendarsFullAccessUsageDescription` / `NSRemindersFullAccessUsageDescription` keys + modern `requestFullAccessTo*` APIs. EventKit sync opt-in via Settings (not on by default in v1). Full detail → `// Features//Agenda.md`.

##### Homepage

Singleton composed-blocks dashboard at `.nexus/homepage.json`. No `id`/`tier`/`parents` — file location is identity. Same `blocks` shape as Contexts; designed to embed anything. Seeded on first launch; not user-deletable. Full detail → `// Features//Homepage.md`.

##### Local-End Translation Principle

**The local file is the spec, not the render.** Anything SQLite computes — board view contents, gallery cards, aggregated counts, relation lookups — is referenced by directive, never inlined. Agents read the directive and understand structure; data lives in SQLite, rendered only inside Pommora.

##### SQLite Schema

Six tables, rebuilt from files on launch or demand. Property schemas live in per-Vault `_vault.json` (canonical) + Agenda's `_agenda.json` (canonical), loaded into memory at app start.

```sql
-- Page index (rebuilt from .md files inside Vaults)
CREATE TABLE pages (
  id TEXT PRIMARY KEY,                -- ULID from frontmatter
  path TEXT UNIQUE NOT NULL,          -- 'Materials/Pages/Attention.md'
  vault_id TEXT NOT NULL,             -- derived from path (containing Vault folder)
  collection_path TEXT,               -- relative path inside Vault if in a Collection sub-folder
  title TEXT NOT NULL,                -- derived from filename (basename minus '.md')
  icon TEXT,
  frontmatter JSON NOT NULL,          -- includes tier1/tier2/tier3 ID arrays + properties
  body TEXT NOT NULL,                 -- raw markdown body (powers FTS)
  modified_at INTEGER NOT NULL
);

-- Item index (rebuilt from .json files inside Vaults)
CREATE TABLE items (
  id TEXT PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,
  vault_id TEXT NOT NULL,
  collection_path TEXT,
  title TEXT NOT NULL,
  icon TEXT,
  description TEXT,                   -- short plain-text field, 250-char cap
  properties JSON NOT NULL,
  tier1 JSON NOT NULL,                -- array of Space IDs
  tier2 JSON NOT NULL,                -- array of Topic IDs
  tier3 JSON NOT NULL,                -- array of Sub-topic IDs
  modified_at INTEGER NOT NULL
);

-- Agenda index (rebuilt from .agenda.json files in <nexus>/Agenda/)
CREATE TABLE agenda (
  id TEXT PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,          -- 'Agenda/Buy-groceries.agenda.json'
  title TEXT NOT NULL,
  icon TEXT,
  start_at TEXT,                      -- ISO-8601; nullable
  end_at TEXT,                        -- ISO-8601; nullable
  due_at TEXT,                        -- ISO-8601; nullable
  completed INTEGER NOT NULL,         -- bool
  eventkit_uuid TEXT,                 -- nullable; populated when synced to EKEventStore
  calendar_id TEXT,                   -- EKCalendar identifier; nullable
  properties JSON NOT NULL,           -- includes `type` Select
  tier1 JSON NOT NULL,
  tier2 JSON NOT NULL,
  tier3 JSON NOT NULL,
  modified_at INTEGER NOT NULL
);

-- Vault index (rebuilt from _vault.json files)
CREATE TABLE vaults (
  id TEXT PRIMARY KEY,
  folder_path TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,                -- derived from folder name
  icon TEXT,
  properties JSON NOT NULL,           -- shared schema for Pages + Items inside
  views JSON NOT NULL,
  modified_at INTEGER NOT NULL
);

-- Contexts (Tiers) index — Spaces / Topics / Sub-topics share one table, discriminated by level
CREATE TABLE tiers (
  id TEXT PRIMARY KEY,
  level INTEGER NOT NULL,             -- 1 | 2 | 3
  path TEXT UNIQUE NOT NULL,          -- file path inside .nexus/spaces or .nexus/topics
  title TEXT NOT NULL,
  icon TEXT,
  color TEXT,                         -- tier-1 only; nullable for tier 2/3
  parents JSON NOT NULL,              -- array of tier IDs at lower levels (file-structural for tier 3)
  linked_relations JSON NOT NULL,     -- additional non-file relations (tier 3 only; empty array for tier 1/2)
  blocks JSON NOT NULL,               -- composed-page block tree
  modified_at INTEGER NOT NULL
);

-- Link index (rebuilt from files)
CREATE TABLE links (
  from_id TEXT NOT NULL,         -- page, item, agenda, tier id
  from_kind TEXT NOT NULL,       -- 'page' | 'item' | 'agenda' | 'tier'
  to_id TEXT NOT NULL,
  to_kind TEXT NOT NULL,         -- 'page' | 'item' | 'agenda' | 'tier' | 'vault'
  property TEXT                  -- NULL for inline wikilinks; 'tier1', 'tier2', 'tier3', 'linked_relations', etc.
);

CREATE INDEX idx_pages_vault ON pages(vault_id);
CREATE INDEX idx_items_vault ON items(vault_id);
CREATE INDEX idx_agenda_due ON agenda(due_at);
CREATE INDEX idx_agenda_start ON agenda(start_at);
CREATE INDEX idx_tiers_level ON tiers(level);
CREATE INDEX idx_links_from ON links(from_id, from_kind);
CREATE INDEX idx_links_to   ON links(to_id, to_kind);
```

Queries use SQLite's JSON1 extension to reach into property values and tier-relation arrays:

```sql
-- All Pages in the "Materials" Vault tagged to a specific Topic
SELECT * FROM pages
WHERE vault_id = '01H...materials-vault-id'
  AND EXISTS (SELECT 1 FROM json_each(json_extract(frontmatter, '$.tier2'))
              WHERE value = '01H...topic-id');

-- All incomplete Agenda items in the next 7 days
SELECT * FROM agenda
WHERE completed = 0
  AND (start_at BETWEEN datetime('now') AND datetime('now', '+7 days')
       OR due_at BETWEEN datetime('now') AND datetime('now', '+7 days'));
```

##### Property Model

- **Values** in Page YAML frontmatter (`.md`), Item `properties` (`.json`), or Agenda `properties` (`.agenda.json`). **Schemas** in each Vault's `_vault.json` (Vault-wide in v1; Collection-local is post-v1 Prospect). Agenda uses parallel `_agenda.json` with two built-ins (`type` Select + `status` Status) plus user-extensible additions.
- **Scoped per Vault**, created via Vault Settings sheet (Notion-style). Members must conform; ad-hoc page-local properties out of v1 (Prospect).
- **V1 catalog (10 types):** number, checkbox, date, date & time, select, multi-select, URL, relation, **status**, **last edited time** (auto). No free-form text — filename = title; "text-shaped" values use Select/Multi-select with creatable options. **Status** has 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done) with user-editable options; group LABELS renamable, 3 structural slots fixed for EventKit compatibility at v0.7.0.
- **Every property can carry an icon** (SF Symbol via `IconPickerField`).
- **Relations are paired by default** — creating a Vault/Collection-scoped Relation atomically creates the reverse on the target Vault. Context-tier-scoped relations stay one-way (Contexts have no `properties[]` schema).
- **Inline option creation forbidden.** Select/Multi-select/Status options come only from the schema editor (Vault Settings → Edit Properties), reachable via right-click "Edit options…" or "Manage options…" link in every value picker.
- **Move-strip rule (Notion-style):** moving a Page/Item across Vaults strips properties not in the destination schema (no quarantine; confirmation warning lists strips). Implemented v0.3.0 (pulled forward from v0.4.0).

Full catalog, config shapes, schema-mutation rules → `// Features//Properties.md`. Implementation phases → `// Planning//v0.3.0-Properties-implementation.md`.

##### View Directives

Five view types in v1:

| Type | Renderer | Notes |
|---|---|---|
| **Table** | Stack-native data table | Sortable columns, inline cell edit |
| **Board** | Kanban layout | Cards grouped by a property's options. v0.9 ships visual layout (edit via card UI to "move" between columns); drag-to-rewrite-frontmatter is post-v1.0. |
| **List** | Plain list | Title + selected inline properties |
| **Gallery** | Grid | Cards with cover image |
| **Cards** | Grid | Cards without cover-first emphasis |

Views appear in two contexts: (1) **inside a Vault** — saved views in `_vault.json`, switch via tabs, scope to Collection sub-folders or whole Vault; (2) **embedded as a widget** — "Embedded Collection View" renders any saved Vault view inside a Context/Homepage with per-embed overrides on filter/sort/group/shown-properties. Per the inline-editing principle, embedded views are fully editable in place.

Each view spec: source Vault (implicit from sidecar location), optional Collection-path scoping, view type, filter expression, sort, group-by property, properties to display, cover image (gallery). Filter expressions parse to a small DSL translating to parameterized `json_extract` SQL. View filters/sorts never modify the source Vault.

In-line `@View` embeds *inside Page bodies* are out of v1 (TextKit 2 layout-attachment complexity); v2+ feasible if Pommora pivots to JS-editor + WKWebView (see `// Features//Prospects.md`).

##### Columns

`@Columns` supported in Pages and Spaces. **V1 columns are equidistant** — widths divide available space evenly by child count; no per-column width config in v1. Ships as Pommora-specific render; file format stays standard `:::columns` Markdown on disk.

##### Sidebar Navigation

Surfaces curated, app-relevant navigation, not filesystem layout. Four top-level groups; last three are default-collapsed disclosure groups. User can drag headings to reorder; initial-boot order: **(heading-less pinned section) / Spaces / Topics / Vaults**.

- **Pinned (heading-less, top)** — three fixed entries (Homepage / Calendar / Recents); labels renamable via Settings. Structurally a `Section` wrapper to host future user-pinned pages (gains "Saved" heading then). `Homepage` opens the singleton dashboard; `Calendar` opens calendar view over Agenda + EventKit-mirrored events; `Recents` shows recently-opened tabs.
- **Spaces** — flat rows for tier-1 Contexts; color/symbol indicator (tagging style settable).
- **Topics** — chevron-disclosure for tier-2 Contexts; expanded shows file-nested Sub-topics. Inherited tagging from parent Space(s); multi-Space Topics show multi-color/symbol.
- **Vaults** — chevron-disclosure for Vaults. Expanded shows Pages directly in vault root + Collection sub-folders as children; each Collection further discloses its Pages. Pages: `doc.text` icon; Collections: `folder` icon.

Items, Agenda items, and Events do NOT appear in the sidebar — they live in the detail-pane Tables (`VaultDetailView`, `CollectionDetailView`). Cosmetic folders (nexus root without `_vault.json`) have no semantic meaning to Pommora; no raw filesystem view in v1.

**Creation is right-click-only.** No "+ New" buttons; right-click headings/rows/sections opens a context menu with "New X" options auto-scoped to the cursor location. Quick-capture (Cmd+Shift+N or menu-bar; pre-v1) is the discoverable counterpart for global creation. Collapsed-by-default disclosure is the general default for hierarchical UI. Full spec → `// Features//Sidebar.md`.

##### Three-Pane Shell + Property Panel

Sidebar (default 240px) / main (flex) / inspector (default 280px). Both side panes drag-resizable from v0.0; widths persist across launches. Default window 1200×800; minimum 960×560. Inspector's default view is the property panel for the active Page in v1; an AI chat interface (frontend to Nathan's existing local CLI, not an API integration) is planned post-v1 (see `// Features//Prospects.md`). Items don't use the inspector — they open in an Item window.

**Window chrome — macOS unified title bar.** No separate Pommora title bar. Traffic-lights render OS-rendered in the sidebar pane's column. A single unified toolbar (`.windowToolbarStyle(.unified(showsTitle: false))`) holds sidebar toggle, back/forward arrows, NavDropdown trigger, and inspector toggle, all in the same row as traffic-lights. No second toolbar row. Pattern: Mail / Notes / Finder.

Below-heading and page-bottom property-panel placements are post-v1 Prospects.

Built on SwiftUI's two-column `NavigationSplitView(sidebar:detail:)` with inspector attached via `.inspector(isPresented:)` (macOS 14+) — Apple's idiomatic pattern (Mail, Notes, Pages). Width via `.inspectorColumnWidth(min:ideal:max:)`; toolbar toggle via `InspectorCommands`. The three-column `NavigationSplitView` variant was rejected — that column is for selected-item drill-down (Mail's list → message-list → message), not a contextual supplementary panel.

##### Nav Dropdown

Main pane is **single-pane.** Navigation history lives in a Liquid Glass dropdown button (SF Symbol `square.on.square`) in the toolbar — popover with two toggleable lists: **Pinned** (user-curated via right-click) and **Recents** (auto-tracked LRU). Replaces the earlier "Top-Bar Tabs" model. Pattern: Things 3 Quick Find, Notes.app Move-To popover.

Single-click highlights, double-click opens in main detail pane. Items open in the existing `ItemWindow` popover; standalone-window previews deferred to the cross-feature PreviewWindow primitive (`// Guidelines//CRUD-Patterns.md → Preview-window prerequisite`). Keyboard: `⌘T` opens dropdown; `⌘[` / `⌘]` walk Recents back/forward. State persists in `<nexus>/.nexus/state.json` (per-nexus, vault-portable); Pinned uncapped; Recents store cap 500; dropdown shows top 100; full-frame Recents view (v0.6.0) shows the full store.

Shipped at v0.2.7.1. Full spec → `// Features//NavDropdown.md`.

##### Item Window

Items open in a popover-style floating surface (Calendar-app event-detail pattern) anchored to click location — not in tabs, not in the inspector. Holds title (editable filename) + icon + Vault-schema property editors + 250-char description + tier1/2/3 relations + read-only meta footer (`id`/`created_at`/`modified_at`). Save commits via `ContentManager.updateItem`. Full spec + v0.3.1 modal-window redesign → `// Features//Items.md`.

##### First-Launch Experience

After the user picks a nexus location, Pommora opens with empty sidebars plus a seeded Homepage singleton at `.nexus/homepage.json` (NOT a Space) as the landing surface via the pinned `Homepage` row. Per-Nexus singletons auto-seed on first manager init: Homepage + Agenda schema sidecar + `tier-config.json` + `saved-config.json`. No tutorial, no walkthrough wizard.

##### Design System

SwiftUI native idioms (semantic colors, Materials, Font scale, SF Symbols) plus small Pommora-brand Color/Font extensions for values SwiftUI doesn't cover (accent, code, callout, blockquote). V1 ships one initial scheme plus in-app customization for accent color and font size (folded into v0.6.0 Settings scaffold). Full design philosophy → `// Guidelines//Design.md`. SF Symbol assignments → `// Guidelines//Symbols.md`. React-side reference → `// ReactInfo//Styling-Tokens.md`.

##### File Renames and Wikilink Updates

Renames are automatic and atomic. When a Page is renamed:

1. Locate every wikilink targeting the old name via the `links` index — one indexed query, not a nexus-wide scan.
2. In one transaction: rename file on disk; update Page's `path` in SQLite; rewrite every `[[Old Name]]` to `[[New Name]]` across referencing Pages; write each affected file atomically (`.tmp` + `rename`).
3. File watcher coalesces resulting change events.

**Wikilink resolution:** `[[Page Name]]` resolves by basename match (Obsidian-style). Basename collisions disambiguate by path: `[[Notes//Roadmap]]` vs. `[[Personal//Roadmap]]`. Renaming a Page with ambiguous siblings updates only references that resolve to it. Wikilinks render as styled colored inline text (Obsidian-style), not Notion-style chips. Relation properties store target IDs and display the target's current title (resolved at render time; renames update display automatically).

##### Data, State, File Watching

- **State.** `@Observable` macro (Swift 5.9+, mature in 6.2) — per-property tracking; `@State` replaces `@StateObject`. Heavy services (NexusIndex, parsers) stay in DI to avoid re-init on view rebuild.
- **Persistence.** `GRDB.swift v7.5+` for "SQLite as index, files canonical": `ValueObservation.tracking { db in ... }`, `.values(in:)` returning `AsyncSequence` change notifications, `FTS5Pattern` for full-text. SwiftData isn't a fit (wraps Core Data; no custom SQLite schema or FTS5 access).
- **Code shape.** Pure Swift Package for data + parsing layer keeps SwiftUI imports out (callable from a CLI target if useful). `actor` wrapping the database boundary, `Sendable` records, `AsyncSequence` surfaces (preferred over Combine in Swift 6 strict concurrency) fit GRDB's `.values(in:)` as the data-to-UI reactive surface. Not enforced (see `// Features//Architecture.md`).
- **File watching.** `DispatchSource.makeFileSystemObjectSource` is per-fd (no recursion) — wrong tool. Use FSEventStream via Swift wrapper (`EonilFSEvents` or hand-rolled `FSEventStreamCreate`). APFS atomic-rename gotchas: editor save = `.tmp` write + rename emits create+delete; debounce 50–100ms by path; track outbound mtimes to ignore Pommora's own writes.

> If pivoting to React, see `// ReactInfo//StateData.md` (Zustand + hand-rolled pub/sub + `@parcel/watcher`).

##### Mac OS Integration

SwiftUI-first-party (no companion bundles): **QuickLook** (`QLPreviewProvider` via QuickLook Preview Extension target; `QLSupportedContentTypes` for `net.daringfireball.markdown`); **CoreSpotlight** (`CSSearchableItem` + `CSSearchableItemAttributeSet`; `.onContinueUserActivity(CSSearchableItemActionType)` deep-links); **Share Extension** (target conforming to `NSExtensionPrincipalClass`); **NSServices** ("New Pommora Page from Selection" — Info.plist + selector); **MenuBarExtra** (macOS 13+; `.menuBarExtraStyle(.window)`); **Sidebar vibrancy + accent** (`NSVisualEffectView` via SwiftUI `Material`; auto accent via `Color.accentColor`); **Finder file-promise drag-out** (`Transferable` + `.draggable`); **Accessibility** (`.accessibilityLabel/Hint/Value/Action`; Dynamic Type + VoiceOver rotor free); **Window state restoration with Spaces** (`Scene` + `@SceneStorage` + NSWindow restoration); **Deep links** (`.onOpenURL` + `CFBundleURLTypes` for `pommora://`).

> If pivoting to React, see `// ReactInfo//MacIntegration.md` for Electron ceilings on each.

##### Distribution

**Sparkle 2.x** for non-MAS auto-update (EdDSA-signed, sandbox-compatible, SwiftUI via `SPUStandardUpdaterController`). **TestFlight for Mac** fully shipped (same as iOS). **Sandboxing for MAS:** user-picked nexus folders via security-scoped bookmarks (`URL.bookmarkData(options: .withSecurityScope)`), resolved with `startAccessingSecurityScopedResource()` on each launch. No feature blocker.

> If pivoting to React, see `// ReactInfo//Distribution.md` (electron-vite + electron-builder + electron-updater + `@electron/notarize`).

---

#### v1 Scope

**In:**

- **Contexts** (3 tiers — Spaces / Topics / Sub-topics) — composed-blocks surfaces; tier labels per-Nexus configurable. Spaces flat in sidebar; Topics chevron-disclose to file-nested Sub-topics. Tier-skip allowed; same-tier file-structural links forbidden. Sub-topics carry `linked_relations` as typed multi-valued property.
- **Vaults + Collections + Content (Pages + Items)** — kind-agnostic folders with shared schema; Collections are sub-folders inheriting Vault schema (no own schema in v1); Pages (`.md`) and Items (`.json`) inside.
- **Pages** — Markdown + YAML frontmatter (incl. per-tier multi-relations `tier1`/`tier2`/`tier3`); editor = native TextKit 2 + `swift-markdown` + vendored `swift-markdown-engine` (shipped v0.2.7.0). Standard Markdown + `@Columns` + `:::callout` directives.
- **Items** — `.json`. Filename = title; conform to parent Vault's schema; `id`, `icon`, `description` (250-char), `tier1/2/3`, timestamps. Open in Item Window popover, not a tab.
- **Agenda** — `.agenda.json` at `<nexus>/Agenda/`. Unified entity (no kind discriminator); `properties.type` Select for user-facing categorization. EventKit-bridgeable by which time fields are populated; sync opt-in.
- **Homepage** — singleton dashboard at `.nexus/homepage.json`. Seeded on first launch.
- Property panel UI driven by Vault + Agenda schemas; all v1 types (10) incl. Status with EventKit-aligned groups; Vault Settings sheet centralizes schema editing + sort + property visibility (filter/group/layout placeholders fill in at v0.6.0).
- Wikilinks (styled colored inline text).
- Automatic file rename with cross-nexus wikilink rewrite.
- File watcher keeping SQLite synced.
- Global search (SQLite FTS5 over Page bodies + frontmatter).
- Four-section sidebar (Saved / Spaces / Topics / Vaults), user-reorderable, default-collapsed. Agenda via Saved → Calendar entry.
- **Inline editing of embedded views** — every embed in a composed-blocks surface is a live editable view of its source.
- One initial design scheme + in-app accent color + font size customization (folded into v0.6.0 Settings scaffold); SwiftUI native handles everything else.

**Out (post-v1):** additional view types, block features, sync, mobile, plugins, ad-hoc properties, multi-Collection pages, independent UI titles, in-line view embeds in Pages, chip wikilinks, Item ↔ Page promotion, board view drag-to-rewrite-frontmatter, etc. — see `// Features//Prospects.md`. Items move from Prospects into `Framework.md` when committed.
