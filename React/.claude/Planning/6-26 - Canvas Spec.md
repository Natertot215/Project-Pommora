## Canvases

An **embedded, interactive canvas** inside a page — a fixed-height surface dropped into the Markdown body, holding free-placed text-blocks, free-hand ink, and drawn lines and shapes. A canvas is its own entity, referenced by a page, not text inlined into one.

> **v1 — deliberately small.** Three object kinds — **text-blocks**, **ink**, **lines/shapes** — placed, drawn, moved, and styled on one fixed-height surface, with a small hover toolbar. **Anchored node-to-node connections** (smart edges that follow boxes) are *out of v1* — a candidate for adopting a graph library later. Pan/zoom, grouping, rotation, and the full style matrix are parked in *Prospects*. The format and seams are built so all of it is additive.

> **Direction is inverted from the usual port.** Canvas is net-new — Swift hasn't built it — so this is React-first, Swift-mirrors-later. The on-disk `.canvas` format is therefore the **cross-build contract**, not a React-local detail: designed portable so the Swift build adopts it unchanged (per the root *conceptual portability* constraint).

### The entity

A canvas is a standalone file — **`<Name>.canvas`** in `.nexus/canvases/`, one file per canvas. Per Pommora's filename-is-title rule, the **filename is the canvas name**; the **ULID lives inside** (`id`), and embeds reference that ULID, so renaming the canvas (renaming its file) never breaks a reference. Same-named canvases auto-suffix the filename (`Notes 2.canvas`) — harmless, since nothing references the filename. Resolution is ULID → file through a small canvas index built on nexus load (a scan of `.nexus/canvases/`), the same id-resolves-to-path pattern pages use.

A canvas is **embeddable in multiple pages**. It's not a navigable tree entity in v1 — it's reached through the pages that embed it (surfacing canvases as browsable is a Prospect). It lives under `.nexus/` rather than the content tree because it's reference-reached, not navigated — still a plain, convention-legible file (per the root *agent-legibility* principle), just out of the sidebar.

### On-disk format

JSONCanvas-*shaped* (`jsoncanvas.org`) — the `{ nodes, edges }` spine and integer `x / y / width / height / color` geometry, chosen as a clean, familiar, minimal shape. It is **not** held to Obsidian round-trip: ink and shapes have no representation in vanilla JSONCanvas, so the format is extended natively. The file also carries its own `id`, `name`, and `height`.

v1 has **three node kinds** (no `edges` array yet — connections are deferred):

