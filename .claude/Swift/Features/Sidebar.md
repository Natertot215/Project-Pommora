### Sidebar

Pommora's leading-edge navigation pane in the three-pane shell. Top-level groups, top to bottom: a heading-less **Pinned** section, then **Contexts** (one section holding the three free-standing tiers), then **Collections**, then any user-created Collection sections.

Per-entity routing rules → [[Domain-Model]]; CRUD UI patterns → `// Guidelines//CRUD-Patterns.md`.

---

#### Layout

- **Pinned (heading-less, at top)** — Homepage / Calendar / Recents.
- **Contexts** — one section under a fixed "Contexts" label holding three disclosure rows, Areas / Topics / Projects. Each tier row reads its label from its renameable per-tier config and expands to that tier's entities as flat leaf rows.
- **Collections** — chevron disclosure of Page Collections (UI label "Collection"); each Collection discloses its root Pages plus its depth-1 Page Sets (label "Set"); each Set discloses its Pages plus its Sub-Sets, recursively. Pages show their frontmatter icon or the default page glyph; Collections and Sets use a folder glyph (per-container icon overridable). The labels rename via Settings; the Collections header default is "Collections".
- **User sections** — user-created sibling sections after Collections, each grouping Collections the user moved into it; labels rename inline.

Tasks and Events surface through the Calendar pin, not a dedicated heading. The Calendar pin opens the Calendar detail surface (Tasks above, Events below); right-clicking it offers New Task / New Event for quick capture.

No always-visible "New" buttons — creation is right-click first, complemented by a hover-only "+" on section and tier headings (hidden at rest). A fuller discoverability layer arrives separately via quick-capture.

##### Section grouping (sidecar-driven)

There are no wrapper folders on disk (see [[Resources/II. Pommora/II. Swift/II. Features/Architecture]]); the sidebar groups each root folder by its per-kind sidecar — the Context sidecars feed the Areas / Topics / Projects tier rows, the Page Collection sidecar feeds the Collections section (or the user section the Collection was moved into), and the Agenda sidecars surface through the Calendar pin rather than any section. The sidecar is the kind authority — it, not the folder name, decides the grouping — and the section headings are pure UI groupings with no on-disk counterpart. A folder without a recognized sidecar triggers the adopter on next launch, but only when there's something to migrate; a fresh non-Pommora folder stays invisible to discovery.

---

#### Section-by-section

##### Pinned (top — no heading)

Three fixed entries render at the top without a heading: Homepage opens the Homepage singleton (see [[Homepage]]); Calendar opens the Calendar detail surface, Tasks above and Events below, with right-click New Task / New Event for quick capture (see [[Resources/II. Pommora/II. Swift/II. Features/Agenda]]); Recents shows the Navigation's Recents store as a full-frame view (see [[Resources/II. Pommora/II. Swift/II. Features/Navigation]]). The section wrapper persists for the future user-pinning feature, gaining a "Saved" header when that ships; entry labels rename via Settings. User-pinning of arbitrary entities is post-v1 — the section gains its heading and "+" affordance then, and the three defaults become movable and removable.

##### Contexts

One section under a fixed "Contexts" label holding exactly three tier disclosure rows — Areas, Topics, Projects — as homogeneous siblings. The tiers are free-standing: no containment, no parents, no cross-tier nesting (see [[Resources/II. Pommora/II. Swift/II. Features/Contexts]]).

Tier rows are expand/collapse only — they carry no selection, so clicking anywhere toggles disclosure; the label reads from the tier config, and creation is via the row's hover "+" or right-click. Entity rows render as flat leaf rows: Area, Topic, and Project rows are all bare icon-plus-title leaves with no parent indicator, since the tiers don't nest. Per-tier drag-reorder persists sibling order per Nexus; clicking an entity opens its detail surface. The tier rows mirror the disclosure shape used by Collections.

##### Collections (default label)

