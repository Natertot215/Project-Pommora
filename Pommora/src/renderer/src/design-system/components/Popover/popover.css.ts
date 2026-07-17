import { style } from '@vanilla-extract/css'

/** Anchored panel — positioned below its (position:relative) trigger container. */
export const anchor = style({
  position: 'absolute',
  top: 'calc(100% + 6px)',
  zIndex: 10,
  minWidth: '220px',
})

export const alignRight = style({ right: 0 })
export const alignLeft = style({ left: 0 })

/** Glass comes from GlassSurface; this adds the corner radius + breathing room. */
export const panel = style({
  borderRadius: '12px',
  padding: '6px',
  overflow: 'hidden',
})
