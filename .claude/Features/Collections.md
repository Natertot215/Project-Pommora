### Page Collections

The operational layer's schema-bearing top tier. A Page Collection is a top-level folder whose sidecar assigns the nexus-wide properties every Page inside it shares — at any nesting depth — plus its saved views, child ordering, and open-in mode. It has no text editor of its own — a pure database surface.


| Entity              | Role                                                                                                           | On disk                                           |
| ------------------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| **Page Collection** | Top tier; assigns the properties every Page inside shares                                                      | Folder + `_pagecollection.json` at the Nexus root |
| **Page Set**        | Recursive sub-folder (any depth); inherits the schema. Depth-1 = "Set" (own views), deeper = "Sub-Set" (plain) | Folder + `_pageset.json` → `PageSets.md`          |
| **Content**         | Pages only (`.md`)                                                                                             | Files at any level                                |

Property definitions live in the nexus-wide registry (`.nexus/properties.json`); the assignment lives **only** on the Collection, and Sets inherit it whole. Nesting is unbounded, with no roll-up. The default UI label is "Collection," renameable per Nexus. Each Collection and depth-1 Set carries its own saved views — the view model, pipeline, and renderers live in `Views.md`. The recursive Set mechanics → `PageSets.md`; the page document → `Pages.md`.

### Features

#### II. Sidecar + Schema

`_pagecollection.json` carries `id`, `icon`, an optional `banner` (a Nexus-relative image path), `properties` (a flat array of assigned registry prop-ids — the nexus-wide properties every Page's frontmatter conforms to), `set_order` + `page_order` (the parent holds its children's order — child Sets and root Pages), `views` (the saved-view configs → `Views.md`), and `open_in`. The title is the folder name, not a field, and foreign keys ride through on every write.

Creating a Collection seeds a name and a fresh ULID only — no default properties. The user adds properties through Collection Settings. The full property catalog, value shapes, and schema mechanics → `Properties.md`.

#### II. Collection Settings

The schema editor — create properties (minted into the nexus-wide registry and assigned here), rename, reorder, change a property's type, and seed per-type options; renames, type changes, and option edits change the global definition for every assigning Collection. Removing a property unassigns it non-destructively — values stay in page frontmatter, restored by re-assigning; the rare global delete (snapshot-first, atomic across every assigner) lives at the registry level. It's reached from the view-settings dropdown's Properties pane. Full schema behavior → `Properties.md`.

#### II. Open-In Mode

Each Collection carries an `open_in` field (`compact` | `window`; absent = `window`) deciding where its Pages open — the main detail pane, or a compact preview card. The field persists on the sidecar; the compact-card routing is Pending, so Pages open in the main pane. Opening behavior → `Pages.md`.

#### II. Move Semantics

Moving a Page **within** a Collection — between its Sets, Sub-Sets, and root, at any depth — is a pure filesystem move with no property loss: the schema is shared and Sets carry none of their own. Moving a Page to a **different** Collection brings it under the destination's assigned schema — a move never strips values; properties the destination doesn't assign ride through as preserved foreign frontmatter rather than rendering, and assigning one there surfaces its values instantly. Pages reparent across Collections by sidebar drag.

### Architecture

#### II. On-Disk Layout

```
<nexus-root>/
  <Collection>/                 ← folder at the Nexus root
    _pagecollection.json        ← assigned properties + views + child ordering + open_in
    <Set>/                      ← depth-1 Set (carries its own views)
      _pageset.json
      <SubSet>/                 ← deeper Sub-Set (plain)
        _pageset.json
        <Page>.md
      <Page>.md
    <Page>.md                   ← Page directly in the Collection root
```

Collections live as siblings at the Nexus root — there's no `Pages/` wrapper. Discovery is position-driven: any root folder carrying `_pagecollection.json` is a Collection, and its sub-folders are Sets at any depth. Banner bytes live under `.nexus/assets/<id>/`, served over the read-only `nexus-asset://` scheme.

#### II. CRUD

One generic folder-entity CRUD: create writes the folder plus an empty sidecar with a fresh ULID; rename is a folder rename; delete moves the folder to `.trash` with no cascade. Top-level Collections persist their order in `.nexus/state.json`; a Collection holds its children's order in `set_order` and `page_order`. Validation rejects an invalid or colliding folder name.

#### II. Index (Model A)

The SQLite index — off the read path, regeneratable — records each page row's owning **Collection** (`page_collection_id`, for every page at any depth) and its **immediate** container (`page_set_id`, null only at the bare Collection root); the mid-level grouping is derived by walking the Set tree, never stored. A schema-version bump drops and rebuilds the whole index. Full data layer → `Architecture.md`.

### Pending

**Compact Preview Window:** The `open_in: compact` routing — a lightweight preview card for a Collection's Pages. The field persists; the routing is unwired, so Pages open in the main pane.
