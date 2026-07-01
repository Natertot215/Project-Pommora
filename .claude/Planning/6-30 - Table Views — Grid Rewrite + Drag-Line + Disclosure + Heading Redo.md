## Table Views — Grid Rewrite + Drag-Line + Disclosure + Heading Redo

> Status: **Ratified design, pending implementation sign-off.** Supersedes the row-grip / disclosure / divider portions of `6-29 - Table Views Part 2 — UIX Redo + Label Fix`. Brainstormed + source-verified 6-30; the architectural pivot (CSS-grid div rows) was green-lit by Nathan.

### Frame

The Part-2 table shipped as an HTML `<table>`. Two new requirements — sidebar-style row **disclosure** (animated reveal/retract of a group's rows) and a **drop-line** reorder — both fight the `<table>` element: a `<tr>` can't take a `grid-template-rows` height transition, and the smooth-shift drag the table currently rides is the exact behavior being rejected. The fix is to re-render the table as a **CSS-grid of divs**, which makes both behaviors native and aligns the surface with the sidebar + editor it's meant to match. The data pipeline, view resolution, reorder/reassign logic, and per-cell rendering are **untouched** — only the row/cell markup and the column resize/hide mechanics are rebuilt on grid.

This doc is the single source for: the grid architecture, the drop-line reorder, the disclosure, the heading-row + group-row + data-cell styling, the divider DRY-up, and the verification each task must pass before it's called done.

### A — Architecture: CSS-grid div rows

- **A-1: Replace `<table>/<thead>/<tbody>/<tr>/<td>/<colgroup>` with a div grid.** Columns are established once via a single `grid-template-columns` (the resolved column widths + a final `1fr` filler). Every band — header, group header, data row — reads those same tracks, so columns stay aligned without a shared `<colgroup>`.

- **A-2: Row structure.** Each row is its own `display: grid` reading a shared `--cols` custom property (preferred over one outer grid with `display: contents` rows) — it lets a group's rows be wrapped in a `Reveal` box that animates without breaking the column grid, and keeps each row independently measurable for the drop-line. Settle the exact shape at implementation start against the disclosure + drag needs.

- **A-3: Preserved logic.** `resolveView` (columns + filter + group + sort), `flattenContainer`, the override layer (order / width / hidden / manual / value), `reorderRow` / `reassignRow` / `canReorderRow`, `reassign.ts`, the `setProperty` op, and cell rendering (`Cell`, `GroupHeader`) all carry over unchanged. The rewrite is JSX + CSS only.

- **A-4: Rebuild on grid.** Column **resize** (was a `<col>` width drag) → adjust the track in `grid-template-columns`. Column **hide animation** (E-11, was the `<col>` width transition) → transition the track to 0, then drop it. Column **drag-reorder** (E-2) → a **fluid smooth-shift** via a per-cell `transform`: the dragged column's heading **and every body cell + both divider lines slide together** with the cursor, neighbours sliding to open the gap (on `--col-shift-ease`), the track order committing on drop — NOT the heading sliding alone with the body snapping on land.
  - *As-built (diverged from the first draft):* the lifted column reads as the **selected highlight** — an opaque band (`--col-drag-band` → `--bg-window`, so it glides solid, not see-through) carrying `--col-highlight` (→ `--state-selected`) + a left divider to match its right one — **not a ghost veil**. Ghosting is reserved for *row/list* reorder (B). The target slot is **edge-based** (whichever column's span the dragged centre is over) with a sticky-zone hysteresis (`COL_SHIFT_HYSTERESIS`), **not** closest-centre — a closest-centre rule lets a far column shift while the dragged one is still mid-traverse over a very wide neighbour (e.g. Title). The gesture is table-local (pointer-capture + window listeners + an ACTIVATION threshold + a pointercancel abort), not the `SortableZone` engine. *(The two axes differ on purpose: **rows** get the drag-line + muted source (B); **columns** get this smooth-shift.)*

- **A-5: Gutter unchanged.** The committed views gutter (`--gutter`, carved from `--content-inset`, grips + chevrons floating left) carries over as-is.

### B — Reorder: sidebar drop-line, muted source

- **B-1: Replace the smooth-shift `SortableZone` with a drop-line DnD** modeled on `Sidebar/sidebarDnd.tsx` + the editor's `MarkdownPM/editor/dragChrome.ts`: an **accent insertion line** marks the exact drop slot; **no row displacement** (the other rows never move).

- **B-2: Muted source in place.** The dragged row dims in place via `--drag-muted` → **`--state-ghost`** (the semantic reorder-ghost token, which → `--tint-primary` — the same `.md-li-drag-source` opacity the editor uses; value-identical, now DRY through one named knob). No floating ghost: the in-place shade already shows what's moving (`dragChrome.ts`'s own rationale). *(Flag if a sidebar-style floating ghost is wanted instead.)*

- **B-3: Line appearance like the sidebar's** — a thin `--drag-line` (→ `--accent`) bar, rounded, with a small dot endpoint, inset to the content width, `pointer-events: none`, above the grid.

- **B-4: Semantics preserved (same function).** A drop **within** a group → reorder, persisted to the per-machine `viewOrders` cache (D-2 / D-5 / D-6). A drop **into a different** group → reassign the grouped property via `setProperty` (D-4 / D-8). The `ACTIVATION` threshold, the within-group clamp, and the multi-sort gating all carry over.

- **B-5: Grip** stays the hover-revealed grip in the views gutter.

### C — Disclosure: Reveal, like the sidebar dropdown

- **C-1: A group's rows reveal / retract via the shared `Reveal` component** (`design-system/components/Reveal.tsx`): `grid-template-rows: 0fr ↔ 1fr` on `--disclosure` / `--ease-standard`, inner `overflow: hidden; min-height: 0`, children unmount once collapsed. This is the *exact* sidebar + heading-fold animation — the div-grid lets it apply to the table rows directly.

- **C-2: Chevron** rotates on `--disclosure` (the `.group-twisty` / `.twisty` already does this — reused, not re-authored).

- **C-3: Members inset one nesting step.** A headered group's rows (+ any nested child group) sit one `--row-indent` step inside the group header — the leftmost cell's `paddingLeft` (`indent(depth+1)` in `renderRows`) — so the disclosure hierarchy is legible (you can see what's within a group vs the base level). The ungrouped root band has no header, so its rows stay flush. Reuses `--row-indent` (the shared per-nesting-depth padding token), since a group member and a nested-Set page are the same visual "one level in."

### D — Heading (column-header) row

- **D-1: Background** → `--heading-fill` (→ `--fill-quinary`).

- **D-2: Top + bottom dividers** → `--border-heading` (→ `--separator-border`). The bottom already reads this token; the **top** (the banner↔body divider) does not yet and must change (see F).

- **D-3: Column dividers — heading row ONLY** → the **segment-divider** look (`design-system/components/Segmented-Controls/segmented.css.ts`): a short, vertically-centered, fully-rounded `--heading-segment` (→ `--label-tertiary`) bar, **shorter than the row height** (as the segmented buttons' dividers are shorter than the capsule). The first column also carries a **leading bar** at the grid's left edge (the gutter↔first-column junction) so the header reads as a bounded segmented strip. Data rows keep their full-height `--cell-divider` hairlines.

- **D-4: Text** → `--heading-text` (→ `--label-control`).

- **D-5: Padding** → slight vertical padding so the header sits off its top + bottom dividers (Swift feel; tuned at build, screenshot for sign-off).

### E — Group rows + data cells

- **E-1: Disclosure (group-header) glyph is left-flush against the gutter — ALWAYS**, independent of its column's alignment (E-5). The group value sits hard at the grid's left edge even when that column's data cells are centered; it is never centered.

- **E-2: Data cell values follow their column's alignment** (E-5) — left / center / right, a per-type default the user can override. (Everything's left today; this introduces the center defaults + the menu.) The Title cell keeps its primary treatment (icon + left).

- **E-3: Icons.** Folder / Set group headers show the **Set's icon** (from its sidecar) — **immune** to the Hide Page Icons toggle. Data rows show the **page icon** (frontmatter) — **obeys** Hide Page Icons.

- **E-4: "None" group** pinned to the **bottom**: header glyph is a **`--none-pill` (→ `solid.greyDefault`) pill labeled "None"** for select / status grouping, and **plain "None" text** for date / time grouping.

- **E-5: Per-column alignment via the native column menu**, copying MarkdownPM's table-column menu exactly (`src/main/tableMenu.ts`'s `Align` submenu: a radio Left / Center / Right with the current one checked). Right-click a column heading → a NATIVE menu: **Align ▸ Left / Center / Right** (current = checked radio) + **Hide**. This *extends the native column menu already shipped* (the lone "Hide Property" item — `src/main/columnMenu.ts`, commit `70150f0`): add the align actions to its `ColumnMenuContext` (carry the current align) + `ColumnMenuAction` union. The cell's `text-align` / `justify-content` follows the resolved column align.

- **E-6: Defaults per declared type.** **Left:** title · number · url (link) · file · date · datetime · last_edited_time (modified) · created. **Center:** checkbox · status · select · multi_select · relation · tier — all of which are contexts (there is no non-context relation).

- **E-7: Persistence.** The per-column align lives in the **SavedView** (synced view config) — a `column_alignments` map (propertyId → `left | center | right`), absent ⇒ the E-6 type default. Mirrors `column_widths`; the `looseObject` slot preserves it for Swift parity.

### F — Dividers + the DRY-up (do LAST)

- **F-1: Banner↔body divider is wrong app-wide.** It's a hardcoded white hairline in `Detail/Banner/Banner.css` (lines 7, 54) — lost in translation; it should be `--separator-border`. Fix everywhere it appears.

- **F-2: Single `--border-heading` variable.** DRY **all heading↔body borders** through one `--border-heading` CSS var tied to `--separator-border`, so the heading hairline has a single source (it lives in the G token layer; this task wires every consumer to it). **Do this last.**

### G — DRY: the table token layer (HARD requirement)

- **G-1: ALL table CSS values live as named CSS custom properties in ONE file under `Detail/Views/Table/`** (a dedicated token block / `table-tokens.css`), each **aliased to a design-system token** — never a raw literal inside a rule. No `#hex`, `%`, `px`, or `ms` scattered through `Table.css`; every value resolves from a named var that points at the token layer, so retuning any one concept is a single edit. This is the standard the existing `--table-pad-*` vars set, extended to **everything**.

- **G-2: The named set** (settle exact names at build; each ties to its token):
  - `--cell-padding-x`, `--cell-padding-y` — cell padding.
  - `--cell-divider` — data-row column hairline → `--separator-border`.
  - `--row-indent` — per-depth nesting step.  ·  `--zoom` — Compact density.
  - `--heading-fill` → `--fill-quinary`  ·  `--heading-text` → `--label-control`  ·  `--heading-divider` → `--border-heading`  ·  `--heading-segment` → `--label-tertiary`.
  - `--gutter` → `--fold-gutter`.
  - **Row drag:** `--drag-line` → `--accent`  ·  `--drag-muted` → `--state-ghost` (→ `--tint-primary`).
  - **Column drag (A-4):** `--col-highlight` → `--state-selected`  ·  `--col-drag-band` → `--bg-window`  ·  `--col-shift-ease` → `--duration-fast` + `--ease-standard`.
  - **Global state tokens** (`design-system/tokens`, consumed by the table): `--state-ghost` → `--tint-primary` (the reorder fade — also MarkdownPM's `.md-li-drag-source`, to be DRY'd to this token in the final cleanup); `--state-muted` → black 15% (reserved, no consumer yet); `--state-selected` → grey 5%. MarkdownPM's table shift transition also rebound to `--duration-fast`.
  - `--none-pill` → `solid.greyDefault`.

- **G-3:** `--border-heading` (F-2) is one of these — the heading-hairline alias, defined here once, consumed everywhere a heading↔body border is drawn.

### Verification Protocol (every task — this is the deliverable)

No task is "done" on a green build. Each runs this loop and is **not complete until every step passes**. The cost of this is trivial against re-doing the work.

- **1. Gate** — `npm run typecheck` (both passes) + `npx vitest run`, both genuinely green. Read the *real* tool output, never a wrapper's exit code.

- **2. Self-screenshot + analysis** — capture the working UI over CDP and **analyze the screenshot against the task's Criteria AND the full design (A–G), point by point.** Every requirement must *visibly* match in the image, not just in the code. A partial or "should be right" match is a fail.

- **3. Review agent** — dispatch a standard adversarial review agent (NOT `Workflow`): it compile-grounds the change (the code does what's claimed; the preserved logic A-3 is intact; no regression), checks the G token-DRY held, and runs a UIX pass on the screenshot against the requirements. Fold its findings; a flagged concern is unfinished work, never a deferral.

- **4. Completion bar** — declare done only when 1–3 pass AND the screenshot has been re-checked against **all** of Nathan's design requirements (not just this task's slice). State explicitly which requirements were confirmed against the image.

### Implementation Plan (phased — each an independent green commit)

- **Task 1 — Grid render parity.** Rewrite the `<table>` as the div grid (A-1…A-5, G). **Criteria:** columns aligned at the same widths as today; header / group headers / data rows / gutter render identically; resize, hide-animation, and column-drag still work; the existing reorder still functions; no logic regression (A-3); all CSS values resolve from the G token layer. **Verify** per protocol; screenshot diffed against the current `<table>` render.

- **Task 2 — Disclosure.** Wrap each group's rows in `Reveal` (C-1 / C-2). **Criteria:** collapsing/expanding a group animates its rows (grid-rows reveal on `--disclosure`), the chevron rotates in sync, collapsed rows leave the DOM; reads like the sidebar dropdown. **Verify**; screenshot the open + a mid-animation + the closed state.

- **Task 3 — Drop-line reorder.** Replace the row engine with the drop-line DnD (B-1…B-5). **Criteria:** dragging a row shows the accent insertion line at the drop slot; the source row mutes in place (`--drag-muted`); NO other-row displacement; within-group drop reorders (viewOrders), cross-group drop reassigns (setProperty); grip unchanged. **Verify**; screenshot caught mid-drag showing the line + the muted source.

- **Task 4 — Heading row + segment dividers** (D-1…D-5). **Criteria:** heading bg = `--heading-fill`; top + bottom dividers = `--border-heading`; column dividers = the segment style (short, centered, rounded, shorter than the row), **heading row only** (data rows keep hairlines); text = `--heading-text`; the slight padding reads. **Verify**; screenshot each divider + the fill + the text.

- **Task 5 — Group rows + data cells + column alignment** (E-1…E-7). **Criteria:** group glyph left-flush against the gutter, regardless of column align; cell values follow their column's align with the E-6 type defaults; right-clicking a column heading pops the native **Align ▸ Left/Center/Right** (current checked) + **Hide**; choosing an align re-aligns the column + persists to the SavedView `column_alignments`; Set icon on folder groups (ignores Hide Page Icons), page icons on rows (obey it); "None" group pinned bottom with the grey pill (select/status) / text (date/time). **Verify**; screenshot a grouped view + the None group + a folder-grouped view + the result of each align choice (the native menu itself can't be CDP-captured — confirm via the resulting cell alignment + the persisted `column_alignments`).

