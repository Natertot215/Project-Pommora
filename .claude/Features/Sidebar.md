## Sidebar

Pommora's leading navigation pane in the three-pane shell. Top to bottom: a **Nexus header**, **Contexts**, **Collections**, and any user-created Collection sections. It renders the pre-ordered `NexusTree`, not a raw filesystem view. The sidebar is a curated navigation surface — section headings are pure UI groupings with no on-disk counterpart, and each row's kind comes from its sidecar, not its folder name. Disclosure state persists per entity across sessions.

### Features

#### II. Nexus Header

A header at the very top carries the Nexus's profile image, its name (the root folder's basename, renamed by double-click), and a subtitle. Selecting it opens the Homepage in the main pane.

#### II. Contexts

The three tiers surface as three disclosure rows, top to bottom Areas → Topics → Projects. A tier row is structural — never selectable, open by default — and its entities render as draggable leaf rows inside it. All three tiers' entities use the grid icon. Full tier behavior → `Contexts.md`.

#### II. Collections, Sets, and Pages

The Collections section discloses each Collection's root Pages and its depth-1 Sets; each Set discloses its Pages and its Sub-Sets, recursively. A depth-1 Set is selectable and opens its scoped view; a Sub-Set is expand-only. Pages are leaf rows. Clicking a Collection opens its active view, a Set its own view, and a Page opens in the main pane. Full container behavior → `Collections.md` + `PageSets.md`.

#### II. User Sections

User-created sibling sections below the default Collections section group Collections for navigation only — membership lives in a config file and never moves a folder on disk. A Collection sits in at most one section; ungrouped Collections stay in the default section.

#### II. Creation

Creation is right-click-first: a native context menu offers "New X" options scoped to the clicked location — a right-click on a Collection makes a Page in that Collection, and each tier creates only its own tier. A hover "+" on section and tier headings offers the same, and ⌘N makes a new Page.

#### II. Drag and Drop

Every entity reorders within its parent by drag, and Pages reparent across the tree — between Sets and across Collections. The interaction is the PommoraDND "sidebar" feel: an accent insertion line marks the drop, the picked row stays muted in place, and a ghost rides the cursor. Order persists parent-side — a container's `set_order` / `page_order`, top-level orders in `state.json`. Engine → `PommoraDND.md`.

#### II. Selection

Selection routes the whole detail pane and reads as a Finder-style quaternary-fill pill at row level. A row's kind and ID drive the selection, with the path riding along for rename-safe reconciliation.

### Pending

**Calendar Pin:** The sidebar entry point for Agenda — a Calendar pin opening the combined Tasks-and-Events surface, with right-click New Task / New Event. Agenda's data layer is in place; the pin and its surface aren't built → `Agenda.md`.