- **Text-block** — a box holding a Markdown string (bold / italic / code / strikethrough only — the subset the editor's inline renderer already styles). Lists, headings, tables, separators, and connections are excluded inside a block. No format extension needed: formatting is Markdown characters in the string.

- **Ink** — a custom node holding `perfect-freehand` stroke data (point array, optional pressure, color, width).

- **Shape** — a custom node with a `shapeKind` (`line` / `rectangle` / `ellipse`) and a token stroke/fill.

**Height is per-canvas**, stored in the file — one height wherever embedded (not per-nexus, not per-embed). Default is a **3:2 ratio against the page's content width**, clamped between a min and max; the three values are named constants in the canvas module. Resizing the embed in one page changes the canvas's height everywhere it's embedded — **intentional**, so a shared canvas stays in sync; a per-embed override is a Prospect.

### Embedding

A page embeds a canvas with **`![[canvas:<ULID>]]`** — the image-embed `![[…]]` form (a block that *replaces* content) plus a `canvas:` discriminator, distinct from a `[[page]]` link. Two ways in:

- **Insert menu** — a *Canvas* entry creates a new `.canvas` file (default name = the page's name, auto-suffixed on collision) and inserts its directive, as one **atomic** edit so a single undo removes both the directive and the just-created file (no orphan).

- **Manual / autocomplete** — typing `![[canvas:` triggers **name-search autocomplete**: you type a canvas *name*, the picker resolves it, and it stores the *ULID*. This reuses the wikilink autocomplete (`useConnectionAutocomplete` + the candidate index + `AutocompletePanel`) with a canvas candidate source added and the `canvas:` context branching it from page candidates — the same "search by name, store by id" behavior pages already have.

### Editor integration

A canvas renders through a **`CanvasWidget extends WidgetType`** beside the table widget (`MarkdownPM/Tables/widget.tsx` is the template): a `StateField` + `Decoration.replace` over the directive line, registered as an atomic range, mounting a React root lazily. It **rebuilds only when the directive line itself changes** — never on edits elsewhere — so the per-keystroke-rescan cost the table work eliminated never appears here. Teardown defers the React unmount past the CodeMirror transaction (`queueMicrotask`).

### Rendering

One **full-SVG scene** in a single coordinate space — so paint order is coherent: any ink stroke, line, or shape can sit above *or* below any object, z-order being simply document order in the `nodes` array. SVG also gives token-bound theming and low idle cost for free at the element counts an embedded canvas reaches.

- **Text-blocks** are `<foreignObject>` HTML inside the scene — text renders through the editor's static inline renderer (`Tables/cellStatic.tsx`), and on edit that *one* block mounts a live editor (the table's **single-live-editor** pattern: only the edited block is a real editor, the rest static HTML). Formatted-text reuse and the no-per-keystroke-cost guarantee both fall out of this, with no z-order penalty.

- **Ink** is one filled `<path>` per stroke from `perfect-freehand`; **shapes** are SVG `<line>` / `<rect>` / `<ellipse>`. Both bind `stroke` / `fill` to design tokens.

z-order is the `nodes` array order; "bring to front" moves a node to the end.

### Interaction

Mental model: Obsidian's for text, Excalidraw's for drawing — both patterns users already know.

- **Create a text-block** — double-click empty canvas drops an editable block with the caret inside (Obsidian's hero gesture); the toolbar's text tool is the secondary path.
- **Edit vs move** — single-click selects and drags; double-click enters edit (caret in, the block flips from rendered Markdown to source); Escape or click-outside re-renders.
- **Tools are one-shot** — after drawing one stroke / line / shape, the active tool reverts to select (right for a small embed where you mostly select and occasionally draw). A lock toggle is deferred.
- **Draw** — ink is pointer down-move-up, one stroke committed. Shapes are drag-to-draw (down = one corner, drag sizes, release commits); **Shift constrains** to square / circle / 45° line. Single-segment lines only; multi-point is deferred.
- **Selection chrome** — an 8-handle bounding box (4 corners + 4 edges) for resize, uniform across blocks, shapes, and strokes; drag the body to move, Shift-drag to axis-constrain; shift-click and marquee-drag multi-select. Rotation and grouping are deferred.
- **Per-selection controls** — a small floating bar *above* the selection (Obsidian-style, not a side panel that would eat the embed's width): delete, color, and *edit* for text-blocks.
- **Scroll belongs to the page** — an unmodified wheel scrolls the document, never pans/zooms the canvas. v1 has no pan/zoom (the fixed-height window *is* the surface; drag its bottom border for more room); pan/zoom is a Prospect.

### In-canvas toolbar

A small **hover-to-reveal toolbar** in the canvas's top-right (Pommora's own placement): undo, redo · text, draw, line, shape. Undo/redo are **canvas-scoped** (a per-canvas history stack, like the page-scoped table history). Per the no-shortcuts-without-sign-off rule, these are toolbar buttons only — any keyboard binding (e.g. ⌘Z inside a focused canvas) is proposed separately, never baked in; in v1, ⌘Z with a canvas focused still drives the page editor, so canvas undo is the toolbar button.

### Lifecycle

- **Deleting a canvas** checks the embed index first — a canvas embedded in any page isn't silently removed; deletion is gated on no remaining embeds (orphan discovery via a future *Manage Canvases* surface is a Prospect).
- **Insert-then-undo** is atomic (above) — undoing the insert removes the file, never orphaning it.
- **Deleting a page** that embeds a canvas leaves the canvas intact (it may be embedded elsewhere) — no cascade.

### Persistence

File-per-canvas, owned by main. A `main/io/canvases.ts` module reads/writes a single `.canvas` file, modeled on the `folds` seam (`main/io/folds.ts`) but **per-entity, not a registry blob** — a canvas is user content, so it gets its own file. Surfaced over a `canvases:get` / `canvases:set` IPC pair returning the standard `{ ok }` envelope; the path-registry entry lives in `main/paths.ts`, the subfolder built like the existing context-tier dirs. Writes are debounced; the directory is created on first write; reads build the id → file index.

### Theming

The canvas frame uses a **`border` token** — the grey solid at 30% opacity. The design system has no reusable border today (inline/hardcoded on the glass material; only a `separator` hairline exists), so v1 introduces this proper `border` token in `color.css.ts` + the `theme-vars.css.ts` bridge — used by the canvas and available to retrofit the inspector, popovers, and glass (a DRY gap this closes). A `canvas-background` token is added the same way. The **6-color object palette** (Obsidian's model — 6 presets + a custom picker) maps to theme variables so it's nexus-consistent; the JSONCanvas `color` field (preset index or hex) maps to tokens on read, keeping the stored format portable while the render stays on-theme.

### Build stack

Hand-written full-SVG shell; one small dependency in v1:

- **`perfect-freehand`** — ink stroke geometry (always loaded).

Everything else is built on primitives already owned: the **pointer-capture drag mechanics** are modeled on PommoraDND's sensor (`design-system/interactions/engine.tsx` — its list-slot engine can't drive free 2D placement, but its capture / activation-threshold / rAF / teardown pattern is the template); the **autocomplete**, **tokens**, and the new **border** token are reused directly. `roughjs` (hand-drawn shape aesthetic) is a Prospect, not a v1 dep — v1 ships clean geometric shapes. Excalidraw (MIT) is the read-only reference for the tool-state machine (`packages/excalidraw/components/App.tsx`), the free-draw pipeline (`packages/element/src/shape.ts`), and shape rendering (`packages/element/src/renderElement.ts`).

### Prospects

- **Anchored node connections** — smart edges that follow boxes (JSONCanvas `edges`), candidate for adopting a graph library (e.g. React Flow).
- Pan / zoom toward a larger surface; grouping; object rotation; multi-point lines.
- The full style matrix (fill style, stroke width/style) and the `roughjs` hand-drawn style.
- Per-embed height override; JSONCanvas `file` / `link` / `group` node types.
- Surfacing canvases as browsable entities; a *Manage Canvases* orphan-cleanup surface.
- Canvas keyboard shortcuts (require focus arbitration with the page editor).
- The Swift build adopting the `.canvas` format to reach parity.
