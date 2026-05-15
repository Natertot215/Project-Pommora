### Pommora — Product Requirements Document

> Living document. Captures the vision, scope, and key architectural decisions for Pommora.

---

#### Vision

Pommora is a personal management platform that combines Obsidian's customization and local-first ethos with Notion's database and view capabilities. Pages are Markdown files; Collections are folder-based database entities holding property schemas and saved views; Spaces are composed dashboard surfaces. The goal is a simpler Notion that's also a more capable Obsidian — without forcing the trade-offs that push users to bounce between the two.

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

Three top-level entity types — **Pages** (`.md`), **Collections** (folder + `_collection.json` sidecar with a `kind`), **Spaces** (`.space.json` block trees) — plus **Items** (`.json`, Collection-bound row-shaped). The Collection kind splits "what shape does an entry have" at the Collection level rather than per-entry. Full definitions, on-disk shapes, capabilities, linking model → `// Features//Domain-Model.md` + per-entity files (`Pages.md`, `Collections.md`, `Items.md`, `Spaces.md`).

---

#### Core Architectural Decisions

##### Stack

Pommora's stack is SwiftUI. Option 2 (WKWebView hosting a JS editor) is the likely direction for the Pages editor.

| Layer | SwiftUI |
|---|---|
| Desktop shell | SwiftUI on macOS Tahoe (26+) |
| UI framework | SwiftUI primary + AppKit interop where SwiftUI falls short (NSTextView/TextKit 2, NSSplitView, NSItemProvider for some drag/drop) |
| Styling | SwiftUI native semantic colors / Materials / Font scale + small Pommora-brand `Color` / `Font` extensions for accent + code + callout values |
| Editor (Pages) | Option 2 (likely): WKWebView hosting Tiptap, Milkdown, or BlockNote — all translate cleanly to Markdown. Option 1 (more ambitious): native NSTextView/AppKit (fork Clearly or original build). |
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
<picked nexus folder>//                   ← canonical content lives here, syncs with cloud
  Tasks//                                  ← Items collection (_collection.json declares kind: "items")
    _collection.json
    Buy groceries.json
    Fix sink.json
    Steam Deck OLED.json
  Papers//                                 ← Pages collection (_collection.json declares kind: "pages")
    _collection.json
    Attention is all you need.md
    Compiler Construction.md
  Projects//                               ← Pages collection
    _collection.json
    Pommora.md
  Quick note.md                            ← Loose Page
  Bookmark.json                            ← Loose Item
  Inbox//                                  ← Cosmetic folder (no _collection.json)
    Travel ideas.md                        ← Loose Page (folder is just organization)
    Saved tweet.json                       ← Loose Item
  attachments//
    image.png
  .nexus//                               ← app-internal config (vault-portable, syncs)
    nexus.json                             ← Codable VaultIdentity: ULID + createdAt (v0.1a)
    state.json                             ← Codable nexus-portable user state (v0.2+)
    spaces//                               ← (v0.10+)
      Homepage.space.json                  ← Seeded on first launch; default landing
      Pommora.space.json
  .trash//                                 ← Deleted entities (nexus-local trash; v1+)
    Tasks//
      Old task.json                        ← Preserves original relative path

~//Library//Application Support//com.nathantaichman.Pommora//   ← machine-specific, never syncs
  state.json                               ← Codable AppState: bookmark + future recent-nexuses
  nexuses//
    <nexus-id>//                           ← keyed by ULID from .nexus/nexus.json
      nexus.db                           ← SQLite index (v0.2+); regeneratable
      cache//                              ← future
```

A folder is a **Collection** if and only if it contains a `_collection.json` file. Folders without one are cosmetic filesystem organization — files inside them are loose (no schema-conforming properties). The app-internal config folder is `.nexus//` (leading dot, hidden — matches `.obsidian` convention). Deleted entities go to **`.trash//`** at the nexus root; the entity's original relative path is preserved inside `.trash//` so restoration is a straight file move.

