### Pommora — Product Requirements Document

> Living document. Captures the vision, scope, and key architectural decisions for Pommora.

---

#### Vision

Personal management platform combining Obsidian's customization + local-first ethos with Notion's database and view capabilities. Pages are Markdown files inside **Page Types** (folder-based database entities holding property schemas + saved views); **Page Collections** are organizational sub-folders sharing the Type's schema, optionally subdivided by schema-less **Page Sets**; **Contexts** (Areas / Topics / Projects — 3-tier) are free-standing organization surfaces. UI labels default to "Vault" + "Collection" + "Set". A simpler Notion that's also a more capable Obsidian — without the trade-offs that push users to bounce between the two.

#### Why

- **Obsidian** gives UI-level customization + a transparent local-first file model, but its Markdown core can't express columns, side-by-side callouts, or in-line filtered views without heavy plugins.
- **Notion's** in-line database views (filtered, sorted, regrouped per page without altering source) are its defining feature; Obsidian's file-as-document architecture can't match this natively.
- Obsidian shines until you need real task management or cross-page coordination. Notion shines until you hit an interface decision you can't change.

Pommora's bet: a Markdown-canonical foundation with SQLite as the property + query engine, and clean separation between content (Pages), structure (Page Types + Collections), and interface (Contexts), delivers Notion's most-loved features without giving up Obsidian's open, hackable, local-first nature.

#### Audience and Posture

- Personal-first, single-user, Mac-first for v1. Linux/Windows aren't on the v1 path (would need a React rebuild). iOS/iPad is long-term intent (SwiftUI ships there for free).
- Always open-source.
- Architected so future cross-device + cloud sync remain viable, but not v1 concerns. Multi-user collaboration + plugin system are out of scope indefinitely.

---

#### Domain Model

Two layers, PARA-aligned:

- **Organization — Contexts** (3 tiers): Areas (tier 1, broad life domains) / Topics (tier 2, subject areas) / **Projects** (tier 3). Three **free-standing** tiers (no containment, no parents) — each a folder with a config sidecar under `.nexus/areas/`, `.nexus/topics/`, `.nexus/projects/`. Per-tier labels user-configurable per-Nexus.
- **Operational — Pages + Agenda:**
  - **Pages:** **Page Type** (root folder + `_pagetype.json`) contains **Page Collections** (sub-folders + `_pagecollection.json` carrying id + type_id + ordering), optionally subdivided by **Page Sets** (sub-folders + `_pageset.json`; no schema, no views — everything inherits from the Collection), which contain **Pages** (`.md`). Strict three levels — deeper folders are sidecar-less and their pages roll up into the nearest Set. UI labels default to "Vault" + "Collection" + "Set".
  - **Agenda:** split into **Agenda Tasks** (`.task.json`, EKReminder-aligned) and **Agenda Events** (`.event.json`, EKEvent-aligned) inside their respective singleton folders at the nexus root — the folder carrying `_taskconfig.json` is the Tasks singleton; the folder carrying `_eventconfig.json` is the Events singleton (sidecar-driven discovery; folder name renameable via Finder). EventKit integration via separate access permissions per kind.
- **No wrapper folders.** All operational containers — Page Types, Tasks singleton, Events singleton — live directly at the nexus root. Sidecar filename alone classifies each folder.
- **Singleton — Homepage** (`.nexus/homepage.json`) — composed-blocks dashboard, one per Nexus.
- **Settings scaffold** (`.nexus/settings.json`) — per-Nexus user-overridable UI labels + accent color.

"Pommora" is prohibited in on-disk JSON field names and Swift type discriminators (`Pommora.X`) — side-prefixed names are canonical (`AgendaTask`, not `Pommora.Task`).

Full definitions, on-disk shapes, linking model → `// Features//Domain-Model.md` + per-entity files (`Contexts.md`, `PageTypes.md`, `Pages.md`, `Agenda.md`, `Homepage.md`).

---

#### Core Architectural Decisions

##### Stack

Pommora's stack is SwiftUI. **The Pages editor shipped at v0.2.7.0 on native NSTextView + Apple `swift-markdown` 0.8.0 + TextKit 2 + the Pommora-owned `MarkdownPM` package** (Apache 2.0, `External/MarkdownPM/`; originally vendored from `swift-markdown-engine`, folded in-tree + rebuilt 2026-06-03). The native TextKit-2 pivot (after a WKWebView fork attempt) gave Pommora Writing Tools (15.1+), Look Up / Translate, spell-check, IME, and dynamic system colors for free. Full editor spec → `// Features//PageEditor.md`.

| Layer | SwiftUI |
|---|---|
| Desktop shell | SwiftUI on macOS Tahoe (26+) |
| UI framework | SwiftUI primary + AppKit interop where needed (NSTextView/TextKit 2, NSSplitView, NSItemProvider) |
| Styling | SwiftUI native semantic colors / Materials / Font scale + small Pommora-brand `Color` / `Font` extensions (accent + code + callout) |
| Editor (Pages) | Shipped v0.2.7.0, rebuilt 2026-06-03: native NSTextView + `swift-markdown` 0.8.0 + TextKit 2 + the Pommora-owned `MarkdownPM` package (`External/MarkdownPM/`). One owned `MarkdownPMStyler` (with an `AppleASTSupplementalStyler` AST helper) covers BlockQuote / Strikethrough / Table; emphasis locates on the Apple AST; HR/ThematicBreak is sole-written by the HR-visibility service. `MarkdownTextLayoutFragment.draw` overrides are the extension point for HR + Blockquote + Tables work. |
| Areas composer | SwiftUI `.draggable` / `.dropDestination` + `Codable` block enum; candidate libs (`visfitness/reorderable`, `stevengharris/SplitView`) evaluated at build time |
| Backend layer | Pure Swift |
| Database | SQLite via GRDB.swift 6.29.3 (FTS5 + `ValueObservation`) |
| Markdown parser | `apple/swift-markdown` (parse only; hand-rolled writer for save path) |
| File watcher | FSEventStream via Swift wrapper |
| Icons | SF Symbols via `Image(systemName:)` |

