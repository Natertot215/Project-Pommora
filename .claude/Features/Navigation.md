### Navigation

How you get from where you are to where you want to be — a **toolbar tab bar** holding your open working set, each tab with its own history and a footer breadcrumb for local moves, over a shared **Navigation layer** for the cross-tree jumps (recent, pinned, searched, favorited) the sidebar tree alone can't serve.

The main pane shows the **active tab's** entity; selecting one in the sidebar, a table, or a breadcrumb drives that tab (replacing its content on an unpinned tab, spawning a new one off a pinned tab). A per-tab history records each selection, and the footer breadcrumb shows the active tab's location. Above the tab bar sits the Navigation layer: a per-Nexus, UI-agnostic store of recents, pins, and favorites, plus client-side title search, surfaced through the surfaces below — all reading the same data in different shapes.

### The Navigation Layer

The shared wayfinding store beneath every navigation surface — built once, read everywhere. Three things live in it:

- **Recents** — an auto history stream, most-recent-first, deduped, capped by a generous roll-off. Every navigation records into it (all kinds, the Homepage included); Back/Forward steps and plain tab-switches don't. It records through the same selection path the sidebar uses, so anything you can open lands in recents.
- **Pins** — the durable, user-ordered working set, stored one file per pin under `.nexus/pins/`. Pins **are** the pinned tabs (left-docked in the tab bar) and also float to the top of the NavWindow gallery — one working set surfaced in two places. Pinning a tab writes a pin; unpinning removes it.
- **Favorites** — the durable, explicitly-curated list. Mutated only by an explicit add / remove / reorder, never automatically.

Entries store only their identity (kind + id + path) — every title, icon, and location is resolved **live** against the current tree at render, so a rename or move is always current and never cached stale. An entry that no longer resolves is hidden at render but never deleted from storage, so a Nexus switch can't silently wipe pins or favorites. Recents, pins, and favorites all **sync** (per-Nexus, last-writer-wins) so they follow you across machines.

**Search** is client-side and title-based: a fuzzy match over a flattened index of every Collection, Set, Page, Context, and the Homepage, plus a cached Agenda snapshot so Tasks and Events are findable. The index is memoized per tree, so typing filters without re-walking the tree.

### Features

#### II. NavWindow

The summoned wayfinding overlay — a non-modal, movable, resizable floating glass panel (`GlassPane`) that always opens centered; its size persists across opens, its position doesn't. A glass rail (a Favorites sidebar) beside a main frame: a search field over a gallery of Recents cards (pins on top), each card resolving location + icon + title live from the tree. It resizes from four corners plus a rail split, doesn't steal focus (the search field focuses on open, nothing behind is blocked), and dismisses on Escape, its shortcut, or the ribbon. Row/card actions (pin / favorite / remove) live in a context menu. Summoned by the sidebar ribbon's Navigation icon or `⌘O` (rebindable via the `commands` map). The NavWindow is also tab 1 of the Page Preview's nav flavor — a perma-pinned map tab whose page tabs open beside it, tab-neutral to the app's own tabs → [[PagePreview]].

Reorder drag differs by the view mode inside NavWindow: the **gallery** reorders pins by displacement (cards reflow to open a slot); the **list** uses the sidebar's insertion-line drag (a drop-line indicator between rows). The general rule — grid surfaces displace, row surfaces show an insertion line.

#### II. Toolbar Tabs

The navigation model: a tab bar in the toolbar holding your open working set, each tab **warm** — it keeps its own scroll and editor undo while you're away, so flipping back lands you where you left off with only one view mounted at a time.

