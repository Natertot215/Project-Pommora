### Pommora — Product Requirements Document

> Living document. Captures the vision, scope, and key architectural decisions for Pommora.

---

#### Vision

Pommora is an all-in-one personal management platform that combines Obsidian's customization and local-first ethos with Notion's database and view capabilities. Pages are Markdown files; Collections are first-class database entities (Notion-style, not folder-based) holding property schemas and saved views; Spaces are customizable dashboard surfaces. The goal is a simpler Notion that's also a more capable Obsidian — without forcing the trade-offs that push users to bounce between the two.

#### Why

Notion and Obsidian each excel where the other falls short:

- **Obsidian** gives unrivaled UI-level customization and a transparent, local-first file model — but its Markdown core can't express columns, side-by-side callouts, or in-line filtered views without heavy plugin reliance.
- **Notion's** in-line database views — filtered, sorted, and regrouped per page without altering the source — are its defining feature. Obsidian's file-as-document architecture can't match this natively.
- **Obsidian** shines until you need real task management or cross-page coordination. **Notion** shines until you hit an interface decision you can't change.

Pommora's bet: a Markdown-canonical foundation with SQLite as the property and query engine, and a clean separation between *content* (Pages), *structure* (Collections), and *interface surfaces* (Spaces), can deliver Notion's most-loved features without giving up Obsidian's open, hackable, local-first nature.

#### Audience and Posture

- Personal-first, single-user, Mac-first for v1.
- Always open-source.
- Architected so future multi-user, cross-device, and plugin support remain viable — but those aren't v1 concerns.

---

#### Domain Model

Pommora is composed of three top-level entity types:

- **Pages** — single Markdown documents. Prose-first editor; flat (Obsidian-style filesystem flexibility, no semantic nesting).
- **Collections** — first-class database entities (Notion-style). Hold property schemas and saved view configurations. Pages belong to Collections via frontmatter, not via folder location.
- **Spaces** — customizable dashboard surfaces at the interface level. Composed of widgets that aggregate Pages and Collection items linked to them.

The model deliberately separates content (Pages), structure (Collections), and interface (Spaces). Collections and Spaces are config-style entities; only Pages hold prose. Full definitions, on-disk shapes, linking model, and open questions live in `// Features//Domain-Model.md`.

---

#### Core Architectural Decisions

##### Stack — Under Active Evaluation

Two viable paths. Both produce identical on-disk Markdown and identical SQLite indexes; they differ in the implementation of the editor surface and the desktop shell.

| Layer | If React + Electron | If SwiftUI |
|---|---|---|
| Desktop shell | Electron | SwiftUI on macOS Tahoe (26+) |
| UI framework | React + TypeScript (strict) | SwiftUI |
| Styling | Tailwind CSS | SwiftUI native + Color / Font extensions from Figma |
| Editor (Pages) | BlockNote (open-source MPL-2.0 core) configured prose-first; pivot doors held open to Tiptap, Milkdown, or Yoopta | Two-phase: Phase A native `TextEditor` + `AttributedString` (iOS 26 / macOS 26+) with quick fork for H4-H6 + toggles; Phase B full custom editor with hover-on-selection bubble toolbar |
| Spaces composer | React DnD library (e.g. dnd-kit) | SwiftUI `Canvas` + `.draggable` / `.dropDestination` |
| Backend layer | Node.js + TypeScript | Pure Swift |
| Database | SQLite via `better-sqlite3` (WAL mode) | SQLite via GRDB.swift (FTS5 + `ValueObservation`) |
| Markdown parser | `remark` + `remark-directive` + `gray-matter` | `apple/swift-markdown` |
| File watcher | `chokidar` | `FSEventStream` (FileSystemEvents) |
| Icons | Material Symbols (`react-material-symbols`) | SF Symbols |

The decision is deferred. The architecture principle below ensures either choice survives a future pivot to the other.

##### Architecture Principle (Load-Bearing)

Pommora's *functionalities* are designed to work across both stack paths. If one stack ships and Pommora is later rebuilt in the other, that rebuild is guided translation work — file formats, SQLite schema, domain model, property catalog, directive syntax, wikilink behavior, view directives, design tokens, and UX patterns survive intact; the codebase doesn't. There is no enforced layer separation; the portability comes from the documented decisions, not from code structure. Full detail → `// Features//Architecture.md`.

##### Cross-Vault Queryability + Cloud Sync Compatibility (Load-Bearing)

A second load-bearing constraint, separate from stack portability:

