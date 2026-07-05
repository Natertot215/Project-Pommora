### Structure (Domain Model)

Pommora is organized as **two layers** with PARA-aligned naming. The organization layer (Contexts) holds categorical anchors; the operational layer (Pages + Agenda) holds the data. Operational entities relate to organization entities through per-tier multi-relation fields. Per-entity detail lives in the dedicated feature docs.

The organization layer is a single kind in three tiers; the operational layer is two kinds (Pages and Agenda); two singletons sit beside them. A **Nexus** is the root — one folder holding everything.

| PARA term | Pommora term | Layer |
|---|---|---|
| (workspace) | **Nexus** | Root |
| Areas | **Areas** (tier 1) | Organization |
| Topics | **Topics** (tier 2) | Organization |
| Projects | **Projects** (tier 3) | Organization |
| Resources | **Pages + Agenda** | Operational |
| (dashboard) | **Homepage** | Singleton |
| Archive | `.trash/` | (system) |

PARA's "Projects" maps to Pommora's tier-3 Projects by design.

### Organization Layer

#### II. Contexts

Three **free-standing** tiers — Areas (1), Topics (2), Projects (3) — each a folder with a config sidecar under `.nexus/`. None contains, parents, or is restricted to another; operational entities tag any tiers independently. Contexts carry no pages and no schema — they're categorical anchors things point at. Full spec → `Contexts.md`.

### Operational Layer

#### II. Pages

| Entity | Role | Default UI label |
|---|---|---|
| **Page Collection** | Top container for Pages; assigns their nexus-wide properties | "Collection" |
| **Page Set** | Recursive sub-folder inside a Collection (any depth); inherits the schema. Depth-1 carries its own views; deeper is plain | "Set" / "Sub-Set" |
| **Page** | Markdown document — prose plus frontmatter | "Page" |

Property definitions live in the nexus-wide registry (`.nexus/properties.json`); a Collection assigns which ones its Pages validate, and that assigned schema applies at any depth — all Sets inherit it. On disk: a Collection is `_pagecollection.json`, every Set is `_pageset.json`, a Page is a `.md` file. The code-level names are `PageCollection` (top) and `PageSet` (recursive); UI labels default to "Collection" / "Set" and rename per Nexus. Full spec → `Collections.md` + `PageSets.md` + `Pages.md`.

#### II. Agenda

The parent schema holding two peer kinds, each with its own config sidecar and the shared property catalog plus tier relations:

- **Task** (`.task.json`) — reminder-shaped: due date, completion, priority.
- **Event** (`.event.json`) — calendar-event-shaped: start, end, location.

Full spec → `Agenda.md`; the property catalog across all kinds → `Properties.md`.

### Singletons

#### II. Homepage

One per Nexus at `.nexus/homepage.json` — a composed-blocks dashboard sharing the Context block shape, with no `id`, `tier`, or `parents` (the file location is its identity). The **Nexus header** at the top of the sidebar is its entry point: selecting it opens the Homepage in the main pane. Seeded on first launch and not user-deletable.

#### II. Settings

Per-Nexus config at `.nexus/settings.json` — UI labels, a profile image and subtitle, the app's `subfield` (footer) key, and the `personalization` block. Labels feed every renameable surface. The full config model — the personalization block, its apply-map, write discipline, and the per-device app config → `Configuration.md`.

### Identity + Linking

#### II. Entity Identity vs Title

- **`id`** — a stable ULID assigned at creation, never changing. Every cross-reference (connections, tier links, the index) is ID-keyed. An adopted entity with no stored id gets a stable id hashed from its Nexus-relative path.

- **Title** — the display name, carried as the filename minus extension, freely renameable. Renames are filesystem renames; ID-keyed references resolve to the current title at render time, never rewritten.

Names are unique within a folder (filename = title): a colliding Page create auto-disambiguates, and a colliding rename is rejected. Titles aren't unique Nexus-wide — Pages in different folders may share one, and a connection to a shared title resolves as ambiguous (→ `Connections.md`).

#### II. The Linking Model

| Link | Stored as | Purpose |
|---|---|---|
| Page → Page (connection) | plain `[[Title]]` in the body, resolved by unique title | Inline reference |
| Operational entity → Context (tier N) | `tierN: [<id>, ...]` at the frontmatter / JSON root | Categorical assignment |
| Context → Context | None — tiers are free-standing (deferred) | — |
| Page → Collection / Set | Implicit by file location | Membership |

Tier relations are the **only** relation-type connection, stored as bare ULID arrays (rename-safe by ID). Body connections are plain `[[Title]]`, rename-safe by cascade. Full rules → `Connections.md` + `Properties.md`.

### Architecture

#### II. On-Disk Model

Files are canonical: Pages are `.md` (YAML frontmatter + body); Contexts, Agenda, sidecars, and all config are JSON. **Kind authority is the parent folder's sidecar filename**, never the extension or a frontmatter field. Foreign keys — and YAML comments on pages — are preserved by value on every write. A SQLite index is a regeneratable accelerator that sits off the read path; losing it costs nothing. Full on-disk spec + the read/IPC engine → `Architecture.md`.

#### II. The NexusTree Contract

The read side is one eager, read-only walk producing a pre-ordered `NexusTree` — Nexus identity, the Homepage banner, the three context tiers, ungrouped top-level Collections (each nesting its Sets then Pages), user-grouped Collection sections, the label set, and the resolved accent — consumed by the renderer without re-sorting. Agenda singletons are discovered but not surfaced. Full shape → `Architecture.md`.

### Pending

**Homepage Block Surface:** The composed-blocks dashboard — embedded views, linked-content widgets, a mini-calendar — sharing the editor that Contexts will use. The Homepage renders only its banner under the Nexus header until that editor lands.

**Settings Editing UI:** The `personalization` block has a write path — a generic setter plus a live apply-map — but no UI yet, so accent, connection color, and the interface toggles are set in `.nexus/settings.json` directly for now; labels and profile are likewise hand-edited. A real settings surface — accent picker, toggle rows, label rename forms, tier-label configuration — is planned. Full config model + the planned editor → `Configuration.md`.
