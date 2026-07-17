import { style } from '@vanilla-extract/css'
import { text, vars } from '@renderer/design-system/tokens'

const c = vars.color

/**
 * Nexus header (Figma node 432:1919) — sits at the top of the sidebar in place of the old
 * Homepage row: a circular photo/avatar slot beside a two-line spine of the nexus title
 * (Headline/Standard, label-primary) over its description (Caption, label-secondary), 6px gap.
 * The highlight tint shows on hover only, never as a static background.
 */
export const header = style({
  display: 'flex',
  alignItems: 'center',
  gap: '6px',
  padding: '5px 8px',
  borderRadius: '8px',
  cursor: 'default',
  selectors: { '&:hover': { background: c.state.hover } },
})

/** Selected state — the header is the live homepage entity; tints when it's the active selection. */
export const headerSelected = style({ background: c.state.selected })

/** Circular photo / avatar slot (32px) — holds the nexus photo (cover-fit) or the default icon.
 *  No background of its own, so a photo with transparency shows the liquid-glass sidebar through. */
export const photo = style({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  flex: '0 0 auto',
  width: '32px',
  height: '32px',
  borderRadius: '50%',
  overflow: 'hidden',
  color: c.label.secondary,
})

/** Faint placeholder tint for the EMPTY slot only — dropped once a photo is set so its
 *  transparent areas fall through to the glass instead of a solid fill. */
export const photoEmpty = style({ background: c.fill.tertiary })

export const photoImg = style({
  width: '100%',
  height: '100%',
  objectFit: 'cover',
  display: 'block',
})

export const textBlock = style({
  display: 'flex',
  flexDirection: 'column',
  gap: '2px',
  minWidth: 0,
  flex: '1 1 auto',
})

const line = {
  margin: 0,
  overflow: 'hidden',
  textOverflow: 'ellipsis',
  whiteSpace: 'nowrap',
} as const

export const title = style([text.headline.semibold, { ...line, color: c.label.primary }])

export const description = style([text.caption.standard, { ...line, color: c.label.secondary }])

/** Muted placeholder shown when no description is set yet. */
export const descriptionEmpty = style([text.caption.standard, { ...line, color: c.label.tertiary }])

// Inline-edit inputs — borderless + transparent so they read exactly like the text they replace.
const inputReset = {
  border: 'none',
  outline: 'none',
  background: 'transparent',
  padding: 0,
  margin: 0,
  width: '100%',
} as const
export const titleInput = style([text.headline.semibold, { ...inputReset, color: c.label.primary }])
export const descriptionInput = style([
  text.caption.standard,
  { ...inputReset, color: c.label.secondary },
])