> If pivoting to React, see `// ReactInfo//Contingency.md` + `// ReactInfo//ReactInfo.md`.

##### Three load-bearing constraints

1. **Stack portability of functionalities.** File formats, SQLite schema, domain model, property catalog, directive syntax, connection behavior, view directives, design values, UX patterns survive a stack rebuild — the codebase doesn't. No enforced layer separation; portability comes from documented decisions. Detail → `// Features//Architecture.md`.

2. **Cross-nexus queryability + cloud sync compatibility.** Types and Collections aren't isolated — any Page or Context can query/link/embed any Type's contents regardless of folder location. On-disk model maps cleanly to a cloud DB: shared `pages` table with `page_type_id` + `page_collection_id` + `properties` JSONB; one `page_types` row per `_pagetype.json`; `agenda_tasks` + `agenda_events` tables; one `contexts` row per Area / Topic / Project. Sync arrives as additive translation. V1 gets device-to-device sync free via nexus in iCloud/Dropbox/any synced folder. **Reference convention:** relations stored by ID (rename-safe); body connections use titles (rewritten on rename via cascade).

3. **Persistent immediate legibility for agents.** External agents (Claude, MCP clients, any tool with filesystem access) read Pommora's entire structured graph — Pages, schemas, Areas, relations, properties — directly from files without tool-call round-trips. SQLite is performance scaffolding, not source of truth. Differentiator from Notion-via-MCP (tool-mediated, opaque) and Obsidian (locally legible but unstructured). Choices that trade file-canonical legibility for app-internal convenience violate this constraint.

##### Storage Model

**Nexus location:** user-pickable on first launch; default `~//PommoraNexus//`. Can sit in iCloud Drive / Dropbox / any synced folder for free device-to-device sync. Path persisted via security-scoped bookmark in app-level state; sandbox enabled from v0.1a (forward-compatible with MAS).

**On disk:**

```
<picked nexus folder>//                    ← canonical content lives here, syncs with cloud
  Assignments//                             ← Page Type (folder + _pagetype.json; UI label "Vault")
    _pagetype.json                          ← shared schema for Pages inside
    Spring-2026//                           ← Page Collection (sub-folder + _pagecollection.json; UI label "Collection")
      _pagecollection.json                  ← per-Collection metadata (id + type_id + page_order + set_order)
      Midterm-Prep//                        ← Page Set (sub-folder + _pageset.json; UI label "Set")
        _pageset.json                       ← per-Set metadata (id + collection_id + icon + page_order)
        Exam-Review.md                      ← Page inside a Page Set
      Essay-1.md                            ← Page at Collection root (no Set)
    Final-Project.md                        ← Page directly in Page Type (no Collection)

  Notes//                                   ← Page Type
    _pagetype.json
    Tech-stack-tradeoffs.md                 ← Page

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
    saved-config.json                       ← Saved-section entry labels
    homepage.json                           ← singleton Homepage entity (composed blocks)
    index.db                                ← SQLite index (v0.2+); regeneratable, schema-versioned
    areas//                                 ← tier-1 Contexts (folder + sidecar, free-standing)
      Personal//
        _area.json                          ← id, tier 1, color, icon, blocks
      Academics//
        _area.json
    topics//                                ← tier-2 Contexts (free-standing)
      Productivity//
        _topic.json                         ← id, tier 2, icon, blocks
    projects//                              ← tier-3 Contexts (free-standing — no longer nested in Topics)
      Pommora//
        _project.json                       ← id, tier 3, icon, blocks

  .trash//                                  ← Deleted entities (nexus-local trash; v1+)
    Assignments//
      Old-essay.md                          ← Preserves original relative path under the source Type

~//Library//Application Support//com.nathantaichman.Pommora//   ← machine-specific, never syncs
  state.json                                ← Codable AppState: bookmark + future recent-nexuses
```

Classification is by sidecar filename alone: folder location at the nexus root plus sidecar presence identifies kind (`_pagetype.json` → Page Type; `_taskconfig.json` / `_eventconfig.json` mark the Tasks / Events singletons — folder names renameable via Finder). App-internal config sits in `.nexus//` (hidden, matches `.obsidian` convention) and holds Contexts + Homepage singleton + tier/saved config + Settings + the SQLite index. Deletes go to `.trash//` at the nexus root, preserving original relative path under each source Type.

**Why the SQLite index lives inside the nexus:** the index is `<nexus>/.nexus/index.db` — it travels with the vault, so a moved or renamed nexus keeps its index without re-pathing. It holds no user data (titles, properties, links, relations only — never Page bodies), so it is fully regeneratable: `PommoraIndex.open` stamps the file with a `schema_version` and force-deletes + rebuilds via `IndexBuilder` whenever that version differs from the code's `currentSchemaVersion`. The Application Support tree holds only machine-specific `state.json` (security-scoped bookmark + recent-nexuses).

