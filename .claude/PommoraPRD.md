### Pommora — Product Requirements Document

> Living document. Captures the vision, scope, and key architectural decisions for Pommora.

---

#### Vision

Personal management platform combining Obsidian's customization + local-first ethos with Notion's database and view capabilities. Pages are Markdown files inside **Page Types** (folder-based database entities holding property schemas + saved views); Items are JSON row records inside **Item Types** (parallel container layer for the Items side); **Page Collections** and **Item Collections** are organizational sub-folders sharing each Type's schema; **Contexts** (Spaces / Topics / Projects — 3-tier) are composed-blocks dashboard surfaces. UI label divergence: Pages-side UI defaults to "Vault" + "Collection"; Items-side UI defaults to "Type" + "Set" (each side has one signature word + one shared word). A simpler Notion that's also a more capable Obsidian — without the trade-offs that push users to bounce between the two.

#### Why

- **Obsidian** gives UI-level customization + a transparent local-first file model, but its Markdown core can't express columns, side-by-side callouts, or in-line filtered views without heavy plugins.
- **Notion's** in-line database views (filtered, sorted, regrouped per page without altering source) are its defining feature; Obsidian's file-as-document architecture can't match this natively.
- Obsidian shines until you need real task management or cross-page coordination. Notion shines until you hit an interface decision you can't change.

Pommora's bet: a Markdown-canonical foundation with SQLite as the property + query engine, and clean separation between content (Pages), data (Items), structure (Page Types + Item Types + their Collections), and interface (Contexts), delivers Notion's most-loved features without giving up Obsidian's open, hackable, local-first nature.

#### Audience and Posture

- Personal-first, single-user, Mac-first for v1. Linux/Windows aren't on the v1 path (would need a React rebuild). iOS/iPad is long-term intent (SwiftUI ships there for free).
- Always open-source.
- Architected so future cross-device + cloud sync remain viable, but not v1 concerns. Multi-user collaboration + plugin system are out of scope indefinitely.

---

#### Domain Model

Two layers, PARA-aligned (ParadigmV2 refactor 2026-05-22):

- **Organization — Contexts** (3 tiers): Spaces (tier 1, broad life domains) / Topics (tier 2, subject areas) / **Projects** (tier 3). All composed-blocks surfaces under `.nexus/spaces/` and `.nexus/topics/`. Per-tier labels user-configurable per-Nexus.
- **Operational — Items + Pages + Agenda:**
  - **Pages side:** **Page Type** (root folder + `_pagetype.json`) contains **Page Collections** (sub-folders + `_pagecollection.json` carrying id + type_id + ordering) which contain **Pages** (`.md`). UI labels default to "Vault" + "Collection".
  - **Items side:** **Item Type** (root folder + `_itemtype.json`) contains **Item Collections** (sub-folders + `_itemcollection.json`) which contain **Items** (`.json`). UI labels default to "Type" + "Set".
  - **Agenda:** split into **Agenda Tasks** (`.task.json`, EKReminder-aligned) and **Agenda Events** (`.event.json`, EKEvent-aligned) inside their respective singleton folders at the nexus root — the folder carrying `_taskconfig.json` is the Tasks singleton; the folder carrying `_eventconfig.json` is the Events singleton (sidecar-driven discovery; folder name renameable via Finder). EventKit integration via separate access permissions per kind.
- **No wrapper folders.** All operational containers — Page Types, Item Types, Tasks singleton, Events singleton — live directly at the nexus root. Sidecar filename alone classifies each folder.
- **Singleton — Homepage** (`.nexus/homepage.json`) — composed-blocks dashboard, one per Nexus.
- **Settings scaffold** (`.nexus/settings.json`) — per-Nexus user-overridable UI labels + accent color.

Code-layer naming is symmetric (`PageType` / `PageCollection` / `ItemType` / `ItemCollection`); UI label vocabulary diverges per side. "Pommora" is prohibited in on-disk JSON field names and Swift type discriminators (`Pommora.X`) — side-prefixed names are canonical (`AgendaTask`, not `Pommora.Task`).

Full definitions, on-disk shapes, linking model → `// Features//Domain-Model.md` + per-entity files (`Contexts.md`, `PageTypes.md`, `Pages.md`, `Items.md`, `Agenda.md`, `Homepage.md`).

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

2. **Cross-nexus queryability + cloud sync compatibility.** Types and Collections aren't isolated — any Page or Context can query/link/embed any Type's contents regardless of folder location. On-disk model maps cleanly to a cloud DB: shared `pages` table with `page_type_id` + `page_collection_id` + `properties` JSONB; parallel `items` table with `item_type_id` + `item_collection_id`; one `page_types` row per `_pagetype.json`; parallel `item_types` row per `_itemtype.json`; `agenda_tasks` + `agenda_events` tables; one `spaces` row per `.space.json`. Sync arrives as additive translation. V1 gets device-to-device sync free via nexus in iCloud/Dropbox/any synced folder. **Reference convention:** relations stored by ID (rename-safe); body wikilinks use names (rewritten on rename).

