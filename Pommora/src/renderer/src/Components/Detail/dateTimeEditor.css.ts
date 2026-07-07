import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'

const c = colorVars.color

export const section = style({ display: 'flex', flexDirection: 'column', gap: '2px' })

/** The "Format" section label — the shared heading tone (label-secondary, footnote semibold). */
export const heading = style([text.footnote.semibold, { color: c.label.secondary, paddingBottom: '4px' }])

/** One config row — leading glyph, label, trailing picker trigger. */
export const row = style({ display: 'flex', alignItems: 'center', gap: '8px', minHeight: '28px' })

export const leading = style({ display: 'inline-flex', color: c.label.secondary })

/** The row label (Date · Day · Time) — the on-control label tone, matching the URL editor's rows. */
export const label = style([text.control.emphasized, { flex: '1 1 auto', color: c.label.control }])

/** The picker trigger — bare button reading in the secondary tone; `&&` beats the toolbar/UA button tone. */
export const trigger = style({
  display: 'inline-flex',
  alignItems: 'center',
  gap: '4px',
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  selectors: { '&&': { color: c.label.secondary } }
})

export const value = style([text.control.standard, { selectors: { '&&': { color: c.label.secondary } } }])
