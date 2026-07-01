### Pommora — Product Requirements Document

> Living document — the vision, scope, and product decisions for Pommora. The build is React + Electron; the on-disk model, domain, and design values are stack-independent by design.

---

### Vision

A personal management platform combining Obsidian's customization and local-first ethos with Notion's database and view capabilities. Pommora is a simpler Notion that's also a more capable Obsidian — without the trade-offs that push people to bounce between the two.

Pages are Markdown documents that live inside **Page Collections** — folder-based database entities that carry a shared property schema and saved views. A Collection nests **Page Sets** to any depth: schema-less organizing sub-folders that inherit the Collection's schema. **Contexts** (Areas / Topics / Projects) are free-standing organization surfaces that tag and gather everything else. The whole product is a folder of plain files the user owns outright.

### Why

- **Obsidian** gives UI-level customization and a transparent local-first file model, but its Markdown core can't express columns, side-by-side callouts, or in-line filtered views without heavy plugins.

- **Notion's** in-line database views — filtered, sorted, and regrouped per page without altering the source — are its defining feature, and Obsidian's file-as-document model can't match it natively.

- Obsidian shines until you need real task management or cross-page coordination. Notion shines until you hit an interface decision you can't change.

Pommora's bet: a Markdown-canonical foundation with a fast property and query engine, and a clean separation between content (Pages), structure (Page Collections + Sets), and interface (Contexts) — delivering Notion's most-loved features without giving up Obsidian's open, hackable, local-first nature.

### Audience and Posture

- Personal-first, single-user, Mac-first for v1. iOS/iPad is long-term intent.
- Always open-source.
- Architected so future cross-device and cloud sync stay viable, but neither is a v1 concern. Multi-user collaboration and a plugin system are out of scope indefinitely.

---

### Domain Model

Two layers, PARA-aligned. The organization layer holds categorical anchors; the operational layer holds the actual data. Operational entities relate to organization entities through per-tier multi-relation fields.

#### Organization layer — Contexts

Three **free-standing** tiers. None contains, parents, or is restricted to another — a Project is not "inside" a Topic; a Topic does not belong to an Area. Each operational entity tags any tiers independently. Per-tier labels are user-configurable; tier *numbers* are load-bearing in code.

| Tier | Default label | Role |
|---|---|---|
| 1 | Areas | Broad life domains — Personal, Academics, Work |
| 2 | Topics | Subject areas — Productivity, Side Projects, Reading List |
| 3 | Projects | Specifics — CS 161, Pommora, "Atomic Habits" |

#### Operational layer

| Entity | Role | Default UI label |
|---|---|---|
| **Page Collection** | Schema-bearing top container for Pages | "Collection" |
| **Page Set** | Recursive sub-folder inside a Collection (any depth); inherits the schema. Depth-1 carries its own views; deeper is plain | "Set" / "Sub-Set" |
| **Page** | Markdown document — prose plus frontmatter | "Page" |
| **Task** | Reminder-shaped: due date, completion, priority | "Task" |
| **Event** | Calendar-event-shaped: start + end, location | "Event" |

Tasks and Events sit under the **Agenda** parent schema. The Page Collection's property schema applies to every Page inside it at any depth — all Sets inherit it whole.

#### Singletons

- **Homepage** — one composed-blocks dashboard per Nexus, the landing surface; seeded on first launch, not user-deletable.
- **Settings** — per-Nexus, user-overridable UI labels and accent color.

#### Identity and linking

- **`id`** — a stable ULID assigned at creation, never changing. Every cross-reference (connections, tier links, the index) is ID-keyed.
- **Title** — the display name, carried as the filename (minus extension), freely renameable. Renames are filesystem renames; ID-keyed references resolve to the current title at render time. Within a container, a colliding Page create auto-disambiguates and a rename is rejected. Titles aren't unique Nexus-wide — a connection to a title shared by two Pages resolves as ambiguous.

Operational entities tag Contexts through `tier1` / `tier2` / `tier3` multi-relation fields — bare ULID arrays at the frontmatter or JSON root, the **only** relation-type connection. Page-to-Page links are body `[[Title]]` connections. Full model and the linking catalog → `Features/Structure.md` plus the per-entity docs.

