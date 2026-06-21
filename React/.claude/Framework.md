## Framework — React Rebuild Roadmap

Where the rebuild stands against Swift. The rebuild **goes as it goes** — no phase plan, no fixed sequence; it catches up to Swift, never ahead of it (the only intentional aheads are below). Shipped detail → `History.md`; session state → `Handoff.md`.

Scope is the **core 7** — data · properties · connections · markdown · navigation · table · gallery — plus the deferred frontier (block editor, Agenda surfacing, Board/List/Cards renderers, settings UI, global search, LLM-chat inspector, OS integrations).

### Rebuilt

Carried over from Swift and working:

- **Data layer** (headless) — CRUD, properties, connections + tier relations, SQLite index, Agenda.
- **Read + navigation** — nexus walk → glass sidebar → selection/detail routing → the pure `filter → group → sort` view pipeline.
- **Write path** — real Mac app; one `mutate` IPC, native right-click menus + ⌘N + inline rename, live index refresh + a file watcher.
- **Sidebar** — full CRUD + drag-and-drop (every entity reorders; pages reparent across the tree).
- **Container views** — Vault / Collection / Context / Homepage over a shared scaffold, with a pages table + image banners.
- **Page editor (MarkdownPM)** — the dynamic-syntax CodeMirror 6 port; core constructs in (remainder under Pending).
- **Design system** — tokenized (color primitives + accent + tint + typography + chips) + a live showcase.
- **Glass + window chrome** — CSS frost material; traffic-lights-in-sidebar window.
- **Drag engine (PommoraDND)** — the in-house sort/reorder substrate behind a swappable seam.

### Pending

Swift has these; React doesn't yet:

- **Editor constructs** — callouts, wikilink 3-state resolution, image/latex, heading folding, the `[[` autocomplete panel, native context menu + stats footer.
- **Page properties UI** — frontmatter inspector + per-type cell editors (data layer already done).
- **Full view system** — Gallery renderer, the view switcher, and per-view Saved-View config (the Table renders today).
- **Agenda surfacing** — Tasks/Events UI + calendar (data layer already done).
- **Homepage widgets** — the composed-blocks dashboard surface.
- **Contexts block editor** — the live, editable block surface for Areas / Topics / Projects.
- **Settings editing UI** — `.nexus/settings.json` (labels + accent) gets a real editor.

### Ahead

What React now has that Swift doesn't:

- **Comment-preserving page writes** — the yaml Document API keeps foreign frontmatter keys *and* YAML comments; Swift's merge preserves keys but drops comments.
- ** Disclosure Animations —** Disclosure animations on surfaces such as sidebars, in-page headings, and others have been and will continue to be used whereas the same is constrained to Swift’s frameworks on the Swift side; purely a visual advancement.
- **Index-independent connections** — `[[link]]` resolution + rename cascade run on a pure in-memory Map, so the SQLite index is purely an accelerator; Swift's resolver + cascade require the index present and fresh.
- **Single-source data-layer core** — one parameterized schema-ops, one folder-entity CRUD, one agenda CRUD, and one zod schema serving both strict and lenient reads, where Swift duplicates across services / managers / shapes. (Tracked for backport in Swift's `Swift-Improvements-from-React-Rebuild.md`.)
