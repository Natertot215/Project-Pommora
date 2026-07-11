## Blocks

Pommora's composable dashboard layer: any **BlockHost** — a folder entity whose config carries the block document — renders a mosaic of draggable, resizable tiles holding real content. The system is deliberately **host-agnostic** (D-2): it works identically under every resolution of the contexts question, with the Homepage (`homepage.json`) serving as the removable dev host until the real hosts land. The layout engine beneath it is **SurfacePM** (→ [[PommoraDND]]'s sibling; engine internals in `SurfacePM/README.md`); this doc is the durable spec of the block system itself. Full decision provenance: `Planning/7-10 - Block Surfaces — Decision Log.md`.

### The Block Document

A host's config carries two modeled keys plus a lock: `layout` (SurfacePM's split tree — bands of row/column splits with tiles as leaves) and `blocks` (the Swift-reserved array, now a tagged union of tile payloads), with `blocks_locked` reserved for the host lock. The shared zod contract lives in `src/shared/blocks.ts`; every write is a locked read-merge-write that touches only its own keys, so foreign keys — the banner included — survive by construction.

Robustness is repair-not-reject at every level: unknown or foreign tile entries are preserved and rendered inert (never stripped, never crashing the host); a layout leaf with no entry holds its space invisibly; a hand-edit's broken value repairs (heights floor, ratios renormalize, unrecognizable nodes drop) without ever wiping the document's survivors; dead references (a deleted page) render inert until the user removes the tile.

### Tile Types

- **Markdown block** — file-backed prose: a ULID-named `.md` in the host's own folder, no frontmatter, no properties, non-searchable. It joins the SQLite link graph as a connection *source* only (nothing links to it; the ULID name is rename-proof by construction). Removing one trashes its file recoverably; the new block default.
- **Page embed** — a reference (`page_id`) to a real Page, rendered through the **shared embed framework** (below). Removing the tile never touches the page.
- **View embed** — a reference to a container's saved view (Linked) or block-owned config (Custom). Spec'd (D-5/D-12, H-4..H-7), not yet built.

Tiles convert between types via the handle menu's **Turn Into** — conversions never touch an embedded source; converting away from markdown trashes the backing file recoverably.

### The Embed Framework

One seam renders a Page inside any foreign surface — SurfacePM tiles today, MarkdownPM's `![[Embed]]` later. The embed **is** the CM6 view: a read-only portal at rest carrying every MarkdownPM affordance (decorations, gutter grips, fold chevrons, wiki-link autocomplete), with editability flipped in place through a live-reconfigured compartment — entering edit is a facet change on the same view, never a remount. An embed edit *is* a page edit, flowing through the page's own debounced save.

The whole embed sizes off **one scale variable** (`--mdpm-scale`, set from the `EMBED_SCALE` knob in `Embeds/PageEmbed.tsx`): the font zoom and every px-fixed dimension — glyphs, gutter, chrome — derive together. Embed zoom is a fixed amount; **resizing a tile is a viewport change, never a scale change**.

Two framework laws with reach beyond blocks:

- **Popups escape the tile.** A tile is a `transform`ed ancestor, which re-anchors `position: fixed` descendants to itself — so any popup born inside an embed renders through a body-level portal, never in the tile's subtree.
- **Scroll is caret-priority.** Blocks are wheel-transparent at rest (the page scrolls; no text I-beam); only the block holding the caret scrolls internally, contained.

### Surface Interaction

Creation is right-click on the surface background: inside a ragged **wedge** the new block fits flush to the row bottom under the tile above the click; on open background it appends as a full-width band. The **drag handle** is a bordered chip notched into the tile's left border (the border curves around it; MarkdownPM's shared grip glyph inside) — drag moves the block, click or right-click opens the block menu: **Type ▸** (Turn Into) · **Style ▸** (Bordered / Borderless) · **Remove** (main-confirmed, trash-recoverable). While a tile holds the caret its handle reveals by pointer proximity to the top-left corner rather than whole-tile hover.

**Borderless** is a per-tile style: the chassis hides until you reach for it — border and notch return on border/handle hover, drag, and resize; a locked host will pin it hidden.

Resize is window-style on the tile's own edges and corners: south stretches the tile alone (the page flows), north negotiates the stacked pair — including across the seam between two full-width bands — east/west move the row splitter, and boundaries magnetize to other tiles' edges near perfect alignment. A full-width row always spans the surface; interior holes are impossible by construction. Blocks track pane toggles 1:1 (tile transitions gate off while the surface width animates), reflow on the Glide feel, and drops beside a block land flush at its height.

### Storage + Host Rules

Hosts live under `.nexus/` (shielded from other apps; root-lift is a breaking Prospect). The block document loads per-host on open — never in the tree walk — and layout writes debounce on gesture end; the watcher ignores host content folders so block edits never cost a re-walk. Markdown-block bodies write pure (no frontmatter envelope, no stamp), locked per file.

#### Pending

- View embeds (Linked → Custom + the nexus-wide row source) with the H-5 slim header chrome.
- Page-embed header chrome (banner + in-line title toggles via the ⋮ menu) — parked; fields stay wired.
- Locks: the host lock (grid-wide static mode), kind-specific tile hover-locks, the container view lock.
- Link-graph host passes: the connection indexer and rename cascade must each gain a host-folder pass (block links currently neither index nor rename-heal).
- The full right-click Insert menu (Page search / View source picker / Block); the wired SettingsPane.
- Navigation surfaces for hosts + the contexts resolution — parked by design.

#### Prospects

- Widget tiles · per-host-kind block rules · free-placement canvas mode · auto-grow markdown tiles · layout undo history · root-level hosts (breaking) · search/connection opt-in for markdown blocks.
