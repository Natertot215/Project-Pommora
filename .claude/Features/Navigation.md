### Navigation

How the single main pane changes what it shows. Today that's Back/Forward history and a footer breadcrumb; a Pinned/Recents popover is the planned fuller surface.

The main pane shows one entity at a time — selecting one in the sidebar, a table, or a breadcrumb routes the whole detail view, replacing the previous selection. A session-local history records each selection, and the footer breadcrumb shows the current location. The richer navigation-history surface — a toolbar popover of Pinned and Recents lists — is Pending.

### Features

#### II. Back and Forward

Back and Forward walk a session history of selections, stepping to the previous or next entity and skipping any deleted along the way. A history step re-selects without re-recording, so stepping doesn't reshuffle the history. The toolbar buttons disable at each end. The history is in-memory and session-local — it isn't persisted.

#### II. Breadcrumb

The footer carries a breadcrumb of the current entity's container path, plus a dimmed forward **ghost crumb** for the last-visited Page within the open container — a one-click way back into where you were. Full footer → `Subfield.md`.

### Pending

**Navigation Popover:** The fuller history surface — a toolbar glyph opening a popover with two lists: a user-curated **Pinned** list and an auto-tracked **Recents** list (LRU, capped). Single-click selects a row, double-click opens it in the main pane, and right-click pins or unpins; the store persists per Nexus. The Back/Forward history and the breadcrumb cover navigation today — the popover, its Pinned and Recents store, and any keyboard accelerators are unbuilt.
