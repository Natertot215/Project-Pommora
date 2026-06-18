### Pommora — Product Requirements Document

> Living document. Captures the vision, scope, and key product decisions for Pommora.

---

### Vision

A personal management platform combining Obsidian's customization and local-first ethos with Notion's database and view capabilities. Pommora is a simpler Notion that's also a more capable Obsidian — without the trade-offs that push people to bounce between the two.

Pages are Markdown documents that live inside **Page Types** — folder-based database entities that carry a shared property schema and saved views. **Page Collections** organize within a Type, optionally subdivided by schema-less **Page Sets**. **Contexts** (Areas / Topics / Projects) are free-standing organization surfaces that tag and gather everything else. UI labels default to "Vault" + "Collection" + "Set".

### Why

- **Obsidian** gives UI-level customization and a transparent local-first file model, but its Markdown core can't express columns, side-by-side callouts, or in-line filtered views without heavy plugins.
- **Notion's** in-line database views — filtered, sorted, and regrouped per page without altering the source — are its defining feature, and Obsidian's file-as-document model can't match it natively.
- Obsidian shines until you need real task management or cross-page coordination. Notion shines until you hit an interface decision you can't change.

Pommora's bet: a Markdown-canonical foundation with a fast property and query engine, and a clean separation between content (Pages), structure (Page Types + Collections), and interface (Contexts) — delivering Notion's most-loved features without giving up Obsidian's open, hackable, local-first nature.

### Audience and Posture

- Personal-first, single-user, Mac-first for v1. iOS/iPad is long-term intent.
- Always open-source.
- Architected so future cross-device and cloud sync stay viable, but neither is a v1 concern. Multi-user collaboration and a plugin system are out of scope indefinitely.

---

### Domain Model

Two layers, PARA-aligned.

**Organization layer — Contexts** (3 tiers): **Areas** (broad life domains) / **Topics** (subject areas) / **Projects**. The three tiers are *free-standing* — no containment, no parents. Each is simply a place that operational entities can be tagged into, and each tier's display label is configurable per Nexus. Contexts are live, fully-editable surfaces of views and queries — never read-only snapshots. (Context-to-context relations are a deferred design pass.)

**Operational layer — Pages + Agenda:**

- **Pages** — Markdown documents inside a **Page Type** (the schema-bearing container). Page Collections organize within a Type and share its schema; Page Sets optionally subdivide a Collection and inherit everything from it. The hierarchy is intentionally shallow — Type, Collection, Set — so structure stays legible. UI labels default to "Vault" / "Collection" / "Set".
- **Agenda** — the calendar layer, split into two entities: **Tasks** (reminder-shaped) and **Events** (calendar-event-shaped). "Agenda" names the parent layer that holds both. EventKit integration is opt-in.

**Singleton — Homepage**: a composed-blocks dashboard, one per Nexus, that can embed anything.

**Settings**: per-Nexus, user-overridable UI labels and accent color.

Full definitions and linking model → `// Features//Domain-Model.md` plus per-entity files (`Contexts.md`, `PageTypes.md`, `Pages.md`, `Agenda.md`, `Homepage.md`).

---

### Core Product Decisions

#### Stack

