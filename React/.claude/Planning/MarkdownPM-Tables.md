## MarkdownPM Tables — Build Spec

**Status:** V3 — two adversarial rounds folded; resize confirmed in v1. The render approach (a per-line CSS-flex grid) is specified and built-then-verified like any render — not gated on a feasibility unknown. An interactive GFM table editor for the React MarkdownPM (CodeMirror 6) — resizable columns, structural ops, and inline cell editing — that stays portable GFM on disk. Product truth: repo-root `PommoraPRD.md`; editor contract: `Features/MarkdownPM.md` + the repo-root `rules/MarkdownPM.md`.

### Intent

Tables are the deferred tier promoted to a real feature: a *managed grid* you edit like Notion, that serializes to a clean GFM pipe table. The governing constraint is **minimalism inside CodeMirror 6** — no second editor engine. The table is **live document text decorated into a grid**, never a replaced block widget, so the cell content stays native CM6 text (caret, undo, IME, spellcheck, the existing inline rendering) and only the table *structure* is render-side chrome.

This was chosen over a ProseMirror-based engine (Milkdown / Tiptap / BlockNote / prosemirror-tables): once the on-disk format is portable GFM, GFM itself caps the feature set (rectangular cells, per-column alignment, inline content — no merged cells, per-cell color, or nested blocks), so the heavy engines buy interaction polish at the cost of a second engine and lossy markdown round-trips. A CM6 decoration layer reaches the entire GFM ceiling with far less surface.

#### Scope

**v1:** detection + grid render, inline live-preview cell editing, column resize (drag), structural ops (add/delete row+column, set alignment) via a right-click grip menu, table creation via the Block submenu, round-trip hardening.

**Deferred:** drag-to-reorder rows/columns (the headless ops ship in v1; the drag wires in later), hover insert/delete affordances beyond the grip, callouts, and tables nested inside blockquotes.

### Architecture

- **Engine:** CodeMirror 6, reusing the existing MarkdownPM strata — `parser/` (micromark + GFM), the `detect/` → `decorations/` decoration pipeline (intent kinds `class` / `hide` / `widget` / `line`), and the `input/` transform layer. No new dependency.
- **The grid is decoration, not a widget.** The table's lines stay in the document. Structural pipes and the delimiter row are hidden; each row is a `display:flex` line, and each cell is a mark-decorated span. Because the text never leaves the document, cell editing is native and free.

#### Rendering mechanism

CM6 renders each document line as a **separate block-level `.cm-line`**, so columns align across rows only if every row resolves to identical per-column widths — which the dash-count makes exact:

- Each table-row line is `display:flex`; each cell's content is wrapped in an explicit mark-span that is a flex item with `flex: <dash-count> 0 0` (grow = the column's dashes, **basis 0** so content size never leaks into width) + `min-width:0` + `overflow-wrap` so long content wraps *inside* the cell. Every row's flex container is the same width (the editor content width), so equal flex weights ⇒ columns line up across the independent lines: width is strictly `dashes_i / Σdashes`.
- **Caret/selection under flex is handled by construction.** The only real gotcha is bare text nodes in a flex container — the browser wraps them in anonymous items, which confuses the contenteditable caret. We never have any: every character sits inside an explicit element (cell spans for content, atomic replace decorations for the hidden pipes), so the flex line has no anonymous items and the caret lands normally inside each cell span. CM6 measures the line's height natively (a wrapping cell just makes a taller line), so no height plumbing is needed. Cross-cell caret motion rides the atomic pipe ranges (see §Cell-Model).

