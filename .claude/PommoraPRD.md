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

Two layers, PARA-aligned:

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
| Database | SQLite via GRDB.swift 6.29.3 (FTS5 + `ValueObservation`) |
| Markdown parser | `apple/swift-markdown` (parse only; hand-rolled writer for save path) |
| File watcher | FSEventStream via Swift wrapper |
| Icons | SF Symbols via `Image(systemName:)` |

> If pivoting to React, see `// ReactInfo//Contingency.md` + `// ReactInfo//ReactInfo.md`.

##### Three load-bearing constraints

1. **Stack portability of functionalities.** File formats, SQLite schema, domain model, property catalog, directive syntax, wikilink behavior, view directives, design values, UX patterns survive a stack rebuild — the codebase doesn't. No enforced layer separation; portability comes from documented decisions. Detail → `// Features//Architecture.md`.

2. **Cross-nexus queryability + cloud sync compatibility.** Types and Collections aren't isolated — any Page or Context can query/link/embed any Type's contents regardless of folder location. On-disk model maps cleanly to a cloud DB: shared `pages` table with `page_type_id` + `page_collection_id` + `properties` JSONB; parallel `items` table with `item_type_id` + `item_collection_id`; one `page_types` row per `_pagetype.json`; parallel `item_types` row per `_itemtype.json`; `agenda_tasks` + `agenda_events` tables; one `contexts` row per Space / Topic / Project. Sync arrives as additive translation. V1 gets device-to-device sync free via nexus in iCloud/Dropbox/any synced folder. **Reference convention:** relations stored by ID (rename-safe); body wikilinks use names (rewritten on rename).

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

  .nexus//                                  ← app-internal config + index (nexus-portable, syncs)
    nexus.json                              ← v0.1a: ULID + createdAt
    state.json                              ← v0.2+: open tabs, sidebar UI state
    settings.json                           ← user-overridable UI labels + accent color
    tier-config.json                        ← Contexts tier labels (singular + plural)
    saved-config.json                       ← Saved-section item labels
    homepage.json                           ← singleton Homepage entity (composed blocks)
    index.db                                ← SQLite index (v0.2+); regeneratable, schema-versioned
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
```

Classification is by sidecar filename alone: folder location at the nexus root plus sidecar presence identifies kind (`_pagetype.json` → Page Type, `_itemtype.json` → Item Type; `_taskconfig.json` / `_eventconfig.json` mark the Tasks / Events singletons — folder names renameable via Finder). App-internal config sits in `.nexus//` (hidden, matches `.obsidian` convention) and holds Contexts + Homepage singleton + tier/saved config + Settings + the SQLite index. Deletes go to `.trash//` at the nexus root, preserving original relative path under each source Type.

**Why the SQLite index lives inside the nexus:** the index is `<nexus>/.nexus/index.db` — it travels with the vault, so a moved or renamed nexus keeps its index without re-pathing. It holds no user data (titles, properties, links, relations only — never Page bodies), so it is fully regeneratable: `PommoraIndex.open` stamps the file with a `schema_version` and force-deletes + rebuilds via `IndexBuilder` whenever that version differs from the code's `currentSchemaVersion`. The Application Support tree holds only machine-specific `state.json` (security-scoped bookmark + recent-nexuses).

##### Pages