---

### Core Product Decisions

#### Stack

Pommora is an Electron desktop app — a React + TypeScript renderer over a Node main process that owns the filesystem, bridged by a narrow typed IPC. State lives in a Zustand store fed by one eager nexus walk; tables render over TanStack. The Pages editor is **MarkdownPM** — a CodeMirror 6 build where Markdown markers show as raw source on the caret line and render styled when the caret leaves.

**No dependency lock-in.** Every library sits behind a thin seam — the editor, YAML, IDs, the SQLite accelerator, the glass material, the drag engine — so it's swappable without touching callers. Version numbers are compatibility pins, not endorsements.

The main process is the sole filesystem owner; the renderer never touches Node. One shared types module is the cross-process contract both sides import, and IPC never throws across the boundary — handlers return a result envelope. Full architecture → `Features/Architecture.md`.

#### Three load-bearing constraints

1. **Portability of functionalities.** The product's value — file formats, domain model, property catalog, connection behavior, design values, UX patterns — survives a stack rebuild. The codebase is replaceable; the documented decisions endure. This React build is itself the proof: the same on-disk model and domain carried over as data plus pure logic.

2. **Cloud-sync-ready and cross-nexus queryable.** Collections aren't isolated silos — property definitions live nexus-wide, so one shared property id means the same thing in every Collection that assigns it and a single query matches across all of them; any Page or Context can query, link, or embed any Collection's contents regardless of where it sits on disk. The on-disk model maps cleanly onto a cloud database, so sync arrives later as an additive translation rather than a rewrite. A Nexus placed in iCloud Drive, Dropbox, or any synced folder already gets device-to-device sync for free.

3. **Agent-legible files.** External agents — Claude, MCP clients, any tool with filesystem access — read Pommora's entire structured graph (Pages, schemas, Areas, relations, properties) straight from plain text files. The bar is convention-aware, not instant to an outsider: a `[[wikilink]]` hides a resolver yet reads perfectly to anyone who knows the system. We strongly prefer formats readable without Pommora's running code, and treat relaxing that for a genuine need as a tradeoff to raise — but the firm line holds: no user data is trapped in a binary blob or held only in the regeneratable index.

#### Storage Philosophy

**Files are canonical.** Everything a user creates lives as a plain file in a folder they pick, and that folder is the whole product — it can sit in any synced location and travels intact. Pages are Markdown with YAML frontmatter; Agenda entries, Contexts, and all configuration are JSON. No database of record holds user data.

**Kind comes from the folder's sidecar, not the file.** Each container folder carries a small config sidecar that declares what it is and what schema its contents share — `_pagecollection.json`, `_pageset.json`, `_area.json` / `_topic.json` / `_project.json`, `_taskconfig.json` / `_eventconfig.json`. A folder *is* a Page Collection because it holds the Page Collection sidecar — folder names stay freely renameable, and classification never depends on a file extension or a frontmatter field. App-internal config and the index live under a hidden `.nexus/` folder that travels with the Nexus.

**Foreign data is preserved.** Frontmatter and sidecar keys Pommora doesn't recognize are carried through untouched on every write — and the page writer preserves YAML comments too, so opening a folder that's also an Obsidian vault leaves notes byte-identical until the user edits them.

**The index is disposable and off the read path.** Reads are a single filesystem walk; nothing user-created depends on a database being present. A SQLite index returns as a regeneratable accelerator for queries — it holds titles, properties, links, and relations, never Page bodies, and rebuilds itself from the files if it's missing or stale. Deletions move to an in-Nexus trash that preserves each item's original location.

Full on-disk spec → `Features/Architecture.md`.

#### Pages

A Page is a Markdown document — one continuous stream, not a stack of blocks. The filename is the title (there is no separate title field), and the parent Page Collection is implied by location. Pages conform to their Collection's schema; values live in YAML frontmatter, keyed by stable property ID.