Pommora is a native macOS app built in SwiftUI, with AppKit interop where SwiftUI falls short (notably the Pages editor's text view). The Pages editor is a native text foundation, which gives the app system Writing Tools, Look Up / Translate, spell-check, and dynamic system colors for free. A pure data-and-parsing layer is kept independent of the UI so the same logic stays portable. Full editor spec → `// Features//PageEditor.md`.

#### Three load-bearing constraints

1. **Portability of functionalities.** The product's value — file formats, domain model, property catalog, connection behavior, design values, UX patterns — survives a stack rebuild. The codebase is replaceable; the documented decisions are what endure. Detail → `// Features//Architecture.md`.

2. **Cloud-sync-ready and cross-nexus queryable.** Types and Collections aren't isolated silos — any Page or Context can query, link, or embed any Type's contents regardless of where it sits on disk. The on-disk model maps cleanly onto a cloud database, so sync arrives later as an additive translation rather than a rewrite. A Nexus placed in iCloud Drive, Dropbox, or any synced folder already gets device-to-device sync for free.

3. **Agent-legible files.** External agents — Claude, MCP clients, any tool with filesystem access — can read Pommora's entire structured graph (Pages, schemas, Areas, relations, properties) straight from the files, with no tool-call round-trips. This is the differentiator from Notion-via-MCP (tool-mediated and opaque) and from Obsidian (legible but unstructured). Any choice that trades file-legibility for app-internal convenience violates this constraint.

#### Storage Philosophy

**Files are canonical.** Everything a user creates lives as a plain file in a folder they pick (default `~//PommoraNexus//`), and that folder is the whole product — it can sit in any synced location and travels intact. Pages are Markdown with YAML frontmatter; Agenda entries, Contexts, and all configuration are JSON. There is no database of record holding user data hostage.

**Kind comes from the folder's sidecar, not the file.** Each container folder carries a small config sidecar that declares what it is and what schema its contents share. A folder *is* a Page Type because it holds a Page Type sidecar — folder names stay freely renameable, and classification never depends on a file extension or a frontmatter field.

**Foreign data is preserved.** Frontmatter Pommora doesn't recognize is carried through untouched on every write, so the format stays friendly to other tools.

**The index is disposable.** A local search-and-query index makes views and full-text search fast, but it holds no user data — only titles, properties, links, and relations, never Page bodies. It lives inside the Nexus so it travels with the vault, and it is fully regeneratable: if it's missing or stale, it rebuilds itself from the files. Deletions move to an in-Nexus trash that preserves each item's original location.

Full on-disk spec → `// Features//Architecture.md`.

#### Pages

A Page is a Markdown document — one continuous stream, not a stack of blocks. The filename is the title (there is no separate title field), and the parent Page Type is implied by location. Pages conform to their Type's schema.

Beyond standard Markdown (headings, lists, code, images, tables, blockquotes), Pages support two Pommora rendering directives: **Columns** (an evenly-divided multi-column section) and **Callouts** (an outlined box, distinct from a blockquote's emphasis bar). Both degrade to plain Markdown for external tools. Headings fold by default. Full detail → `// Features//Pages.md`.

#### Page Types, Collections, and Sets

A **Page Type** is the operational container — a folder carrying a shared property schema and a set of saved views. It has no text editor of its own; it's a pure database surface (table / board / list / cards / gallery). **Page Collections** are sub-folders that share the Type's schema but carry their own ordering and views. **Page Sets** optionally subdivide a Collection, inheriting everything from it. Moving a Page across Types strips any properties the destination schema doesn't define, with a confirmation warning. Each Type chooses where its Pages open — a compact preview window, or the main detail pane. Full detail → `// Features//PageTypes.md` + `// Features//Sets.md`.

#### Contexts (Areas / Topics / Projects)

Three free-standing tiers — none contains or parents another. Each is a folder with a config sidecar and a reserved composed-blocks field for the live views and queries it will hold. Tier labels are user-configurable per Nexus (singular and plural). Context-to-context relations are a deferred design pass. Full detail → `// Features//Contexts.md`.

#### Agenda (Tasks + Events)

The calendar layer, split into two distinct entities:

- **Tasks** — reminder-shaped: optional due date, an optional "not before" start, completion, priority, recurrence, and alarms. A built-in, non-deletable **Status** property bridges to the system reminder's completed state.
- **Events** — calendar-event-shaped: required start and end, optional location, all-day, recurrence, and alarms. A built-in **Status** property is user-set and decoupled from the dates — the user marks it to track their own engagement with the event.

Each kind carries its own schema sidecar, and the layer self-seeds on a new Nexus. EventKit sync is opt-in via Settings (the data layer is in place; live mirroring is planned). Agenda has no dedicated sidebar section — it surfaces through the Calendar entry. UI labels ("Task" / "Event") are renameable. Full detail → `// Features//Agenda.md`.

#### Homepage

A singleton composed-blocks dashboard — the landing surface, seeded on first launch and not user-deletable. It shares the Contexts block shape and is designed to embed anything. Full detail → `// Features//Homepage.md`.

#### Properties

Property **schemas** are scoped per Type and edited from a Notion-style settings sheet; property **values** live in each entity's frontmatter or JSON. A property's identity is a stable internal ID, so renaming its display label never touches member files. The v1 catalog deliberately omits free-form text (the filename is the title; "text-shaped" values use creatable Select options). **Status** uses three fixed structural groups (Upcoming / In Progress / Done) for calendar compatibility, with user-editable options and renamable group labels. A **File / Attachment** type copies files into the Nexus and stores relative paths. Every property can carry an icon.

The only relation-type connection is the context-tier link — there are no user-creatable relation properties, and option lists are managed only through the schema editor, never created inline. Full catalog → `// Features//Properties.md`.

#### Views

V1 view types: **Table**, **Board**, **List**, **Gallery**, and **Cards**. Views appear in two places: saved as tabs inside any storage container (every container, not just the schema-bearing Type, can carry its own view configuration), and embedded as a widget inside a Context or the Homepage with per-embed overrides on filter, sort, group, and shown properties. Embedded views are fully editable in place. A view never modifies its source — filtering and sorting are presentation only. In-line view embeds inside Page bodies are a Prospect. Full detail → `// Features//Views.md`.

#### The Local-End Translation Principle

**The local file is the spec, not the render.** Anything the index computes — board contents, gallery cards, aggregated counts, relation lookups — is referenced by directive in the file, never inlined. An external agent reads the directive and understands the structure; the rendered data lives only inside Pommora.

#### Connections

Connections are body `[[Title]]` links — the sole connection syntax, rendered as styled colored inline text (Obsidian-style), never as Notion-style chips. The disk format stays plain and Obsidian-compatible. In v1, connections resolve by globally-unique title, so a rename cascades: every referencing body is rewritten to the new title atomically. Relation values, by contrast, are ID-keyed and need no rewrite on rename. A file watcher keeps the index synced when files change outside the app. Canonical spec → `// Features//Connections.md`.

#### Sidebar Navigation

The sidebar surfaces curated, app-relevant navigation — not a raw filesystem view. Top-level groups, default-collapsed and user-reorderable: a heading-less **Pinned** section (Homepage / Calendar / Recents) at the top, then **Contexts** (Areas / Topics / Projects as disclosure rows), then **Vaults** (Page Types disclosing their Collections, Sets, and Pages), then any user-created vault sections. Agenda surfaces through the Pinned Calendar entry rather than its own rows.

Creation is right-click-only — no "+ New" buttons. A context menu offers "New X" options scoped to the cursor location, and a global quick-capture hotkey is the discoverable counterpart for creating from anywhere. Full spec → `// Features//Sidebar.md`.

#### App Shell + Property Surfaces

A three-pane shell: sidebar / main / inspector, both side panes drag-resizable with persisted widths. The inspector hosts the **Claude chat** (a frontend to a local CLI, not an API integration). Properties do *not* live in that inspector — they live with the content: a pulldown at the top of a Page in the main window, and a compact frontmatter inspector in the preview window.

The window uses the macOS unified title bar — no separate Pommora chrome — with a single toolbar holding the sidebar toggle, back/forward, the navigation dropdown, and the inspector toggle, in the Mail / Notes / Finder idiom. The shell is built on SwiftUI's two-column split view with the inspector as a supplementary panel.

#### Detail Header + Banner

Every entity opens under a consistent header. Containers (Page Types and Collections) can set an optional **banner** image that bleeds edge-to-edge under the side panes; when a banner is set, the title overlays its bottom-leading corner, otherwise it sits as plain chrome above the content. An unset banner shows a hover-revealed "Add Banner" affordance.

#### Navigation Dropdown

The main pane is single-pane; navigation history lives in a dropdown button in the toolbar — a popover with two lists, user-curated **Pinned** and auto-tracked **Recents** (in the Things 3 Quick Find idiom). Single-click highlights, double-click opens; state persists per-Nexus. Full spec → `// Features//NavDropdown.md`.

#### Page Preview Window

Pages from a preview-mode vault open in a lightweight **preview window** — one per Page, child-attached to the main window so it rides its moves and never behaves as its own app window. It opens locked (read-only) with the inspector open; unlocking reveals an Open action, and a shortcut promotes the Page into the main detail pane. A Page already shown in the main pane never previews. Full spec → `// Features//Pages.md`.

#### First-Launch Experience

After the user picks a Nexus location, Pommora opens with empty sidebars and a seeded Homepage as the landing surface. The Nexus's singletons — Homepage, tier and label config, Settings, and the Tasks and Events folders — auto-seed on first launch. No tutorial, no walkthrough wizard.

#### Design System

SwiftUI-native idioms (semantic colors, Materials, the system Font scale, SF Symbols) plus a small set of Pommora-brand extensions for values the system doesn't cover (accent, code, callout, blockquote). V1 ships one scheme plus in-app customization of accent color and font size. Full philosophy → `// Guidelines//Design.md`; symbol assignments → `// Guidelines//Symbols.md`.

#### macOS Integration

First-party system integration with no companion bundles: QuickLook previews, Spotlight indexing with deep-link continuation, a Share Extension, a "New Page from Selection" Service, a menu-bar extra, Finder drag-out, full accessibility, window-state restoration across Spaces, and `pommora://` deep links.

#### Distribution

Auto-update for the direct build, TestFlight for Mac, and Mac App Store readiness via sandbox-safe security-scoped access to the user's chosen Nexus folder — no feature blocker.

---

### v1 Scope

**In:**

- **Contexts** (Areas / Topics / Projects) — free-standing organization surfaces with per-Nexus configurable labels, all three in one sidebar section. No containment, no parents, no cross-tier links.
- **Page Types + Collections + Sets + Pages** — schema-bearing Types, schema-sharing Collections, schema-less Sets, and Markdown Pages. UI labels renameable. Each Type chooses preview-window vs. main-pane opening.
- **Pages** — Markdown + frontmatter (including per-tier multi-relations), native editor, Columns and Callouts.
- **Agenda** — Tasks and Events with a required built-in Status on each; sync opt-in (data layer in place, live mirroring planned); surfaced through the Calendar entry, no sidebar section.
- **Homepage** — singleton dashboard, seeded on first launch.
- **Settings** — storage, label wiring across renameable surfaces, and accent-color reading now; full editing UI planned.
- Property panel driven by each entity's schema; the full v1 catalog including Status and File / Attachment; per-view configuration (sort / group / filter / layout / visibility).
- Connections — `[[Page]]` inline links, the sole connection syntax.
- Automatic rename with connection cascade across all referencing bodies.
- A file watcher keeping the index synced, and global full-text search.
- Sidebar (Pinned / Contexts / Vaults) plus user-creatable vault sections, reorderable and default-collapsed.
- Inline editing of embedded views.
- One design scheme plus in-app accent and font-size customization.

**Out (post-v1):** additional view types, block features, sync, mobile, plugins, ad-hoc properties, multi-Collection pages, independent UI titles, in-line view embeds in Pages, chip-style connections, full Settings editing UI, and more — see `// Features//Prospects.md`. Prospects move into `Framework.md` when committed.

---

#### What Items Were (historical pointer)

Items were Pommora's second operational entity beside Pages, from the founding paradigm until the 2026-06 PagesV2 collapse, when the two converged to redundancy — same file format, property catalog, container shape, and tier relations. The per-vault open mode (preview vs. window) absorbed the only remaining difference onto a single Page entity. The collapse deleted rather than migrated; legacy Item folders adopt as ordinary Page Types, and the retired item-link syntax is now plain preserved text. Full record → `History.md`.
