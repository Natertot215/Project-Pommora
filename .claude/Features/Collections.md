### Collections

The Pages-side middle tier: **Vault → Collection → Set (optional) → Pages**. A Page Collection is an organizational sub-folder inside a Page Type (`_pagecollection.json` sidecar) for visual / structural grouping within a large Vault. UI label **"Collection"** by default, renameable per Nexus. A Collection always lives inside a parent Type — there is no standalone Collection file-shape. The Type + the schema model → [[PageTypes]]; the optional Set sub-tier → [[Sets]].

---

#### Entity + Sidecar

`_pagecollection.json` carries `id`, `type_id` (explicit parent-Type reference — stable across renames, so external query tools never infer nesting), optional `icon` (mirrored to SQLite for the context picker) and `banner` (→ [[Views]]), `views` (independent SavedViews), `set_order` + `page_order` (the parent holds its children's order — child Sets plus the Collection's own root Pages), and `modified_at`. **No `properties`** — the schema is the parent Type's, inherited whole; Collection-local schema overrides are a Prospect (→ [[Prospects]]). Title = folder name.

---

#### Schema-Inherit, Views-Independent

The load-bearing split: a Collection **inherits the Type's property schema** (its Pages conform to the same schema as any Page in the Type) but owns its **independent `views[]`** — a Collection can ship a Board view while its parent Type stays on Table; each container's saved-view config stands alone (→ [[Views]]).

---

#### CRUD + Moves

Create = sub-folder + sidecar; rename = atomic folder rename (id / type_id preserved, rollback on failure); delete = move to `.trash/` (confirm when non-empty), with child Pages moving **up** into the Type root rather than trashed alongside. **In-Vault moves are strip-free** — a Page moving between Collections, Sets, and the Type root is a pure filesystem move (shared schema); moving a Page to a *different* Type strips off-schema properties with a confirmation (→ [[PageTypes]] § Move-strip).

---

#### Sidebar + Detail

A Collection is a selectable chevron-disclosure row showing its Sets (expandable, never selectable) plus its root Pages; clicking opens its active saved view **collection-scoped** — grouped by Set with an ungrouped root band by default (→ [[Views]]). Right-click: New Page / New Set / Rename / Change Icon / Delete (→ [[Sidebar]]).

---

#### Index + Healing

A collections row per Collection in the index, cascade-deleting from its parent Type (child Pages move up, not cascade). Title is unique per Type (folder constraint). Adoption auto-tags a sidecar-less depth-1 folder inside a Type as a Collection (`_pagecollection.json`); `ContainerIDHealer` mints a fresh ULID for a Finder-duplicated Collection sidecar on load.