Pages support everything in standard Markdown — paragraphs, headings, bulleted / numbered / task lists, fenced and inline code, images, GFM tables, blockquotes, and horizontal rules — all of which round-trip natively to any external tool. **Headings fold**, with the fold state held in a per-machine file rather than the portable `.md`. On top of that, Pages support two Pommora rendering directives, each degrading to plain Markdown for external tools:

- **Columns** — a section rendered in evenly-divided horizontal columns; visual layout only.
- **Callouts** — content rendered as an outlined box, distinct from a blockquote's filled left-bar emphasis.

Each Collection decides where its Pages open — the main detail pane, or a compact preview card. Editor architecture → `Features/MarkdownPM.md`; the page entity → `Features/Pages.md`.

#### Page Collections and Sets

A **Page Collection** is the operational container — a top-level folder whose sidecar assigns the nexus-wide properties shared by every Page inside it, plus its saved views, child ordering, and an open-in mode. It has no text editor of its own; it's a pure database surface (table / gallery, with more renderers to come).

A Collection nests **Page Sets** to any depth — schema-less sub-folders that inherit the Collection's whole schema. The first level (a "Set") carries its own views and sorting and is selectable; deeper levels ("Sub-Sets") are plain organizing folders. Nesting is unbounded, with no roll-up — discovery, rendering, and navigation recurse on the real folder tree.

Moving a Page **across Collections** never strips — its values ride along, the destination shows only the properties it assigns, and the rest sit inert in frontmatter until assigned there; moving **within** a Collection (between its Sets and root, at any depth) changes nothing, since the schema is shared. The schema is edited from a Collection Settings surface; per-view configuration (sort / filter / group / layout) is a separate per-view surface. Full detail → `Features/Collections.md` + `Features/PageSets.md`.

#### Contexts (Areas / Topics / Projects)

Three free-standing tiers, each a folder with a config sidecar carrying `id`, `tier`, an optional `icon`, an optional `banner`, and a `blocks` array reserved for the future composed-blocks surface. There is no `parents` field and no containment. The folder name is the title; renaming in the UI renames the folder.

A tier relation is a **dual surface**: an operational entity tags a Context by holding its ID in `tier1` / `tier2` / `tier3`, and the Context reads back every entity that tags it through a reverse index query — Contexts carry no schema and store no inbound list. Context-to-context relations are a deferred design pass. Full detail → `Features/Contexts.md`.

#### Agenda (Tasks + Events)

The calendar layer, split into two distinct entities mirroring EventKit, each stored in its own singleton folder discovered by a config sidecar:

- **Tasks** (`.task.json`) — optional due date, an optional "not before" start, completion, priority, recurrence, and alarms.
- **Events** (`.event.json`) — required start and end, optional location, all-day, recurrence, and alarms.

Both carry the shared property catalog and `tier1` / `tier2` / `tier3` relations, plus a built-in, non-deletable **Status** whose three groups (Upcoming / In Progress / Done) map cleanly onto reminder/calendar semantics. EventKit sync is opt-in. Full detail → `Features/Agenda.md`.

#### Properties

Property **definitions** live in one nexus-wide registry (`.nexus/properties.json`) — defined once, assigned by any Collection, one shared definition and option set everywhere; an Agenda config keeps its own definitions. Property **values** live in each entity's frontmatter or JSON. A property's identity is a stable ULID, so renaming its display label never touches member files. The v1 catalog:

- **Number**, **Checkbox**, **Date** (date-only or with-time), **Select**, **Multi-select**, **Status**, **URL**, **Relation** (tier-only), **Last Edited Time** (derived), and **File / Attachment**.

There is no free-form text type — the filename is the title, and text-shaped values use creatable Select options. **Status** uses three fixed structural groups for calendar compatibility, with user-editable options inside each. There are no user-creatable relation properties — the context-tier link is the sole relation — and option lists are managed through the schema editor, never typed inline. Status and Relation values use a tagged on-disk shape (`$status` / `$rel`) so an agent can identify them from any single file without the schema. Full catalog → `Features/Properties.md`.

#### Views

