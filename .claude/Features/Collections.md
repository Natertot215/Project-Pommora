### Collections — see [[PageTypes|Page Types]] (for Pages) or [[Items]] (for Items)

"Collection" is a generic prose term — the on-disk concept splits per side:

- **Page Collections** — Pages-side organizational sub-folders inside a Page Type. UI label "Collection" by default. Full spec → [[PageTypes]].
- **Item Collections** — Items-side organizational sub-folders inside an Item Type. UI label **"Set"** by default. Full spec → [[Items]].

- Both share the on-disk shape (sub-folder + per-kind sidecar carrying `id` + `type_id` + ordering + `modified_at` + `views[]`). Property **schemas** inherit from the parent Type (no per-Collection schema override in v1 — that's a Prospect.)
- **view surfaces** are independent — every Collection carries its own `views[]`, so a Page Collection can ship a Board view while its parent Page Type stays on Table. 
- Sidecar filenames are per-kind: Page Collections carry `_pagecollection.json`; Item Collections carry `_itemcollection.json`. Same JSON shape inside; the filename + the parent folder's per-kind Type sidecar disambiguate side. The UI label divergence is intentional — each side has one signature word and one shared word (Pages: "Vault" + "Collection"; Items: "Type" + "Set").

In generic prose discussing schema mechanics, ordering, or queries, the term "Collection" covers both. Use "Page Collection" or "Item Collection" when side-specific.

There is no standalone "Collection" entity at the file-shape level — Collections always live inside a parent Type and inherit its schema.

→ [[PageTypes]] — Pages-side container layer (Page Types + Page Collections)
→ [[Items]] — Items-side container layer (Item Types + Item Collections)
