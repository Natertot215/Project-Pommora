### Collections — see [[PageTypes|Page Types]]

**Page Collections** are organizational sub-folders inside a Page Type (`_pagecollection.json` sidecar). UI label "Collection" by default (renameable via Settings). They inherit the parent Page Type's property schema but carry independent `views[]` (a Page Collection can ship a Board view while its parent Type stays on Table). There is no standalone "Collection" file-shape — a Collection always lives inside a parent Type.

A Collection optionally subdivides into **Page Sets** — schema-less folders carrying `_pageset.json` (shipped v0.4.1; full spec → [[Sets]]). The Collection's sidecar holds `set_order` (its Sets' display order) alongside `page_order` (its root Pages' order — pages inside a Set order via that Set's own `page_order`). The Collection detail view shows root pages plus each Set's pages as a flat concatenation; its footer add menu offers New Page + New Set.

Full spec → [[PageTypes]].
