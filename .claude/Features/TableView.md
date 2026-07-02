## TableView

The built renderer of the five view types (`Views.md`) — a Collection's or depth-1 Set's Pages drawn as rows on a single CSS grid. It's presentation only: the pipeline (columns → filter → group → sort) hands it resolved groups and per-cell values; TableView owns the layout, the column ergonomics, and the row/group chrome. Every tunable number lives in `table-tokens.css` (the §G single source); `Table.css` carries no raw values.

### The Shared Grid

The header band and every data row are separate CSS grids that read **one shared track set** (`--cols`, set inline) — so columns align across all bands without a `<colgroup>`. Each track is a resolved column width, and a trailing `1fr` **filler** absorbs any pane width past the summed columns so the grid always spans full-width; the filler is also the `:last-child` anchor that keeps the last real column's divider. Group sections are full-width bands *off* the column grid, so a disclosure row is independent of the columns and its members can wrap without breaking alignment.

**Every column — the title included — holds its resolved width** (the Apple table model; the earlier elastic-`minmax` title was deliberately reverted). No column is ever compressed to absorb growth or a narrowing pane.

### Overflow & Scroll

While the columns' total width fits the pane, the table stays **capped** at the content inset and the filler eats the slack. The moment any mechanism pushes the sum past the pane — a resize (every type is uncapped; only the legibility mins clamp), an added column, a narrowed window — the grid's `min-width` (the full column sum) exceeds the pane and the **whole view h-scrolls**: heading and rows slide together, content passes under the edges, the left gutter stays the solid boundary. While overflowing, the right inset **flattens** to the glass edge (a scoped inset var toggled by the `overflowing` class, driven by one table-level ResizeObserver). The **inspector is conditional**: a fitting table gives way to it (the compressed right inset), an overflowing one keeps its width and scrolls beneath the hovering glass — fit is measured against the pre-compression pane width so the boundary can't oscillate.

### Full-Bleed Heading

The heading band's fill + bottom seam **bleed to both glass edges** — the sidebar edge on the left, the inspector/window edge on the right — while its column tracks stay locked to the body grid. Negative side margins widen the band's border box out to the glass (the background covers the border box, so the fill reaches the edge); matching left **and** right padding then re-land its tracks on the *exact* content width of a data row — an un-padded (wider) header would resolve its tracks against a different box than the rows and drift every column. The band stays inside the grid, so it h-scrolls with the body.

### The Views Gutter

A strip carved from the content inset, left of the grid, where the row **drag grips** and group **disclosure chevrons** float — the same lane, and the same width knob, as MarkdownPM's fold gutter, so a table and a Page body read consistently. Inside the table the general gutter var is remapped to this narrower grip lane; full-bleed surfaces read the un-shadowed content-gutter alias for the true content-to-glass distance (see Non-Obvious). Group **disclosure headers are sticky-left** so the group label + its chevron hold the gutter and stay legible while the property columns scroll horizontally.

### Groups

Structural (Set / Sub-Set disclosure) and property groups render as full-width disclosure bands. A header's chevron + folder glyph read as one cluster in the gutter, so the header itself is indented by nesting alone (no cell-padding base) and the chevron lands in the grip lane. A headered group's members nest **one indent step inside** the header; a Set-within-a-Set steps in again, recursively. Ungrouped/loose rows instead sit at the loose-inset — tucked a touch left of the column inset, landing near the Title column — and property grouping's **no-value rows get the identical treatment: no "None" band**, a header-less flattened tail pinned last (`empty_placement` rides as decode parity, never read). Collapse rides a Reveal on the shared disclosure motion (the chevron and the row grid animate together; collapsed rows leave the DOM).

**Band drag** — a group header drags by its **glyph** (the icon + name cluster; the chevron and the hover "+" isolate on pointerdown, so they can never arm it), riding the same insertion-line gesture as row drag over a frozen snapshot of geometry AND the band list (a mid-drag tree swap dirties both together). Vertical band order is **manual-only and view-owned**: a structural drop merges into the view-level `group_order` (one flat set-id array covering every nesting level, merged over the FULL tree so collapsed siblings survive the write); a property drop writes `group.order` + flips `order_mode` to manual (its first UI writer). The sidebar's order never mirrors in — only a **cross-tree drop** (a Set band's nest highlight — its whole region past the header top zone, rows included — or a between-slot whose implied parent differs from the dragged band's) touches the filesystem: `moveSet` carries the destination's *current* children with the moved id appended, while the visual slot persists only in the view order. The ungrouped tail never drags and is never a target; Esc aborts the drag, like every drag surface. Locked rationale + reversal seams → `History.md` (07-02).

### Columns

