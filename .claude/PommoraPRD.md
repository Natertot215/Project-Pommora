### Pommora — Product Requirements Document

> Living document. Captures the vision, scope, and key architectural decisions for Pommora.

---

#### Vision

Pommora is a personal management platform that combines Obsidian's customization and local-first ethos with Notion's database and view capabilities. Pages are Markdown files; **Vaults** are folder-based database entities holding property schemas and saved views (with **Collections** as sub-folders sharing the Vault's schema); **Contexts** (Spaces / Topics / Sub-topics — a 3-tier system) are composed-blocks dashboard surfaces. The goal is a simpler Notion that's also a more capable Obsidian — without forcing the trade-offs that push users to bounce between the two.

#### Why

Notion and Obsidian each excel where the other falls short:

- **Obsidian** gives unrivaled UI-level customization and a transparent, local-first file model — but its Markdown core can't express columns, side-by-side callouts, or in-line filtered views without heavy plugin reliance.
- **Notion's** in-line database views — filtered, sorted, and regrouped per page without altering the source — are its defining feature. Obsidian's file-as-document architecture can't match this natively.
- **Obsidian** shines until you need real task management or cross-page coordination. **Notion** shines until you hit an interface decision you can't change.

Pommora's bet: a Markdown-canonical foundation with SQLite as the property and query engine, and a clean separation between content (Pages), data (Items), structure (Collections), and interface surfaces (Spaces), can deliver Notion's most-loved features without giving up Obsidian's open, hackable, local-first nature.

#### Audience and Posture

- Personal-first, single-user, Mac-first for v1. Linux / Windows aren't on the v1 path and become contingency-only on SwiftUI — they'd need a React rebuild. iOS / iPad is real long-term intent (SwiftUI ships there essentially for free).
- Always open-source.
- Architected so future cross-device and cloud sync support remain viable — but those aren't v1 concerns. Multi-user collaboration and a plugin system are explicitly out of scope (now and indefinitely).

---

#### Domain Model

Two layers with PARA-aligned naming:

**Organization layer — Contexts** (3 tiers): Spaces (tier 1, broad life domains) / Topics (tier 2, subject areas) / Sub-topics (tier 3). All three are composed-blocks surfaces stored under `.nexus/spaces/` and `.nexus/topics/`. Per-tier labels user-configurable per-Nexus.

**Operational layer — Vaults + Agenda:**
- **Vaults** (folder + `_vault.json` with shared schema) contain **Collections** (sub-folders, share Vault schema in v1) which contain **Content** — **Pages** (`.md`) and **Items** (`.json`). Vaults are kind-agnostic.
- **Agenda** (`<nexus>/Agenda/` with `_agenda.json` schema) holds **Agenda items** (`.agenda.json`) — calendar-anchored entities (tasks / events / to-dos / phases) with EventKit integration. Sibling of Vaults, not nested.

**Singleton — Homepage** (`.nexus/homepage.json`) — composed-blocks dashboard, one per Nexus.

Full definitions, on-disk shapes, capabilities, linking model → `// Features//Domain-Model.md` + per-entity files (`Contexts.md`, `Vaults.md`, `Pages.md`, `Items.md`, `Agenda.md`, `Homepage.md`). Complete implementation spec → `// Planning//Contexts-Vaults-spec.md`.

---

#### Core Architectural Decisions

##### Stack

Pommora's stack is SwiftUI. Option 2 (WKWebView hosting a JS editor) is the likely direction for the Pages editor.

| Layer | SwiftUI |
|---|---|
| Desktop shell | SwiftUI on macOS Tahoe (26+) |
| UI framework | SwiftUI primary + AppKit interop where SwiftUI falls short (NSTextView/TextKit 2, NSSplitView, NSItemProvider for some drag/drop) |
| Styling | SwiftUI native semantic colors / Materials / Font scale + small Pommora-brand `Color` / `Font` extensions for accent + code + callout values |
| Editor (Pages) | Option 2 (likely): WKWebView hosting Tiptap, Milkdown, or BlockNote — all translate cleanly to Markdown. Option 1 (more ambitious): native NSTextView + `swift-markdown` + TextKit 2 (Clearly as fork-reference). |
| Spaces composer | SwiftUI `.draggable` / `.dropDestination` + `Codable` block enum; candidate vertical-reorder and split-pane component libraries (e.g. `visfitness/reorderable`, `stevengharris/SplitView`) evaluated at build time |
| Backend layer | Pure Swift |
| Database | SQLite via GRDB.swift v7.5+ (FTS5 + `ValueObservation`) |
| Markdown parser | `apple/swift-markdown` (parse only; hand-rolled writer for save path) |
| File watcher | FSEventStream via Swift wrapper |
| Icons | SF Symbols via `Image(systemName:)` (no indirection needed) |

> If pivoting to React, see `// ReactInfo//Contingency.md` for translation patterns and `// ReactInfo//ReactInfo.md` for the topic-based reference index.

##### Three load-bearing constraints

1. **Stack portability of functionalities.** File formats, SQLite schema, domain model, property catalog, directive syntax, wikilink behavior, view directives, design values, and UX patterns survive a stack rebuild. The codebase doesn't. No enforced layer separation; portability comes from documented decisions. Detail → `// Features//Architecture.md`.

2. **Cross-nexus queryability + cloud sync compatibility.** Collections aren't isolated — a Page or Space anywhere in the nexus can query, link to, or embed any Collection regardless of folder location. The on-disk model maps cleanly to a cloud DB: a single shared `pages` table with `collection_id` + `properties` JSONB; a parallel `items` table; one `collections` row per `_collection.json`; one `spaces` row per `.space.json`. Sync arrives later as additive translation, not redesign. Cloud sync is real long-term intent. For v1, users get device-to-device sync for free by placing the nexus in iCloud Drive / Dropbox / any synced folder. **Reference convention:** relations are stored by ID (rename-safe); body wikilinks use names (rewritten on rename).

3. **Persistent immediate legibility for agents.** An external agent (Claude, any MCP client, any tool with filesystem access) reads Pommora's entire structured graph — Pages, Items, Collection schemas, Spaces, relations, properties — directly from files, without tool-call round-trips. SQLite is performance scaffolding, not the source of truth. This is Pommora's differentiator from Notion-via-MCP (tool-mediated, opaque) and from Obsidian (locally legible but unstructured). Architectural choices that would trade file-canonical legibility for app-internal convenience violate this constraint.

##### Storage Model

**Nexus location:** User-pickable on first launch. Pommora suggests `~// PommoraNexus//` as the default; the user can place the nexus anywhere — including iCloud Drive, Dropbox, or any synced folder for free device-to-device sync. The chosen path is persisted via security-scoped bookmark in app-level state; sandbox is enabled from v0.1a (forward-compatible with MAS distribution).

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

A folder is a **Vault** if and only if it contains a `_vault.json` file. Folders inside a Vault (without their own `_vault.json`) are Collections that share the Vault's schema. Folders at the nexus root without `_vault.json` are cosmetic — but `Agenda/` is reserved for the Agenda operational entity. The app-internal config folder is `.nexus//` (leading dot, hidden — matches `.obsidian` convention) and now also holds Contexts (Spaces / Topics / Sub-topics) + Homepage singleton + tier/saved config. Deleted entities go to **`.trash//`** at the nexus root; the entity's original relative path is preserved.

**Why the SQLite index lives outside the nexus:** placing `nexus.db` inside a vault that may be on iCloud Drive / Dropbox / another sync surface risks file-conflict-driven corruption (SQLite's locking assumes single-host filesystem semantics). The Application Support per-nexus subdir, keyed by ULID, survives vault rename/move and is marked `isExcludedFromBackupKey` so iCloud Backup skips the regeneratable index. The vault folder stays purely canonical content; the index is the app's private mirror.

##### Pages

Each Page is a `.md` file with:

- **YAML frontmatter** — `id` (ULID), `icon`, **per-tier multi-relations** (`tier1` / `tier2` / `tier3` pointing to Contexts), and property values from the parent Vault's schema. No `vault` field (membership is by folder location). No `title` field (filename = title). Pages conform to the Vault's schema; ad-hoc page-local properties are out of v1 scope (Prospect).
- **Markdown body** — prose.

Pages are **Markdown documents, not block surfaces** — one continuous Markdown stream from top to bottom. They support all standard Markdown (paragraphs, headings H1–H5 in v0's type scale (no H6 token), lists, code blocks + inline code (SF Mono; `code//` tokens), images, GFM tables, blockquotes, horizontal rules) plus **two Pommora-specific rendering directives**:

- **`@Columns`** — multi-column rendering directive. Marks a section of the Page to render as N horizontal columns (equidistant width by child count). The Markdown content inside is unchanged; the directive only affects layout. On disk the file is one continuous Markdown document with `:::columns` fenced notation.
- **`:::callout`** — outlined-box callout. Renders content as a minimally-rounded bordered box, distinct from blockquotes (which are filled with a left-side emphasis bar). Default text uses the primary text token; border binds to an independent `callout//` token.

Both directives resolve cleanly when read by an external Markdown tool — the directive notation appears as inert text and the content is standard Markdown. Same principle as Notion's Markdown export. The previously-proposed `@View` (in-line database view embed in a Page) is deferred to v2+; embedded Collection views remain available *inside Spaces* as widget blocks.

**Headings are foldable by default** — clicking the chevron on any heading collapses the content below until the next equal-or-higher heading. Built-in UI behavior on every heading, not a directive; no on-disk syntax. There is no separate `:::toggle` construct.

**Block-level features as a project term belongs to Spaces only.** Pages don't have blocks.

`@View` inside the prose flow is the harder direction on Option 1 (native editor); on Option 2 (WKWebView + JS editor), the same node-component approach BlockNote and Tiptap support directly applies. Embedded views remain available inside Spaces regardless of editor path.

##### Vaults

Each Vault is a folder + a `_vault.json` schema sidecar:

```json
{
  "id": "01HXXXXX...",
  "icon": "folder",
  "properties": [ /* shared property schema entries */ ],
  "views": [ /* saved view configurations */ ]
}
```

The Vault's title comes from the folder name. Vaults are **kind-agnostic** — Pages and Items both coexist under the shared schema. **Collections** are pure sub-folders inside a Vault that inherit the Vault's schema (no own metadata file in v1). Collection-local schema overrides are a post-v1 Prospect. Vaults have no text-editor surface — they're pure database viewers (table / board / list / cards / gallery).

Full detail → `Features/Vaults.md`.

##### Contexts (Spaces / Topics / Sub-topics)

Three-tier organization layer; all three tiers are composed-blocks surfaces. Tier-1 (Spaces) at `.nexus/spaces/<Title>.space.json`; tier-2 (Topics) at `.nexus/topics/<Title>/_topic.json`; tier-3 (Sub-topics) at `.nexus/topics/<TopicFolder>/<Title>.subtopic.json`. Topics multi-parent across Spaces; Sub-topics single-parent at file with additional `linked_relations` as a typed property. Tier labels user-configurable per-Nexus (Capacities-style singular + plural).

```json
// Example .space.json
{
  "id": "01H...",
  "tier": 1,
  "icon": "person.circle",
  "color": "blue",                       // tier-1 only
  "blocks": [
    { "type": "heading", "level": 1, "text": "Personal" },
    { "type": "embedded-collection-view", "vault_id": "01H...", "view_id": "01H..." }
  ]
}
```

Same `blocks` shape as Homepage. Full detail → `Features/Contexts.md`.

##### Agenda

Calendar-anchored items (events, tasks, to-dos, phases) live in `<nexus>/Agenda/` as `.agenda.json` files. Single unified entity with `properties.type` as a Select (defaults: Task / To-Do / Phase / Event; user-extensible). EventKit mapping data-driven — `start_at` + `end_at` → `EKEvent`; `due_at` only → `EKReminder`; neither → unscheduled `EKReminder`.

Sandbox + permissions required for EventKit access: `com.apple.security.personal-information.calendars` entitlement + `NSCalendarsFullAccessUsageDescription` / `NSRemindersFullAccessUsageDescription` Info.plist keys + modern `requestFullAccessTo*` APIs. EventKit sync NOT enabled by default in v1 — opt-in via Settings.

Full detail → `Features/Agenda.md`.

##### Homepage

Singleton composed-blocks dashboard at `.nexus/homepage.json`. No `id` / no `tier` / no `parents` — file location IS the identity. Same `blocks` shape as a Context, but designed as the user's general home page that can embed anything. Seeded on first launch; not user-deletable.

Full detail → `Features/Homepage.md`.

##### Local-End Translation Principle

**The local file is the spec, not the render.** Anything SQLite computes — the contents of a board view, the cards in a gallery, aggregated counts, relation lookups — is referenced by directive but never inlined. An agent reading the file sees the directive and understands the structure; the data lives in SQLite and is rendered only inside Pommora.

##### SQLite Schema

Six tables. All rebuilt from files on launch or on demand. Property schemas live inside per-Vault `_vault.json` files (canonical) and the Agenda layer's `_agenda.json` (canonical), loaded into memory at app start.

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

- **Property values** in Page YAML frontmatter (`.md`), Item `properties` key (`.json`), or Agenda item `properties` key (`.agenda.json`).
- **Property schemas** live inside each Vault's `_vault.json` (Vault-wide in v1; Collection-local schemas are a post-v1 Prospect). Agenda items use a parallel `_agenda.json` with **two built-in properties** (`type` Select + `status` Status) plus user-extensible additions.
- **Properties are scoped per Vault** and created via the Vault Settings sheet (Notion-style — see `// Features//Vaults.md` "Vault Settings sheet" section).
- **Members must conform to the Vault's schema.** Ad-hoc page-local properties are out of v1 scope (Prospect).
- **V1 catalog (10 types):** number, checkbox, date, date & time, select, multi-select, URL, relation, **status**, and **last edited time** (auto-property). **No free-form text type** — title is the filename; "text-shaped" values use Select / Multi-select with creatable options. **Status is a first-class type** with 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done), each containing user-editable options. Group LABELS are user-renamable; the 3 structural slots are fixed to preserve EventKit compatibility at v0.7.0.
- **Every property can carry an icon.** SF Symbol via `IconPickerField` — shown next to property name in schema editor, property panel, column headers.
- **Relations are paired by default.** Vault- and Collection-scoped Relation properties REQUIRE dual configuration — creating one atomically creates a paired reverse property on the target Vault. Context-tier-scoped relations stay one-way (Contexts have no `properties[]` schema).
- **Inline option creation forbidden.** Options for Select / Multi-select / Status are added only via the schema editor (Vault Settings → Edit Properties), reachable via right-click "Edit options…" on any property value or "Manage options…" link at the bottom of every value picker. Value pickers consume options; they don't produce them.
- **Move-strip rule (Notion-style):** moving a Page or Item across Vaults strips properties not in the destination Vault's schema. No quarantine, no backup. The user gets a **simple confirmation warning** listing which properties will be stripped before the move proceeds. v0.3.0 implements this (pulled forward from v0.4.0 since it's tightly coupled to property schema).

Full type catalog, config shapes, schema-mutation rules → `// Features//Properties.md`. Implementation phases → `// Planning//v0.3.0-Properties-implementation.md`.

##### View Directives

Five view types in v1:

| Type | Renderer | Notes |
|---|---|---|
| **Table** | Stack-native data table | Sortable columns, inline cell edit |
| **Board** | Kanban layout | Cards grouped by a property's options. v0.9 ships the visual layout (edit a card via the card UI to "move" it between columns). Drag-to-rewrite-frontmatter is a planned follow-up post-v1.0 foundations. |
| **List** | Plain list | Title plus selected inline properties |
| **Gallery** | Grid layout | Cards with cover image |
| **Cards** | Grid layout | Cards without cover-first emphasis |

**Two contexts where views appear:**

1. **Inside a Vault** — saved views configured per-Vault, stored in `_vault.json`. Switch via tabs above the view area. Views can scope to specific Collection sub-folders or span the whole Vault.
2. **Embedded as a widget** — the "Embedded Collection View" widget renders any saved Vault view inside a composed-blocks surface (Context page, Homepage), with per-embed overrides on filter / sort / group / shown-properties. Per the inline-editing principle, embedded views are **fully editable in place** — not read-only snapshots.

Each view spec carries: source Vault (implicit from sidecar location), optional Collection-path scoping, view type, filter expression, sort, group-by property, properties to display, and (for gallery) cover image property. Filter expressions parse to a small DSL and translate to parameterized `json_extract` SQL queries. **Filters and sorts on a view never modify the source Vault** — purely view-local.

In-line view embeds *inside Page bodies* (a `@View` directive in prose) are out of v1. The v2+ revisit is feasible on Option 2 (WKWebView + JS editor); harder on Option 1 (native editor) due to layout-attachment complexity.

##### Columns

The `@Columns` directive is supported in both Pages and Spaces. **V1 columns are equidistant** — widths divide the available horizontal space evenly by child count. No per-column width configuration in v1.

Implementation is deferred to the editor build; the directive ships as a Pommora-specific render with equidistant child columns (file format stays standard `:::columns` Markdown on disk).

##### Sidebar Navigation

The sidebar surfaces curated, app-relevant navigation, not filesystem layout. Four top-level groups, the last three collapsible disclosure groups (all default-collapsed). **The user can drag the headings to reorder them**; initial-boot order is **(heading-less pinned section) / Spaces / Topics / Vaults**.

- **Pinned (heading-less, at top)** — three fixed entries (Homepage / Calendar / Recents); labels renamable via Settings. Structurally a `Section` wrapper to host future user-pinned pages (at which point it gains a "Saved" heading); renders without a header text today. `Homepage` opens the singleton dashboard entity; `Calendar` opens a calendar view over Agenda + EventKit-mirrored system events; `Recents` shows recently-opened tabs.
- **Spaces** — flat rows for tier-1 Contexts. Each Space row shows a color/symbol indicator (tagging style settable).
- **Topics** — chevron-disclosure rows for tier-2 Contexts. Expanded view shows file-nested Sub-topics. Topic rows carry inherited tagging from parent Space(s); multi-Space Topics show multi-color/symbol indicators.
- **Vaults** — chevron-disclosure rows for Vaults. Expanded view shows **Pages directly in the vault root + Collection sub-folders** as children; each Collection further discloses its own Pages. Pages render with the `doc.text` icon; Collections with the `folder` icon.

**Items, Agenda items, and Events do NOT appear in the sidebar** — they live exclusively in the detail-pane Tables (`VaultDetailView`, `CollectionDetailView`). The sidebar tree is the structural / Page-shaped view; the detail pane is the full data view. Cosmetic folders (at the nexus root, without `_vault.json`) are user-driven filesystem organization with no semantic meaning to Pommora. No raw filesystem view in v1.

**Creation is right-click-only.** No always-visible "+ New" buttons anywhere — users right-click headings, rows, or section areas to open a context menu whose "New X" options auto-scope to the cursor location (right-click on a Vault → "New Collection / New Page" both scoped to THAT Vault; right-click on a Collection → "New Page" in THAT Collection; etc.). Quick-capture (Cmd+Shift+N or menu-bar; pre-v1) is the planned discoverable counterpart for global creation.

"Collapsed-by-default disclosure" is the general default for any hierarchical UI elsewhere in the app. Full sidebar spec → `Features/Sidebar.md`.

##### Three-Pane Shell + Property Panel

Sidebar (default 240px) / main (flex) / inspector (default 280px). Both side panes are drag-resizable via splitters from v0.0 onward; resized widths persist across launches. Default window size 1200×800; minimum 960×560 (keeps both side panes legible). The inspector's **default view is the property panel** for the active Page in v1; an **AI chat interface** is a planned future addition to the inspector (post-v1; a frontend to Nathan's existing local CLI — not an API integration; see `// Features//Prospects.md`). (Items don't use the inspector — they open in an Item window. See "Item Window" below.)

**Window chrome — macOS unified title bar.** No separate Pommora title bar. The macOS traffic-light buttons render in the top-left at runtime (OS-rendered, not custom) within the sidebar pane's column. A single horizontal band — the unified toolbar (`.windowToolbarStyle(.unified(showsTitle: false))`) — holds the sidebar toggle, back/forward arrows, the NavDropdown trigger button, and the inspector toggle, all in the same row as the traffic lights. No second toolbar row. Pattern: Mail / Notes / Finder on macOS.

Below-heading and page-bottom property-panel placements are post-v1 Prospects.

Built on SwiftUI's two-column `NavigationSplitView(sidebar:detail:)` with the inspector pane attached to the detail column via the `.inspector(isPresented:)` modifier (macOS 14+). This is Apple's idiomatic pattern for main-pane + supplementary side panel — used by Mail, Notes, and Pages. Inspector width is set via `.inspectorColumnWidth(min:ideal:max:)`; the toolbar toggle integrates automatically via `InspectorCommands`. The third-column variant of `NavigationSplitView` was considered and rejected — that column is designed for selected-item drill-down (Mail's list → message-list → message), not for a contextual supplementary panel.

##### Nav Dropdown

The main pane is **single-pane.** Navigation history lives in a **Liquid Glass dropdown button** (SF Symbol `square.on.square`) in the toolbar — opening a popover with two toggleable lists: **Favorites** (user-curated via hover-star) and **Recents** (auto-tracked LRU). Replaces the original v0.2.8 "Top-Bar Tabs" model — pivot locked 2026-05-18. Pattern reference: Things 3 Quick Find, Notes.app Move-To popover.

Clicking a row in the dropdown opens the entity in a **standalone macOS window** (`WindowGroup(for: EntityRef.self)` within the same Pommora process — draggable, resizable, not a separate app instance). The window carries a minimal toolbar with an **Expand** button that promotes the entity into the main detail pane and dismisses the standalone window. Recents records ONLY on commit-to-main-frame — dismissing the standalone window without expanding does NOT update Recents.

- **Open the dropdown** — `⌘T` or click the toolbar button.
- **Walk Recents** — back / forward arrows in the toolbar, or `⌘[` / `⌘]`.
- **Favorite an entry** — hover a row, click the star. Hover-star is the only entry point.
- **Recents cap** — 500 in the underlying store; dropdown displays top 100; sidebar full-frame Recents view (v0.6.0+) shows the full 500 with sort + filter.
- **Favorites** — uncapped, separate Codable array, insertion-ordered.

Entity roster: Pages, Vaults, Spaces, Topics, Sub-topics, Items (popover-only, `ItemWindow`), Agenda items (v0.6.0+, chip label "Task"). Collections excluded for v0.2.7.2 simplicity. Homepage never appears.

**State persistence:** Recents + Favorites + back/forward cursor persist across launches. Stored in `<nexus>/.nexus/state.json` (per-nexus, vault-portable).

**Items don't get standalone windows** — selecting an Item from the dropdown opens its `ItemWindow` popover directly (the popover IS the opening surface, so Recents records immediately).

Full implementation spec at `// Features//NavDropdown.md`.

##### Item Window

Items don't open as tabs or in the inspector. Selecting an Item — from a detail-pane Table row, a table cell in a Collection view, a wikilink, or an embedded Collection view — opens an **Item window**: a popover-style floating surface anchored to where the click occurred. Reference: Calendar.app event-detail popover; macOS Finder's Get Info window. (Items don't appear in the sidebar, so there's no sidebar trigger — Item discovery happens in detail-pane views.)

The window contains:

- **Title** — the filename, editable in place (rename retitles the underlying `.json` file).
- **Icon** — optional SF Symbol via TextField (curated SymbolPicker UI deferred to polish).
- **Properties** — typed inputs for each property in the parent **Vault's schema** (via `PropertyEditorRow` dispatching per `PropertyType`). Items always belong to exactly one Vault — no "loose" Item state.
- **Description** — plain-text field, **hard cap 250 characters**. Sized so the field fits within the window without scrolling; keeps the JSON file small and cloud-sync-friendly.
- **Tier 1 / Tier 2 / Tier 3 relations** — read-only ULID display in v0.2; full relation picker UI lands v0.3.0 (shared `ContextTierPicker` component, parent-grouped — tier-2 by parent Space, tier-3 by parent Topic).
- **Meta footer** — `id`, `created_at`, `modified_at` read-only.

Dismissed by clicking Done, pressing Esc, or closing the window. Save commits via `ContentManager.updateItem` (with a `renameItem` pre-step if the title changed).

##### First-Launch Experience

On first launch, after the user picks a nexus location, Pommora opens with empty sidebars plus a single seeded **Homepage singleton entity** at `.nexus// homepage.json` (NOT a Space), opened as the landing surface via the pinned `Homepage` row at the top of the sidebar. Per-Nexus singletons auto-seed on first manager init: Homepage + Agenda schema sidecar + `tier-config.json` + `saved-config.json`. No tutorial, no walkthrough wizard.

##### Design System

SwiftUI native idioms (semantic colors, Materials, Font scale, SF Symbols) plus a small set of Pommora-brand Color/Font extensions for values SwiftUI doesn't cover (accent, code, callout, blockquote). v1 ships with one initial scheme plus in-app customization for accent color and font size (Framework v0.12). Full design philosophy, component conventions, brand-value placement → `// Guidelines//UIX-Guide.md`. React-side reference (~118-token Figma system) at `// ReactInfo// Styling-Tokens.md`.

##### File Renames and Wikilink Updates

Renames are automatic and atomic. When a Page is renamed:

1. Pommora locates every wikilink targeting the old name using the `links` index — one indexed query, not a nexus-wide scan.
2. Inside one transaction: rename the file on disk; update the Page's `path` in SQLite; rewrite every `[[Old Name]]` reference to `[[New Name]]` across referencing Pages; write each affected file atomically (`.tmp` + `rename`).
3. The file watcher coalesces resulting change events.

**Wikilink resolution rules:**

- `[[Page Name]]` resolves by basename match (Obsidian-style).
- If two Pages share a basename, disambiguation uses path: `[[Notes// Roadmap]]` vs. `[[Personal// Roadmap]]`.
- Renaming a Page with ambiguous siblings updates only the references that resolve to it.
- Wikilinks render as styled colored inline text (Obsidian-style), not Notion-style chips.

Relation properties store target IDs and display the target's current title (resolved at render time; renames update display automatically).

##### Data, State, File Watching

**State.** `@Observable` macro (Swift 5.9+, mature in 6.2) is the standard — per-property tracking eliminates wasteful redraws; `@State` replaces `@StateObject`. Heavy services (NexusIndex, parsers) stay in DI, not view state, to avoid re-init on view rebuild.

**Persistence.** `GRDB.swift v7.5+` is the established SQLite toolkit for Pommora's "SQLite as index, files canonical" shape. The relevant primitives — `ValueObservation.tracking { db in ... }` for observation, `.values(in:)` returning an `AsyncSequence` over change notifications, and `FTS5Pattern` for full-text — are documented and stable.

SwiftData isn't a fit — it wraps Core Data and doesn't expose a custom SQLite schema or FTS5 directly, both of which Pommora needs.

**Code shape.** A pure Swift Package for the data + parsing layer keeps SwiftUI imports out of it so the same code remains callable from a CLI tool target if useful. An `actor` wrapping the database boundary, `Sendable` records, and `AsyncSequence` surfaces (preferred over Combine in Swift 6 strict concurrency) fit the documented GRDB APIs — `.values(in:)` serves as the data-to-UI reactive surface directly. Not enforced architecture (see `// Features//Architecture.md`).

**File watching.** `DispatchSource.makeFileSystemObjectSource` is per-fd (no recursion) — wrong tool for nexus-folder watching. Use FSEventStream via a Swift wrapper (`EonilFSEvents`, or hand-rolled `FSEventStreamCreate`). APFS / atomic-rename gotchas: editor save = `.tmp` write + rename emits create+delete events; debounce 50–100ms by path; track outbound mtimes to ignore Pommora's own writes.

> If pivoting to React, see `// ReactInfo// StateData.md` for the Zustand + hand-rolled pub/sub + `@parcel/watcher` equivalent.

##### Mac OS Integration

Areas where SwiftUI is first-party (no companion bundles needed):

- **QuickLook (.md preview via Finder spacebar).** Ship a `QLPreviewProvider` subclass via a QuickLook Preview Extension target; declare `QLSupportedContentTypes` for `net.daringfireball.markdown`. Renders Pommora pages straight from Finder.
- **CoreSpotlight (nexus-wide system search).** `CSSearchableItem` + `CSSearchableItemAttributeSet` indexes pages into Spotlight; `.onContinueUserActivity(CSSearchableItemActionType)` deep-links results back into Pommora.
- **Share Extension (receive shares from Safari/Mail).** Add a Share Extension target conforming to `NSExtensionPrincipalClass`. Standard macOS pattern.
- **NSServices ("New Pommora Page from Selection").** Declare in `Info.plist`, implement selector. One-method handler.
- **MenuBarExtra (macOS 13+).** First-party menu-bar item; `.menuBarExtraStyle(.window)` enables rich popovers; instant, native-feel.
- **Sidebar vibrancy + accent.** `NSVisualEffectView` via SwiftUI's `Material` (`.regular`, `.sidebar`, etc.); automatic accent color via `Color.accentColor`; reactive theme integration.
- **Finder file-promise drag-out.** Native via `Transferable` + `.draggable` — drag a page from the sidebar to Finder writes the file at the drop location.
- **Accessibility (VoiceOver, Dynamic Type, keyboard nav).** First-party modifiers (`.accessibilityLabel/Hint/Value/Action`); Dynamic Type free; VoiceOver rotor support free.
- **Window state restoration with Spaces.** `Scene` + `@SceneStorage` integrates with NSWindow restoration including macOS Spaces.
- **Deep links.** `.onOpenURL` + `Info.plist` `CFBundleURLTypes` for `pommora://` URLs.

> If pivoting to React, see `// ReactInfo// MacIntegration.md` for the Electron ceilings, companion-bundle territory, and hard ceilings on each of the above.

##### Distribution

- **Sparkle 2.x** is the non-MAS auto-update standard (EdDSA-signed, sandbox-compatible, full SwiftUI support via `SPUStandardUpdaterController`).
- **TestFlight for Mac** is fully shipped — same capabilities as iOS.
- **Sandboxing for MAS:** user-picked nexus folders work via security-scoped bookmarks (`URL.bookmarkData(options: .withSecurityScope)`) persisted and resolved with `startAccessingSecurityScopedResource()` on each launch. Standard pattern; no feature blocker.

> If pivoting to React, see `// ReactInfo// Distribution.md` for the electron-vite + electron-builder + electron-updater + `@electron/notarize` equivalent.

---

#### v1 Scope

**In:**

- **Contexts** (3 tiers — Spaces / Topics / Sub-topics) — composed-blocks surfaces; tier labels user-configurable per-Nexus. Spaces flat in sidebar; Topics chevron-disclosure expanding to file-nested Sub-topics. Tier-skip allowed; same-tier file-structural links forbidden. Sub-topics carry `linked_relations` as typed multi-valued property.
- **Vaults + Collections + Content (Pages + Items)** — Vaults are kind-agnostic folders with shared schema; Collections are sub-folders inheriting Vault schema (no own schema in v1); Pages (`.md`) and Items (`.json`) live inside.
- **Pages** — Markdown documents with YAML frontmatter (including per-tier multi-relations `tier1` / `tier2` / `tier3`); editor surface is one of two SwiftUI options. Standard Markdown plus two Pommora-specific rendering directives (`@Columns` + `:::callout`).
- **Items** — `.json` files. Filename = title; conform to parent Vault's schema; `id`, `icon`, `description` (250-char cap), `tier1/2/3` multi-relations, timestamps. Open in an Item Window (popover), not a tab.
- **Agenda** — `.agenda.json` files at `<nexus>/Agenda/`. Unified entity (no kind discriminator); `properties.type` Select for user-facing categorization. EventKit-bridgeable based on which time fields are populated. EventKit sync opt-in.
- **Homepage** — singleton composed-blocks dashboard at `.nexus/homepage.json`. Seeded on first launch.
- Property panel UI driven by Vault and Agenda schemas, all v1 property types (10) including Status with EventKit-aligned groups; Vault Settings sheet centralizes schema editing + sort + property visibility (filter/group/layout placeholders fill in at v0.6.0).
- Wikilinks (styled colored inline text).
- Automatic file rename with cross-nexus wikilink rewrite.
- File watcher keeping SQLite synced.
- Global search (SQLite FTS5 over Page bodies and frontmatter).
- Four-section sidebar (Saved / Spaces / Topics / Vaults), user-reorderable, default-collapsed. Agenda accessed via Saved → Calendar entry.
- **Inline editing of embedded views** — every embed in a composed-blocks surface (Context, Homepage) is a live editable view of its source (not a snapshot).
- Single initial design scheme, plus in-app customization for accent color and font size (Framework v0.12). SwiftUI native handles everything else.

**Out (post-v1):**

Post-v1 features — additional view types, block features, sync, mobile, plugins, ad-hoc properties, multi-Collection pages, independent UI titles, in-line view embeds in Pages, chip wikilinks, Item ↔ Page promotion, board view drag-to-rewrite-frontmatter, etc. — live in `// Features//Prospects.md`. Items move from Prospects into `Framework.md` when committed.
