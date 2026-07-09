## Sidebar

Pommora's leading navigation pane in the three-pane shell. It has two regions: a fixed **ribbon** — an icon strip pinned to the left edge — and a **content column** whose contents switch with the ribbon. The ribbon is its own bordered section *outside* the scrolling content, so the content's scroll never crosses or moves it. The content column renders the pre-ordered `NexusTree`, not a raw filesystem view; its rows' kinds come from their sidecars, not folder names. Disclosure state persists per entity across sessions.

### Features

#### II. Ribbon

An icon strip down the left edge, divided from the content by a vertical rule. It's a surface launcher — each icon points at a surface, and surfaces live in different panes:

- **Homepage** — pinned at the top, drawn as the Nexus's profile photo. Selecting it opens the Homepage in the main pane; it doesn't change what the content column shows. Right-click the photo to set or change it.
- **Navigation · Agenda · Contexts · Collections · Settings** — below Homepage, in that default order, and drag-to-reorder (Homepage stays pinned). **Collections · Contexts · Agenda** switch the content column's mode; **Navigation · Settings** are placeholders for future glass-window surfaces and do nothing yet. The mode icons reuse each kind's own entity icon, tracking any personalization override.

The active mode and the ribbon order both persist per-Nexus in `personalization` (→ `Configuration.md`). The ribbon collapses and expands with the sidebar; an always-on ribbon that survives collapse is a later prospect.

#### II. Content Modes

The content column renders one mode at a time (an instant swap — no transition):

- **Collections** — each Collection's root Pages and depth-1 Sets, recursively, plus any user-created sibling sections (their headings stay). A depth-1 Set is selectable and opens its scoped view; a Sub-Set is expand-only; Pages are leaf rows. Full container behaviour → `Collections.md` + `PageSets.md`.
- **Contexts** — the three free-standing tiers as disclosure rows, top to bottom Areas → Topics → Projects, each holding its draggable leaf rows. Full tier behaviour → `Contexts.md`.
- **Agenda** — a read-only list of Tasks then Events, read on demand. Rows are display-only for now; opening an agenda entity is future work → `Agenda.md`.

The mode is the label, so the Contexts and Collections section headings are gone; user-section headings remain (they're user-named groups).

#### II. Creation

Creation is right-click-first: right-click the empty area of a mode for its native "New" menu — a Collection in Collections mode, a tier (Area / Topic / Project) in Contexts mode. Right-clicking a row instead pops that row's own menu, and ⌘N makes a new Page.

#### II. Drag and Drop

Every entity reorders within its parent by drag, and Pages reparent across the tree — between Sets and across Collections. The interaction is the PommoraDND "sidebar" feel: an accent insertion line marks the drop, the picked row stays muted in place, and a ghost rides the cursor. Order persists parent-side — a container's `set_order` / `page_order`, top-level orders in `state.json`. Each mode is its own drag zone. Engine → `PommoraDND.md`.

#### II. Selection

Selection routes the whole detail pane and reads as a Finder-style quaternary-fill pill at row level. A row's kind and ID drive the selection, with the path riding along for rename-safe reconciliation. Switching the ribbon mode never changes the current selection — the main pane holds until a row is clicked.

#### II. Row Labels

A row's label truncates to an ellipsis at rest; hovering reveals the full name by scrolling the label — icon included, the whole label rides one scroll box — within the row, bounded by the sidebar's trailing edge. Content sliding off the left **eclipses** into the glass through a soft mask rather than hard-clipping, but *only once a row is actually scrolled off its start* — a bare hover never dims the icon. Un-hovering slides the label back to the start on the sidebar's shared panel-slide timing. The ellipsis-at-rest → scroll-on-hover primitive (`truncateHoverScroll`) is shared with chips and menu rows; the left-edge eclipse is the sidebar's opt-in.
