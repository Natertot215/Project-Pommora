### Collections — see [[PageTypes|Page Types]] (for Pages) or [[Items]] (for Items)

Post-ParadigmV2, "Collection" is a generic prose term — the on-disk concept splits per side:

- **Page Collections** — Pages-side organizational sub-folders inside a Page Type. UI label "Collection" by default. Full spec → [[PageTypes]].
- **Item Collections** — Items-side organizational sub-folders inside an Item Type. UI label **"Set"** by default. Full spec → [[Items]].

Both share the on-disk shape (sub-folder + per-kind sidecar carrying `id` + `type_id` + ordering + `modified_at`; properties + views inherit from the parent Type). Sidecar filenames are per-kind: Page Collections carry `_pagecollection.json`; Item Collections carry `_itemcollection.json`. Same JSON shape inside; the filename + the parent folder's per-kind Type sidecar disambiguate side. The UI label divergence is intentional — each side has one signature word and one shared word (Pages: "Vault" + "Collection"; Items: "Type" + "Set").

In generic prose discussing schema mechanics, ordering, or queries, the term "Collection" covers both. Use "Page Collection" or "Item Collection" when side-specific.

This doc is retained as a stub redirect — there is no standalone Collection entity post-ParadigmV2. The pre-existing "Collections as standalone typed-at-creation entities" model is gone.

→ [[PageTypes]] — Pages-side container layer (Page Types + Page Collections)
→ [[Items]] — Items-side container layer (Item Types + Item Collections)
