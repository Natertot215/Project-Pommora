import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../design-system/tokens/color.css'
import { tintAt, TINT_STEPS } from '../../design-system/tokens/tint'

const c = colorVars.color

// ── KNOBS — the ViewSettings grid + tiles (tune here) ──
const GRID = {
  gapX: 8, // between-cell horizontal gap
  gapY: 8, // between-cell vertical gap
  edgeY: 8, // grid insets against the dividers above/below
  tileRadius: 8, // tile corner radius
  tileBorder: 2, // tile border width
  tileAspect: 1.5 // wider than tall (the Figma proportion)
}

/** The 3×2 type grid. */
export const grid = style({
  display: 'grid',
  gridTemplateColumns: 'repeat(3, 1fr)',
  gap: `${GRID.gapY}px ${GRID.gapX}px`,
  padding: `${GRID.edgeY}px 0`
})

/** One type tile — a rounded rect, wider than tall, holding only its type glyph. A SOLID surface fill
 *  (not the glass backdrop) backs the glyph so its anti-aliased strokes rasterize against a known colour
 *  instead of the composited frost — the fix for the fuzzy-icon aliasing. The `&&` pins the glyph tone
 *  above `.app-toolbar button`'s control-tone rule (the pane lives in the toolbar's DOM). */
export const tile = style({
  aspectRatio: `${GRID.tileAspect}`,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: `${GRID.tileBorder}px solid ${c.separator.border}`,
  borderRadius: `${GRID.tileRadius}px`,
  background: c.surface.secondary,
  padding: 0,
  cursor: 'default',
  selectors: { '&&': { color: c.label.secondary } }
})

/** The selected type — accent border at tint-primary. */
export const tileSelected = style({ borderColor: tintAt('var(--accent)', TINT_STEPS.primary) })