A view is a saved presentation of a Collection's (or depth-1 Set's) Pages — it never modifies its source. Each container's sidecar holds an ordered list of saved views; the active view is tracked per-machine so switching it doesn't churn the synced file. A view records its renderer type, property layout (column order plus a hidden set), and its sort / filter / group config, fed by one pure pipeline: **fetch → filter → group → sort**.

V1 view types are **Table**, **Board**, **List**, **Gallery**, and **Cards**. Views also embed as widgets inside a Context or the Homepage with per-embed overrides. Two capabilities go beyond the baseline: multi-key sort, and recursive AND/OR filter groups. Full detail → `Features/Views.md`.

#### The Local-End Translation Principle

**The local file is the spec, not the render.** Anything the index computes — board contents, gallery cards, aggregated counts, relation lookups — is referenced by directive in the file, never inlined. An external agent reads the directive and understands the structure; the rendered data lives only inside Pommora.

#### Connections

Connections are body `[[Title]]` links — the sole connection syntax, rendered as styled colored inline text (Obsidian-style), never as Notion-style chips. The disk format stays plain and Obsidian-compatible: just the bracketed title, no embedded id or alias.

In v1, connections resolve by title. A uniquely-held title is live and navigable; a title held by two Pages is ambiguous; an unmatched one renders as inert literal text with the brackets visible, going live the moment a single matching Page exists. Renaming a target **cascades** atomically — every referencing body is rewritten to the new title, or the whole rename rolls back. Resolution and cascade run on an in-memory map, so the SQLite index stays a pure accelerator the feature never depends on. Typing `[[` opens an autocomplete listing Pages Nexus-wide. Canonical spec → `Features/Connections.md`.

#### Sidebar Navigation

The sidebar surfaces curated, app-relevant navigation — not a raw filesystem view. Top to bottom: a **Nexus header** (profile image, title, subtitle) whose selection opens the Homepage; then **Contexts** (Areas / Topics / Projects as disclosure rows); then **Collections** (each disclosing its root Pages, its Sets, and recursively its Sub-Sets and Pages); then any user-created Collection sections that group Collections for navigation only. Agenda surfaces through a Calendar entry rather than its own rows.

Every entity reorders by drag-and-drop, and Pages reparent across the tree. Creation is right-click-first — a context menu offers "New X" options scoped to the cursor location — complemented by a hover "+" on headings. Full spec → `Features/Sidebar.md`.

#### App Shell + Property Surfaces

A three-pane shell: sidebar / main / inspector, both side panes drag-resizable with persisted widths. The inspector is reserved for the **Claude chat** (a frontend to a local CLI, not an API integration); its own design pass is pending. Properties do *not* live there — they live with the content, in a panel attached to the Page. Inspector → `Features/Inspector.md`.

Every entity opens under a consistent header. Containers can set an optional **banner** image that bleeds edge-to-edge under the side panes; when set, the title overlays its bottom-leading corner, and the banner and title lock in place while the body scrolls.

#### Navigation History

The main pane is single-pane. **Back / Forward** step a navigation history, and a footer **breadcrumb** — with a dimmed forward ghost-crumb for the last-visited page — tracks location. A toolbar **dropdown** with a user-curated **Pinned** list and an auto-tracked **Recents** list (LRU, capped) is the fuller history surface. Full spec → `Features/Navigation.md`.

#### First-Launch Experience

On launch Pommora restores the last opened Nexus or opens empty — never a launch modal. ⌘O picks a Nexus folder, and a dropped folder opens the same way. The Nexus's singletons — Homepage, tier and label config, Settings, and the Tasks and Events folders — auto-seed on first sight. Opening a folder that isn't yet a Nexus runs an idempotent adoption pass that classifies each folder by position and leaves existing notes untouched until edited. No tutorial, no walkthrough wizard.

#### Design System

A two-tier token system — primitives (one neutral base at opacities, accent, tints, the type ramp) feeding semantic aliases — authored in code and sourced from a Figma library. Colors are authored as hex; the token layer is the single source. Glass uses two materials: a CSS **frost** for Window and Surface, and Apple **"Liquid Glass"** for Controls. Motion is tokenized, with a canonical bloom-and-retract for panes and menus. V1 ships one scheme plus in-app accent customization. Full philosophy → `Features/Design.md`; type → `Features/Typography.md`; motion → `Features/Interaction.md`.

