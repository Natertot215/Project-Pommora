# Per-Block Zoom Implementation Plan (V2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each SurfacePM markdown-block and page-embed tile its own "Scale" factor that shrinks/grows the *content* (text + glyphs + chevrons + grips + tile handle) while the tile-edge→text inset, the fold-gutter width, and the edge-fade all stay fixed.

**Architecture:** A per-tile factor `Z` (one of five discrete steps) lives on the block entry and maps to a `.spm-tile.blk-zoom-*` class that sets **one CSS var `--block-zoom`** on the tile. Everything reads that one var: the **font** (`.cm-content` font-size × `--block-zoom` — linear, no zoom curve, no clamp), the **glyphs** (`--glyph-scale = --mdpm-scale × --block-zoom` → chevron/grips/checkbox), and the **handle** (its size dims × `--block-zoom`). Structural dims (padding, fold-gutter width) stay on the untouched `--mdpm-scale` and never see `Z`. No JS font math, no per-tile props — the whole scale is CSS off one inherited var.

**Tech Stack:** React 19 + TS renderer, CodeMirror 6 (MarkdownPM), Zustand, zod, Vitest. Plain CSS + vanilla-extract. No new dependencies.

**Revision note (V2):** folds a two-agent review of V1. Adversarial pass fixed: the 0.5× page-embed **clamp desync** (F1 → font now scales linearly off `--block-zoom`, not the clamped exponential level — this also deleted the `zoomLevelForFactor` math and the PageEmbed/MarkdownBlock font wiring), a **typecheck failure** on the un-narrowed union (F2 → `zoom?` added to `ViewBlockEntry`), and the **handle distortion** (F3 → scale height + radius, not just width). Simplification pass folded: derive `cls`/`label` from the factor list; reuse the menu's existing `titleFieldLoc` footnote idiom instead of a new `text` import. Confirmed-correct-and-kept: class-based `--block-zoom` (SurfaceView has no per-tile style hook — inline would force an engine change), and the two-var split (the handle is a sibling outside `.mdpm-shell`, so it needs `--block-zoom` directly).

## Global Constraints

- **Freeze-inset is the whole point.** `Z` must NOT change: the tile-edge→text inset, the fold-gutter WIDTH, the content padding, or the edge-fade/blur. Only content + glyphs + handle scale.
- **Five discrete steps, exact values:** `1.25`, `1.00`, `0.85`, `0.65`, `0.50`. Default `1.00`.
- **`Z` is relative to each tile's natural base.** `1.00x` = the tile as it renders today (page embed already 0.9-baked, markdown block 1:1). `Z` multiplies on top; it never resets tiles to a common absolute size.
- **Absent = 1.0.** Store `zoom` only when `Z ≠ 1`; clear the key at `1.0` (G-4 absent-default, matches `style`/`locked`).
- **Font scales LINEARLY off `--block-zoom`, never through `zoom.ts`'s clamped exponential curve.** (Routing a factor through `zoomLevelForFactor`→`clampZoom` floors the page-embed 0.5× step and desyncs it from its glyphs — the V1 bug.)
- **Two spellings, by design:** the menu row shows the compact form (`1x`, `0.5x`); the picker list shows two decimals (`1.00x`, `0.50x`) — both DERIVED from the factor, never hand-kept.
- **Colors/tokens from the design system.** The trailing value uses `font.scale.footnote` + `c.label.secondary`, matching the file's existing `titleFieldLoc`. Never hand-author a hex or font-size.
- **Phase 1 = markdown blocks + page embeds ONLY.** View embeds (tables) are OUT OF SCOPE — the Scale row must NOT appear on view-embed tiles (see Deferred Phase 2).
- **Gates (from `Pommora/`):** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (capture the real `$?` to a file — never trust a piped exit) + `npx vitest run` + `env -u ELECTRON_RUN_AS_NODE npm run build`. Biome auto-formats on write.
- **CSS + component props HMR; `src/main`/preload + CM6 extension code don't.** A production build + relaunch is the reliable eyeball.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `src/renderer/src/Blocks/blockZoom.ts` | The Scale model: the 5 factors + a derived `zoomStep` lookup | **Create** |
| `src/renderer/src/Blocks/blockZoom.test.ts` | Unit tests for the model | **Create** |
| `src/shared/blocks.ts` | `zoom?: number` on all three entries + zod | Modify |
| `src/renderer/src/MarkdownPM/Styles.css` | `--glyph-scale`; move chevron+grips onto it; `.cm-content` font-size × `--block-zoom` | Modify |
| `src/renderer/src/Embeds/embeds.css` | Checkbox → `--glyph-scale`; gutter/padding STAY on `--mdpm-scale` | Modify |
| `src/renderer/src/SurfacePM/surfacepm.css` | Handle dims × `--block-zoom`; 4 `.spm-tile.blk-zoom-*` → `--block-zoom` rules | Modify |
| `src/renderer/src/Blocks/BlockSurface.tsx` | `tileClassName` zoom class; `setBlockZoom`; menu wiring | Modify |
| `src/renderer/src/Blocks/BlockHandleMenu.tsx` | The `Scale` row + trailing value + double-chevron + step sub-pane | Modify |
| `src/renderer/src/Blocks/handleMenu.css.ts` | The `Scale` trailing-value styles (mirroring `titleFieldLoc`) | Modify |
| `.claude/Features/SurfacePM.md` · `.claude/Handoff.md` | Durable spec + snapshot | Modify |

