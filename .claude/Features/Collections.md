### Collections — see [[PageTypes|Page Types]] (for Pages) or [[Items]] (for Items)

"Collection" is a generic prose term — the on-disk concept splits per side:

- **Page Collections** — organizational sub-folders inside a Page Type (`_pagecollection.json` sidecar). UI label "Collection" by default. Full spec → [[PageTypes]].
- **Item Collections** — organizational sub-folders inside an Item Type (`_itemcollection.json` sidecar). UI label **"Set"** by default. Full spec → [[Items]].

Both share the same JSON shape and inherit their parent Type's property schema, but carry independent `views[]` (a Page Collection can ship a Board view while its parent Type stays on Table). There is no standalone "Collection" file-shape — a Collection always lives inside a parent Type.

In generic prose covering schema mechanics, ordering, or queries, "Collection" covers both; use "Page Collection" / "Item Collection" when side-specific.

→ [[PageTypes]] — Pages-side container layer (Page Types + Page Collections)
→ [[Items]] — Items-side container layer (Item Types + Item Collections)