Widths are per-type `{min, default, max}` (one DRY source keyed by the column's declared type), clamped on every resolve so a stale saved value can't squash a column below legibility or past its cap. Ergonomics:

- **Resize** — a right-edge hit-strip; the live track width is the feedback (no separate bar). The pointer delta is divided by the live density factor so a screen drag maps onto the pre-zoom track.

- **Reorder** — grabbing a header smooth-shifts the whole column (header + every cell + divider) as one opaque band carrying the selected highlight; neighbours slide to open the gap on the shift curve. Edge-based slot detection with a hysteresis zone, correct for wildly-varying widths.

- **Hide** — animates the track set shut on the disclosure token, then drops the column.

- **Alignment · Style · menu** — right-click a header for the OS-native column menu (Align · Style · Hide). Style is per-type: status Pill/Capsule/Checkbox · checkbox Checkbox/Switch · link Title/Full Link · file Filename/Full Path · number formats · date/time formats (labels are format-type *names*, never rendered samples); the choice persists per-view in the SavedView's `column_styles` (a deliberate divergence from Swift's def-level format keys, which ride through defs as inert foreign keys). Select/multi carry no Style — their chips always render pill. The title is the primary column — not hideable, not alignable, not styleable.

### Rows & Cells

A data cell's content is type-aware — a page icon (at the shared secondary-glyph tone, a step under the title text), title text, chips, or a link — and its **look + formats read the per-view column style**: a status renders as a labeled pill, an icon-only capsule (the chip token set's capsule shape, glyph by the value's fixed group: dashed circle / minus / check), or the checkbox square with the same group glyph; a checkbox as the square or the real Switch; files as one chip per attachment (basename or full path); dates and numbers through the Swift-parity formatters. Column dividers differ by band: the heading draws short, centered, fully-rounded **segment bars** (a segmented-control feel) between columns, while data rows draw full-height **hairlines**. The row divider is a top border on the row (spanning the filler too) and the first row of each group drops it, so a line only ever falls *between* two rows. Row height is driven by the vertical cell padding. Hover and selection are Finder-style fills. **Row drag** is the drop-line DnD (`PommoraDND.md`): a hover-revealed grip in the gutter lifts the row, which mutes in place while an accent line + dot mark the slot — nothing displaces.

**Every cell owns its click** (the ratified gesture matrix — portable to Gallery/List/Cards): the title cell is the *only* navigate; status/select/multi single-click opens the shared PickerMenu value dropdown (options as chips; multi toggles and stays open); a checkbox-look status cell instead cycles its group (empty box → minus → check, writing each group's first-in-order option, skipping empty groups); a checkbox toggles; a number single-click enters the inline editor; a link opens externally through the sanctioned link IPC (raw anchor navigation is denied by main's hardening); each file chip opens its own file through the root-validated file IPC. **Right-click always opens a menu, never acts**: the title gets Rename · Change Icon · Delete; style-bearing types get their *column's* Style radios; link/file add Edit; select/multi pop nothing. Inline edits follow Enter = confirm · click-out = save · Esc = revert; the number input filters invalid keystrokes at the source; an empty commit clears the value. The row background is a no-op — and every cell still arms the row drag past the activation threshold, so cell gestures own only the sub-threshold press-release. The editing surfaces (picker, editor, status cycle, value formatters) live view-agnostic in `PropertyEditing/`, mounted by this table first and by the other container views later.

### Density

A single **zoom** knob (Standard / Compact) scales text, chips, padding, and widths together — the grid resolves percentage zoom zoom-aware, so a `100%`-width grid still fills the pane at either density.

### Tokens

`table-tokens.css` is the one place any table dimension is tuned — cell padding (and thus row height), the icon gaps, the nesting-indent step, the loose-row inset, the gutter width, the border weight, and every heading treatment each route through a named knob, aliased to a design-system token wherever one exists. `Table.css` carries no raw px / % / hex / ms in any rule.

### Non-Obvious

- **The gutter var is shadowed inside the table.** The global gutter (content-to-glass margin) is remapped to the narrower fold-gutter grip lane within the table scope, so the grips/chevrons sit in the strip. Full-bleed surfaces (the heading band) therefore can't read the shadowed var for the true content-to-glass distance — they read a dedicated un-shadowed content-gutter alias. Mixing the two is the classic source of a few-px heading misalignment.

- **The heading's both-sides padding and the grid's summed `min-width` are one mechanism.** The padding re-lands the heading's tracks on the rows' content width; the `min-width` (the full column sum) is what makes overflow scroll instead of clip — change either and re-check the other against a heading-vs-row column drift.

- **The reorder density factor is read from the zoom token, not back-solved.** Column-drag geometry reads the CSS zoom var directly; a `header-width ÷ track-width` back-solve bakes in whatever layout slack the grid has (it broke under the since-reverted elastic title) — the token is the ground truth.

- **A sticky group header pins at the gutter edge, losing its nesting indent while pinned.** A deeply-nested group's chevron clamps to the same x as a top-level one once scrolled far enough — a legibility-preserving pin that reverts on scroll-back, never clipping content.

### Known Issues

- **Row grips scroll with their row on horizontal scroll.** The disclosure headers + chevrons stay pinned, but the hover-only drag grips ride their row's cell off to the left — freezing them cleanly means freezing the whole title column (a frozen first column), which is a separate decision.
