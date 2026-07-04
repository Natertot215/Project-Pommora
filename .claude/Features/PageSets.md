## Page Sets

The recursive sub-container on the [[Studio/Pommora/II. Features/Pages|Pages]] side. A Page Set is a folder inside [[Collections]] that nests to any depth. One type, two roles by depth:

- **Set** (depth-1, a direct child of the Collection) — carries its own views and is selectable.
- **Sub-Set** (depth-2+) — a plain organizing folder, expand-only.

A Set's role — Set or Sub-Set, view-bearing or not — is a function of its depth in the folder tree, computed at render time and never stored: the same folder becomes a Set or a Sub-Set purely by where it sits. Every Set at every depth inherits the Collection's whole schema and adds none of its own. Nesting is unbounded, with no roll-up.

### Features

#### II. Sidecar

`_pageset.json` holds the Set's `id`, `parent_id` (its immediate parent — a Collection at depth-1, a Set deeper), `icon`, `page_order` (its own Pages), and `set_order` (its child Sets). A depth-1 Set additionally carries `views` and an optional `banner`; deeper Sub-Sets may carry those fields but they're ignored. The title is the folder name, the default icon is a folder glyph, and foreign keys ride through on every write.

#### II. Recursive Nesting

Sets nest to any depth — no cap. Discovery, rendering, navigation, and the index all recurse on the real folder tree. A folder tree can't cycle, and depth is the literal directory depth.

#### II. Depth-1 View Rule

Only a depth-1 Set — one whose parent is a top-tier Collection — carries and renders views; deeper Sub-Sets are plain. Eligibility is a render-time check, not stored state, so it's move-safe: reparenting a depth-1 Set under another Set makes it depth-2, and its `views` go dormant — kept in the sidecar, no longer rendered. Lift a Set back to depth-1 and they re-surface. The saved-view model → `Views.md`.

#### II. Selection + Navigation

A **depth-1 Set is selectable** — it opens its own scoped view and carries its path for rename-safe reconciliation. **Sub-Sets (depth-2+) are expand-only** — clicking toggles the disclosure, and they have no detail view. A Set's disclosure shows its child Sub-Sets and its Pages. Sidebar layout → `Sidebar.md`.

#### II. Moves

Within one Collection, moving a Page or a whole Set — between Sets, Sub-Sets, and the Collection root, at any depth — is a pure filesystem move with no property loss; Sets carry no schema of their own. Reparenting that changes a Set's depth flips its view-eligibility automatically. Cross-Collection moves are governed by the destination schema → `Collections.md`.

### Architecture

#### II. CRUD

Page Sets run through the same generic folder-entity CRUD as Collections and Contexts: create writes the folder plus a sidecar with a fresh ULID and the immediate `parent_id`; rename is a folder rename; move reparents the whole subtree; delete moves the folder — with its Sub-Sets and Pages — to `.trash`, recoverable. Reorder persists the parent's `page_order` and `set_order` on each drag.

#### II. Index (Model A)

Each `page_sets` row references exactly one parent — `parent_collection_id` at depth-1, `parent_set_id` deeper. A page records its owning top-tier Collection plus its immediate Set (null at the Collection root); the depth-1 collection is derived by walking the Set tree, never stored on the page. Pages in Sets are ordinary page rows, so search, connections, and relations include them inherently. Full index → `Architecture.md`.

### Pending

**Delete Set Only (Re-Home Pages):** The current delete trashes the folder and everything in it. A second mode would dissolve a Set while re-homing its Pages up one level into the immediate parent, distinct from trashing the whole folder.
