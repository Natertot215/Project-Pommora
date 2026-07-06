import { style } from '@vanilla-extract/css'
import { vars as colorVars, inputFieldVar } from '../../design-system/tokens/color.css'

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

/** The icon + title header row (icon-picker stub + the view's editable title). */
export const header = style({ display: 'flex', alignItems: 'center', gap: '8px', padding: '2px 0 6px 2px' })

/** The square icon button — a dashed placeholder until the Figma icon picker lands. */
export const iconButton = style({
  flex: '0 0 auto',
  width: '28px',
  height: '28px',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  borderRadius: '8px',
  border: 'none',
  background: inputFieldVar,
  cursor: 'default',
  color: c.label.tertiary,
  selectors: { '&:hover': { background: c.fill.quaternary } }
})

/** The title interaction-field takes the remaining width. */
export const titleField = style({ flex: '1 1 auto', minWidth: 0 })

/** The 3×2 type grid. */
export const grid = style({
  display: 'grid',
  gridTemplateColumns: 'repeat(3, 1fr)',
  gap: `${GRID.gapY}px ${GRID.gapX}px`,
  padding: `${GRID.edgeY}px 0`
})

/** One type tile — a rounded rect, wider than tall, holding only its type glyph. */
export const tile = style({
  aspectRatio: `${GRID.tileAspect}`,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: `${GRID.tileBorder}px solid ${c.separator.border}`,
  borderRadius: `${GRID.tileRadius}px`,
  background: 'none',
  padding: 0,
  cursor: 'default',
  color: c.label.tertiary
})

/** The selected type — accent border (tint-primary). */
export const tileSelected = style({ borderColor: 'var(--accent)' })