Decorations stay in the existing `ViewPlugin` (line decorations + same-line replaces only — no block-spanning replaces, matching the layer's current invariant). If a specific browser quirk ever forced it, the alternative is a single block-wrapped CSS-grid region via a `StateField` — an alternative pattern, not a feasibility escape hatch.

- **Self-healing:** a region is a grid **iff `parse(region)` yields a single `table` node spanning it**, re-evaluated per document change. A half-typed or broken table (no delimiter yet, delimiter merged into the header) falls back to raw text; the caret offset is preserved (same document text) and the one-frame reflow between grid-height and raw-text-height is accepted as the cost of staying source-canonical.
- **Headless + swappable.** All table logic lives in a dedicated `Tables/` module: a framework-free core (model, codec, operations, region detection) importing neither CodeMirror nor React, unit-tested in isolation, plus a thin CM6/DOM adapter. The feature is one CM6 extension; removing that registration degrades tables to plain text without touching anything else.

### On-Disk Format — The Dash-Count Width Convention

**Ratified paradigm decision.** Column width is encoded **in the source, as the number of dashes per delimiter cell** — the Pandoc convention (`---|-` ⇒ 75% / 25%). Widths render as ratios via CSS flex (`flex: <dashes> 0 0`); no sidecar, no frontmatter.

- **Width = dash count only.** Alignment colons are excluded from the width measure, so re-aligning a column never changes its width and vice-versa.
- **Alignment = delimiter colons** (`:--` left, `:-:` center, `--:` right, `--` none) — standard GFM, read from micromark's `align`. Width-dashes and alignment-colons coexist in the same delimiter cell.
- **Default magnitude is chosen for fluid resize.** A fresh table seeds each column with a moderate dash count (target total ≈ 20+ across the row) so the resize quantum (one dash) is a small fraction of the width and reads as smooth. Delimiter rows are hidden, so a longer delimiter costs nothing visible. **Minimum = 1 dash** per column.
- **Insert column** appends a new delimiter cell with the **average** of the existing columns' dash counts (so it renders at roughly the neighbours' width); existing columns keep their dash counts. Because the total grows, every column's rendered width rescales proportionally — this is expected (the table shares a fixed width), and it is the minimal-diff choice. ("Equal width" holds only for a freshly-seeded table, not for inserts into a resized one.)
- **Best-effort cosmetic.** Pandoc honors the convention; tools that don't (GitHub, vanilla Obsidian) render the table normally and ignore the widths, and an external reformatter may normalize the dashes away — columns then fall back to equal. Widths are never data; losing them never loses content.

**Codec note:** the mdast table node carries structure + alignment + cell offsets but **not** the dash counts — the AST discards delimiter widths (verified). The codec reads the **raw delimiter line** to count dashes per cell, and uses micromark for everything else. All codec offset math uses the same unit micromark reports (codepoint offsets) so an astral-plane emoji in a cell never shifts structural-pipe positions; the raw delimiter scan is surrogate-safe.

**Supersedes** the Swift `rules/MarkdownPM.md` §9.2 (column widths → frontmatter) and the React parked "widths → `.nexus/` sidecar" note. The divergence is principled: TextKit cannot render custom inline widths without forfeiting TextKit 2, which forced Swift toward frontmatter; CSS flex can, so React encodes width in portable source. This becomes the shared Swift/React convention; record in repo-root `History.md` and mark the Swift rules doc stale.

### Detection