Chevron disclosure. Each Collection discloses both its root Pages and its depth-1 Page Sets as children; each Set discloses its Pages plus any Sub-Sets; each Sub-Set discloses its Pages plus deeper Sub-Sets, recursively.

Depth-1 Set rows are selectable and open their own scoped view. Sub-Set rows (depth-2+) are expandable but never selectable — no selection chrome, and clicking only toggles disclosure (Sub-Sets have no detail view). Drag-reorder inside a container is two-zone: Sets reorder among Sets, Pages among Pages, and cross-zone drags are rejected; order persists parent-side. Collections don't display tagging (they're operational, not categorical). Clicking a Collection opens its active saved view (Sets nested structurally), a depth-1 Set opens its own scoped view, and a Page routes per the Collection's open-in mode — the main detail pane (default) or a preview window (see [[Resources/II. Pommora/II. Swift/II. Features/Pages]]).

##### User Collection sections (navigation-only grouping)

User-creatable sections that group Collections below the default Collections section, persisted in a sidebar-sections sidecar; writes are atomic and failures surface as a sidebar toast.

Grouping is navigation-only — it never moves a Collection folder on disk; membership lives solely in the config. A Collection sits in at most one section; moving it strips it from every other section in the same write. Ungrouped Collections stay in the default Collections section, and deleting a section ungroups its Collections back to it (no Collection data touched). An empty section renders header-only, never a placeholder row. A dangling Collection ID (Collection deleted after grouping) stays in the config and skip-renders — the config is not self-healed. Each section renders the identical disclosure shape as the default Collections section, reusing the same Collection row.

Affordances: Add Section in the Collections header context menu (stub then inline-rename); Move to Section / Remove from Section in a Collection row's menu (shown once at least one section exists); Rename Section / Delete Section in the user-section header's menu.

---

#### Creation affordances

Creation is right-click-first with no always-visible "New" buttons: right-click a heading, row, or area and the menu's "New X" options auto-scope to that location's tier or container. Location scoping is load-bearing — right-clicking a Collection produces a "New Page" that creates IN that Collection. The three tier rows each create only their own tier (no cross-tier creation — the tiers are independent). This matches Finder, Notion, and Obsidian.

Beyond New entries, the menus carry the natural edit actions per row: Contexts entity rows offer Rename / Change Icon / Delete; the Collections header offers Add Section; a Collection row offers Collection Settings (the schema editor), Move to / Remove from Section, Rename / Change Icon / Delete; a Set offers Rename / Change Icon / Move to / Delete (two delete modes — see [[Resources/II. Pommora/II. Swift/II. Features/PageSets]]); a Page offers Rename / Delete; a user-section header offers Rename / Delete (delete ungroups its Collections). There are no Agenda menu rows in the sidebar — Agenda creation lives on the Calendar pin.

Tier and section headings also expose a hover-only "+" as a discoverable complement, opening that tier or section's new flow while keeping the sidebar quiet at rest. A fuller global creation path arrives via quick-capture, expected to absorb most CRUD entry traffic.

---

#### Selection + structure constraints

Selection reads Finder-style: a subtle quaternary-fill rounded pill at row level. Two load-bearing rules govern the structure, and breaking either has regressed a launch crash in the list-diffing layer.

- **Selection chrome lives at row level, never in-content.** Each row derives its own selected state and applies the pill through the list-row background, so the fill spans the full row including the chevron gutter rather than stopping at the content's leading edge; the selected row's icon and text shift to the accent color and brighten slightly. Row content stays pure and carries no chrome of its own. An untagged row inside a tagged container inherits that container's selection, so a deliberately non-selectable row (e.g. a Sub-Set row) needs its own distinct non-selecting tag plus selection explicitly disabled on its label.
- **Every section's rows stay homogeneous.** Don't mix flat-leaf rows and disclosure rows in one section, and don't substitute a placeholder leaf for an empty section (an empty user section renders header-only) — the list coordinator can crash on that asymmetry.

---

#### Section ordering

Initial-boot order is Pinned, Contexts, Collections, then user sections; order persists per Nexus.