**Why the SQLite index lives outside the nexus:** placing `nexus.db` inside a vault that may be on iCloud Drive / Dropbox / another sync surface risks file-conflict-driven corruption (SQLite's locking assumes single-host filesystem semantics). The Application Support per-nexus subdir, keyed by ULID, survives vault rename/move and is marked `isExcludedFromBackupKey` so iCloud Backup skips the regeneratable index. The vault folder stays purely canonical content; the index is the app's private mirror.

##### Pages

Each Page is a `.md` file with:

- **YAML frontmatter** — `id` (ULID), `icon`, `spaces` (multi-relation to Space IDs), and property values from the Collection's schema. No `collection` field (membership is by folder location). No `title` field (filename = title). Members conform to the Collection's schema; loose Pages hold only built-in fields.
- **Markdown body** — prose.

Pages are **Markdown documents, not block surfaces** — one continuous Markdown stream from top to bottom. They support all standard Markdown (paragraphs, headings H1–H5 in v0's type scale (no H6 token), lists, code blocks + inline code (SF Mono; `code//` tokens), images, GFM tables, blockquotes, horizontal rules) plus **two Pommora-specific rendering directives**:

- **`@Columns`** — multi-column rendering directive. Marks a section of the Page to render as N horizontal columns (equidistant width by child count). The Markdown content inside is unchanged; the directive only affects layout. On disk the file is one continuous Markdown document with `:::columns` fenced notation.
- **`:::callout`** — outlined-box callout. Renders content as a minimally-rounded bordered box, distinct from blockquotes (which are filled with a left-side emphasis bar). Default text uses the primary text token; border binds to an independent `callout//` token.

Both directives resolve cleanly when read by an external Markdown tool — the directive notation appears as inert text and the content is standard Markdown. Same principle as Notion's Markdown export. The previously-proposed `@View` (in-line database view embed in a Page) is deferred to v2+; embedded Collection views remain available *inside Spaces* as widget blocks.

**Headings are foldable by default** — clicking the chevron on any heading collapses the content below until the next equal-or-higher heading. Built-in UI behavior on every heading, not a directive; no on-disk syntax. There is no separate `:::toggle` construct.

**Block-level features as a project term belongs to Spaces only.** Pages don't have blocks.

`@View` inside the prose flow is the harder direction on Option 1 (native editor); on Option 2 (WKWebView + JS editor), the same node-component approach BlockNote and Tiptap support directly applies. Embedded views remain available inside Spaces regardless of editor path.

##### Collections

Each Collection is a folder + a `_collection.json` schema sidecar inside it (Make.md folder-notes pattern):

```json
{
  "id": "01HXXXXX...",
  "kind": "pages",                /* or "items" — set at creation, persistent */
  "icon": "checkbox",
  "properties": [ /* property schema entries */ ],
  "views": [ /* saved view configurations */ ]
}
```

The Collection's title comes from the folder name. Members are uniformly one kind: all `.md` Pages if `kind: "pages"`; all `.json` Items if `kind: "items"`. Changing `kind` after creation is not supported in v1. Collections have no text-editor surface — they're pure database viewers (table / board / list / cards / gallery).

##### Spaces

Each Space is a `.space.json` file in `.nexus// spaces//` holding the full block tree:

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
    { "type": "callout", "text": "..." }
  ]
}
```

The Space's title comes from the filename. Spaces hold both *text blocks* (paragraph, headings, lists, callouts, code, columns, image) and *widget blocks* (linked-pages, embedded-collection-view, link-list) intermixed.

##### Local-End Translation Principle

**The local file is the spec, not the render.** Anything SQLite computes — the contents of a board view, the cards in a gallery, aggregated counts, relation lookups — is referenced by directive but never inlined. An agent reading the file sees the directive and understands the structure; the data lives in SQLite and is rendered only inside Pommora.

##### SQLite Schema

Five tables. All rebuilt from files on launch or on demand. Property schemas live inside per-Collection JSON files (canonical) and are loaded into memory at app start.

```sql
-- Page index (rebuilt from .md files in the nexus)
CREATE TABLE pages (
  id TEXT PRIMARY KEY,                -- ULID from frontmatter
  path TEXT UNIQUE NOT NULL,          -- 'Tasks// Buy groceries.md' or 'Quick note.md'
  collection_id TEXT,                 -- derived from path; NULL for loose Pages
  title TEXT NOT NULL,                -- derived from filename (basename minus '.md')
  icon TEXT,
  frontmatter JSON NOT NULL,
  body TEXT NOT NULL,                 -- raw markdown body (powers FTS)
  modified_at INTEGER NOT NULL
);