`.md` file with YAML frontmatter (`id` ULID, `icon`, per-tier multi-relations `tier1`/`tier2`/`tier3`, property values from parent Page Type's schema; no `page_type` or `title` field — filename = title, parent Page Type is implicit by file location) + Markdown body. Pages conform to the Page Type's schema; ad-hoc page-local properties are out of v1 (Prospect).

Pages are Markdown documents, not block surfaces — one continuous stream. Standard Markdown (headings H1–H5, lists, code blocks + inline code (SF Mono; `code//` tokens), images, GFM tables, blockquotes, HRs) plus two Pommora rendering directives: **`@Columns`** (`:::columns` fenced section; renders N equidistant horizontal columns; layout-only, content inside is standard Markdown) and **`:::callout`** (outlined-box, distinct from blockquotes' left-side emphasis bar; border binds to `callout//` token).

Both directives resolve to inert text + standard Markdown for external tools (Notion's Markdown export principle). Headings are foldable by default (chevron collapses until next equal-or-higher heading); no `:::toggle` construct, no on-disk syntax. Blocks belong to Spaces only. `@View` in-line embeds in Page bodies are out of v1 (TextKit 2 layout-attachment complexity); embedded views remain available inside Spaces. Full detail → `// Features//Pages.md`.

##### Page Types + Item Types

Symmetric operational-layer container layer. Both kinds:

- **Page Type** — folder at `<nexus>/<Title>/` + `_pagetype.json` sidecar (`id`, `icon`, `properties[]` shared schema, `views[]`, `collection_order`, `page_order`). Title = folder name. **Page Collections** are sub-folders inside a Page Type, sharing the Type's schema (their own `_pagecollection.json` carries `id` + `type_id` + `page_order` only). UI label "Vault" / "Collection" by default. Full detail → `// Features//PageTypes.md`.
- **Item Type** — folder at `<nexus>/<Title>/` + `_itemtype.json` sidecar (mirror shape, plus `item_order`, `template_config` reserved). **Item Collections** are sub-folders inside an Item Type, each carrying `_itemcollection.json`. UI label "Type" / "Set" by default. Full detail → `// Features//Items.md`.

Both Types have no text-editor surface — pure database viewers (table / board / list / cards / gallery). Move-strip applies cross-Type (Page across Page Types, Item across Item Types). Schema-bearing layer + organizational sub-folder layer is the shared pattern across both sides.

##### Contexts (Spaces / Topics / Projects)

Three-tier organization layer; all three are composed-blocks surfaces. Tier-1 Spaces: `.nexus/spaces/<Title>.space.json` (carries `color`, tier-1 only). Tier-2 Topics: `.nexus/topics/<Title>/_topic.json` (multi-parent across Spaces). Tier-3 **Projects**: `.nexus/topics/<TopicFolder>/<Title>.project.json` (single file-structural parent + `linked_relations` typed property). Tier labels user-configurable per-Nexus (Capacities-style singular + plural). Same `blocks` shape as Homepage. Full detail → `// Features//Contexts.md`.

##### Agenda

Calendar-anchored items split into two distinct entities:

- **Agenda Tasks** — `.task.json` files inside the Tasks singleton folder at the nexus root (the root folder carrying `_taskconfig.json`; default name `Tasks/`, renameable via Finder). EKReminder-aligned: `due_at` (optional), `start_at` (optional "not before"), `completed`, `priority` (0–9), `recurrence`, `alarm_offsets`, required **built-in `status` Status** (EventKit-aligned 3-group; non-deletable; bridges to `EKReminder.isCompleted`).
- **Agenda Events** — `.event.json` files inside the Events singleton folder at the nexus root (the root folder carrying `_eventconfig.json`; default name `Events/`, renameable via Finder). EKEvent-aligned: required `start_at` + `end_at`, optional `location`, `all_day`, `recurrence`, `alarm_offsets`, `alarm_absolute`. Required **built-in `status` Status** (same 3 EventKit-aligned groups as AgendaTask; user-set, decoupled from `start_at` / `end_at` date math — the user marks status to track their own engagement with the event).

Schemas live in per-side per-kind sidecars: the Tasks singleton's `_taskconfig.json` (AgendaTask schema) and the Events singleton's `_eventconfig.json` (AgendaEvent schema). Sidecar-driven discovery — first root folder found carrying each sidecar wins; if no folder carries the sidecar on a brand-new nexus, managers eagerly seed `Tasks/` + `Events/` at the root on launch. Swift type names are `AgendaTask` and `AgendaEvent` (prefixed to avoid `_Concurrency.Task` and `Event` stdlib collisions; the "no `Pommora.X` qualification" rule rejects `Pommora.Task`). UI labels remain "Task" / "Event" (renameable via Settings).

EventKit requires `com.apple.security.personal-information.calendars` entitlement + `NSCalendarsFullAccessUsageDescription` / `NSRemindersFullAccessUsageDescription` keys + modern `requestFullAccessTo*` APIs (separate permissions per kind). EventKit sync opt-in via Settings (data layer ships v0.3.0; sync ships v0.6.0). Agenda has NO dedicated sidebar section — surfaces via the Calendar pin entry. Full detail → `// Features//Agenda.md`.

##### Homepage

Singleton composed-blocks dashboard at `.nexus/homepage.json`. No `id`/`tier`/`parents` — file location is identity. Same `blocks` shape as Contexts; designed to embed anything. Seeded on first launch; not user-deletable. Full detail → `// Features//Homepage.md`.

##### Local-End Translation Principle

**The local file is the spec, not the render.** Anything SQLite computes — board view contents, gallery cards, aggregated counts, relation lookups — is referenced by directive, never inlined. Agents read the directive and understand structure; data lives in SQLite, rendered only inside Pommora.

##### SQLite Schema

Twelve data tables plus an internal `meta` table, rebuilt from files on launch or demand. The index stores titles, properties, links, and relations — **not** Page bodies or frontmatter (the `pages` table has no body column; full-text search reads files). Property schemas live in each Type's per-kind sidecar (`_pagetype.json` / `_itemtype.json`) and each Agenda kind's per-kind sidecar (`_taskconfig.json` / `_eventconfig.json`) — all canonical on disk, loaded into memory at app start. DDL lives in `Index/IndexSchema.swift`.

```sql
-- Page Type index (one row per <nexus>/<Title>/_pagetype.json at the root)
CREATE TABLE page_types (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  icon TEXT,
  modified_at TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1
);

-- Item Type index (one row per <nexus>/<Title>/_itemtype.json at the root)
CREATE TABLE item_types (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  icon TEXT,
  modified_at TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1
);

-- Page Collection index (sub-folders inside a Page Type)
CREATE TABLE page_collections (
  id TEXT PRIMARY KEY,
  page_type_id TEXT NOT NULL REFERENCES page_types(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  modified_at TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1
);

-- Item Collection index (sub-folders inside an Item Type)
CREATE TABLE item_collections (
  id TEXT PRIMARY KEY,
  item_type_id TEXT NOT NULL REFERENCES item_types(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  modified_at TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1
);

-- Page index (rebuilt from .md files inside any Page Type folder; no body/frontmatter columns)
CREATE TABLE pages (
  id TEXT PRIMARY KEY,                                                       -- ULID from frontmatter
  page_type_id TEXT NOT NULL REFERENCES page_types(id) ON DELETE CASCADE,
  page_collection_id TEXT REFERENCES page_collections(id) ON DELETE SET NULL, -- nullable
  title TEXT NOT NULL,                                                       -- derived from filename
  properties TEXT NOT NULL DEFAULT '{}',                                     -- JSON; property values
  modified_at TEXT NOT NULL
);

-- Item index (rebuilt from .json files inside any Item Type folder)
CREATE TABLE items (
  id TEXT PRIMARY KEY,
  item_type_id TEXT NOT NULL REFERENCES item_types(id) ON DELETE CASCADE,
  item_collection_id TEXT REFERENCES item_collections(id) ON DELETE SET NULL, -- nullable
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',                                       -- 250-char cap
  properties TEXT NOT NULL DEFAULT '{}',                                     -- JSON
  modified_at TEXT NOT NULL
);

-- Agenda Task index (rebuilt from .task.json files in the Tasks singleton folder)
CREATE TABLE agenda_tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  due_at TEXT,                        -- ISO-8601; nullable (EKReminder.dueDateComponents)
  properties TEXT NOT NULL DEFAULT '{}', -- JSON; includes required built-in `status` Status
  modified_at TEXT NOT NULL
);

-- Agenda Event index (rebuilt from .event.json files in the Events singleton folder)
CREATE TABLE agenda_events (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  start_at TEXT NOT NULL,             -- ISO-8601 (EKEvent.startDate; required)
  end_at TEXT NOT NULL,               -- ISO-8601 (EKEvent.endDate; required)
  properties TEXT NOT NULL DEFAULT '{}', -- JSON; includes required built-in `status` Status
  modified_at TEXT NOT NULL
);

-- Contexts index — Spaces / Topics / Projects share one table, discriminated by tier
CREATE TABLE contexts (
  id TEXT PRIMARY KEY,
  tier INTEGER NOT NULL,              -- 1 (Space) | 2 (Topic) | 3 (Project)
  title TEXT NOT NULL,
  parent_topic_id TEXT                -- tier-3 Projects: file-structural parent Topic; nullable for tier 1/2
);

-- Relation index — property-typed links (paired relations, tier relations via property_id)
CREATE TABLE relations (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL,
  source_kind TEXT NOT NULL,          -- 'page' | 'item' | 'agenda_task' | 'agenda_event'
  target_id TEXT NOT NULL,
  target_kind TEXT NOT NULL,
  property_id TEXT NOT NULL,
  modified_at TEXT NOT NULL
);

-- Tier-link index — tier1/tier2/tier3 membership (composite PK)
CREATE TABLE tier_links (
  entity_id TEXT NOT NULL,
  entity_kind TEXT NOT NULL,          -- 'page' | 'item' | 'agenda_task' | 'agenda_event'
  tier INTEGER NOT NULL,              -- 1 | 2 | 3
  target_id TEXT NOT NULL,            -- Context ID
  PRIMARY KEY (entity_id, entity_kind, tier, target_id)
);

-- Property-definition index (one row per property in any Type's schema)
CREATE TABLE property_definitions (
  id TEXT PRIMARY KEY,
  owning_type_id TEXT NOT NULL,
  owning_type_kind TEXT NOT NULL,     -- 'page_type' | 'item_type' | 'agenda_task' | 'agenda_event'
  name TEXT NOT NULL,                 -- renameable display label
  type TEXT NOT NULL,                 -- property type tag
  config TEXT NOT NULL DEFAULT '{}',  -- JSON; per-type config (options, formats, etc.)
  position INTEGER NOT NULL DEFAULT 0,
  modified_at TEXT NOT NULL
);

CREATE INDEX idx_pages_page_type_id ON pages(page_type_id);
CREATE INDEX idx_pages_page_collection_id ON pages(page_collection_id);
CREATE INDEX idx_items_item_type_id ON items(item_type_id);
CREATE INDEX idx_items_item_collection_id ON items(item_collection_id);
CREATE INDEX idx_page_collections_page_type_id ON page_collections(page_type_id);
CREATE INDEX idx_item_collections_item_type_id ON item_collections(item_type_id);
CREATE INDEX idx_relations_source_id ON relations(source_id);
CREATE INDEX idx_relations_target_id ON relations(target_id);
CREATE INDEX idx_relations_property_id ON relations(property_id);
CREATE INDEX idx_tier_links_entity ON tier_links(entity_id, entity_kind);
CREATE INDEX idx_tier_links_target ON tier_links(target_id);
CREATE INDEX idx_property_definitions_owning_type ON property_definitions(owning_type_id, owning_type_kind);
CREATE INDEX idx_contexts_tier ON contexts(tier);
CREATE INDEX idx_contexts_parent_topic ON contexts(parent_topic_id);
```

The internal `meta(key, value)` table holds the global `schema_version`; on mismatch with the code's `currentSchemaVersion`, the whole index file is deleted and rebuilt. Queries use SQLite's JSON1 extension to reach into the `properties` JSON, and join `tier_links` / `relations` for tier-relation and paired-relation lookups:

```sql
-- All Pages in the "Notes" Page Type tagged to a specific Topic
SELECT p.* FROM pages p
JOIN tier_links tl ON tl.entity_id = p.id AND tl.entity_kind = 'page' AND tl.tier = 2
WHERE p.page_type_id = '01H...notes-page-type-id'
  AND tl.target_id = '01H...topic-id';

-- All Agenda Tasks due in the next 7 days
SELECT * FROM agenda_tasks
WHERE due_at BETWEEN datetime('now') AND datetime('now', '+7 days');

-- All Agenda Events starting in the next 7 days
SELECT * FROM agenda_events
WHERE start_at BETWEEN datetime('now') AND datetime('now', '+7 days');
```

##### Property Model

- **Values** in Page YAML frontmatter (`.md`), Item `properties` (`.json`), AgendaTask `properties` (`.task.json`), or AgendaEvent `properties` (`.event.json`). **Schemas** live in each Type's per-kind sidecar (`_pagetype.json` / `_itemtype.json`) and each Agenda kind's per-kind sidecar (`_taskconfig.json` / `_eventconfig.json`). Collection-local overrides remain a post-v1 Prospect — Page Collections + Item Collections inherit their parent Type's schema in v0.3.0.
- **Scoped per Type**, created via per-Type Settings sheet (Page Type Settings sheet on Pages side; Item Type Settings sheet on Items side — Notion-style). Members must conform; ad-hoc page-local properties out of v1 (Prospect).
- **V1 catalog (11 types):** Number, Checkbox, Date, Date & Time, Select, Multi-select, Status, URL, Relation, Last Edited Time (auto), File / Attachment. No free-form text — filename = title; "text-shaped" values use Select/Multi-select with creatable options. **Status** has 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done) with user-editable options; group labels renamable, 3 structural slots fixed for EventKit compatibility. Status is built-in required on both AgendaTask AND AgendaEvent schemas; NOT auto-seeded on Page Types or Item Types.
- **Property identity = ID, not name.** Every property in a Type's schema carries a stable ULID `id`; frontmatter / JSON `properties` block keys reference the property ID. `name` is a renameable display label — renames are schema-only (no member-file cascade).
- **Cross-side relations supported.** Pages-side schemas can target Item Types / Item Collections, and vice versa. Cross-side *promotion* (transforming an Item INTO a Page) remains a post-v1 Prospect — different concept.
- **File / Attachment** property type — files copy into `<nexus>/.nexus/attachments/<entity-id>/<original-filename>` on attach; property stores nexus-relative paths. Especially load-bearing for Items.
- **Every property can carry an icon** (SF Symbol via `IconPickerField`).
- **Relations are paired by default** — creating a Type-scoped or Collection-scoped Relation atomically creates the reverse on the target. Four container/sub-folder relation scopes: `page_type(id)`, `item_type(id)`, `page_collection(id)`, `item_collection(id)`. Context-tier-scoped relations (`context_tier(N)`) stay one-way (Contexts have no `properties[]` schema).
- **Inline option creation forbidden.** Select/Multi-select/Status options come only from the schema editor (per-Type Settings → Edit Properties), reachable via right-click "Edit options…" or "Manage options…" link in every value picker.
- **Move-strip rule (Notion-style):** moving a Page across Page Types or an Item across Item Types strips properties not in the destination schema (no quarantine; confirmation warning lists strips). Implemented v0.3.0 (pulled forward from v0.4.0).

Full catalog, config shapes, schema-mutation rules → `// Features//Properties.md`.

##### View Directives

Five view types in v1:

| Type | Renderer | Notes |
|---|---|---|
| **Table** | Stack-native data table | Sortable columns, inline cell edit |
| **Board** | Kanban layout | Cards grouped by a property's options. Visual layout first (edit via card UI to "move" between columns); drag-to-rewrite-frontmatter is post-v1.0. |
| **List** | Plain list | Title + selected inline properties |
| **Gallery** | Grid | Cards with cover image |
| **Cards** | Grid | Cards without cover-first emphasis |

Views appear in two contexts: (1) **inside any storage container** — saved views in each container's sidecar `views[]` (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json`), switch via tabs. Every storage container has its own view surfaces, not just the schema-bearing Types — a Page Collection can carry a Board view independent of the parent Page Type's Table; schema is inherited from the Type but the saved-view configuration is per-container. (2) **embedded as a widget** — "Embedded Collection View" renders any saved view inside a Context/Homepage with per-embed overrides on filter/sort/group/shown-properties. Per the inline-editing principle, embedded views are fully editable in place.

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

**Creation is right-click-only.** No "+ New" buttons; right-click headings/rows/sections opens a context menu with "New X" options auto-scoped to the cursor location. Both Pages-side and Items-side rows ship designed (New Vault / New Collection / New Page on the Pages side; New Set / New Item on the Items side; Vault Settings… / Type Settings… on Type rows for the schema editors). Quick-capture (Cmd+Shift+N or menu-bar; pre-v1) is the discoverable counterpart for global creation. Collapsed-by-default disclosure is the general default for hierarchical UI. Full spec → `// Features//Sidebar.md`.

##### Three-Pane Shell + Property Surfaces

Sidebar (default 240px) / main (flex) / inspector (default 280px). Both side panes drag-resizable from v0.0; widths persist across launches. Default window 1200×800; minimum 960×560.

**Main-window inspector hosts the Claude chat** (frontend to Nathan's local CLI, not an API integration; subprocess bridge) — ships in a v0.3.x patch when designed. **Properties do NOT live in the main-window inspector.** They live in three different surfaces depending on context (full spec at [[Properties]] § "Where Properties Live"):

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

After the user picks a nexus location, Pommora opens with empty sidebars plus a seeded Homepage singleton at `.nexus/homepage.json` (NOT a Space) as the landing surface via the pinned `Homepage` row. Per-Nexus singletons auto-seed on first manager init: Homepage + `tier-config.json` + `saved-config.json` + `settings.json` (user-overridable UI labels + accent color) + Tasks singleton folder (default `Tasks/`) carrying `_taskconfig.json` + Events singleton folder (default `Events/`) carrying `_eventconfig.json`. No tutorial, no walkthrough wizard.

##### Design System

SwiftUI native idioms (semantic colors, Materials, Font scale, SF Symbols) plus small Pommora-brand Color/Font extensions for values SwiftUI doesn't cover (accent, code, callout, blockquote). V1 ships one initial scheme plus in-app customization for accent color and font size (folded into v0.6.0 Settings scaffold). Full design philosophy → `// Guidelines//Design.md`. SF Symbol assignments → `// Guidelines//Symbols.md`.

##### File Renames and Wikilink Resolution

Renames are filesystem renames + nothing else — no cross-file rewrite of wikilinks or relation values is needed because both are ID-keyed. The file watcher updates the SQLite `path` field; references in other files continue to resolve via ULID.

**Wikilink resolution:** disk format `[[Title|01HXYZ...]]` — title is the human-readable label, the ULID after the pipe is the unambiguous reference. The displayed title updates automatically at render time via the ULID; the stored reference never changes. Untargeted `[[Title]]` (typed without autocomplete, or pasted from another tool) resolves by current basename match; ambiguous matches are underlined in the editor. Wikilinks render as styled colored inline text (Obsidian-style), not Notion-style chips. Relation properties store target IDs as `{"$rel": "<ULID>"}` and display the target's current title.

##### Data, State, File Watching

- **State.** `@Observable` macro (Swift 5.9+, mature in 6.2) — per-property tracking; `@State` replaces `@StateObject`. Heavy services (NexusIndex, parsers) stay in DI to avoid re-init on view rebuild.
- **Persistence.** `GRDB.swift` (6.29.3) for "SQLite as index, files canonical": `ValueObservation.tracking { db in ... }`, `.values(in:)` returning `AsyncSequence` change notifications, `FTS5Pattern` for full-text. SwiftData isn't a fit (wraps Core Data; no custom SQLite schema or FTS5 access).
- **Code shape.** Pure Swift Package for data + parsing layer keeps SwiftUI imports out (callable from a CLI target if useful). `actor` wrapping the database boundary, `Sendable` records, `AsyncSequence` surfaces (preferred over Combine in Swift 6 strict concurrency) fit GRDB's `.values(in:)` as the data-to-UI reactive surface. Not enforced (see `// Features//Architecture.md`).
- **File watching.** `DispatchSource.makeFileSystemObjectSource` is per-fd (no recursion) — wrong tool. Use FSEventStream via Swift wrapper (`EonilFSEvents` or hand-rolled `FSEventStreamCreate`). APFS atomic-rename gotchas: editor save = `.tmp` write + rename emits create+delete; debounce 50–100ms by path; track outbound mtimes to ignore Pommora's own writes.

##### Mac OS Integration

SwiftUI-first-party (no companion bundles): **QuickLook** (`QLPreviewProvider` via QuickLook Preview Extension target; `QLSupportedContentTypes` for `net.daringfireball.markdown`); **CoreSpotlight** (`CSSearchableItem` + `CSSearchableItemAttributeSet`; `.onContinueUserActivity(CSSearchableItemActionType)` deep-links); **Share Extension** (target conforming to `NSExtensionPrincipalClass`); **NSServices** ("New Pommora Page from Selection" — Info.plist + selector); **MenuBarExtra** (macOS 13+; `.menuBarExtraStyle(.window)`); **Sidebar vibrancy + accent** (`NSVisualEffectView` via SwiftUI `Material`; auto accent via `Color.accentColor`); **Finder file-promise drag-out** (`Transferable` + `.draggable`); **Accessibility** (`.accessibilityLabel/Hint/Value/Action`; Dynamic Type + VoiceOver rotor free); **Window state restoration with Spaces** (`Scene` + `@SceneStorage` + NSWindow restoration); **Deep links** (`.onOpenURL` + `CFBundleURLTypes` for `pommora://`).


##### Distribution

**Sparkle 2.x** for non-MAS auto-update (EdDSA-signed, sandbox-compatible, SwiftUI via `SPUStandardUpdaterController`). **TestFlight for Mac** fully shipped (same as iOS). **Sandboxing for MAS:** user-picked nexus folders via security-scoped bookmarks (`URL.bookmarkData(options: .withSecurityScope)`), resolved with `startAccessingSecurityScopedResource()` on each launch. No feature blocker.

---

#### v1 Scope

**In:**

- **Contexts** (3 tiers — Spaces / Topics / **Projects**) — composed-blocks surfaces; tier labels per-Nexus configurable. Spaces flat in sidebar; Topics chevron-disclose to file-nested Projects. Tier-skip allowed; same-tier file-structural links forbidden. Projects carry `linked_relations` as typed multi-valued property.
- **Page Types + Page Collections + Pages** (Pages side) and **Item Types + Item Collections + Items** (Items side) — symmetric container layers. Each Type carries its per-kind sidecar (`_pagetype.json` / `_itemtype.json`); Collections are sub-folders sharing the Type's schema (their `_pagecollection.json` / `_itemcollection.json` carries id + type_id + ordering only). UI labels: Pages get "Vault" + "Collection"; Items get "Type" + "Set" (renameable via Settings).
- **Pages** — Markdown + YAML frontmatter (incl. per-tier multi-relations `tier1`/`tier2`/`tier3`); editor = native TextKit 2 + `swift-markdown` + vendored `swift-markdown-engine` (shipped v0.2.7.0). Standard Markdown + `@Columns` + `:::callout` directives.
- **Items** — `.json`. Filename = display title (renameable; not the identity); each Item carries a stable ULID `id`. Conform to parent Item Type's schema; `id`, `icon`, `description` (250-char), `tier1/2/3`, timestamps. Properties keyed by property ID. Open in Item Window popover, not a tab.
- **Agenda** — split into **Agenda Tasks** (`.task.json`, EKReminder-aligned) and **Agenda Events** (`.event.json`, EKEvent-aligned) inside their respective root-level singleton folders (the folder carrying `_taskconfig.json` is the Tasks singleton; the folder carrying `_eventconfig.json` is the Events singleton). Required `status` Status property on both Agenda Tasks and Agenda Events (built-in, non-deletable). AgendaTask bridges to `EKReminder.isCompleted`; AgendaEvent Status is user-set, decoupled from `start_at` / `end_at`. Sync opt-in (data layer ships v0.3.0; sync ships v0.6.0). NO sidebar section — Calendar pin entry surfaces both kinds.
- **Homepage** — singleton dashboard at `.nexus/homepage.json`. Seeded on first launch.
- **Settings scaffold** — `.nexus/settings.json` + `SettingsManager` + UI label wiring across all renameable surfaces + accent color reading. Settings editing UI ships v0.6.0; storage + label-read plumbing + Cmd+, stub scene ship at v0.3.0.
- Property panel UI driven by Page Type / Item Type / AgendaTask / AgendaEvent schemas; all 11 v1 property types incl. Status with EventKit-aligned groups + File / Attachment; per-Type Settings sheet centralizes schema editing (Edit Properties + Templates placeholder). Per-view configuration (Sort / Group By / Filter / Layout / Property Visibility) lives in the View Settings surface; phasing in `Framework.md`.
- Wikilinks (styled colored inline text).
- Automatic file rename with cross-nexus wikilink rewrite.
- File watcher keeping SQLite synced.
- Global search (SQLite FTS5 over Page bodies + frontmatter).
- Five-section sidebar (Pinned / Spaces / Topics / Items / Pages), user-reorderable, default-collapsed. Agenda surfaces via Pinned → Calendar.
- **Inline editing of embedded views** — every embed in a composed-blocks surface is a live editable view of its source.
- One initial design scheme + in-app accent color + font size customization (folded into v0.6.0 Settings UI on top of the v0.3.0 Settings scaffold); SwiftUI native handles everything else.

**Out (post-v1):** additional view types, block features, sync, mobile, plugins, ad-hoc properties, multi-Collection pages, independent UI titles, in-line view embeds in Pages, chip wikilinks, Item ↔ Page cross-side promotion, board view drag-to-rewrite-frontmatter, per-Item-Type templates, full Settings editing UI, etc. — see `// Features//Prospects.md`. Items move from Prospects into `Framework.md` when committed.