3. **Persistent immediate legibility for agents.** External agents (Claude, MCP clients, any tool with filesystem access) read Pommora's entire structured graph — Pages, Items, Collection schemas, Spaces, relations, properties — directly from files without tool-call round-trips. SQLite is performance scaffolding, not source of truth. Differentiator from Notion-via-MCP (tool-mediated, opaque) and Obsidian (locally legible but unstructured). Choices that trade file-canonical legibility for app-internal convenience violate this constraint.

##### Storage Model

**Nexus location:** user-pickable on first launch; default `~//PommoraNexus//`. Can sit in iCloud Drive / Dropbox / any synced folder for free device-to-device sync. Path persisted via security-scoped bookmark in app-level state; sandbox enabled from v0.1a (forward-compatible with MAS).

**On disk:**

```
<picked nexus folder>//                    ← canonical content lives here, syncs with cloud
  Assignments//                             ← Page Type (folder + _pagetype.json; UI label "Vault")
    _pagetype.json                          ← shared schema for Pages inside
    Spring-2026//                           ← Page Collection (sub-folder + _pagecollection.json; UI label "Collection")
      _pagecollection.json                  ← per-Collection metadata (id + type_id + page_order)
      Essay-1.md                            ← Page
    Final-Project.md                        ← Page directly in Page Type (no Collection)

  Notes//                                   ← Page Type
    _pagetype.json
    Tech-stack-tradeoffs.md                 ← Page

  Bookmarks//                               ← Item Type (folder + _itemtype.json; UI label "Type")
    _itemtype.json
    Tech//                                  ← Item Collection (sub-folder + _itemcollection.json; UI label "Set")
      _itemcollection.json                  ← per-Collection metadata (id + type_id + item_order)
      Swift-evolution.json                  ← Item
    Hacker-News.json                        ← Item directly in Item Type (no Collection)

  Books//                                   ← Item Type
    _itemtype.json
    Atomic-Habits.json

  Tasks//                                   ← AgendaTask singleton (folder carrying _taskconfig.json)
    _taskconfig.json                        ← AgendaTask schema (EKReminder-aligned)
    Submit-grant-proposal.task.json

  Events//                                  ← AgendaEvent singleton (folder carrying _eventconfig.json)
    _eventconfig.json                       ← AgendaEvent schema (EKEvent-aligned)
    Team-standup.event.json

  .nexus//                                  ← app-internal config (nexus-portable, syncs)
    nexus.json                              ← v0.1a: ULID + createdAt
    state.json                              ← v0.2+: open tabs, sidebar UI state
    settings.json                           ← v0.3.0 ParadigmV2: user-overridable UI labels + accent color
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
        CS-161.project.json                 ← tier-3 Project, file-structural parent = this folder
        Linear-Algebra.project.json
      Productivity//
        _topic.json                         ← parents: [Personal-id, Work-id] (multi-Space)
        GTD-method.project.json

  .trash//                                  ← Deleted entities (nexus-local trash; v1+)
    Assignments//
      Old-essay.md                          ← Preserves original relative path under the source Type

~//Library//Application Support//com.nathantaichman.Pommora//   ← machine-specific, never syncs
  state.json                                ← Codable AppState: bookmark + future recent-nexuses
  nexuses//
    <nexus-id>//                            ← keyed by ULID from .nexus/nexus.json
      nexus.db                              ← SQLite index (v0.2+); regeneratable
      cache//                               ← future
```