**NOT changed (V2):** `PageEmbed.tsx`, `PageEmbedBlock.tsx`, `MarkdownBlock.tsx` — the font path is CSS off `--block-zoom`, so no per-tile font prop is threaded. Paths verified current; re-ground exact line numbers at pickup.

---

### Task 1: The Scale model

**Files:**
- Create: `src/renderer/src/Blocks/blockZoom.ts`
- Test: `src/renderer/src/Blocks/blockZoom.test.ts`

**Interfaces:**
- Consumes: nothing (no cross-module import — the default `1` is just a factor in the list).
- Produces: `ZOOM_FACTORS: readonly number[]`, `DEFAULT_ZOOM = 1`, `ZOOM_STEPS: ZoomStep[]`, `zoomStep(factor?: number): ZoomStep`. `ZoomStep = { factor: number; cls: string; inline: string; label: string }` — `cls`/`inline`/`label` all DERIVED from `factor`.

- [ ] **Step 1: Write the failing test**

Create `src/renderer/src/Blocks/blockZoom.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { DEFAULT_ZOOM, ZOOM_STEPS, zoomStep } from './blockZoom'

describe('blockZoom', () => {
  it('has the five ratified factors, high to low', () => {
    expect(ZOOM_STEPS.map((s) => s.factor)).toEqual([1.25, 1, 0.85, 0.65, 0.5])
  })

  it('derives cls (padded, 1.0 has none), and both spellings', () => {
    expect(zoomStep(1)).toMatchObject({ factor: DEFAULT_ZOOM, cls: '', inline: '1x', label: '1.00x' })
    expect(zoomStep(0.85)).toMatchObject({ cls: 'blk-zoom-085', inline: '0.85x', label: '0.85x' })
    expect(zoomStep(0.5)).toMatchObject({ cls: 'blk-zoom-050', inline: '0.5x', label: '0.50x' })
    expect(zoomStep(1.25).cls).toBe('blk-zoom-125')
  })

  it('resolves an absent factor to the 1.0 step', () => {
    expect(zoomStep(undefined).factor).toBe(1)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Pommora && npx vitest run src/renderer/src/Blocks/blockZoom.test.ts`
Expected: FAIL — `Cannot find module './blockZoom'`.

- [ ] **Step 3: Write minimal implementation**

Create `src/renderer/src/Blocks/blockZoom.ts`:

