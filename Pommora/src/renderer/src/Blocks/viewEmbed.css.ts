import { globalStyle, style } from '@vanilla-extract/css'
import { vars as colorVars } from '../design-system/tokens/color.css'
import { text } from '../design-system/tokens/typography.css'
import { EMBED_ZOOM } from '../Embeds/embedScale'

const c = colorVars.color

export const tile = style({ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0 })

/** H-5's header — title row over the (future) switcher row; single-view collapses them to one. */
export const head = style({
  display: 'flex',
  alignItems: 'center',
  gap: '8px',
  padding: '9px 12px 7px 14px',
  borderBottom: `1px solid ${c.fill.quaternary}`,
  flex: 'none'
})

export const title = style([
  text.control.semibold,
  { color: c.label.primary, flex: '1 1 auto', minWidth: 0, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }
])

/** The config affordance — hover chrome (G-4's top-right family), same glyph as the toolbar Settings. */
export const configBtn = style({
  border: 'none',
  background: 'none',
  padding: '2px',
  display: 'flex',
  color: c.label.tertiary,
  opacity: 0,
  transition: 'opacity 120ms ease',
  ':hover': { color: c.label.secondary }
})
globalStyle(`${tile}:hover ${configBtn}`, { opacity: 1 })

export const body = style({ flex: '1 1 auto', minWidth: 0, minHeight: 0, overflow: 'hidden' })

/** The fixed embed zoom lands on the table's own token scope — the var is declared ON
 *  .table-view (table-tokens.css), so only a descendant-scoped redeclaration outranks it. */
globalStyle(`${body} .table-view, ${body} .table-empty`, { vars: { '--zoom': String(EMBED_ZOOM) } })