-- Item index (rebuilt from .json files inside Items collections or loose locations)
CREATE TABLE items (
  id TEXT PRIMARY KEY,                -- ULID from the Item file
  path TEXT UNIQUE NOT NULL,
  collection_id TEXT,                 -- derived from path; NULL for loose Items
  title TEXT NOT NULL,                -- derived from filename (basename minus '.json')
  icon TEXT,
  description TEXT,                   -- short plain-text field
  properties JSON NOT NULL,           -- schema-conforming property values
  spaces JSON NOT NULL,               -- Space ID multi-relation
  modified_at INTEGER NOT NULL
);

-- Collection index (rebuilt from _collection.json files)
CREATE TABLE collections (
  id TEXT PRIMARY KEY,
  folder_path TEXT UNIQUE NOT NULL,
  kind TEXT NOT NULL,                 -- 'pages' | 'items'; set at creation, persistent
  title TEXT NOT NULL,                -- derived from folder name
  icon TEXT,
  properties JSON NOT NULL,
  views JSON NOT NULL,
  modified_at INTEGER NOT NULL
);

-- Space index (rebuilt from .space.json files)
CREATE TABLE spaces (
  id TEXT PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,                -- derived from filename (basename minus '.space.json')
  icon TEXT,
  blocks JSON NOT NULL,
  modified_at INTEGER NOT NULL
);

-- Link index (rebuilt from files)
CREATE TABLE links (
  from_id TEXT NOT NULL,         -- page or item id
  from_kind TEXT NOT NULL,       -- 'page' | 'item'
  to_id TEXT NOT NULL,           -- page, item, collection, or space id
  to_kind TEXT NOT NULL,         -- 'page' | 'item' | 'collection' | 'space'
  property TEXT                  -- NULL for inline wikilinks; 'collection', 'spaces', 'related', etc. for property links
);

CREATE INDEX idx_pages_collection ON pages(collection_id);
CREATE INDEX idx_items_collection ON items(collection_id);
CREATE INDEX idx_links_from ON links(from_id, from_kind);
CREATE INDEX idx_links_to   ON links(to_id, to_kind);
```

Queries use SQLite's JSON1 extension to reach into property values:

```sql
SELECT * FROM pages
WHERE collection_id = '01HXXXXX...'
  AND json_extract(frontmatter, '$.properties.status') = 'Active';
```

##### Property Model

- **Property values** in Page frontmatter (`.md`) or Item `properties` key (`.json`).
- **Property schemas** live inside each Collection's `_collection.json`.
- **Properties are scoped per Collection** and created on-demand, Notion-style.
- **Members must conform to the Collection's schema.** Ad-hoc page-local properties are out of v1 scope (Prospect). Loose entities have no schema and hold only built-in fields.
- **V1 catalog (8 types):** number, checkbox, date, date & time, select, multi-select, relation, URL. **No free-form text type** — title is the filename; "text-shaped" values use Select / Multi-select with creatable options. **No dedicated Status type** — Status-like properties are Selects named "Status."
- **Move-strip rule (Notion-style):** moving a member across Collections (or in/out of loose state) strips properties not in the destination's schema. No quarantine, no backup. The user gets a **simple confirmation warning** listing which properties will be stripped before the move proceeds.

Full type catalog, config shapes, schema-mutation rules → `// Features//Properties.md`.

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

1. **Inside a Collection** — saved views configured per-Collection, stored in `_collection.json`. Switch via tabs above the view area.
2. **Embedded as a Space widget** — the "Embedded Collection View" widget renders any saved Collection view inside a Space, with per-embed overrides on filter / sort / group / shown-properties.

Each view spec carries: source Collection (implicit from sidecar location), view type, filter expression, sort, group-by property, properties to display, and (for gallery) cover image property. Filter expressions parse to a small DSL and translate to parameterized `json_extract` SQL queries. **Filters and sorts on a view never modify the source Collection** — purely view-local.