##### Pages

`.md` file with YAML frontmatter (`id` ULID, `icon`, per-tier multi-relations `tier1`/`tier2`/`tier3`, property values from parent Page Type's schema; no `page_type` or `title` field — filename = title, parent Page Type is implicit by file location) + Markdown body. Pages conform to the Page Type's schema; ad-hoc page-local properties are out of v1 (Prospect).

Pages are Markdown documents, not block surfaces — one continuous stream. Standard Markdown (headings H1–H5, lists, code blocks + inline code (SF Mono; `code//` tokens), images, GFM tables, blockquotes, HRs) plus two Pommora rendering directives: **`@Columns`** (`:::columns` fenced section; renders N equidistant horizontal columns; layout-only, content inside is standard Markdown) and **`:::callout`** (outlined-box, distinct from blockquotes' left-side emphasis bar; border binds to `callout//` token).

Both directives resolve to inert text + standard Markdown for external tools (Notion's Markdown export principle). Headings are foldable by default (chevron collapses until next equal-or-higher heading); no `:::toggle` construct, no on-disk syntax. Blocks belong to Contexts (the deferred composed-blocks surface), not Pages. `@View` in-line embeds in Page bodies are out of v1 (TextKit 2 layout-attachment complexity). Full detail → `// Features//Pages.md`.

##### Page Types

The operational-layer container: a **Page Type** is a folder at `<nexus>/<Title>/` + `_pagetype.json` sidecar (`id`, `icon`, `properties[]` shared schema, `views[]`, `collection_order`, `page_order`, `default_sort`, optional `open_in`). Title = folder name. **Page Collections** are sub-folders inside a Page Type, sharing the Type's schema (their own `_pagecollection.json` carries `id` + `type_id` + `icon` + ordering + `views[]`). **Page Sets** are optional sub-folders inside a Collection (`_pageset.json` — `id` + `collection_id` + `icon` + `page_order`; no schema, no views, no settings — everything inherits from the Collection). The hierarchy is strictly three levels — depth-3+ folders are sidecar-less and their pages roll up into the nearest Set. UI labels "Vault" / "Collection" / "Set" by default. Full detail → `// Features//PageTypes.md` + `// Features//Sets.md`.

A Page Type has no text-editor surface — a pure database viewer (table / board / list / cards / gallery). Move-strip applies cross-Type (a Page moved across Page Types loses properties absent from the destination schema). The per-vault `open_in` field (`compact` | `window`; absent = `window`) decides where the vault's Pages open — the PagePreview window or the main detail pane.

##### Contexts (Areas / Topics / Projects)

Three **free-standing** tiers — none contains or parents another. Each is a folder with a config sidecar: tier-1 Areas `.nexus/areas/<Title>/_area.json` (carries `color`, tier-1 only), tier-2 Topics `.nexus/topics/<Title>/_topic.json`, tier-3 **Projects** `.nexus/projects/<Title>/_project.json`. Bare entities — `id` / `tier` / `icon` / `blocks` (a reserved, currently-empty composed-blocks field) / `modified_at`. Tier labels user-configurable per-Nexus (Capacities-style singular + plural). Context→context relations are a deferred design pass. Full detail → `// Features//Contexts.md`.

##### Agenda

Calendar-anchored entries split into two distinct entities:

- **Agenda Tasks** — `.task.json` files inside the Tasks singleton folder at the nexus root (the root folder carrying `_taskconfig.json`; default name `Tasks/`, renameable via Finder). EKReminder-aligned: `due_at` (optional), `start_at` (optional "not before"), `completed`, `priority` (0–9), `recurrence`, `alarm_offsets`, required **built-in `status` Status** (EventKit-aligned 3-group; non-deletable; bridges to `EKReminder.isCompleted`).
- **Agenda Events** — `.event.json` files inside the Events singleton folder at the nexus root (the root folder carrying `_eventconfig.json`; default name `Events/`, renameable via Finder). EKEvent-aligned: required `start_at` + `end_at`, optional `location`, `all_day`, `recurrence`, `alarm_offsets`, `alarm_absolute`. Required **built-in `status` Status** (same 3 EventKit-aligned groups as AgendaTask; user-set, decoupled from `start_at` / `end_at` date math — the user marks status to track their own engagement with the event).

Schemas live in per-side per-kind sidecars: the Tasks singleton's `_taskconfig.json` (AgendaTask schema) and the Events singleton's `_eventconfig.json` (AgendaEvent schema). Sidecar-driven discovery — first root folder found carrying each sidecar wins; if no folder carries the sidecar on a brand-new nexus, managers eagerly seed `Tasks/` + `Events/` at the root on launch. Swift type names are `AgendaTask` and `AgendaEvent` (prefixed to avoid `_Concurrency.Task` and `Event` stdlib collisions; the "no `Pommora.X` qualification" rule rejects `Pommora.Task`). UI labels remain "Task" / "Event" (renameable via Settings).

EventKit requires `com.apple.security.personal-information.calendars` entitlement + `NSCalendarsFullAccessUsageDescription` / `NSRemindersFullAccessUsageDescription` keys + modern `requestFullAccessTo*` APIs (separate permissions per kind). EventKit sync opt-in via Settings (data layer ships v0.3.0; sync ships v0.6.0). Agenda has NO dedicated sidebar section — surfaces via the Calendar pin entry. Full detail → `// Features//Agenda.md`.

##### Homepage

Singleton composed-blocks dashboard at `.nexus/homepage.json`. No `id`/`tier`/`parents` — file location is identity. Same `blocks` shape as Contexts; designed to embed anything. Seeded on first launch; not user-deletable. Full detail → `// Features//Homepage.md`.

##### Local-End Translation Principle

**The local file is the spec, not the render.** Anything SQLite computes — board view contents, gallery cards, aggregated counts, relation lookups — is referenced by directive, never inlined. Agents read the directive and understand structure; data lives in SQLite, rendered only inside Pommora.

##### SQLite Schema

Ten data tables plus an internal `meta` table, rebuilt from files when the stored `schema_version` mismatches the code's (currently **14**). The index stores titles, properties, links, connections, and context-tier relations — **not** Page bodies or frontmatter (the `pages` table has no body column; full-text search reads files). Property schemas live in each Type's per-kind sidecar (`_pagetype.json` / `_taskconfig.json` / `_eventconfig.json`) — all canonical on disk, loaded into memory at app start. DDL lives in `Index/IndexSchema.swift`.

```sql
-- Page Type index (one row per <nexus>/<Title>/_pagetype.json at the root)
CREATE TABLE page_types (
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
  icon TEXT,
  modified_at TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1
);

-- Page Set index (sub-folders inside a Page Collection)
CREATE TABLE page_sets (
  id TEXT PRIMARY KEY,
  page_collection_id TEXT NOT NULL REFERENCES page_collections(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  icon TEXT,
  modified_at TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1
);

-- Page index (rebuilt from .md files inside any Page Type folder; no body/frontmatter columns)
CREATE TABLE pages (
  id TEXT PRIMARY KEY,                                                        -- ULID from frontmatter
  page_type_id TEXT NOT NULL REFERENCES page_types(id) ON DELETE CASCADE,
  page_collection_id TEXT REFERENCES page_collections(id) ON DELETE SET NULL, -- nullable
  page_set_id TEXT REFERENCES page_sets(id) ON DELETE SET NULL,               -- nullable
  title TEXT NOT NULL,                                                        -- derived from filename
  icon TEXT,
  properties TEXT NOT NULL DEFAULT '{}',                                      -- JSON; property values
  modified_at TEXT NOT NULL
);

-- Agenda Task index (rebuilt from .task.json files in the Tasks singleton folder)
CREATE TABLE agenda_tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  icon TEXT,
  due_at TEXT,                        -- ISO-8601; nullable (EKReminder.dueDateComponents)
  properties TEXT NOT NULL DEFAULT '{}', -- JSON; includes required built-in `status` Status
  modified_at TEXT NOT NULL
);

-- Agenda Event index (rebuilt from .event.json files in the Events singleton folder)
CREATE TABLE agenda_events (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  icon TEXT,
  start_at TEXT NOT NULL,             -- ISO-8601 (EKEvent.startDate; required)
  end_at TEXT NOT NULL,               -- ISO-8601 (EKEvent.endDate; required)
  properties TEXT NOT NULL DEFAULT '{}', -- JSON; includes required built-in `status` Status
  modified_at TEXT NOT NULL
);

-- Contexts index — Areas / Topics / Projects share one table, discriminated by tier
CREATE TABLE contexts (
  id TEXT PRIMARY KEY,
  tier INTEGER NOT NULL,              -- 1 (Area) | 2 (Topic) | 3 (Project)
  title TEXT NOT NULL,
  icon TEXT                           -- free-standing tiers: no parent column
);

-- Context-link index — tier relations only (tier1/2/3 emit one row each via property_id)
CREATE TABLE context_links (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  target_id TEXT NOT NULL,
  target_kind TEXT NOT NULL,
  property_id TEXT NOT NULL,
  modified_at TEXT NOT NULL
);

-- Connection index — derived edges from body [[ ]] links (page-only)
CREATE TABLE connections (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL,
  source_kind TEXT NOT NULL,          -- always "page" (connections are page-only)
  target_id TEXT,                     -- NULL while phantom (unresolved)
  target_kind TEXT NOT NULL,          -- always "page" (from [[ ]])
  target_title TEXT NOT NULL,         -- normalized (trimmed+lowercased) — resolution key
  surface TEXT NOT NULL,              -- always "page_body"
  multiplicity INTEGER NOT NULL DEFAULT 1,
  weight REAL NOT NULL DEFAULT 1.0,
  resolved INTEGER NOT NULL DEFAULT 0,
  modified_at TEXT NOT NULL
);

-- Property-definition index (one row per property in any Type's schema)
CREATE TABLE property_definitions (
  id TEXT PRIMARY KEY,
  owning_type_id TEXT NOT NULL,
  owning_type_kind TEXT NOT NULL,
  name TEXT NOT NULL,                 -- renameable display label
  type TEXT NOT NULL,                 -- property type tag
  config TEXT NOT NULL DEFAULT '{}',  -- JSON; per-type config (options, formats, etc.)
  position INTEGER NOT NULL DEFAULT 0,
  modified_at TEXT NOT NULL
);

CREATE INDEX idx_pages_page_type_id ON pages(page_type_id);
CREATE INDEX idx_pages_page_collection_id ON pages(page_collection_id);
CREATE INDEX idx_pages_page_set_id ON pages(page_set_id);
CREATE INDEX idx_page_collections_page_type_id ON page_collections(page_type_id);
CREATE INDEX idx_page_sets_page_collection_id ON page_sets(page_collection_id);
CREATE INDEX idx_context_links_source_id ON context_links(source_id);
CREATE INDEX idx_context_links_target_id ON context_links(target_id);
CREATE INDEX idx_context_links_property_id ON context_links(property_id);
CREATE INDEX idx_property_definitions_owning_type ON property_definitions(owning_type_id, owning_type_kind);
CREATE INDEX idx_contexts_tier ON contexts(tier);
CREATE INDEX idx_connections_source_id ON connections(source_id);
CREATE INDEX idx_connections_target_id ON connections(target_id);
CREATE INDEX idx_connections_target_title ON connections(target_kind, target_title);
CREATE INDEX idx_pages_title ON pages(title COLLATE NOCASE);
```

The internal `meta(key, value)` table holds the global `schema_version`; on mismatch with the code's `currentSchemaVersion`, the whole index file is deleted and rebuilt. Queries use SQLite's JSON1 extension to reach into the `properties` JSON, and join `context_links` for tier-relation lookups (each tier value emits one `context_links` row, keyed by the reserved tier property ID):

```sql
-- All Pages in the "Notes" Page Type tagged to a specific Topic
SELECT p.* FROM pages p
JOIN context_links r ON r.source_id = p.id AND r.source_kind = 'page' AND r.property_id = '_tier2'
WHERE p.page_type_id = '01H...notes-page-type-id'
  AND r.target_id = '01H...topic-id';

-- All Agenda Tasks due in the next 7 days
SELECT * FROM agenda_tasks
WHERE due_at BETWEEN datetime('now') AND datetime('now', '+7 days');

-- All Agenda Events starting in the next 7 days
SELECT * FROM agenda_events
WHERE start_at BETWEEN datetime('now') AND datetime('now', '+7 days');
```

##### Property Model

- **Values** in Page YAML frontmatter (`.md`), AgendaTask `properties` (`.task.json`), or AgendaEvent `properties` (`.event.json`). **Schemas** live in each Type's per-kind sidecar (`_pagetype.json`) and each Agenda kind's per-kind sidecar (`_taskconfig.json` / `_eventconfig.json`). Collection-local overrides remain a post-v1 Prospect — Page Collections inherit their parent Type's schema.
- **Scoped per Type**, created via the Page Type Settings sheet (Notion-style). Members must conform; ad-hoc page-local properties out of v1 (Prospect).
- **V1 catalog (10 types)** — full catalog in `// Features//Properties.md`. No free-form text — filename = title; "text-shaped" values use Select/Multi-select with creatable options. **Status** has 3 EventKit-aligned fixed groups (Upcoming / In Progress / Done) with user-editable options; group labels renamable, 3 structural slots fixed for EventKit compatibility. Status is built-in required on both AgendaTask AND AgendaEvent schemas; NOT auto-seeded on Page Types.
- **Property identity = ID, not name.** Every property in a Type's schema carries a stable ULID `id`; frontmatter / JSON `properties` block keys reference the property ID. `name` is a renameable display label — renames are schema-only (no member-file cascade).
- **User relations removed.** User-creatable relation properties were retired in the Contextv2 refactor (2026-06-04). The only surviving relation-type connection is the context-tier link (`tier1`/`tier2`/`tier3`).
- **File / Attachment** property type — files copy into `<nexus>/.nexus/attachments/<entity-id>/<original-filename>` on attach; property stores nexus-relative paths.
- **Every property can carry an icon** (SF Symbol via the native `IconPicker`).
- **Context-tier links are one-way and pre-configured** — `tier1`/`tier2`/`tier3` are built-in relation properties (merged via `BuiltInContextLinkProperties`) stored at frontmatter root. There are no user-creatable paired/dual relations; the `DualRelationCoordinator` machinery has been removed.
- **Inline option creation forbidden.** Select/Multi-select/Status options come only from the schema editor (Vault Settings → Edit Properties), reachable via right-click "Edit options…" or "Manage options…" link in every value picker.
- **Move-strip rule (Notion-style):** moving a Page across Page Types strips properties not in the destination schema (no quarantine; confirmation warning lists strips). Implemented v0.3.0.

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

Views appear in two contexts: (1) **inside any storage container** — saved views in each container's sidecar `views[]` (`_pagetype.json` / `_pagecollection.json`), switch via tabs. Every storage container has its own view surfaces, not just the schema-bearing Types — a Page Collection can carry a Board view independent of the parent Page Type's Table; schema is inherited from the Type but the saved-view configuration is per-container. (2) **embedded as a widget** — "Embedded Collection View" renders any saved view inside a Context/Homepage with per-embed overrides on filter/sort/group/shown-properties. Per the inline-editing principle, embedded views are fully editable in place.

Each view spec: source Type (implicit from sidecar location), optional Collection-path scoping, view type, filter expression, sort, group-by property, properties to display, cover image (gallery). Filter expressions parse to a small DSL translating to parameterized `json_extract` SQL. View filters/sorts never modify the source Type.

In-line `@View` embeds *inside Page bodies* are out of v1 (TextKit 2 layout-attachment complexity); v2+ feasible if Pommora pivots to JS-editor + WKWebView (see `// Features//Prospects.md`).

##### Columns

`@Columns` supported in Pages and Areas. **V1 columns are equidistant** — widths divide available space evenly by child count; no per-column width config in v1. Ships as Pommora-specific render; file format stays standard `:::columns` Markdown on disk.

##### Sidebar Navigation

Surfaces curated, app-relevant navigation, not filesystem layout. Top-level groups (plus user-creatable vault sections); the headed groups are default-collapsed disclosure groups. User can drag headings to reorder; initial-boot order: **(heading-less pinned section) / Contexts / Vaults / user sections**. No dedicated Agenda section — Agenda Tasks + Agenda Events surface via the Pinned section's Calendar entry.

- **Pinned (heading-less, top)** — three fixed entries (Homepage / Calendar / Recents); labels renamable via Settings. Structurally a `Section` wrapper to host future user-pinned pages (gains "Saved" heading then). `Homepage` opens the singleton dashboard; `Calendar` opens calendar view over Agenda Tasks + Agenda Events + EventKit-mirrored events; `Recents` shows recently-opened tabs.
- **Contexts** — one "Contexts" section with three `square.grid.2x2` disclosure rows (Areas / Topics / Projects), expand/collapse only; each tier's entities are flat leaf rows. Areas carry a color/symbol indicator. The tiers are free-standing — no parent-derived tagging.
- **Vaults** (default label, renameable via Settings) — chevron-disclosure for Page Types (UI label "Vault" by default). Each Type discloses Page Collections (UI label "Collection") + root Pages; each Collection discloses Page Sets (UI label "Set"; expandable, never selectable) + its Pages. Pages: `doc.text` icon; Collections + Sets: `folder` icon.
- **User sections** — user-created sibling sections after Vaults that group Vaults for navigation only (`.nexus/sidebar-sections.json`; single-membership; ungrouped Vaults stay in the default Vaults section).

Agenda Tasks and Agenda Events do NOT appear in the sidebar — they surface via the Calendar pin entry, not as sidebar rows. The Vaults section classifies root folders by sidecar filename (rows are root folders carrying `_pagetype.json`). No raw filesystem view in v1.

**Creation is right-click-only.** No "+ New" buttons; right-click headings/rows/sections opens a context menu with "New X" options auto-scoped to the cursor location (New Vault / New Collection / New Page; Vault Settings… on Vault rows for the schema editor; Add Section on the Vaults heading). Quick-capture (Cmd+Shift+N or menu-bar; pre-v1) is the discoverable counterpart for global creation. Collapsed-by-default disclosure is the general default for hierarchical UI. Full spec → `// Features//Sidebar.md`.

##### Three-Pane Shell + Property Surfaces

Sidebar (default 240px) / main (flex) / inspector (default 280px). Both side panes drag-resizable from v0.0; widths persist across launches. Default window 1200×800; minimum 960×560.

**Main-window inspector hosts the Claude chat** (frontend to Nathan's local CLI, not an API integration; subprocess bridge) — ships at v0.7.0 (LLM Interface). **Properties do NOT live in the main-window inspector under the locked direction.** They live in two surfaces depending on context (full spec at [[Properties]] § "Where Properties Live"):

| Surface | Property home |
|---|---|
| **Page in main window** | Target: NavDropdown-style pulldown at top of content (lazy properties); today the editor's `.inspector` (`FrontmatterInspector`) until the pulldown ships |
| **PagePreview window** | The shared `FrontmatterInspector` mounted compact (defaults open) |

**Window chrome — macOS unified title bar.** No separate Pommora title bar. Traffic-lights render OS-rendered in the sidebar pane's column. A single unified toolbar (`.windowToolbarStyle(.unified(showsTitle: false))`) holds sidebar toggle, back/forward arrows, NavDropdown trigger, and inspector toggle, all in the same row as traffic-lights. No second toolbar row. Pattern: Mail / Notes / Finder.

Built on SwiftUI's two-column `NavigationSplitView(sidebar:detail:)` with inspector attached via `.inspector(isPresented:)` (macOS 14+) — Apple's idiomatic pattern (Mail, Notes, Pages). Width via `.inspectorColumnWidth(min:ideal:max:)`; toolbar toggle via `InspectorCommands`. The three-column `NavigationSplitView` variant was rejected — that column is for selection drill-down (Mail's list → message-list → message), not a contextual supplementary panel.

##### Nav Dropdown

Main pane is **single-pane.** Navigation history lives in a Liquid Glass dropdown button (SF Symbol `square.on.square`) in the toolbar — popover with two toggleable lists: **Pinned** (user-curated via right-click) and **Recents** (auto-tracked LRU). Replaces the earlier "Top-Bar Tabs" model. Pattern: Things 3 Quick Find, Notes.app Move-To popover.

Single-click highlights, double-click opens in main detail pane. Keyboard: `⌘T` opens dropdown; `⌘[` / `⌘]` walk Recents back/forward. State persists in `<nexus>/.nexus/state.json` (per-nexus, vault-portable); Pinned uncapped; Recents store cap 500; dropdown shows top 100; full-frame Recents view (v0.7.0) shows the full store.

Shipped at v0.2.7.1. Full spec → `// Features//NavDropdown.md`.

##### PagePreview Window

Pages in a `compact`-mode vault open in **PagePreview** — a real `WindowGroup` window (`id: "page-preview"`, `for: PageRef.self`; one window per Page, re-open focuses) restricted to never act as its own app window: traffic lights hidden, no Dock minimize, no Window menu / Mission Control presence, no fullscreen Space; child-attached above the main window at normal level (rides its moves, never floats over other apps, hides with it, closes with it and on Nexus switch). Standard `windowBackground` material — the only glass is the two `WindowCapsuleButton` capsules (✕ close, inspector toggle). Windows open **locked** (read-only) with the inspector **open** — the shared `FrontmatterInspector` mounted compact; the footer lock toggles editing, and unlocking reveals an **Open** button. `Ctrl-Cmd-F` or a title-strip double-click promotes the Page to the main detail pane. Default 840×540; minimum 630×424. A Page already shown in the main pane never previews (edit-conflict guard); every open path routes through `PageOpenRouter`. Full spec → `// Features//Pages.md` § "Opening behavior".

##### First-Launch Experience

After the user picks a nexus location, Pommora opens with empty sidebars plus a seeded Homepage singleton at `.nexus/homepage.json` (NOT an Area) as the landing surface via the pinned `Homepage` row. Per-Nexus singletons auto-seed on first manager init: Homepage + `tier-config.json` + `saved-config.json` + `settings.json` (user-overridable UI labels + accent color) + Tasks singleton folder (default `Tasks/`) carrying `_taskconfig.json` + Events singleton folder (default `Events/`) carrying `_eventconfig.json`. No tutorial, no walkthrough wizard.

##### Design System

SwiftUI native idioms (semantic colors, Materials, Font scale, SF Symbols) plus small Pommora-brand Color/Font extensions for values SwiftUI doesn't cover (accent, code, callout, blockquote). V1 ships one initial scheme plus in-app customization for accent color and font size (folded into the v0.7.0 Settings UI). Full design philosophy → `// Guidelines//Design.md`. SF Symbol assignments → `// Guidelines//Symbols.md`.

##### File Renames and Connection Resolution

Renames are filesystem renames for the file itself. **Relation** values (`tier1/2/3`, `$rel`) are ID-keyed — a rename needs no rewrite, since references resolve via ULID. **Connections** (body `[[ ]]` / `{{ }}`) are title-keyed in v1, so a rename **cascades**: every referencing body is rewritten to the new title (atomic — see [[Connections]]). ULID-keyed connection resolution is a *potential* post-v1 method for once duplicate titles are allowed, not the v1 mechanism. The file watcher updates the SQLite `path` field on external moves.

**Connection resolution:** disk format is plain `[[Title]]` (Obsidian-compatible); Pommora never writes a piped ULID form. v1 resolves **by globally-unique title** — no in-body id and no frontmatter mirror — with rename-safety from cascade. Canonical spec → [[Connections]]. Relation properties store target IDs as `{"$rel": "<ULID>"}` and display the target's current title.

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

- **Contexts** (3 tiers — Areas / Topics / **Projects**) — free-standing folder+sidecar organization surfaces; tier labels per-Nexus configurable. All three render in one "Contexts" sidebar section as disclosure rows. No containment, no parents, no cross-tier links — context→context relations are a deferred design pass.
- **Page Types + Page Collections + Page Sets + Pages** — each Page Type carries its `_pagetype.json` sidecar; Collections are sub-folders sharing the Type's schema (their `_pagecollection.json` carries id + type_id + icon + ordering + views); Sets are optional schema-less sub-folders inside Collections (`_pageset.json`). UI labels "Vault" + "Collection" + "Set" (renameable via Settings). Per-vault `open_in` mode (`compact` → PagePreview window; `window` → main detail pane).
- **Pages** — Markdown + YAML frontmatter (incl. per-tier multi-relations `tier1`/`tier2`/`tier3`); editor = native TextKit 2 + `swift-markdown` + the Pommora-owned `MarkdownPM` (shipped v0.2.7.0). Standard Markdown + `@Columns` + `:::callout` directives.
- **Agenda** — split into **Agenda Tasks** (`.task.json`, EKReminder-aligned) and **Agenda Events** (`.event.json`, EKEvent-aligned) inside their respective root-level singleton folders (the folder carrying `_taskconfig.json` is the Tasks singleton; the folder carrying `_eventconfig.json` is the Events singleton). Required `status` Status property on both Agenda Tasks and Agenda Events (built-in, non-deletable). AgendaTask bridges to `EKReminder.isCompleted`; AgendaEvent Status is user-set, decoupled from `start_at` / `end_at`. Sync opt-in (data layer ships v0.3.0; sync ships v0.6.0). NO sidebar section — Calendar pin entry surfaces both kinds.
- **Homepage** — singleton dashboard at `.nexus/homepage.json`. Seeded on first launch.
- **Settings scaffold** — `.nexus/settings.json` + `SettingsManager` + UI label wiring across all renameable surfaces + accent color reading. Settings editing UI ships v0.7.0; storage + label-read plumbing + Cmd+, stub scene shipped at v0.3.0.
- Property panel UI driven by Page Type / AgendaTask / AgendaEvent schemas; all 10 v1 property types incl. Status with EventKit-aligned groups + File / Attachment; the Vault Settings sheet centralizes schema editing. Per-view configuration (Sort / Group By / Filter / Layout / Property Visibility) lives in the View Settings surface; phasing in `Framework.md`.
- Connections — `[[Page]]` inline links (styled colored text; the sole connection syntax).
- Automatic file rename with cross-nexus connection cascade (title rewrite across all referencing bodies).
- File watcher keeping SQLite synced.
- Global search (SQLite FTS5 over Page bodies + frontmatter).
- Sidebar (Pinned / Contexts / Vaults) plus user-creatable vault sections, user-reorderable, default-collapsed. Agenda surfaces via Pinned → Calendar.
- **Inline editing of embedded views** — every embed in a composed-blocks surface is a live editable view of its source.
- One initial design scheme + in-app accent color + font size customization (folded into the v0.7.0 Settings UI on top of the v0.3.0 Settings scaffold); SwiftUI native handles everything else.

**Out (post-v1):** additional view types, block features, sync, mobile, plugins, ad-hoc properties, multi-Collection pages, independent UI titles, in-line view embeds in Pages, chip-style connection variants, board view drag-to-rewrite-frontmatter, full Settings editing UI, etc. — see `// Features//Prospects.md`. Prospects move into `Framework.md` when committed.

---

#### What Items Were (historical — retrospective)

> **Items no longer exist.** This section is the sanctioned record of the retired entity — everything below is past tense, kept so the product's history stays legible. Ship-by-ship record → `History.md`; superseding decision → `Guidelines/Paradigm-Decisions.md` #17.

Items were Pommora's second operational entity beside Pages, from the founding paradigm (2026-05-16) until the PagesV2 collapse (2026-06-09/10). The split mirrored Notion's "row in a database" vs "page with a body": **Items were row-shaped** — properties plus a short capped description — while Pages were prose-bearing.

**The entity model.** An Item was one plain `.md` file (YAML frontmatter + body) inside an **Item Type** — a root folder carrying an `_itemtype.json` sidecar that held the property schema shared by every Item inside, exactly parallel to a Page Type. **Item Collections** (`_itemcollection.json`) were organizational sub-folders within a Type, schema-inherited like Page Collections. The capped description WAS the body ("Shape A" — no frontmatter description field, no mirror), limited to 500 markdown-source characters (`ItemValidator.maxDescriptionLength`, per-Type `description_cap` override), validated on save and never silently clamped. Items shared Pages' single `AtomicYAMLMarkdown` codec — one read/write pipeline for both forms, with foreign frontmatter preserved by value. (Items had earlier been whole-`.json` files; the 2026-06-02 "Items are Markdown" migration converted them.)

**Vocabulary.** The code layer was symmetric (`PageType` / `PageCollection` / `ItemType` / `ItemCollection` — same shape, different content) while UI vocabulary diverged per side: Pages got the distinctive "Vault" + generic "Collection"; Items got the generic **"Type"** + distinctive **"Set"** — each side one signature word and one shared word, all renameable via Settings.

**The Class stamp.** Because both forms were `.md`, the extension couldn't discriminate them. The parent Type folder's sidecar was the kind authority, and each content file carried a reserved, UI-hidden, **non-authoritative** `Class` frontmatter stamp (`item` | `page`) recording its form; a stamp/folder disagreement or a homeless file was to route to a hidden `.unsorted` inbox. The stamp died with the entity — Pommora no longer writes `Class`, and an on-disk `Class` key is now ordinary preserved foreign frontmatter.

**The Item Window.** Items never opened in the main detail pane. They opened in the **Item Window** — a native, draggable, dismissible floating panel (a non-activating `NSPanel`, fixed ≈800×560, hidden traffic lights, custom ✕ + Esc to close) that never stole focus from the main window. One config-driven `ItemWindowRenderer` drew every window from a per-Type/per-Collection **`template_config`** (ItemsV2, 2026-06-03): a layout archetype enum, **promoted ("pinned") properties** rendered in a segmented property bar below the title, per-property display variants, an image-filtered cover, and description-cap overrides — edited in a WYSIWYG "Templates" settings pane. Non-promoted properties lived in the window's trailing inspector.

**Connections.** Items had their own inline link syntax: **`{{Title}}`** (Pommora-only, beside Pages' Obsidian-compatible `[[Title]]`), with the bracket type naming the target's kind. Resolved item links rendered as an inline **chip** (icon + title highlight) where page links rendered as plain styled colored text. The `{{ }}` grammar — tokenizer, styler, autocomplete, chip renderer — was retired wholesale; `{{` is plain text today. The chip *visual design* survives as one dormant Component Library design file (`Properties/Chips/ChipLink.swift`).

**The index.** The SQLite index carried three item tables — `items` (with a `description` projection of the body), `item_types`, and `item_collections` — parallel to the page tables, dropped at schema v11.

**Why and when it collapsed.** Ratified 2026-06-09 after the Items↔Pages collapse evaluation: the two entities had converged to the point of redundancy — same file format, same codec, same property catalog, same container shape, same tier relations — leaving only a body-length cap and a render surface as the differences. Neither needed a second entity: per-vault **`open_in`** settings (`compact` | `window`) now give any vault the row-shaped glance experience via the **PagePreview window** or the full-page experience in the detail pane, on a single Page entity. The collapse deleted rather than migrated (no on-disk data change; the index is regeneratable); legacy `_itemtype.json` folders adopt as ordinary sidecar-less Page Types with the stale sidecar left inert.
