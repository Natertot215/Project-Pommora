### Navigation

How you get from where you are to where you want to be — the single main pane's history and breadcrumb for local moves, and a shared **Navigation layer** for the cross-tree jumps (recent, pinned, searched, favorited) the sidebar tree alone can't serve.

The main pane shows one entity at a time — selecting one in the sidebar, a table, or a breadcrumb routes the whole detail view, replacing the previous selection. A session-local history records each selection, and the footer breadcrumb shows the current location. Above that sits the Navigation layer: a per-Nexus, UI-agnostic store of recents, pins, and favorites, plus client-side title search, surfaced through two entry points that read the same data in different shapes.

### The Navigation Layer

The shared wayfinding store beneath both navigation surfaces — built once, read everywhere. Three things live in it:

- **Recents** — an auto history stream, most-recent-first, deduped, capped by a generous roll-off. Every navigation records into it (all kinds, the Homepage included); Back/Forward steps don't. It records through the same selection path the sidebar uses, so anything you can open lands in recents.
- **Temp-pins** — a flag that floats a recents entry to the top and holds it there until unpinned. The "open tabs" feel without a tab bar: a working set pinned above the churn of history. Pins live on the recents stream, not a separate list.
- **Favorites** — the durable, explicitly-curated list. Mutated only by an explicit add / remove / reorder, never automatically.

Entries store only their identity (kind + id + path) — every title, icon, and location is resolved **live** against the current tree at render, so a rename or move is always current and never cached stale. An entry that no longer resolves (deleted, or read against a different Nexus after a switch) is hidden at render but never deleted from storage, so a Nexus switch can't silently wipe favorites. Recents and favorites both **sync** (per-Nexus sidecars under `.nexus/`, last-writer-wins) so they follow you across machines; the recents stream persists debounced, pins and favorites immediately, and a durable write is flushed before quit.

**Search** is client-side and title-based: a fuzzy match over a flattened index of every Collection, Set, Page (page titles included), Context, and the Homepage, plus a cached Agenda snapshot so Tasks and Events are findable. The index is memoized per tree, so typing filters without re-walking the tree.

### Features

#### II. Back and Forward

Back and Forward walk a session history of selections, stepping to the previous or next entity and skipping any deleted along the way. A history step re-selects without re-recording, so stepping doesn't reshuffle the history. The toolbar buttons disable at each end. The history is in-memory and session-local — it isn't persisted.

#### II. Breadcrumb

The footer carries a breadcrumb of the current entity's container path, plus a dimmed forward **ghost crumb** for the last-visited Page within the open container — a one-click way back into where you were. Full footer → `Subfield.md`.

#### II. NavPane and NavMenu

Two surfaces over the one layer, same data, different presentation:

- **NavPane** — a non-modal, movable, resizable floating glass mini-shell summoned by the sidebar ribbon's Navigation icon or `⌘O` (rebindable via the `commands` map). It's a `GlassPane` (the dimmer picker frost) that always opens centered — its size persists across opens, its position doesn't — with a glass rail beside a main frame: a search field over the recents list, each row reading (icon)(title … container path) with the title and path each eclipse-scrolling when long, and both lists carrying the shared scroll-edge fade for a list longer than the pane. It resizes from four corners plus a rail split, doesn't steal focus (the search field focuses on open, nothing behind is blocked), and dismisses on Escape, `⌘O`, or the ribbon. Per-row actions (pin / favorite / remove) live in a context menu, not the row.
- **NavMenu** — the toolbar Navigation button's dropdown, rendered on the shared beak-glass menu surface sized to the Settings dropdown's footprint. Its content is undecided — a placeholder pending the call on what a compact dropdown nav holds versus the fuller NavPane.

The NavPane's row list + shell are built and live; the open visual work is its **gallery** form (the recents as Figma cards, behind the rail's Style toggle), the **pin / current-item marker** on the row inset, and the NavMenu's content.

### Pending

**Navigation design + advanced modes:** The Figma-designed content for both surfaces (the gallery cards, the dropdown layout, per-row affordances). NavPane's **preview mode** — a toggle tied to the page open-in setting that slides the pane to an in-pane page preview with a chevron-back to the nav view, rather than routing the main pane. Agenda entries are search-listable now but route nowhere: their card resolution and a compact placeholder preview window belong to Agenda's own feature. Whether the non-Page kinds (Collections, Sets, Contexts, Homepage) show as cards or filter out is an open display call. Body / full-text search (today's is title-only) waits on a query layer. The block-surface Insert / Link-Page picker is a future consumer of this layer's page-filtered recents (→ `SurfacePM.md`).