In-line view embeds *inside Pages* (a `@View` directive in prose) are out of v1. The v2+ revisit is feasible on Option 2 (WKWebView + JS editor); harder on Option 1 (native editor) due to layout-attachment complexity.

##### Columns

The `@Columns` directive is supported in both Pages and Spaces. **V1 columns are equidistant** — widths divide the available horizontal space evenly by child count. No per-column width configuration in v1.

Implementation is deferred to the editor build; the directive ships as a Pommora-specific render with equidistant child columns (file format stays standard `:::columns` Markdown on disk).

##### Sidebar Navigation

The sidebar surfaces curated, app-relevant navigation, not filesystem layout. Three top-level headings, all collapsible disclosure groups, all default-collapsed. **The user can drag the headings to reorder them**; initial-boot order is Spaces / Saved / Collections.

- **Spaces** — list of all Spaces. Each Space is a leaf label (no disclosure); clicking opens the Space.
- **Saved** — placeholder heading only. Pinning is **out of v1 scope**; the heading exists in the sidebar architecture so it doesn't need to be re-added later, but it's non-operational in v1. Pinning ships post-v1.
- **Collections** — list of all Collections, kind-agnostic. Each Collection is a folder-style disclosure expanding to its members (`.md` Pages or `.json` Items as leaf labels). A per-row kind indicator (Page-icon vs Item-icon) is a setting-toggleable Prospect.

**Loose Pages and loose Items aren't a sidebar group.** Reach them via search or wikilinks. Cosmetic folders (no `_collection.json`) carry no semantic meaning and are user-driven filesystem organization only. No raw filesystem view in v1.

"Collapsed-by-default disclosure" is the general default for any hierarchical UI elsewhere in the app.

##### Three-Pane Shell + Property Panel