#### macOS Integration

First-party where Electron reaches it — the native menu bar, `pommora://` deep links, notifications, dark mode, and a tray icon. QuickLook previews, a Share Extension, and deep Spotlight indexing require a companion Swift bundle shipped alongside. Finder file-promise drag-out, true sidebar vibrancy, and Spaces-aware window restoration are Electron ceilings to ship a companion for or accept. Detail → `Resources/Mac-Integration.md`.

#### Distribution

The current build is ad-hoc-signed. A distributable release adds electron-builder packaging, electron-updater auto-update over GitHub Releases for the direct build, and `@electron/notarize` for a Developer ID identity under the hardened runtime. A Mac App Store build runs sandboxed with security-scoped access to the user-picked Nexus folder — the same constraint a sandboxed native build carries, no feature blocker. Detail → `Resources/Distribution.md`.

---

### v1 Scope

- **Contexts** (Areas / Topics / Projects) — free-standing organization surfaces with per-Nexus configurable labels, all three in one sidebar section. No containment, no parents, no cross-tier links.
- **Page Collections + Sets + Pages** — schema-bearing Collections, schema-less recursive Sets, and Markdown Pages. UI labels renameable. Each Collection chooses preview-card vs. main-pane opening.
- **Pages** — Markdown + frontmatter (including per-tier multi-relations), the MarkdownPM editor, Columns and Callouts.
- **Agenda** — Tasks and Events with a required built-in Status on each; sync opt-in; reached through a Calendar entry, no sidebar section.
- **Homepage** — singleton dashboard, seeded on first launch.
- **Settings** — storage, label wiring across renameable surfaces, and accent-color reading now; full editing UI planned.
- Property panel driven by each entity's schema, the full v1 catalog (including Status and File / Attachment), and per-view configuration (sort / group / filter / layout / visibility).
- Connections — `[[Page]]` inline links, the sole connection syntax, with automatic rename cascade across all referencing bodies.
- A file watcher keeping the index synced, and global full-text search.
- Sidebar (Nexus header / Contexts / Collections) plus user-creatable Collection sections, reorderable with drag-and-drop.
- Inline editing of embedded views.
- One design scheme plus in-app accent customization.

**Out (post-v1):** additional view types beyond the v1 set, synced page-body blocks, sync, mobile, plugins, ad-hoc properties, multi-Collection pages, independent UI titles, in-line view embeds in Pages, chip-style connections, full Settings editing UI, and more — see **Prospects** below.

#### What Items Were (historical pointer)

Items were Pommora's second operational entity beside Pages until the two converged to redundancy — identical file format, property catalog, container shape, and tier relations. The per-collection open mode (preview vs. window) absorbed the last difference onto a single Page entity; legacy Item folders adopt as ordinary Page Collections, and the retired item-link syntax is now plain preserved text. Full record → `History.md`.
---

### Prospects

Ideas considered and deliberately parked — not on the active roadmap (`Framework.md`), not yet planned. Each notes what it is and why it's waiting; promote one into `Planning/` when it becomes active.

**Animated Syntax Reveal (Editor):** A quick slide/fade as MarkdownPM reveals a line's raw syntax under the caret, instead of the instant snap.

**Parked — not cleanly achievable against the current design.** The editor hides markers with a zero-width `Decoration.replace` (no DOM element — deliberately, so surrounding text never shifts), so there is nothing to animate *out* when the caret leaves; and revealed inline markers (`**`, `_`) are bare document text with no class to animate *in*. A true in-and-out slide would mean keeping every marker permanently mounted and animating its **width**, which jiggles the whole line's text on every caret move — worse than the clean snap, and it fights the no-shift design the editor is built around.

The realistic version is an **entry-only fade-in**: wrap revealed markers in a shared class and play a keyframe on mount, reusing the motion tokens; exit stays instant (CodeMirror removes the element with no exit hook). Revisit only if the soft-reveal feel is wanted enough to accept the entry-only asymmetry.
