import { style } from '@vanilla-extract/css'
import { text, vars } from '@renderer/design-system/tokens'

const c = vars.color

/** Scrim behind the crop dialog — system black at 45% (color-mix is the project's opacity mechanism). */
export const backdrop = style({
  position: 'fixed',
  inset: 0,
  zIndex: 1000,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  background: `color-mix(in srgb, ${c.system.black} 45%, transparent)`,
})

/** Dialog panel — layout on top of the GlassSurface frost Material (the design-system surface glass). */
export const panel = style({
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'center',
  gap: '14px',
  padding: '18px',
  borderRadius: '12px',
  border: `1px solid ${c.separator.border}`,
  boxShadow: `0 20px 60px color-mix(in srgb, ${c.system.black} 55%, transparent)`,
})

export const title = style([text.headline.emphasized, { color: c.label.primary }])

/** The crop viewport — clips the image; a surface fills it behind the photo while it loads. */
export const viewport = style({
  position: 'relative',
  overflow: 'hidden',
  borderRadius: '8px',
  background: c.surface.primary,
  cursor: 'grab',
  touchAction: 'none',
  userSelect: 'none',
})
export const grabbing = style({ cursor: 'grabbing' })

/** The dark, blurred surround outside the circle (clear inside) — a masked backdrop-filter overlay. */
export const surround = style({ position: 'absolute', inset: 0, pointerEvents: 'none' })

/** A hairline ring marking the exact crop circle. */
export const ring = style({
  position: 'absolute',
  borderRadius: '50%',
  border: `1px solid ${c.label.secondary}`,
  pointerEvents: 'none',
})

export const slider = style({ width: '100%', accentColor: 'var(--accent)', cursor: 'pointer' })

export const message = style([text.footnote.standard, { color: c.label.secondary }])

export const actions = style({
  display: 'flex',
  gap: '8px',
  alignSelf: 'stretch',
  justifyContent: 'flex-end',
})

const buttonBase = {
  padding: '5px 14px',
  borderRadius: '7px',
  border: 'none',
  cursor: 'default',
} as const
export const button = style([
  text.body.standard,
  {
    ...buttonBase,
    color: c.label.primary,
    background: c.fill.secondary,
    selectors: { '&:hover': { background: c.fill.primary } },
  },
])
export const buttonPrimary = style([
  text.body.emphasized,
  {
    ...buttonBase,
    color: c.label.primary,
    background: 'var(--accent)',
    selectors: { '&:disabled': { opacity: 0.5 } },
  },
])
