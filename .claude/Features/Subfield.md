## Subfield (Footer)

The bottom bar of every content view, named the **Subfield**. A breadcrumb on the left, per-view items on the right. Lives in `Detail/Subfield/`, mounted by `DetailPane` below the routed view.

> **v1 — deliberately small. Much more is planned** (see *Roadmap* below): user-reorderable items, user-defined items, and per-view configuration. The structure here is the seam for all of it.

### What It Shows

- **Breadcrumb** (`SubfieldBreadcrumb` + `crumbs.ts`) — the ancestor chain for the open view. Collection + depth-1 Set segments navigate (`store.select`); deeper Sub-Sets are plain; the current segment is inert. A container view also shows the **ghost crumb**: the last page you backed out of, rendered dimmed but still clickable to jump forward. The trail is `store.trail` (last-visited page per container id), recorded while a page is open.
- **Per-view items** (`subfieldItems.tsx`) — a registry keyed by view kind. v1: **pages** show `lines · words · characters` (`subfieldStats.ts`, Markdown-stripped prose), **live as you type** — the editor's `liveBody` buffer in the store feeds the count ahead of the debounced save; **Collections / Sets** show a **+** add-menu (New Page / New container). **Homepage + Contexts show no Subfield yet** — nothing to display there until they have content.

### Look

- Type is the **Subline** scale (8/10 by 1.25 — the app's smallest), bound to `subline.emphasized`. Text is the single **`label.control`** token; the glyphs (breadcrumb `›`, stats `·`, the `+`) are **`label.secondary`** and a step larger + bolder. Fixed bar height (`--subline-h`) so switching to a view with fewer items never janks it. The top divider is the 1.25px title-divider hairline. Left/right indent sits at the gutter midpoint (full gutter read wonky at this size).
- **App-level collapse** — one `store.subfieldExpanded` flag shared across every view. A hover-revealed chevron rides directly above the bar (mirrors its height, bounces with the slide); the reveal zone is a large bottom-right region tracked in `DetailPane` (`.subfield-near`) so it never blocks clicks beneath.

### Persistence

Per-nexus, in `.nexus/settings.json` under an app-specific **`subfield`** foreign key (unknown keys are preserved, so it round-trips safely): `{ order: per-view item ids, expanded }`. Read/written by `main/settings.ts` `readSubfield`/`writeSubfield`; surfaced over `subfield:get` / `subfield:set` IPC (mirrors the `folds` seam). The store loads it once on nexus open and persists on every change. Item ids from disk are validated against the registry before render.

### Roadmap (Planned)

- **Reorder** the items via PommoraDND (horizontal) — the persisted `order` is already wired; the drag UI is the next piece.
- **User-defined items**, possibly **scoped** — the registry + per-view `order` is the extensibility seam.
- **Per-view configuration UI** — choosing which items each view kind shows.
- Bring the Subfield to **Homepage + Contexts** once they have content worth surfacing.