- **Cross-vault queryability** — each Collection's schema and member set is encapsulated in its folder, but the Collection participates in vault-wide queries and links. A Page or Space anywhere in the vault can query, link to, or embed any Collection regardless of folder location. Collections are never *isolated* — only their schemas and Pages are *contained*.
- **Cloud sync compatibility** — the model must translate cleanly to a cloud database (e.g. Supabase). The mapping is direct and mirrors the local SQLite shape: a single shared `pages` table where each row carries `collection_id` and a `properties` JSONB column (matching Notion / Airtable / AFFiNE convention); each `_collection.json` schema → a row in a `collections` table; each Space → one row in a `spaces` table with the block tree as a JSON column. Sync arrives later as an additive translation layer; v1 must not paint us into a corner that requires redesigning the on-disk model when sync lands.
- **Implication for relations:** frontmatter relation properties reference targets by **ID** (not by path or filename), so renames don't break links. Body wikilinks (`[[Page Name]]`) reference by name and are rewritten on rename. Two reference mechanisms, each fit for purpose.

##### Storage Model

**Vault location:** Fixed at `~// PommoraVault//` for v1.

**On disk:**

```
~// PommoraVault//
  Tasks//                      ← Collection (folder + _collection.json inside)
    _collection.json           ← Schema + saved views for this Collection
    Buy groceries.md           ← Member Page
    Fix sink.md                ← Member Page
  Projects//                   ← Another Collection
    _collection.json
    Pommora.md
  Quick note.md                ← Loose Page (not inside any Collection folder)
  Notes//                      ← Cosmetic folder (no _collection.json → not a Collection)
    Travel ideas.md            ← Loose Page (folder is just organization)
  attachments//
    image.png
  _pommora//
    pommora.db                 ← SQLite index (regeneratable)
    spaces//                   ← Notion-page-style composed surfaces
      Pommora.space.json
      Health.space.json
```

**A folder is a Collection** if and only if it contains a `_collection.json` file. Folders without one are cosmetic filesystem organization — Pages inside them are loose Pages.

**Each Page** consists of:

1. **YAML frontmatter** — `id` (ULID), `icon`, `spaces` (multi-relation to Space IDs by ID), and property values from the Collection's schema. **No `collection` field** — membership is by folder location. **No `title` field** — the Page's title is its filename (minus `.md`); renaming the title in the UI renames the file. Properties must conform to the Collection's schema; ad-hoc properties not in the schema are out of v1 scope.
2. **Markdown body** — prose
3. **Block-level features allowed in Page body for v1** — `@Columns` (multi-column container; equidistant in v1), callouts (visual container with optional color attribute; no icons or semantic types; composes with `@Columns` for Notion-style side-by-side callouts), and **toggles** (collapsible content blocks, Notion-style — clickable triangle expands/collapses inner content). The previously-proposed `@View` (in-line database view embed inside a Page) is deferred to v2+. Embedded Collection views remain available *inside Spaces* (as widget blocks) for v1.

   **For React**

   `@View` is reachable when revisited — block editors like BlockNote support embedding a custom view inside the editor natively (custom block component).

   **For Swift**

   `@View` is not feasible inside the native `TextEditor`, which doesn't support inline non-text views; would require an `NSTextView` / TextKit 2 surface. This is the basis for the v2+ deferral being noted as React-only.

Folders inside `~// PommoraVault//` are **purely cosmetic**. They have no semantic meaning to Pommora. Move Pages between folders freely; Collection membership is established by the `collection` frontmatter field, not by location.

**Each Collection** is a folder + a `_collection.json` schema sidecar inside the folder (Make.md folder-notes pattern applied to databases). The JSON sidecar holds:

```json
{
  "id": "01HXXXXX...",
  "icon": "checkbox",
  "properties": [ /* property schema entries */ ],
  "views": [ /* saved view configurations */ ]
}
```

The Collection's title comes from the **folder name** — no `title` field in the JSON. The folder physically contains the member Pages as `.md` files alongside `_collection.json`.

**Each Space** is a JSON file holding the full block tree (Notion-page-style):

```json
{
  "id": "01HXXXXX...",
  "icon": "rocket",
  "blocks": [
    { "type": "heading", "level": 1, "text": "Pommora" },
    { "type": "paragraph", "text": "Active project notes." },
    { "type": "linked-pages", "view": "list", "filter": "..." },
    { "type": "columns", "children": [
      { "type": "embedded-collection-view", "collection_id": "01H...", "view_id": "01H..." },
      { "type": "link-list", "items": [ /* ... */ ] }
    ]},
    { "type": "callout", "icon": "info", "text": "..." }
  ]
}
```

