### Sidebar

Pommora's leading-edge navigation pane in the three-pane shell. Top-level groups, top to bottom: a heading-less **Pinned** section, then **Contexts** (one section holding the three free-standing tiers), then **Vaults**, then any user-created vault sections.

Per-entity routing rules → [[Domain-Model]]; CRUD UI patterns → `// Guidelines//CRUD-Patterns.md`.

---

#### Layout

- **Pinned (heading-less, at top)** — Homepage / Calendar / Recents.
- **Contexts** — one section under a fixed "Contexts" label holding three disclosure rows, Areas / Topics / Projects. Each tier row reads its label from its renameable per-tier config and expands to that tier's entities as flat leaf rows.
- **Vaults** — chevron disclosure of Page Types (UI label "Vault"); each Vault discloses its root Pages plus its Page Collections (label "Collection"); each Collection discloses its Page Sets (label "Set") plus its Pages; each Set discloses its Pages. Pages show their frontmatter icon or the default page glyph; Collections and Sets use a folder glyph (per-Set icon overridable). All three labels rename via Settings; the Vaults header default is "Vaults".
- **User sections** — user-created sibling sections after Vaults, each grouping Vaults the user moved into it; labels rename inline.

Tasks and Events surface through the Calendar pin, not a dedicated heading. The Calendar pin opens the Calendar detail surface (Tasks above, Events below); right-clicking it offers New Task / New Event for quick capture.

No always-visible "New" buttons — creation is right-click first, complemented by a hover-only "+" on section and tier headings (hidden at rest). A fuller discoverability layer arrives separately via quick-capture.

##### Section grouping (sidecar-driven)

There are no wrapper folders on disk (see [[Architecture]]); the sidebar groups each root folder by its per-kind sidecar — the Context sidecars feed the Areas / Topics / Projects tier rows, the Page Type sidecar feeds the Vaults section (or the user section the vault was moved into), and the Agenda sidecars surface through the Calendar pin rather than any section. The sidecar is the kind authority — it, not the folder name, decides the grouping — and the section headings are pure UI groupings with no on-disk counterpart. A folder without a recognized sidecar triggers the adopter on next launch, but only when there's something to migrate; a fresh non-Pommora folder stays invisible to discovery.

---

#### Section-by-section

##### Pinned (top — no heading)

Three fixed entries render at the top without a heading: Homepage opens the Homepage singleton (see [[Homepage]]); Calendar opens the Calendar detail surface, Tasks above and Events below, with right-click New Task / New Event for quick capture (see [[Agenda]]); Recents shows the Navigation's Recents store as a full-frame view (see [[Navigation]]). The section wrapper persists for the future user-pinning feature, gaining a "Saved" header when that ships; entry labels rename via Settings. User-pinning of arbitrary entities is post-v1 — the section gains its heading and "+" affordance then, and the three defaults become movable and removable.

##### Contexts

One section under a fixed "Contexts" label holding exactly three tier disclosure rows — Areas, Topics, Projects — as homogeneous siblings. The tiers are free-standing: no containment, no parents, no cross-tier nesting (see [[Contexts]]).

Tier rows are expand/collapse only — they carry no selection, so clicking anywhere toggles disclosure; the label reads from the tier config, and creation is via the row's hover "+" or right-click. Entity rows render as flat leaf rows: Area, Topic, and Project rows are all bare icon-plus-title leaves with no parent indicator, since the tiers don't nest. Per-tier drag-reorder persists sibling order per Nexus; clicking an entity opens its detail surface. The tier rows mirror the disclosure shape used by Vaults.

##### Vaults (default label)

Chevron disclosure. Each Page Type discloses both its root Pages and its Page Collection sub-folders as children; each Collection discloses its Sets plus its Pages; each Set discloses its Pages.

Page Set rows are expandable but never selectable — no selection chrome, and clicking only toggles disclosure (Sets have no detail view). Drag-reorder inside a Collection is two-zone: Sets reorder among Sets, Pages among Pages, and cross-zone drags are rejected; order persists parent-side. Page Types don't display tagging (they're operational, not categorical). Clicking a Page Type opens its hierarchical Table, a Collection opens a scoped view, and a Page routes per the vault's open-in mode — the main detail pane (default) or a preview window (see [[Pages]]).

##### User vault sections (navigation-only grouping)

User-creatable sections that group Vaults below the default Vaults section, persisted in a sidebar-sections sidecar; writes are atomic and failures surface as a sidebar toast.

Grouping is navigation-only — it never moves a vault folder on disk; membership lives solely in the config. A vault sits in at most one section; moving it strips it from every other section in the same write. Ungrouped vaults stay in the default Vaults section, and deleting a section ungroups its vaults back to it (no vault data touched). An empty section renders header-only, never a placeholder row. A dangling vault ID (vault deleted after grouping) stays in the config and skip-renders — the config is not self-healed. Each section renders the identical disclosure shape as the default Vaults section, reusing the same Page-Type row.

Affordances: Add Section in the Vaults header context menu (stub then inline-rename); Move to Section / Remove from Section in a vault row's menu (shown once at least one section exists); Rename Section / Delete Section in the user-section header's menu.

---

#### Creation affordances

Creation is right-click-first with no always-visible "New" buttons: right-click a heading, row, or area and the menu's "New X" options auto-scope to that location's tier or container. Location scoping is load-bearing — right-clicking a Collection produces a "New Page" that creates IN that Collection. The three tier rows each create only their own tier (no cross-tier creation — the tiers are independent). This matches Finder, Notion, and Obsidian.

Beyond New entries, the menus carry the natural edit actions per row: Contexts entity rows offer Rename / Change Icon / Delete; the Vaults header offers Add Section; a Page Type row offers Vault Settings (the schema editor), Move to / Remove from Section, Rename / Change Icon / Delete; a Collection offers Rename / Delete; a Set offers Rename / Change Icon / Move to another Collection / Delete (two delete modes — see [[Sets]]); a Page offers Rename / Delete; a user-section header offers Rename / Delete (delete ungroups its vaults). There are no Agenda menu rows in the sidebar — Agenda creation lives on the Calendar pin.

Tier and section headings also expose a hover-only "+" as a discoverable complement, opening that tier or section's new flow while keeping the sidebar quiet at rest. A fuller global creation path arrives via quick-capture, expected to absorb most CRUD entry traffic.

---

#### Selection + structure constraints

Selection reads Finder-style: a subtle quaternary-fill rounded pill at row level. Two load-bearing rules govern the structure, and breaking either has regressed a launch crash in the list-diffing layer.

- **Selection chrome lives at row level, never in-content.** Each row derives its own selected state and applies the pill through the list-row background, so the fill spans the full row including the chevron gutter rather than stopping at the content's leading edge; the selected row's icon and text shift to the accent color and brighten slightly. Row content stays pure and carries no chrome of its own. An untagged row inside a tagged container inherits that container's selection, so a deliberately non-selectable row (e.g. a Set row) needs its own distinct non-selecting tag plus selection explicitly disabled on its label.
- **Every section's rows stay homogeneous.** Don't mix flat-leaf rows and disclosure rows in one section, and don't substitute a placeholder leaf for an empty section (an empty user section renders header-only) — the list coordinator can crash on that asymmetry.

---

#### Section ordering

Initial-boot order is Pinned, Contexts, Vaults, then user sections; order persists per Nexus.