- **Renders as a grid only when valid GFM** (the self-healing trigger above) — a header row plus a valid delimiter row (zero body rows is allowed → a header-only grid).
- **Top-level only** for v1 — a table nested in a blockquote stays normal quoted text (gridding inside a quote card is deferred).
- **Code-fence guard** — a pipe table inside a fenced code block stays code, reusing the existing `isInsideCode` guard.
- **Both GFM forms accepted** — with or without leading/trailing pipes; anything the editor itself writes emits the canonical fully-piped form.
- **Ragged foreign rows** render padded to the column count (GFM's own behavior); the source is left untouched until a user edit, and the editor's own ops always keep tables rectangular.

### The Cell Model — No-Syntax, Live-Preview

The defining experience: **the user has no clue it is a pipe table.**

- **Table structure is never visible** — pipes and the delimiter row are always hidden, never revealed, even with the caret inside a cell.
- **Cells are full live-preview editors.** Inline content renders formatted with **caret-reveal of inline syntax** — identical to the main editor — while the table structure never reveals. Inline constructs render in cells (bold, italic, strikethrough, inline code, links, connections) along with the inline auto-formats (arrows, dashes). Block constructs (blockquote, lists, headings) stay literal — matches GFM, since cells are inline-only.
- **Navigation, not structure, from the keyboard.** Tab → next cell, Shift+Tab → previous, Enter → cell below; each exits the table at its edge. No keystroke ever creates structure or a newline.

#### In-cell pipes — the two cases

The cell pipe model is a **dichotomy**, resolved by treating **micromark's cell boundaries as the sole authority** for which `|` is structural — never a raw pipe scan:

1. **Structural boundary pipe** → hidden (registered atomic, see below).
2. **Escaped content pipe `\|`** → render the `|` glyph, hide the backslash. Typing `|` in a cell inserts `\|`. The backslash codec is idempotent: decode(`\|`) → content `|`, encode(`|`) → `\|`; a literal backslash-then-pipe the user wants is `\\|`.

There is no third "raw pipe inside inline code" case: a bare `|` inside a cell — even within a `` `code span` `` — terminates the cell in GFM and breaks the table parse, so **every** literal pipe is the escaped form above.

#### Caret navigation across hidden structure

- **Arrow keys:** every structural pipe **and the delimiter line** are registered in the `EditorView.atomicRanges` facet (separate from being replace-decorated), so horizontal motion skips them in one logical step and the caret never lands inside hidden structure. This facet governs **arrow-key motion only — it does not clamp direct programmatic selection**, so Tab/Enter cell-jumps compute their own valid landing offset (the next cell's content start) rather than relying on the facet.
- **Vertical motion** (Up/Down) from a header cell explicitly **skips the hidden delimiter line** to the first body row.
- **Clicks** that `posAtCoords`-resolve inside a hidden range snap to the nearest cell-content edge (no caret trap on dead space).
- **Backspace/Delete that would cross a structural pipe** (cell→cell, cell→delimiter) is suppressed; within-cell deletion is native. The table handler registers at `Prec.highest` (the existing `smartBackspace`/`autoDelete` keymap already sits at `Prec.high`) and returns `false` outside structural boundaries so the existing behavior still runs everywhere else.
- **Connections/links in a cell:** the existing single-click-to-navigate handler keeps priority on a connection/link token; cell-focus handling applies elsewhere in the cell.

### Structure — Menu-Only, Via The Grip

Structural change is explicit and menu-driven; there is no finicky keyboard or syntax path. (A plain cell-right-click menu was considered and rejected: it would overlap the cell's formatting menu, and the grip is also the future drag-reorder anchor.)

- **The grip:** a floating Lucide grip (2×3 dot icon), `label-secondary`, revealed on hover — one above each column, one beside each row, oriented to the drag axis.
- **Right-click the grip** opens that row's or column's structural menu. This is a separate surface from the cell's formatting context menu, so the two never overlap.
- **Menu:** Insert column (left/right) · Insert row (above/below) · Delete column · Delete row · Align column (left/center/right) · Delete table.
- **Edge rules:** the header cannot be deleted as a row (use Delete table); deleting the last column deletes the whole table; deleting the last body row leaves a valid header-only grid. New rows are empty; a new column takes the average dash width (see §On-Disk).
- **Creation:** the native context menu's **Block submenu** — which currently holds quote/code/hr/callout and gains an **"Insert Table"** entry — inserts a **3×3** grid (three columns, three rows, row 1 the header) with empty cells, placed below the caret line (it never splits the current line).
- The grip is also the **future drag-reorder anchor** — right-click is the menu now; left-drag becomes reorder later.

### Resize — Cursor-Based Drag

- Hovering a column boundary changes the cursor to `col-resize`; dragging resizes.
- A drag **transfers dashes between the two adjacent columns** — the total is held constant and only those two columns change, so every *non-adjacent* column keeps its exact rendered width (its `dashes/total` ratio is untouched).
- **Fluid feel, honest contract:** during the drag the boundary tracks the cursor continuously; the source delimiter gains/loses a whole dash at each step threshold; on release the boundary snaps to the nearest whole-dash ratio. Resolution is the total dash count — at the seeded default magnitude this is smooth; a table dragged down toward the 1-dash floor resizes in visibly discrete steps (inherent, accepted).
- The shrinking column clamps at the 1-dash floor. A single-column table has no internal boundary and is not resizable.
- Undo granularity for resize is out of scope for v1 (native CodeMirror history).

### Rendering

Structural rendering is specified here; pixel-level aesthetics (padding, exact colors) are tuned live against the running editor, not pre-specified.

- **Page font.** Cells **auto-wrap** — content longer than the column (including while typing) grows the cell taller; width never reflows from typing (basis-0 flex). Each row is a native CM6 line that measures its own wrapped height, so no `requestMeasure` plumbing is needed.
- **Header:** `fill-tertiary` background + `body-emphasized` text, which carries the header/body separation (no separate underline).
- **Grid lines:** reuse the design-system `--separator-border` token — no bespoke table border styling.
- **Alignment:** per-column left/center/right from the delimiter colons, applied to every cell in the column.
- **Width:** the table fills the text-column width; columns share it by dash-ratio. **No horizontal scroll** — a table with many columns yields narrow columns that wrap tall (accepted for v1).
- **Affordances:** grips fade in on hover of the column/row; boundaries show the `col-resize` cursor; empty *and* whitespace-only cells render as real, min-height cells.

### Round-Trip & Portability

- **Never auto-tidy.** Source is mutated only on a user gesture (typing, a structural op, a resize). A foreign table opened and left untouched saves back byte-identical.
- **Foreign tables render gracefully** — equal columns until the user resizes or edits.
- **Pipes** follow the §Cell-Model dichotomy; the backslash escape is idempotent.
- **Emoji / non-ASCII:** micromark reports character (codepoint) offsets, so React avoids the Swift build's UTF-8-byte column bug; the codec keeps all offset math in that same unit and guards surrogate pairs, so an emoji in a cell never splits or shifts structural positions.
- **Minimal diffs:** structural edits emit canonical fully-piped GFM only for the parts they touch; resize edits dash counts in place; the table is never wholesale reformatted.

### Edge Cases — Rulings

- **Whitespace-only cell** → renders as an empty, min-height cell.
- **1×1 table** (one header cell, no body) → a single-column header-only grid; not resizable (single column).
- **Paste over a selected table (or part of one)** → the selection is replaced with the pasted text as raw source, then detection re-grids — no structural merge.
- **Table as the first document line** → the column grips render in the top padding / over the first row's top edge (no line above to host them).
- **Table as the last document line** → Enter-to-exit at the bottom edge appends a trailing newline to exit into (a user-gesture mutation, acceptable).
- **Many columns** → no horizontal scroll; columns narrow and wrap (see §Rendering).
- **Empty table region** (header + delimiter, no body) → valid header-only grid (per §Detection).

### Reorder — Post-v1 Seam

- The headless core exposes `moveRow` and `moveColumn` in v1 (pure, unit-tested) so the drag is a clean later wire-in — built-for, not built.
- The grip is the drag anchor. When drag ships: rows reorder via PommoraDND's table/grid sort engine (`onReorder` → `moveRow`); columns need a small companion handler (`→ moveColumn`); and inside CodeMirror it needs a `contentEditable` guard (the kit lacks one) plus a portal z-index check against CM6's own overlays.

### Module Shape — `MarkdownPM/Tables/`

```
Tables/
  model.ts        headless: TableModel (rows, cells, per-column alignment + dash-width) + pure accessors
  codec.ts        headless: GFM text ↔ TableModel — reads raw delimiter dash counts + micromark structure/alignment/cell-boundaries; round-trip stable + idempotent escaping
  operations.ts   headless: add/delete/move row+column, setAlignment, resizeColumn(dashDelta), insertColumn(avgWidth) — all model → model
  regions.ts      headless: locate valid table blocks in a doc (single table node spanning the region)
  index.ts        the seam: the TableEngine API + the CM6 extension factory the editor registers
  decorations.ts  CM6 adapter: regions → decorations (hide structural pipes + delimiter, flex cells, header, grips) + atomicRanges facet
  input.ts        CM6 adapter: cell navigation (Tab/Enter), backspace/delete boundary suppression, content-pipe escape
  resize.ts       DOM: the standalone boundary pointer handler → operations.resizeColumn
  Tables.css      appearance (design-system tokens via the --var bridge)
  *.test.ts       headless-core corpus tests
```

- **Headless:** the core (`model`/`codec`/`operations`/`regions`) imports neither CodeMirror nor React — pure TypeScript over strings and a `TableModel`, unit-tested standalone.
- **Swappable:** `index.ts` exports one CM6 extension appended in the editor's extension assembly. Removing that line degrades tables to plain text; nothing else is touched.

### Build Sequence

A green commit per slice; the headless core is testable before any CM6 wiring exists.

1. **Headless core** — `model` + `codec` (read/write dash-count widths + alignment + the pipe dichotomy + idempotent escaping) + `regions` (the self-healing detector) + `operations` (add/delete/move/insert row+column, resize, align). Pure logic, unit-tested against a corpus including ragged/foreign/escaped/emoji cells.
2. **Off-caret render** — implement the per-line-flex grid (every cell's content in an explicit flex-item span; structural pipes + delimiter hidden as atomic ranges), then header treatment, alignment, and grid lines. This is the visual foundation the later slices sit on; verify column alignment + caret behavior here.
3. **Live cell editing + navigation** — caret-reveal inline content, structure stays hidden, `atomicRanges` registration, Tab/Enter/click navigation, boundary-crossing backspace/delete suppression, content-pipe escape.
4. **Grip + structural menu** — the grip affordance and right-click menu wired to `operations`; "Insert Table" in the Block submenu (`BlockFormat` gains `'table'`).
5. **Resize** — boundary cursor + drag → dash transfer with fluid cursor tracking and on-release snap.
6. **Round-trip hardening** — foreign/ragged tables, paste-over-selection, emoji guarding, and verification that nothing auto-tidies on save.

Reorder (drag) is a post-v1 slice on top of the v1 headless `moveRow`/`moveColumn`.