- **Task 6 — Banner divider fix + `--border-heading` DRY** (F-1 / F-2). Last. **Criteria:** the banner↔body divider is `--separator-border` app-wide (no hardcoded hairline remains anywhere); every heading↔body border routes through `--border-heading`; nothing else shifted. **Verify**; screenshot the banner↔body seam + a heading hairline.

### Open / confirm at build

- **Ghost** — omitted per B-2 (in-place shade suffices). Flag if a floating ghost is wanted.
- **Row structure (A-2)** — exact grid shape decided at implementation start.
- **Header padding (D-5)** + **segment-divider exact height / inset (D-3)** — tuned at build, screenshot for sign-off.

### Sources (verified 6-30)

- **Disclosure** — `design-system/components/Reveal.tsx`; `--disclosure` / `--ease-standard` in `tokens/motion.ts`.
- **Drop-line** — `Sidebar/sidebarDnd.tsx` (insertion line + ghost + no displacement); `MarkdownPM/editor/dragChrome.ts` (accent line + in-place shade); muted alias `--tint-primary` on `.md-li-drag-source` (`MarkdownPM/Styles.css:360`).
- **Tokens** — `--fill-quinary`, `--separator-border`, `--label-tertiary`, `solid.greyDefault` in `tokens/color.css.ts`; `--label-control` promoted into `tokens/color.css.ts` (`label.control`, out of `styles.css`); `--border-heading` is a new global seam token in `tokens/theme-vars.css.ts`.
- **Segment divider** — `design-system/components/Segmented-Controls/segmented.css.ts`.
- **Banner divider** — `Detail/Banner/Banner.css:7,54`.