```ts
// The per-block Scale model (G-10): a fixed set of discrete zoom factors a tile can carry. The factor
// is user-facing and RELATIVE to the tile's natural size (1.0 = no change). It rides ONE CSS var
// --block-zoom (keyed off `cls`); the font + glyphs + handle all derive from it. No JS font math — the
// factor is applied linearly in CSS, so it never touches the editor's clamped zoom curve.

export const DEFAULT_ZOOM = 1
export const ZOOM_FACTORS: readonly number[] = [1.25, 1, 0.85, 0.65, 0.5]

export interface ZoomStep {
  factor: number
  /** The `.spm-tile` class that sets --block-zoom; empty for 1.0 (the var falls back to 1). */
  cls: string
  /** Compact form for the menu row's trailing value ("0.5x"). */
  inline: string
  /** Two-decimal form for the picker list ("0.50x"). */
  label: string
}

const step = (factor: number): ZoomStep => ({
  factor,
  cls: factor === DEFAULT_ZOOM ? '' : `blk-zoom-${String(Math.round(factor * 100)).padStart(3, '0')}`,
  inline: `${factor}x`,
  label: `${factor.toFixed(2)}x`
})

export const ZOOM_STEPS: ZoomStep[] = ZOOM_FACTORS.map(step)

/** Resolve a stored factor to its step; an absent or off-grid value falls to 1.0 (the tile never
 *  renders at a size that isn't a ratified step). */
export function zoomStep(factor?: number): ZoomStep {
  return ZOOM_STEPS.find((s) => s.factor === factor) ?? step(DEFAULT_ZOOM)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Pommora && npx vitest run src/renderer/src/Blocks/blockZoom.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Pommora/src/renderer/src/Blocks/blockZoom.ts Pommora/src/renderer/src/Blocks/blockZoom.test.ts
git commit -m "feat(blocks): Scale model — 5 discrete factors, derived class + labels"
```

---

### Task 2: The `zoom` entry field

**Files:**
- Modify: `src/shared/blocks.ts` (all three entry interfaces + all three zod schemas)
- Test: `src/shared/blocks.test.ts` (add a case; create if absent — `ls` first)