The Space's title comes from the **filename** (e.g. `Pommora.space.json` → "Pommora") — no `title` field in the JSON. Spaces hold both *text blocks* (paragraph, headings, lists, callouts, code, columns, image) and *widget blocks* (linked-pages, embedded-collection-view, link-list) intermixed in the same tree.

##### Local-End Translation Principle

**The Markdown file is the spec, not the render.** Anything SQLite computes — the contents of a board view, the cards in a gallery, backlinks, aggregated counts — is referenced by directive but never inlined into a Page. Claude (or any text editor, or any human reading the file) sees the directive and understands the structure; the actual data lives in SQLite and is rendered only inside Pommora.

Acceptable file representations:

- A view directive carries the spec (source Collection, view type, filter, sort, group), not the data
- Property values stay in Page frontmatter so Claude can edit them directly with standard YAML tooling
- Wikilinks (`[[Page Name]]`) stay as-is — readable, editable, queryable
- Collection schemas and Space layouts live as JSON files in `_pommora//` — config, not prose, but still files (greppable, version-controllable, portable)

##### SQLite Schema

Four tables. All rebuilt from files on launch or on demand. Property schemas live inside per-Collection JSON files (canonical), loaded into memory at app start.

```sql
-- Page index (rebuilt from .md files in the vault)
CREATE TABLE pages (
  id TEXT PRIMARY KEY,                -- ULID from frontmatter
  path TEXT UNIQUE NOT NULL,          -- 'Tasks// Buy groceries.md' or 'Quick note.md'
  collection_id TEXT,                 -- derived from path at index time (Collection whose folder contains this Page); NULL for loose Pages
  title TEXT NOT NULL,                -- derived from filename (basename minus '.md')
  icon TEXT,
  frontmatter JSON NOT NULL,
  body TEXT NOT NULL,                 -- raw markdown body (powers FTS)
  modified_at INTEGER NOT NULL
);

-- Collection index (rebuilt from _collection.json files in the vault)
CREATE TABLE collections (
  id TEXT PRIMARY KEY,
  folder_path TEXT UNIQUE NOT NULL,   -- 'Tasks//' (the folder containing _collection.json)
  title TEXT NOT NULL,                -- derived from folder name
  icon TEXT,
  properties JSON NOT NULL,
  views JSON NOT NULL,
  modified_at INTEGER NOT NULL
);

-- Space index (rebuilt from .space.json files)
CREATE TABLE spaces (
  id TEXT PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,          -- '_pommora// spaces// Pommora.space.json'
  title TEXT NOT NULL,                -- derived from filename (basename minus '.space.json')
  icon TEXT,
  blocks JSON NOT NULL,               -- the full block tree from the .space.json
  modified_at INTEGER NOT NULL
);

-- Link index (rebuilt from files)
CREATE TABLE links (
  from_id TEXT NOT NULL,         -- always a page id
  to_id TEXT NOT NULL,           -- page, collection, or space id
  to_kind TEXT NOT NULL,         -- 'page' | 'collection' | 'space'
  property TEXT                  -- NULL for inline wikilinks; 'collection', 'spaces', 'related', etc. for property links
);

CREATE INDEX idx_pages_collection ON pages(collection_id);
CREATE INDEX idx_links_from ON links(from_id);
CREATE INDEX idx_links_to   ON links(to_id, to_kind);
```

Queries use SQLite's JSON1 extension to reach into frontmatter:

```sql
SELECT * FROM pages
WHERE collection_id = '01HXXXXX...'
  AND json_extract(frontmatter, '$.properties.status') = 'Active';
```

##### Property Model

- **Property values** in Page frontmatter
- **Property schemas** live inside each Collection's `_collection.json` sidecar (canonical, exportable, version-controllable). No more shared `schemas.json` — each Collection owns its schema directly.
- **Properties are scoped per Collection** and created on-demand, Notion-style
- **A Page's properties must conform to its Collection's schema.** Ad-hoc page-local properties not in the schema are out of v1 scope. Loose Pages have no schema and hold only `id`, `icon`, `spaces`, and link properties.
- **V1 types:** number, checkbox, date, date & time, select, status, multi-select, relation, URL. **No free-form text type** — title is the filename (handled by the file system), and "text-shaped" values use Select / Multi-select with creatable options (Notion behavior).