- **Pinned tabs** dock left as compact icons (the entity icon + a pin accent; the full name reveals on hover); they are the pin set, persist, and are *protected* — navigating while a pinned tab is active opens a new tab rather than replacing it. **Unpinned tabs** sit to the right as scratch tabs — navigating replaces the active one in place unless "Open in New Tab" is used.
- **The full tab set persists and syncs** — closing Pommora never resets your tabs; they reopen (cold) on relaunch and travel across devices. Warm view-state (scroll, undo) is session-only; heading folds re-fold from their durable per-page store.
- **Lifecycle:** closing the active tab focuses the most-recently-used tab; the close `×` shows only on unpinned tabs (unpin first to close a pin); a deleted entity's unpinned tab closes while its pinned tab render-hides (the pin file stays); the last tab closing drops to NavView. Opening an entity already in a tab focuses that tab — never a duplicate.
- **Interaction:** within-zone drag reorders (pinned among pinned, unpinned among unpinned); `Ctrl`+`Tab` / `Ctrl`+`Shift`+`Tab` cycles all tabs; a tab's right-click menu offers Pin/Unpin · Close. A reveal-on-hover setting can hide the bar when idle.
- **Iconography:** tab icons resolve live like every nav surface — the Homepage tab wears the nexus photo (the home glyph only when none is set), and a NavView tab reads "New Tab" under the copy glyph.

The model + interaction spec, the warm-state mechanism, and the visual knobs → `Planning/Multi-Tab Nexus — Decision Log.md` + `— Implementation Plan.md`.

#### II. Back and Forward

Back and Forward walk **per-tab** history — each tab owns its own stack, and the toolbar arrows step the active tab, skipping any deleted entities along the way. A history step re-selects without re-recording. History belongs to the unpinned strip: a pinned tab holds none (its content never changes in place), so the arrows disable there. A tab's history *targets* persist with the set (so Back still works after relaunch, cold); the warm state is session-only.

#### II. NavPane

The toolbar Navigation button's dropdown — a compact form of the same nav-layer data (recents / pins / search) on the shared beak-glass menu surface, sized to the Settings dropdown's footprint. Its exact content is a design pass; it's the quick-glance sibling to the fuller NavWindow.

#### II. NavView

The new-tab page — a full-window Recents **gallery or list** + search bar (the NavWindow gallery scaled up, on the Homepage-shared background). It is the empty state: a `+` opens it, a nexus with no open tabs defaults to it, and closing the last tab lands on it. Picking a card or a row opens that entity into the tab. NavView shares the gallery + list components with NavWindow but stays its own surface (never a merged shell). As a detail-pane resident, its **List / Gallery toggle lives in the detail-pane [[Subfield]] footer** (the `none`-kind `viewType` item), not on a rail — the footer describes NavView the way it describes a page. Search always renders as gallery cards; the toggle switches only the recents/empty view. The list is **reorderable and shows the pinned group** above recents (like NavWindow's list) — recents drag on the shared drop-line and commit through `setRecentsOrder`.

**View mode persists per surface.** NavWindow's list/gallery choice and NavView's are **two separate** store slices (`navWindowMode` / `navViewMode`), each persisted per-nexus under the `navViewModes` settings key (`main/settings.ts`, mirroring the subfield seam) — flipping one never moves the other, and both survive relaunch. This replaced NavWindow's old session-only module var, which also couldn't re-render a sibling subtree (NavView's toggle and the view are siblings, so the state had to move to the store).

#### II. Breadcrumb

The footer carries a breadcrumb of the active tab's container path, plus a dimmed forward **ghost crumb** for the last-visited Page within the open container — a one-click way back into where you were. Full footer → `Subfield.md`.

### Pending

**Surface build state:** NavWindow (the overlay), **Toolbar Tabs**, and **NavView** are shipped; NavWindow's Figma gallery form, the pin/current-item row marker, and the rail content are the open design work. **NavPane** (the dropdown) is a placeholder pending its content call.

**Deferred:** Agenda entries are search-listable but route to a placeholder preview window that belongs to Agenda's feature. Body / full-text search (today's is title-only) waits on a query layer. Drag-to-pin across the tab divider, and dragging a tab out into its own window, are Prospects.