**Interfaces:**
- Produces: `zoom?: number` on `MarkdownBlockEntry`, `PageBlockEntry`, AND `ViewBlockEntry` (the last one keeps the `BlockEntry` union uniform so `.zoom` reads at un-narrowed sites typecheck — see Task 4/5; it's never surfaced for view tiles, the Scale row is `type !== 'view'` gated).

- [ ] **Step 1: Write the failing test**

Add to `src/shared/blocks.test.ts` (create with this if absent):

```ts
import { describe, expect, it } from 'vitest'
import { knownBlock } from './blocks'

describe('block entry zoom field', () => {
  it('round-trips a numeric zoom on a page entry', () => {
    expect(knownBlock({ id: 'b', type: 'page', page_id: 'p1', zoom: 1.25 })?.zoom).toBe(1.25)
  })

  it('drops a non-numeric zoom to undefined without failing the entry (E-1 foreign-data guard)', () => {
    const e = knownBlock({ id: 'c', type: 'markdown', zoom: 'big' })
    expect(e).not.toBeNull()
    expect(e?.zoom).toBeUndefined()
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Pommora && npx vitest run src/shared/blocks.test.ts`
Expected: FAIL — the first case: `zoom` stripped (not yet in the schema), `?.zoom` is `undefined`.

- [ ] **Step 3: Write minimal implementation**

In `src/shared/blocks.ts`, add `zoom?: number` to `MarkdownBlockEntry`, `PageBlockEntry`, and `ViewBlockEntry` (same one-line comment on each):

```ts
  /** Per-tile Scale (G-10): a discrete zoom factor over the tile's natural size. Absent = 1.0.
   *  (On view entries the field just keeps the union uniform — view tiles don't surface Scale yet.) */
  zoom?: number
```

Add the shared field beside `lockedField`, and include it in `markdownEntry`, `pageEntry`, AND `viewEntry`:

```ts
const zoomField = z.number().positive().optional().catch(undefined)
```

(Add `zoom: zoomField` to all three `z.looseObject({...})` schemas.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Pommora && npx vitest run src/shared/blocks.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pommora/src/shared/blocks.ts Pommora/src/shared/blocks.test.ts
git commit -m "feat(blocks): zoom field on block entries (absent = 1.0; uniform union)"
```

---

### Task 3: One var (`--block-zoom`) drives font + glyphs + handle

CSS-only. Deliverable: **the full-page editor is visually unchanged, and setting `--block-zoom` on a `.spm-tile` (dev-tools override, or Task 4's class) scales font + glyphs + handle together while padding/gutter/edge-fade stay put.** Verified by build + eyeball (no meaningful unit test for a CSS var).

**Files:**
- Modify: `src/renderer/src/MarkdownPM/Styles.css` (add `--glyph-scale`; chevron ~:17, grips ~:199–229; `.cm-content` font-size ~:69)
- Modify: `src/renderer/src/Embeds/embeds.css` (checkbox ~:36)
- Modify: `src/renderer/src/SurfacePM/surfacepm.css` (handle ~:78–96; add 4 zoom rules)

**Interfaces:**
- Consumes: `--block-zoom` (falls back to `1` everywhere).
- Produces: `--glyph-scale = --mdpm-scale × --block-zoom`; `.cm-content` font scales × `--block-zoom`; handle dims × `--block-zoom`; `.spm-tile.blk-zoom-{125,085,065,050}` set `--block-zoom`.

- [ ] **Step 1: `--glyph-scale` + the font multiply (Styles.css)**

In `.mdpm-shell` (~:13–27), add ABOVE `--fold-chevron-size`:

```css
  /* Glyph scale = the structural px scale × the per-block Scale (G-10). Structural dims (gutter WIDTH,
     content padding) stay on --mdpm-scale and never see --block-zoom; only glyphs read this. Absent
     --block-zoom (full-page editor, or a 1.0 tile) makes this identical to --mdpm-scale. */
  --glyph-scale: calc(var(--mdpm-scale) * var(--block-zoom, 1));
```

Change `--fold-chevron-size` (~:17) from `* var(--mdpm-scale)` to `* var(--glyph-scale)`.

Multiply the content font-size by the per-block factor. `.cm-content` (~:69) `font-size: var(--editor-font-size, 15px)` becomes:

```css
  /* The base is --editor-font-size (the editor `zoom` prop). --block-zoom applies the per-block Scale
     LINEARLY here — NOT through the clamped zoom curve — so it stays locked to --glyph-scale (both are
     × --block-zoom) and never floors. Absent --block-zoom ⇒ unchanged. em children ride this root. */
  font-size: calc(var(--editor-font-size, 15px) * var(--block-zoom, 1));
```

- [ ] **Step 2: Grips → `--glyph-scale` (Styles.css)**

In the grip rules (~:199–229), change every grip `px * var(--mdpm-scale)` to `px * var(--glyph-scale)`:
- `width`/`height: calc(14px * var(--mdpm-scale))` → `* var(--glyph-scale)`.
- centering `left: calc(... - 14px * var(--mdpm-scale)) / 2)` → `* var(--glyph-scale)` (both grip rules).
- `top: var(--grip-top, calc(0.8em - 7px * var(--mdpm-scale)))` → `- 7px * var(--glyph-scale)` (both). The `0.8em` half stays — it rides the font, which now carries `Z`.

- [ ] **Step 3: Checkbox → `--glyph-scale`; gutter/padding frozen (embeds.css)**

`.pgembed .md-checkbox { zoom: var(--mdpm-scale) }` (~:36) → `zoom: var(--glyph-scale)`. **Do NOT touch** `--fold-gutter: calc(20px * var(--mdpm-scale))` (~:16) or the `.cm-content` padding (~:28) — structural, frozen.

- [ ] **Step 4: Handle scales as a unit + the zoom classes (surfacepm.css)**

In `.spm-handle` (~:78–96), scale the size dims by `--block-zoom` (keep `top: 16px` — that's position, not size; scaling only size keeps the chip proportional AND anchored, since `left` already derives from `--handle-w`):

```css
  --handle-w: calc(12px * var(--block-zoom, 1));
  --grip-size: calc(14px * var(--block-zoom, 1)); /* the glyph's size — independent of the chip */
  height: calc(22px * var(--block-zoom, 1));
  border-radius: calc(4px * var(--block-zoom, 1));
```

Add after the `.spm-tile` base rule (with the other tile-state rules):

```css
/* Per-block Scale (G-10): one discrete var on the tile; the font (via .cm-content), the editor glyphs
   (via --glyph-scale), and the handle all read it — the frozen gutter/padding do not. Five steps; 1.0
   needs no class (--block-zoom falls back to 1). */
.spm-tile.blk-zoom-125 {
  --block-zoom: 1.25;
}
.spm-tile.blk-zoom-085 {
  --block-zoom: 0.85;
}
.spm-tile.blk-zoom-065 {
  --block-zoom: 0.65;
}
.spm-tile.blk-zoom-050 {
  --block-zoom: 0.5;
}
```

- [ ] **Step 5: Gate + verify the full-page editor is untouched, and a manual override scales cleanly**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck > /tmp/tc.log 2>&1; echo "TC=$?"; npx vitest run > /tmp/vt.log 2>&1; echo "VT=$?"; env -u ELECTRON_RUN_AS_NODE npm run build > /tmp/bd.log 2>&1; echo "BD=$?"` — grep each log; expect `TC=0 VT=0 BD=0`.

Relaunch. (a) Open a full **page**: chevrons, grips, checkboxes, and text must be **identical to before** (proof `--block-zoom` absent ⇒ `--glyph-scale === --mdpm-scale` and font × 1). (b) In dev tools, add `--block-zoom: 0.5` to one `.spm-tile` on the homepage and confirm its text + chevrons + grips + handle shrink **in lockstep** (no font/glyph mismatch) while the inset + fold-gutter width + edge-fade hold.

- [ ] **Step 6: Commit**

```bash
git add Pommora/src/renderer/src/MarkdownPM/Styles.css Pommora/src/renderer/src/Embeds/embeds.css Pommora/src/renderer/src/SurfacePM/surfacepm.css
git commit -m "refactor(mdpm): --block-zoom drives font + --glyph-scale + handle; structural frozen"
```

---

### Task 4: Wire the entry → the tile class

Deliverable: **an entry's `zoom` sets the tile's `--block-zoom` class, so a hand-set `zoom` on disk scales that tile.** No component font wiring (Task 3 made the font pure CSS).

**Files:**
- Modify: `src/renderer/src/Blocks/BlockSurface.tsx` (`tileClassName` + a `setBlockZoom` writer)

**Interfaces:**
- Consumes: `zoomStep` (Task 1); `entries: Map<string, BlockEntry>` (already in `BlockSurface`).
- Produces: `setBlockZoom(id: string, factor: number): void` (writes `zoom`, clears it at `1`).

- [ ] **Step 1: Emit the zoom class in `tileClassName`**

Import at top: `import { zoomStep } from './blockZoom'`. In `tileClassName(id)`, add to the `classes` array (`.zoom` is now on the whole union, so no narrowing needed):

```tsx
zoomStep(entries.get(id)?.zoom).cls || null,
```

- [ ] **Step 2: Add the writer**

Near `mutateViewEntry`, add (NOT type-gated — `zoom` is on the union; the caller only offers it on markdown/page):

```tsx
// Per-block Scale writer (G-10): patches the RAW entry so foreign keys survive (E-1); clears `zoom`
// at 1.0 so the default stays an absent key. Mirrors setStyle/toggleLock.
const setBlockZoom = useCallback(
  (id: string, factor: number) => {
    saveBlocks((cur) =>
      cur.map((raw) => {
        if (knownBlock(raw)?.id !== id) return raw
        const next = { ...(raw as Record<string, unknown>) }
        if (factor === 1) delete next.zoom
        else next.zoom = factor
        return next
      })
    )
  },
  [saveBlocks]
)
```

- [ ] **Step 3: Gate + verify a disk-set zoom + a LIVE change**

Run the full gate (Step 5 form); expect `TC=0 VT=0 BD=0`.

On a disposable host (or a hand-edited block doc — NOT via CDP on the real Nexus, it autosaves): add `"zoom": 0.5` to a markdown/page entry, relaunch → that tile scales, inset frozen. Then, **critically**, verify a LIVE change re-lays-out the editor: with the app running, flip the class on a `.spm-tile` in dev tools (e.g. add `blk-zoom-050`) and confirm the CM6 embed **re-measures** (caret, line boxes, and click-to-caret land correctly at the new size — not just visually smaller with stale geometry). If geometry is stale, the fallback is to key the tile's editor on its zoom factor so it remounts on change (`key={\`${id}:${entry.zoom ?? 1}\`}` in `renderTile`); note which was needed.

- [ ] **Step 4: Commit**

```bash
git add Pommora/src/renderer/src/Blocks/BlockSurface.tsx
git commit -m "feat(surfacepm): entry.zoom drives the tile Scale class + the writer"
```

---

### Task 5: The "Scale" picker in the handle menu

Deliverable: **a `Scale` row (markdown + page tiles only) whose trailing value opens a 5-step picker; picking scales the tile and persists.**

**Files:**
- Modify: `src/renderer/src/Blocks/BlockHandleMenu.tsx` (the row + the `scale` sub-pane)
- Modify: `src/renderer/src/Blocks/handleMenu.css.ts` (trailing-value styles, mirroring `titleFieldLoc`)
- Modify: `src/renderer/src/Blocks/BlockSurface.tsx` (pass `zoom` + `onSetZoom` to the menu)

**Interfaces:**
- Consumes: `ZOOM_STEPS`, `zoomStep` (Task 1); `setBlockZoom` (Task 4). `entry.zoom` reads cleanly now (Task 2 made the union uniform).
- Produces: `BlockHandleMenu` gains `zoom?: number` and `onSetZoom?: (factor: number) => void`; a `pane === 'scale'` sub-pane.

- [ ] **Step 1: Pass `zoom` + `onSetZoom` from the surface**

In `BlockSurface.tsx`, at the `<BlockHandleMenu .../>` render (mirror how `onToggleLock` is wired; re-ground the local `menuEntry`/`handleMenu` names at pickup):

```tsx
zoom={menuEntry?.zoom}
onSetZoom={(factor) => handleMenu && setBlockZoom(handleMenu.id, factor)}
```

- [ ] **Step 2: The `Scale` row + `scale` pane (BlockHandleMenu.tsx)**

Import `{ ZOOM_STEPS, zoomStep } from './blockZoom'`. Add props `zoom?: number`, `onSetZoom?: (factor: number) => void`. Widen the pane union to include `'scale'`.

Add to the root rows, **markdown + page only**, muted under lock like its siblings. Trailing = the compact value + a double-chevron:

```tsx
{entry.type !== 'view' && (
  <MenuItem
    className={cx(s.row, rowMute)}
    leading={<Icon name="scaling" size={GLYPH} />}
    trailing={
      <span className={s.scaleTrailing}>
        <span className={s.scaleValue}>{zoomStep(zoom).inline}</span>
        <Icon name="chevrons-up-down" size={GLYPH} />
      </span>
    }
    onClick={locked ? undefined : () => setPane('scale')}
  >
    Scale
  </MenuItem>
)}
```

Add the `scale` sub-pane (beside `stylePane`), current step checked:

```tsx
const scalePane = (
  <div className={s.pane}>
    <MenuPaneTopRow label="Menu" current="Scale" onBack={() => setPane('root')} contentClassName={s.barScale} />
    {ZOOM_STEPS.map((st) => (
      <MenuItem
        key={st.label}
        className={s.row}
        trailing={zoomStep(zoom).factor === st.factor ? <Icon name="check" size={GLYPH} /> : undefined}
        onClick={act(() => onSetZoom?.(st.factor))}
      >
        {st.label}
      </MenuItem>
    ))}
  </div>
)
```

Wire `pane === 'scale'` → `scalePane` into the existing `detail` chain and the `PaneSlider open` condition exactly as `'style'` is handled.

- [ ] **Step 3: Style the trailing value (handleMenu.css.ts)**

Mirror the file's existing `titleFieldLoc` (footnote size/line + `label.secondary`) — do NOT import the composed `text` token; this file styles via `font.scale.*` directly:

```ts
export const scaleTrailing = style({ display: 'inline-flex', alignItems: 'center', gap: '2px', color: c.label.tertiary })
export const scaleValue = style({ fontSize: font.scale.footnote.size, lineHeight: font.scale.footnote.line, color: c.label.secondary })
```

(`font` and `c` are already imported in this file — confirm at pickup; the `titleFieldLoc`/`titleFieldLocIcon` pair proves the two-tone idiom.)

- [ ] **Step 4: Gate + verify the picker end-to-end**

Run the full gate; expect `TC=0 VT=0 BD=0`.

Relaunch, open a markdown/page tile's handle menu: the `Scale` row shows `1x` + a double-chevron in the footnote/secondary tone; clicking slides to the 5 steps with `1.00x` checked; picking `0.65x` closes the menu, shrinks that tile in lockstep (inset frozen), and persists across a relaunch. Open a **view-embed** tile's menu → **no Scale row**. CDP-clip + read (do not send) the open picker + a zoomed tile; confirm against this spec.

- [ ] **Step 5: Commit**

```bash
git add Pommora/src/renderer/src/Blocks/BlockHandleMenu.tsx Pommora/src/renderer/src/Blocks/handleMenu.css.ts Pommora/src/renderer/src/Blocks/BlockSurface.tsx
git commit -m "feat(surfacepm): Scale row + 5-step picker in the block handle menu"
```

---

### Task 6: Docs + post-functional review

**Files:** `.claude/Features/SurfacePM.md`, `.claude/Handoff.md`

- [ ] **Step 1:** In `SurfacePM.md` Surface Interaction, add: a tile carries a per-block **Scale** (five discrete steps, default 1×, set from the handle menu) that scales content + glyphs + handle while the inset, fold-gutter width, and edge-fade stay frozen. In `#### Pending`, add **Table (view-embed) Scale** = Phase 2 (the density knob must move off CSS `zoom` to font-size-driven text + fixed px padding/widths + reworked `TableView.tsx` pointer math). Name tokens, not `#hex`/px values.
- [ ] **Step 2:** Update `Handoff.md` via `/handoff` (Session Summary + Next Session): per-block Scale shipped on markdown/page tiles; table Scale is the open Phase 2.
- [ ] **Step 3:** Dispatch a `build-breaking-agent` on the working-tree diff (freeze-inset holds at every step incl. 0.5× on a page embed; lock keeps the picker unreachable; the view gate; live re-measure). Fold verified findings, then commit docs.

```bash
git add ".claude/Features/SurfacePM.md" ".claude/Handoff.md"
git commit -m "docs(surfacepm): per-block Scale shipped; table Scale deferred to Phase 2"
```

---

## Deferred — Phase 2: Table (view-embed) Scale (OUT OF SCOPE)

View embeds are excluded. Their density is the CSS `zoom` property (`Table.css` `.table-grid`/`.group-header-row`, fed `--zoom = VIEW_EMBED_ZOOM`), which magnifies text + padding + borders + column widths **uniformly** — it structurally cannot freeze padding while scaling text. Matching freeze-inset is a re-architecture, its own plan: drive table text/chips by `font-size × Z`; keep `--cell-padding-*`/`--row-indent`/borders/column-width on fixed px; rework the pointer-coordinate conversions in `TableView.tsx` (~:309, :958, :1279) that divide by a uniform `zoom`; then extend the Scale row to `type === 'view'`. (The table's documented "Compact = 0.9" was never wired — comment-only in `table-tokens.css`; Phase 2 supersedes it.)

---

## Self-Review

**Spec coverage:** 5 derived steps + default (T1) · persistence absent=1, uniform union (T2) · freeze inset/gutter/blur while scaling font+glyphs+handle in lockstep (T3, verified T3.5/T4.3) · handle scales proportionally (T3.4) · Scale row + footnote-secondary trailing + double-chevron + picker `1.00x`, view-gated (T5) · relative-to-natural-size (font × --block-zoom over each tile's own --editor-font-size + --mdpm-scale base). No gaps.

**Review findings folded:** F1 clamp → linear CSS font (T3.1), no `zoomLevelForFactor`. F2 typecheck → `zoom?` on `ViewBlockEntry` (T2). F3 handle → height+radius scaled (T3.4). Simplifications → derived `ZOOM_STEPS` (T1), reused `titleFieldLoc` typography (T5.3), dropped the cross-module default import.

**Placeholder scan:** none — complete code + exact commands throughout.

**Type consistency:** `zoomStep`/`ZOOM_STEPS`/`ZoomStep` identical T1/T4/T5; `zoom?: number` (T2) read as `entry.zoom`/`zoom` prop (T4/T5); `setBlockZoom(id, factor)` defined T4, called T5.

**Two build-time calls (screenshot + confirm, non-blocking):** (1) the picker renders as a sliding sub-pane (DRY with the menu's `Style ▸` drill) — swap to a literal anchored dropdown only if Nathan dislikes it on sight. (2) The live-re-measure check (T4.3) may force a keyed editor remount on zoom change — a known fallback, not a blocker.