Sidebar (default 240px) / main (flex) / inspector (default 280px). Both side panes are drag-resizable via splitters from v0.0 onward; resized widths persist across launches. Default window size 1200×800; minimum 960×560 (keeps both side panes legible). The inspector's **default view is the property panel** for the active Page in v1; an **AI chat interface** is a planned future addition to the inspector (post-v1; a frontend to Nathan's existing local CLI — not an API integration; see `// Features//Prospects.md`). (Items don't use the inspector — they open in an Item window. See "Item Window" below.)

**Window chrome — macOS unified title bar.** No separate Pommora title bar. The macOS traffic-light buttons render in the top-left at runtime (OS-rendered, not custom) within the sidebar pane's column. The top-bar tab row sits in the same horizontal band as the traffic lights, starting from the right edge of the sidebar column and spanning across the main pane. Pattern: Obsidian / Notion / Linear on macOS.

Below-heading and page-bottom property-panel placements are post-v1 Prospects.

Built on SwiftUI's two-column `NavigationSplitView(sidebar:detail:)` with the inspector pane attached to the detail column via the `.inspector(isPresented:)` modifier (macOS 14+). This is Apple's idiomatic pattern for main-pane + supplementary side panel — used by Mail, Notes, and Pages. Inspector width is set via `.inspectorColumnWidth(min:ideal:max:)`; the toolbar toggle integrates automatically via `InspectorCommands`. The third-column variant of `NavigationSplitView` was considered and rejected — that column is designed for selected-item drill-down (Mail's list → message-list → message), not for a contextual supplementary panel.

##### Top-Bar Tabs

The main pane is **multi-tabbed.** A row of tabs sits at the top of the main pane; each tab represents one open view — a Page, a Collection (with its active saved view), or a Space. One tab is active; clicking another switches the main pane to that view. Pattern reference: Obsidian's tab UI, Notion's tab navigation.

- **New tab** — `+` button at the end of the tab row, or `Cmd+T` (opens an empty new-tab state with a quick-open / recents palette).
- **Close tab** — per-tab `×`, or `Cmd+W`.
- **Reorder** — drag tabs left / right.
- **Cycle** — `Cmd+1..9` jumps to that-numbered tab; `Ctrl+Tab` / `Ctrl+Shift+Tab` cycle next / previous.
- **Multiple tabs** — open at once; each preserves internal state (scroll position, selection where reasonable) when switching away and back.

Tab labels show the entity's title (= filename) and a small icon (entity-kind icon: page / collection / space). The active tab is visually continuous with the main pane it heads; inactive tabs sit recessed. Implementation uses SwiftUI `Material` for the tab-row backdrop with the active tab distinguished via opacity / brightness on top — no custom color extensions for tab states.

**State persistence:** open tabs and the active tab persist across launches. Stored in app settings.

**Items don't get their own tabs in v1** — selecting an Item opens an **Item window** (popover anchored to the trigger), not a tab. Tabs are reserved for full-pane views (Pages, Collections, Spaces).

##### Item Window

Items don't open as tabs or in the inspector. Selecting an Item — from a sidebar row, a table cell in a Collection view, a wikilink, or an embedded Collection view — opens an **Item window**: a popover-style floating surface anchored to where the click occurred. Reference: Calendar.app event-detail popover; macOS Finder's Get Info window.

The window contains:

- **Title** — the filename, editable in place (rename retitles the underlying `.json` file).
- **Properties** — typed inputs for each property in the parent Items collection's schema. Loose Items show no schema-conforming properties (only built-in fields).
- **Description** — plain-text field, **hard cap 250 characters**. Sized so the field fits within the window without scrolling; keeps the JSON file small and cloud-sync-friendly.

Dismissed by clicking outside, pressing Esc, or closing the window.

##### First-Launch Experience

On first launch, after the user picks a nexus location, Pommora opens with empty sidebars plus a single seeded `Homepage` Space at `.nexus// spaces// Homepage.space.json`, opened as the landing surface. No tutorial, no walkthrough wizard.

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

- **Pages** — Markdown documents with YAML frontmatter; editor surface is one of two SwiftUI options (Option 1 native source-with-decorations text editor, or Option 2 WKWebView hosting a JS editor). Standard Markdown (paragraphs, headings H1–H5 in v0's type scale (foldable by default), lists, code blocks + inline code (SF Mono; `code//` tokens), images, GFM tables, blockquotes, horizontal rules) plus two Pommora-specific rendering directives (`@Columns` + `:::callout`). Blockquotes and callouts are distinct constructs (blockquote = filled with left bar; callout = outlined). Members conform to a Pages collection's schema; loose Pages hold only built-in fields.
- **Collections** — folder + `_collection.json` schema sidecar. Typed at creation (`"kind": "pages" | "items"`). Property schemas + saved view configurations inside the sidecar. Five view types (table / board / list / cards / gallery) with per-view filter / sort / group / shown-properties controls.
- **Items** — `.json` files. Filename = title; member Items conform to the Collection schema; loose Items carry only built-in fields. `id`, `icon`, `description` (plain text, 250-char cap), `spaces`, timestamps. No Markdown body. Open in an Item window (popover), not a tab.
- **Spaces** — Notion-page-style composition surfaces (`.space.json`) with a full block tree. Text blocks + widget blocks intermixed. Drag-to-arrange and slash-menu insertion.
- Property panel UI driven by Collection schemas, all v1 property types (8).
- Wikilinks (styled colored inline text).
- Automatic file rename with cross-nexus wikilink rewrite.
- File watcher keeping SQLite synced.
- Global search (SQLite FTS5 over Page bodies and frontmatter).
- Three-heading sidebar (Spaces / Saved / Collections), user-reorderable, default-collapsed. Saved is a non-operational placeholder heading in v1 (pinning is post-v1). Loose entities reachable via search or wikilinks (not a sidebar group).
- Single initial design scheme, plus in-app customization for accent color and font size (Framework v0.12). SwiftUI native handles everything else.

**Out (post-v1):**

Post-v1 features — additional view types, block features, sync, mobile, plugins, ad-hoc properties, multi-Collection pages, independent UI titles, in-line view embeds in Pages, chip wikilinks, Item ↔ Page promotion, board view drag-to-rewrite-frontmatter, etc. — live in `// Features//Prospects.md`. Items move from Prospects into `Framework.md` when committed.