Full type catalog, config shapes, schema-mutation rules, and creation flow → `// Features//Properties.md`

##### View Directives

V1 ships five view types, available in two contexts:

| Type | Renderer | Notes |
|---|---|---|
| **Table** | Stack-native data table | Sortable columns, inline edit |
| **Board** | Drag-and-drop kanban | Drag cards between columns; updates source Page's frontmatter |
| **List** | Plain list | Title plus selected inline properties |
| **Gallery** | Grid layout | Cards with cover image |
| **Cards** | Grid layout | Cards without cover-first emphasis |

**Two contexts where views appear in v1:**

1. **Inside a Collection** — saved views configured per-Collection, stored in the Collection's `.collection.json` file. Switch between them via tabs above the view area.

2. **Embedded as a Space widget** — the "Embedded Collection View" widget renders any saved Collection view inside a Space. References a Collection by ID and overrides filter / sort / group / shown-properties locally without modifying the Collection's saved views.

**Deferred:** in-line view embeds *inside Pages* (via a `@View` directive in the prose) are out of v1 and are React-only when revisited (see Storage Model above for the stack reasoning).

Each view spec carries: source Collection, view type, filter expression, sort, group-by property, properties to display, and (for gallery) cover image property. Filter expressions parse to a small DSL and translate to parameterized `json_extract` SQL queries.

**Filters and sorts on a view never modify the source Collection** — they are purely view-local.

##### Columns

Multi-column block (`@Columns` directive) is supported in both Pages and Spaces. **V1 columns are equidistant** — column widths divide the available horizontal space evenly based on the number of children. No per-column width configuration in v1 (no inline attributes, no sidecar layout config). Adjustable widths are deferred to a later version.

**For React**

Implemented as a custom block in BlockNote core (avoiding `@blocknote/xl-multi-column`, which is GPL-3.0 OR a paid commercial license).

**For Swift**

Implemented via a segment-based render pattern: a `:::columns` segment renders as an `HStack` of sub-`TextEditor`s with equidistant child widths.

##### Pages, Collections, Spaces

Brief summary; per-entity detail lives in `// Features//Pages.md`, `// Features//Collections.md`, and `// Features//Spaces.md`. The linking model, properties summary, sidebar pattern, and open questions live in `// Features//Domain-Model.md`.

- A **Page** = one Markdown file, prose-first editor, flat (no nesting). Member of a Collection if it lives inside that Collection's folder; otherwise loose.

- A **Collection** = a folder + a `_collection.json` schema sidecar inside that folder (Make.md folder-notes pattern). Holds a property schema and saved view configurations. No text-editor surface — purely a database viewer. Membership is by file location.

- A **Space** = a Notion-page-style block-composition surface (`.space.json`). Holds a full block tree of text blocks and widget blocks intermixed. Independent of Collections.

- Pages link to Spaces via a `spaces` multi-relation property in frontmatter.

- Pages link to other Pages via wikilinks (`[[Page Name]]`) in body or relation properties.

##### Sidebar Navigation

The sidebar surfaces logical organization (Spaces and Collections), not filesystem layout. Top-level groups: **Spaces**, **Collections** (collapsible disclosure groups; default state collapsed; expanding reveals member Pages), **Loose Pages** (collapsible). No raw filesystem view in v1.

The "collapsed-by-default disclosure" pattern is the general default for any hierarchical or grouped UI we build elsewhere in the app.

##### Design System

The Figma file is the source of truth. v1 ships with one initial scheme **plus in-app customization for colors and typography** (see Framework v0.12) — the user can override token values from a settings panel. Variables use semantic role-based names (`surface// primary// bg`, never `bg-zinc-900`) so the same design exports cleanly to either stack's consumer.

**For React**

Tokens export to CSS custom properties (e.g. `--surface-primary-bg`); icons via Material Symbols (`react-material-symbols`). Custom design system created via Storybook testing and Claude-Figma workflow.

**For Swift**

Tokens export to SwiftUI `Color` extensions (e.g. `Color.surface.primary.bg`); icons via SF Symbols.

Full token taxonomy, dual-axis tier model, and customization details → `// Guidelines//UIX-Guide.md`.

##### File Renames and Wikilink Updates

Renames are automatic and atomic. When a Page is renamed (via the UI, sidebar, or page-title edit):