A folder at the nexus root containing `_pagetype.json` is a **Page Type**; a folder at the nexus root containing `_itemtype.json` is an **Item Type**. Sub-folders inside a Page Type carrying `_pagecollection.json` are **Page Collections** (sharing the Type's schema; sidecar carries only id + type_id + page_order); same shape with `_itemcollection.json` inside an Item Type defines an **Item Collection**. The Tasks singleton is the root folder carrying `_taskconfig.json`; the Events singleton is the root folder carrying `_eventconfig.json` (sidecar-driven discovery — folder name is renameable via Finder). All classification is by sidecar filename; folder location at root + sidecar presence alone identifies kind. App-internal config sits in `.nexus//` (hidden, matches `.obsidian` convention) and holds Contexts + Homepage singleton + tier/saved config + Settings. Deletes go to `.trash//` at the nexus root, preserving original relative path under each source Type.

**Why the SQLite index lives outside the nexus:** `nexus.db` inside an iCloud/Dropbox-synced vault risks file-conflict-driven corruption (SQLite's locking assumes single-host filesystem semantics). The Application Support per-nexus subdir is keyed by ULID (survives vault rename/move) and marked `isExcludedFromBackupKey` so iCloud Backup skips the regeneratable index.

##### Pages

`.md` file with YAML frontmatter (`id` ULID, `icon`, per-tier multi-relations `tier1`/`tier2`/`tier3`, property values from parent Page Type's schema; no `page_type` or `title` field — filename = title, parent Page Type is implicit by file location) + Markdown body. Pages conform to the Page Type's schema; ad-hoc page-local properties are out of v1 (Prospect).

Pages are Markdown documents, not block surfaces — one continuous stream. Standard Markdown (headings H1–H5, lists, code blocks + inline code (SF Mono; `code//` tokens), images, GFM tables, blockquotes, HRs) plus two Pommora rendering directives: **`@Columns`** (`:::columns` fenced section; renders N equidistant horizontal columns; layout-only, content inside is standard Markdown) and **`:::callout`** (outlined-box, distinct from blockquotes' left-side emphasis bar; border binds to `callout//` token).

Both directives resolve to inert text + standard Markdown for external tools (Notion's Markdown export principle). Headings are foldable by default (chevron collapses until next equal-or-higher heading); no `:::toggle` construct, no on-disk syntax. Blocks belong to Spaces only. `@View` in-line embeds in Page bodies are out of v1 (TextKit 2 layout-attachment complexity); embedded views remain available inside Spaces. Full detail → `// Features//Pages.md`.

##### Page Types + Item Types

Symmetric operational-layer container layer (ParadigmV2). Both kinds:

- **Page Type** — folder at `<nexus>/<Title>/` + `_pagetype.json` sidecar (`id`, `icon`, `properties[]` shared schema, `views[]`, `collection_order`, `page_order`). Title = folder name. **Page Collections** are sub-folders inside a Page Type, sharing the Type's schema (their own `_pagecollection.json` carries `id` + `type_id` + `page_order` only). UI label "Vault" / "Collection" by default. Full detail → `// Features//PageTypes.md`.
- **Item Type** — folder at `<nexus>/<Title>/` + `_itemtype.json` sidecar (mirror shape, plus `item_order`, `template_config` reserved). **Item Collections** are sub-folders inside an Item Type, each carrying `_itemcollection.json`. UI label "Type" / "Set" by default. Full detail → `// Features//Items.md`.

Both Types have no text-editor surface — pure database viewers (table / board / list / cards / gallery). Move-strip applies cross-Type (Page across Page Types, Item across Item Types). Schema-bearing layer + organizational sub-folder layer is the locked pattern across both sides.

##### Contexts (Spaces / Topics / Projects)

Three-tier organization layer; all three are composed-blocks surfaces. Tier-1 Spaces: `.nexus/spaces/<Title>.space.json` (carries `color`, tier-1 only). Tier-2 Topics: `.nexus/topics/<Title>/_topic.json` (multi-parent across Spaces). Tier-3 **Projects**: `.nexus/topics/<TopicFolder>/<Title>.project.json` (single file-structural parent + `linked_relations` typed property). Tier labels user-configurable per-Nexus (Capacities-style singular + plural). Same `blocks` shape as Homepage. Full detail → `// Features//Contexts.md`.

##### Agenda

Calendar-anchored items split into two distinct entities (ParadigmV2):

- **Agenda Tasks** — `.task.json` files inside the Tasks singleton folder at the nexus root (the root folder carrying `_taskconfig.json`; default name `Tasks/`, renameable via Finder). EKReminder-aligned: `due_at` (optional), `start_at` (optional "not before"), `completed`, `priority` (0–9), `recurrence`, `alarm_offsets`, required **built-in `status` Status** (EventKit-aligned 3-group; non-deletable; bridges to `EKReminder.isCompleted`).
- **Agenda Events** — `.event.json` files inside the Events singleton folder at the nexus root (the root folder carrying `_eventconfig.json`; default name `Events/`, renameable via Finder). EKEvent-aligned: required `start_at` + `end_at`, optional `location`, `all_day`, `recurrence`, `alarm_offsets`, `alarm_absolute`. No built-in Status (events derive effective state from `start_at` / `end_at` relative to now — completion isn't an event concept). Users may add Status manually if useful.

Schemas live in per-side per-kind sidecars: the Tasks singleton's `_taskconfig.json` (AgendaTask schema) and the Events singleton's `_eventconfig.json` (AgendaEvent schema). Sidecar-driven discovery — first root folder found carrying each sidecar wins; if no folder carries the sidecar on a brand-new nexus, managers eagerly seed `Tasks/` + `Events/` at the root on launch. Swift type names are `AgendaTask` and `AgendaEvent` (prefixed to avoid `_Concurrency.Task` and `Event` stdlib collisions; the "no `Pommora.X` qualification" rule rejects `Pommora.Task`). UI labels remain "Task" / "Event" (renameable via Settings).

EventKit requires `com.apple.security.personal-information.calendars` entitlement + `NSCalendarsFullAccessUsageDescription` / `NSRemindersFullAccessUsageDescription` keys + modern `requestFullAccessTo*` APIs (separate permissions per kind). EventKit sync opt-in via Settings (data layer ships v0.3.0; sync ships v0.6.0). Agenda has NO dedicated sidebar section — surfaces via the Calendar pin entry. Full detail → `// Features//Agenda.md`.

##### Homepage

Singleton composed-blocks dashboard at `.nexus/homepage.json`. No `id`/`tier`/`parents` — file location is identity. Same `blocks` shape as Contexts; designed to embed anything. Seeded on first launch; not user-deletable. Full detail → `// Features//Homepage.md`.

##### Local-End Translation Principle

**The local file is the spec, not the render.** Anything SQLite computes — board view contents, gallery cards, aggregated counts, relation lookups — is referenced by directive, never inlined. Agents read the directive and understand structure; data lives in SQLite, rendered only inside Pommora.

##### SQLite Schema

Eight tables, rebuilt from files on launch or demand. Property schemas live in each Type's per-kind sidecar (`_pagetype.json` / `_itemtype.json`) and each Agenda kind's per-kind sidecar (`_taskconfig.json` / `_eventconfig.json`) — all canonical on disk, loaded into memory at app start.

```sql
-- Page index (rebuilt from .md files inside any Page Type folder at the nexus root)
CREATE TABLE pages (
  id TEXT PRIMARY KEY,                -- ULID from frontmatter
  path TEXT UNIQUE NOT NULL,          -- 'Assignments/Spring-2026/Essay-1.md'
  page_type_id TEXT NOT NULL,         -- derived from path (containing Page Type folder)
  page_collection_id TEXT,            -- nullable; populated when Page lives inside a Page Collection
  title TEXT NOT NULL,                -- derived from filename (basename minus '.md')
  icon TEXT,
  frontmatter JSON NOT NULL,          -- includes tier1/tier2/tier3 ID arrays + properties
  body TEXT NOT NULL,                 -- raw markdown body (powers FTS)
  modified_at INTEGER NOT NULL
);

-- Item index (rebuilt from .json files inside any Item Type folder at the nexus root)
CREATE TABLE items (
  id TEXT PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,          -- 'Bookmarks/Tech/Swift-evolution.json'
  item_type_id TEXT NOT NULL,
  item_collection_id TEXT,            -- nullable; populated when Item lives inside an Item Collection
  title TEXT NOT NULL,
  icon TEXT,
  description TEXT,                   -- short plain-text field, 250-char cap
  properties JSON NOT NULL,
  tier1 JSON NOT NULL,                -- array of Space IDs
  tier2 JSON NOT NULL,                -- array of Topic IDs
  tier3 JSON NOT NULL,                -- array of Project IDs (post-ParadigmV2 rename from Sub-topic)
  modified_at INTEGER NOT NULL
);

-- Agenda Task index (rebuilt from .task.json files in the Tasks singleton folder at the nexus root)
CREATE TABLE agenda_tasks (
  id TEXT PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,          -- 'Tasks/Submit-grant-proposal.task.json'
  title TEXT NOT NULL,
  icon TEXT,
  due_at TEXT,                        -- ISO-8601; nullable (EKReminder.dueDateComponents)
  start_at TEXT,                      -- ISO-8601; nullable (EKReminder "not before")
  completed INTEGER NOT NULL,         -- bool
  completed_at TEXT,                  -- ISO-8601; nullable
  priority INTEGER NOT NULL,          -- 0-9 (EKReminder.priority)
  eventkit_uuid TEXT,                 -- nullable; populated when synced to EKEventStore
  calendar_id TEXT,                   -- EKCalendar identifier; nullable
  properties JSON NOT NULL,           -- includes required built-in `status` Status (EventKit-bridged)
  tier1 JSON NOT NULL,
  tier2 JSON NOT NULL,
  tier3 JSON NOT NULL,
  modified_at INTEGER NOT NULL
);

-- Agenda Event index (rebuilt from .event.json files in the Events singleton folder at the nexus root)
CREATE TABLE agenda_events (
  id TEXT PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,          -- 'Events/Team-standup.event.json'
  title TEXT NOT NULL,
  icon TEXT,
  start_at TEXT NOT NULL,             -- ISO-8601 (EKEvent.startDate; required)
  end_at TEXT NOT NULL,               -- ISO-8601 (EKEvent.endDate; required)
  all_day INTEGER NOT NULL,           -- bool
  location TEXT,                      -- EKEvent.location; nullable
  eventkit_uuid TEXT,                 -- nullable
  calendar_id TEXT,                   -- nullable
  properties JSON NOT NULL,           -- user-defined only; no built-in fields (events derive state from start_at/end_at)
  tier1 JSON NOT NULL,
  tier2 JSON NOT NULL,
  tier3 JSON NOT NULL,
  modified_at INTEGER NOT NULL
);

-- Page Type index (rebuilt from <nexus>/<Title>/_pagetype.json files at the root)
CREATE TABLE page_types (
  id TEXT PRIMARY KEY,
  folder_path TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,                -- derived from folder name
  icon TEXT,
  properties JSON NOT NULL,           -- shared schema for Pages inside
  views JSON NOT NULL,
  modified_at INTEGER NOT NULL
);

-- Item Type index (rebuilt from <nexus>/<Title>/_itemtype.json files at the root)
CREATE TABLE item_types (
  id TEXT PRIMARY KEY,
  folder_path TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  icon TEXT,
  properties JSON NOT NULL,
  views JSON NOT NULL,
  template_config JSON,               -- reserved (null in v0.3.0); per-Item-Type template
  modified_at INTEGER NOT NULL
);

-- Contexts (Tiers) index — Spaces / Topics / Projects share one table, discriminated by level
CREATE TABLE tiers (
  id TEXT PRIMARY KEY,
  level INTEGER NOT NULL,             -- 1 (Space) | 2 (Topic) | 3 (Project)
  path TEXT UNIQUE NOT NULL,          -- file path inside .nexus/spaces or .nexus/topics
  title TEXT NOT NULL,
  icon TEXT,
  color TEXT,                         -- tier-1 only; nullable for tier 2/3
  parents JSON NOT NULL,              -- array of tier IDs at lower levels (file-structural for tier 3 Projects)
  linked_relations JSON NOT NULL,     -- additional non-file relations (tier 3 Projects only; empty array for tier 1/2)
  blocks JSON NOT NULL,               -- composed-page block tree
  modified_at INTEGER NOT NULL
);

-- Link index (rebuilt from files)
CREATE TABLE links (
  from_id TEXT NOT NULL,         -- page, item, agenda_task, agenda_event, tier id
  from_kind TEXT NOT NULL,       -- 'page' | 'item' | 'agenda_task' | 'agenda_event' | 'tier'
  to_id TEXT NOT NULL,
  to_kind TEXT NOT NULL,         -- 'page' | 'item' | 'agenda_task' | 'agenda_event' | 'tier' | 'page_type' | 'item_type'
  property TEXT                  -- NULL for inline wikilinks; 'tier1', 'tier2', 'tier3', 'linked_relations', etc.
);

CREATE INDEX idx_pages_type ON pages(page_type_id);
CREATE INDEX idx_pages_collection ON pages(page_collection_id);
CREATE INDEX idx_items_type ON items(item_type_id);
CREATE INDEX idx_items_collection ON items(item_collection_id);
CREATE INDEX idx_agenda_tasks_due ON agenda_tasks(due_at);
CREATE INDEX idx_agenda_tasks_completed ON agenda_tasks(completed);
CREATE INDEX idx_agenda_events_start ON agenda_events(start_at);
CREATE INDEX idx_tiers_level ON tiers(level);
CREATE INDEX idx_links_from ON links(from_id, from_kind);
CREATE INDEX idx_links_to   ON links(to_id, to_kind);
```

Queries use SQLite's JSON1 extension to reach into property values and tier-relation arrays:

```sql
-- All Pages in the "Notes" Page Type tagged to a specific Topic
SELECT * FROM pages
WHERE page_type_id = '01H...notes-page-type-id'
  AND EXISTS (SELECT 1 FROM json_each(json_extract(frontmatter, '$.tier2'))
              WHERE value = '01H...topic-id');

-- All incomplete Agenda Tasks due in the next 7 days
SELECT * FROM agenda_tasks
WHERE completed = 0
  AND due_at BETWEEN datetime('now') AND datetime('now', '+7 days');

-- All Agenda Events starting in the next 7 days
SELECT * FROM agenda_events
WHERE start_at BETWEEN datetime('now') AND datetime('now', '+7 days');
```

##### Property Model

- **Values** in Page YAML frontmatter (`.md`), Item `properties` (`.json`), AgendaTask `properties` (`.task.json`), or AgendaEvent `properties` (`.event.json`). **Schemas** live in each Type's per-kind sidecar (`_pagetype.json` / `_itemtype.json`) and each Agenda kind's per-kind sidecar (`_taskconfig.json` / `_eventconfig.json`). Collection-local overrides remain a post-v1 Prospect — Page Collections + Item Collections inherit their parent Type's schema in v0.3.0.
- **Scoped per Type**, created via per-Type Settings sheet (Page Type Settings sheet on Pages side; Item Type Settings sheet on Items side — Notion-style). Members must conform; ad-hoc page-local properties out of v1 (Prospect).
- **V1 catalog (10 types):** number, checkbox, date, date & time, select, multi-select, URL, relation, **status**, **last edited time** (auto). No free-form text — filename = title; "text-shaped" values use Select/Multi-select with creatable options. **Status** has 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done) with user-editable options; group LABELS renamable, 3 structural slots fixed for EventKit compatibility. Status is built-in required on AgendaTask schema; NOT on AgendaEvent schema; NOT auto-seeded on Page Types or Item Types.
- **Every property can carry an icon** (SF Symbol via `IconPickerField`).
- **Relations are paired by default** — creating a Type-scoped or Collection-scoped Relation atomically creates the reverse on the target. Four container/sub-folder relation scopes: `page_type(id)`, `item_type(id)`, `page_collection(id)`, `item_collection(id)`. Context-tier-scoped relations (`context_tier(N)`) stay one-way (Contexts have no `properties[]` schema).
- **Inline option creation forbidden.** Select/Multi-select/Status options come only from the schema editor (per-Type Settings → Edit Properties), reachable via right-click "Edit options…" or "Manage options…" link in every value picker.
- **Move-strip rule (Notion-style):** moving a Page across Page Types or an Item across Item Types strips properties not in the destination schema (no quarantine; confirmation warning lists strips). Implemented v0.3.0 (pulled forward from v0.4.0).

Full catalog, config shapes, schema-mutation rules → `// Features//Properties.md`. Implementation plan → `// Planning//v0.3.0-Properties-plan.md`.

##### View Directives

Five view types in v1:

| Type | Renderer | Notes |
|---|---|---|
| **Table** | Stack-native data table | Sortable columns, inline cell edit |
| **Board** | Kanban layout | Cards grouped by a property's options. v0.9 ships visual layout (edit via card UI to "move" between columns); drag-to-rewrite-frontmatter is post-v1.0. |
| **List** | Plain list | Title + selected inline properties |
| **Gallery** | Grid | Cards with cover image |
| **Cards** | Grid | Cards without cover-first emphasis |

Views appear in two contexts: (1) **inside a Type** — saved views in the Type's per-kind sidecar (`_pagetype.json` or `_itemtype.json`), switch via tabs, scope to Collection sub-folders or whole Type; (2) **embedded as a widget** — "Embedded Collection View" renders any saved Type view inside a Context/Homepage with per-embed overrides on filter/sort/group/shown-properties. Per the inline-editing principle, embedded views are fully editable in place.

Each view spec: source Type (implicit from sidecar location), optional Collection-path scoping, view type, filter expression, sort, group-by property, properties to display, cover image (gallery). Filter expressions parse to a small DSL translating to parameterized `json_extract` SQL. View filters/sorts never modify the source Type.

In-line `@View` embeds *inside Page bodies* are out of v1 (TextKit 2 layout-attachment complexity); v2+ feasible if Pommora pivots to JS-editor + WKWebView (see `// Features//Prospects.md`).

##### Columns

`@Columns` supported in Pages and Spaces. **V1 columns are equidistant** — widths divide available space evenly by child count; no per-column width config in v1. Ships as Pommora-specific render; file format stays standard `:::columns` Markdown on disk.

##### Sidebar Navigation

Surfaces curated, app-relevant navigation, not filesystem layout. Five top-level groups; last four are default-collapsed disclosure groups. User can drag headings to reorder; initial-boot order: **(heading-less pinned section) / Spaces / Topics / Items / Pages**. Items sits above Pages — quicker-capture entities ride higher in the visual hierarchy. No dedicated Agenda section — Agenda Tasks + Agenda Events surface via the Pinned section's Calendar entry.

- **Pinned (heading-less, top)** — three fixed entries (Homepage / Calendar / Recents); labels renamable via Settings. Structurally a `Section` wrapper to host future user-pinned pages (gains "Saved" heading then). `Homepage` opens the singleton dashboard; `Calendar` opens calendar view over Agenda Tasks + Agenda Events + EventKit-mirrored events; `Recents` shows recently-opened tabs.
- **Spaces** — flat rows for tier-1 Contexts; color/symbol indicator (tagging style settable).
- **Topics** — chevron-disclosure for tier-2 Contexts; expanded shows file-nested Projects (tier-3). Inherited tagging from parent Space(s); multi-Space Topics show multi-color/symbol.
- **Items** (default label, renameable via Settings) — chevron-disclosure for Item Types (UI label "Type" by default). Each Type discloses Item Collections (UI label "Set"). Items themselves do NOT appear in the sidebar — they live in the detail-pane Table.
- **Pages** (default label, renameable via Settings) — chevron-disclosure for Page Types (UI label "Vault" by default). Each Type discloses Page Collections (UI label "Collection") + root Pages. Pages: `doc.text` icon; Collections: `folder` icon.

Items, Agenda Tasks, and Agenda Events do NOT appear in the sidebar — they live in detail-pane Tables (`ItemTypeDetailView` / `ItemCollectionDetailView` / `PageTypeDetailView` / `PageCollectionDetailView`) or the Calendar surface. Section headings (Items / Pages) classify root folders by sidecar filename — Pages-section rows are root folders carrying `_pagetype.json`; Items-section rows are root folders carrying `_itemtype.json`. The Tasks + Events singletons surface via the Calendar pin entry, not as sidebar rows. No raw filesystem view in v1.

**Creation is right-click-only.** No "+ New" buttons; right-click headings/rows/sections opens a context menu with "New X" options auto-scoped to the cursor location. Pages-side rows ship designed at v0.3.0 (New Vault / New Collection / New Page / Rename / Delete); Items-side rows ship as minimal stubs at v0.3.0 (designed UI lands in a follow-up plan). Quick-capture (Cmd+Shift+N or menu-bar; pre-v1) is the discoverable counterpart for global creation. Collapsed-by-default disclosure is the general default for hierarchical UI. Full spec → `// Features//Sidebar.md`.

##### Three-Pane Shell + Property Surfaces

Sidebar (default 240px) / main (flex) / inspector (default 280px). Both side panes drag-resizable from v0.0; widths persist across launches. Default window 1200×800; minimum 960×560.

**Main-window inspector hosts the Claude chat** (frontend to Nathan's local CLI, not an API integration; subprocess bridge) — ships in a v0.3.x patch, whenever designed. **Properties do NOT live in the main-window inspector.** They live in three different surfaces depending on context (locked 2026-05-23 brainstorm — full spec at [[Properties]] § "Where Properties Live"):

| Surface | Property home |
|---|---|
| **Page in main window** | NavDropdown-style pulldown at top of content (populated-only + "+ Add property" picker; lazy properties) |
| **Page Preview** (standalone window, PreviewWindow primitive) | Property panel inside the window's own inspector (toggle, default closed) |
| **Item Window** (popover) | Property panel inside the popover's own inspector (toggle, default closed) + pinned-property chips above title, saved at Item Collection level |

**Window chrome — macOS unified title bar.** No separate Pommora title bar. Traffic-lights render OS-rendered in the sidebar pane's column. A single unified toolbar (`.windowToolbarStyle(.unified(showsTitle: false))`) holds sidebar toggle, back/forward arrows, NavDropdown trigger, and inspector toggle, all in the same row as traffic-lights. No second toolbar row. Pattern: Mail / Notes / Finder.

Built on SwiftUI's two-column `NavigationSplitView(sidebar:detail:)` with inspector attached via `.inspector(isPresented:)` (macOS 14+) — Apple's idiomatic pattern (Mail, Notes, Pages). Width via `.inspectorColumnWidth(min:ideal:max:)`; toolbar toggle via `InspectorCommands`. The three-column `NavigationSplitView` variant was rejected — that column is for selected-item drill-down (Mail's list → message-list → message), not a contextual supplementary panel.

##### Nav Dropdown

Main pane is **single-pane.** Navigation history lives in a Liquid Glass dropdown button (SF Symbol `square.on.square`) in the toolbar — popover with two toggleable lists: **Pinned** (user-curated via right-click) and **Recents** (auto-tracked LRU). Replaces the earlier "Top-Bar Tabs" model. Pattern: Things 3 Quick Find, Notes.app Move-To popover.

Single-click highlights, double-click opens in main detail pane. Items open in the existing `ItemWindow` popover; standalone-window previews deferred to the cross-feature PreviewWindow primitive (`// Guidelines//CRUD-Patterns.md → Preview-window prerequisite`). Keyboard: `⌘T` opens dropdown; `⌘[` / `⌘]` walk Recents back/forward. State persists in `<nexus>/.nexus/state.json` (per-nexus, vault-portable); Pinned uncapped; Recents store cap 500; dropdown shows top 100; full-frame Recents view (v0.6.0) shows the full store.

Shipped at v0.2.7.1. Full spec → `// Features//NavDropdown.md`.

##### Item Window

Items open in a popover-style floating surface (Calendar-app event-detail pattern) anchored to click location — not in tabs, not in the inspector. Holds title (editable filename) + icon + parent Item Type's schema property editors + 250-char description + tier1/2/3 relations + read-only meta footer (`id`/`created_at`/`modified_at`). Save commits via `ItemContentManager.updateItem`. Full spec + v0.3.1 modal-window redesign → `// Features//Items.md`.

##### First-Launch Experience

After the user picks a nexus location, Pommora opens with empty sidebars plus a seeded Homepage singleton at `.nexus/homepage.json` (NOT a Space) as the landing surface via the pinned `Homepage` row. Per-Nexus singletons auto-seed on first manager init: Homepage + `tier-config.json` + `saved-config.json` + `settings.json` (ParadigmV2 — carries UI labels + accent color) + Tasks singleton folder (default `Tasks/`) carrying `_taskconfig.json` + Events singleton folder (default `Events/`) carrying `_eventconfig.json`. No tutorial, no walkthrough wizard.

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

- **Contexts** (3 tiers — Spaces / Topics / **Projects**) — composed-blocks surfaces; tier labels per-Nexus configurable. Spaces flat in sidebar; Topics chevron-disclose to file-nested Projects. Tier-skip allowed; same-tier file-structural links forbidden. Projects carry `linked_relations` as typed multi-valued property.
- **Page Types + Page Collections + Pages** (Pages side) and **Item Types + Item Collections + Items** (Items side) — symmetric container layers (ParadigmV2). Each Type carries its per-kind sidecar (`_pagetype.json` / `_itemtype.json`); Collections are sub-folders sharing the Type's schema (their `_pagecollection.json` / `_itemcollection.json` carries id + type_id + ordering only). UI labels: Pages get "Vault" + "Collection"; Items get "Type" + "Set" (renameable via Settings).
- **Pages** — Markdown + YAML frontmatter (incl. per-tier multi-relations `tier1`/`tier2`/`tier3`); editor = native TextKit 2 + `swift-markdown` + vendored `swift-markdown-engine` (shipped v0.2.7.0). Standard Markdown + `@Columns` + `:::callout` directives.
- **Items** — `.json`. Filename = title; conform to parent Item Type's schema; `id`, `icon`, `description` (250-char), `tier1/2/3`, timestamps. Open in Item Window popover, not a tab.
- **Agenda** — split into **Agenda Tasks** (`.task.json`, EKReminder-aligned) and **Agenda Events** (`.event.json`, EKEvent-aligned) inside their respective root-level singleton folders (the folder carrying `_taskconfig.json` is the Tasks singleton; the folder carrying `_eventconfig.json` is the Events singleton). Required `status` Status property on Agenda Tasks (built-in, non-deletable, EventKit-bridged); not auto-seeded on Agenda Events. Sync opt-in (data layer ships v0.3.0; sync ships v0.6.0). NO sidebar section — Calendar pin entry surfaces both kinds.
- **Homepage** — singleton dashboard at `.nexus/homepage.json`. Seeded on first launch.
- **Settings scaffold** (ParadigmV2 v0.3.0) — `.nexus/settings.json` + `SettingsManager` + UI label wiring across all renameable surfaces + accent color reading. Settings editing UI ships v0.6.0; v0.3.0 ships storage + label-read plumbing + Cmd+, stub scene.
- Property panel UI driven by Page Type / Item Type / AgendaTask / AgendaEvent schemas; all v1 types (10) incl. Status with EventKit-aligned groups; per-Type Settings sheet centralizes schema editing + sort + property visibility (filter/group/layout placeholders fill in at v0.6.0).
- Wikilinks (styled colored inline text).
- Automatic file rename with cross-nexus wikilink rewrite.
- File watcher keeping SQLite synced.
- Global search (SQLite FTS5 over Page bodies + frontmatter).
- Five-section sidebar (Pinned / Spaces / Topics / Items / Pages), user-reorderable, default-collapsed. Agenda surfaces via Pinned → Calendar.
- **Inline editing of embedded views** — every embed in a composed-blocks surface is a live editable view of its source.
- One initial design scheme + in-app accent color + font size customization (folded into v0.6.0 Settings UI on top of the v0.3.0 Settings scaffold); SwiftUI native handles everything else.

**Out (post-v1):** additional view types, block features, sync, mobile, plugins, ad-hoc properties, multi-Collection pages, independent UI titles, in-line view embeds in Pages, chip wikilinks, Item ↔ Page cross-side promotion, board view drag-to-rewrite-frontmatter, per-Item-Type templates, full Settings editing UI, etc. — see `// Features//Prospects.md`. Items move from Prospects into `Framework.md` when committed.