1. Pommora locates every wikilink targeting the old name using the `links` index — one indexed query, not a vault-wide scan.
2. Inside one transaction:
   - Rename the file on disk
   - Update the Page's `path` in the SQLite index
   - Rewrite every `[[Old Name]]` reference to `[[New Name]]` across all referencing Pages
   - Re-write each affected file atomically (write to `.tmp`, then `rename`)
3. The file watcher coalesces the resulting change events; no redundant re-indexing.

**Wikilink resolution rules:**

- `[[Page Name]]` resolves by basename match (Obsidian-style)
- If two Pages share a basename, disambiguation uses path: `[[Notes// Roadmap]]` vs. `[[Personal// Roadmap]]`
- Renaming a Page that has ambiguous siblings updates only the references that resolve to it
- Wikilinks render as **styled colored inline text** (Obsidian-style hyperlink), not as Notion-style chips/pills — across both stacks

---

#### v1 Scope

**In:**

- **Pages** — Markdown files with YAML frontmatter, prose-first editor (paragraphs, headings H1-H6, lists, code blocks, images, tables, callouts, toggles), `@Columns` block. Membership is by location: a Page in a Collection's folder is a member; a Page elsewhere is loose. No `title` field in frontmatter (filename = title); no ad-hoc properties (must conform to Collection schema).

- **Collections** — folder + `_collection.json` schema sidecar. Property schemas and saved view configurations live inside the sidecar. Five view types (table, board, list, cards, gallery) with per-view filter / sort / group / shown-properties controls. No text-editor surface — pure database viewers.

- **Spaces** — Notion-page-style composition surfaces (`.space.json` files) with a full block tree. Text blocks (paragraph, headings, lists, callout, code, columns, image) and widget blocks (linked-pages, embedded-collection-view, link-list) intermixed. Drag-to-arrange and slash-menu insertion.
- Property panel UI driven by Collection schemas, with all v1 property types (text, number, checkbox, date, datetime, select, status, multi-select, relation, URL)
- Wikilinks plus a backlinks panel (styled colored inline text, not chips)
- Automatic file rename with cross-vault wikilink rewrite
- File watcher keeping SQLite index synced (across Pages, Collections, and Spaces)
- Global search (SQLite FTS5 over Page bodies and frontmatter)
- Sidebar showing Spaces and Collections (collapsible, collapsed by default; loose Pages as a separate group)
- Single initial design scheme driven by Figma tokens, plus **in-app customization for colors and typography** (Framework v0.12) — the user can override token values from a settings panel

**Out (post-v1):**

The full catalogue of potential post-v1 features and brainstormed ideas — additional view types, block features, design polish, sync, mobile, plugins, ad-hoc properties, multi-Collection pages, independent UI titles, in-line view embeds in Pages, chip wikilinks, etc. — lives in `// Features//Prospects.md`. Items aren't committed to specific versions; they move from Prospects into `Framework.md` when they become committed work.

---

#### Companion Documents

Per-entity feature specs and cross-cutting topics live in `// Features//`. The PRD captures the high-level architecture; feature docs hold the implementation-level detail.

- **`// Features//Domain-Model.md`** — entity overview, linking model, properties summary, sidebar pattern, resolved decisions, open questions

- **`// Features//Pages.md`** — Pages on-disk shape, frontmatter, block-level features, editor surface (React BlockNote / Swift Phase A + Phase B), wikilinks

- **`// Features//Collections.md`** — `_collection.json` schema, view types, capabilities, loose Pages, embedded views

- **`// Features//Spaces.md`** — `.space.json` schema, drag-and-drop canvas, block types, why Spaces exist

- **`// Features//Architecture.md`** — what survives a stack rebuild (conceptual portability of functionalities), what doesn't, practical discipline

- **`// Features//Properties.md`** — full property type catalog and schema rules

- **`// Features//Prospects.md`** — catalogue of potential post-v1 features and brainstormed ideas (not committed to any version)

Stack-specific reference docs and external-resource catalog at `.claude//` top level:

- **`Resources.md`** — external resources (libraries, documentation) catalog, organized by stack
- **`ReactInfo.md`** — React+Electron implementation reference (editor + Spaces + state-data + Mac integration + distribution)
- **`SwiftInfo.md`** — SwiftUI implementation reference (parallel structure to ReactInfo)

Design-system source of truth at `.claude// Guidelines//UIX-Guide.md` — Figma source-of-truth, dual-export naming, tier model.

Project root docs at `.claude//`: `CLAUDE.md` (router), `Handoff.md` (current state), `History.md` (decisions log), `Framework.md` (roadmap).
