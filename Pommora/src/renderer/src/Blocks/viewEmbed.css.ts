import { globalStyle, style } from '@vanilla-extract/css'
import { vars as colorVars } from '../design-system/tokens/color.css'
import { TINT_STEPS, tintAt } from '../design-system/tokens/tint'
import { text } from '../design-system/tokens/typography.css'
import { VIEW_EMBED_ZOOM } from '../Embeds/embedScale'

const c = colorVars.color

export const tile = style({ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0 })

/** H-5's title row — the ####-scale editable title over the switcher; its bottom hairline is
 *  the header's ONLY divider (none under the pills, none at all once the row is hidden). */
export const titleRow = style({
  display: 'flex',
  alignItems: 'center',
  gap: '8px',
  padding: '9px 12px 7px 14px',
  borderBottom: `1px solid ${c.fill.quaternary}`,
  flex: 'none'
})

const titleType = [text.title3.bold, { color: c.label.primary }] as const

export const titleText = style([
  ...titleType,
  { flex: '1 1 auto', minWidth: 0, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }
])

/** The rename field the title flips into on click — the same text, editable in place. */
export const titleInput = style([
  ...titleType,
  { flex: '1 1 auto', minWidth: 0, border: 'none', background: 'none', padding: 0, outline: 'none' }
])

/** The switcher row — view pills (+ New View) leading, the config affordance trailing when
 *  the title row is hidden and this line is the whole header. */
export const switcherRow = style({
  display: 'flex',
  alignItems: 'center',
  gap: '6px',
  padding: '6px 12px 6px 14px',
  flex: 'none'
})

/** A view pill: icon + label-control title on the quinary fill, hairline-bordered. The active
 *  view's pill wears the accent tint on its border — the pane's active-row marker, pill-shaped. */
export const pill = style([
  text.control.emphasized,
  {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '5px',
    padding: '3px 8px',
    borderRadius: '4px',
    background: c.fill.quinary,
    border: `1px solid ${c.separator.segment}`,
    color: c.label.secondary,
    whiteSpace: 'nowrap',
    cursor: 'default'
  }
])

export const pillActive = style({
  borderColor: tintAt('var(--accent)', TINT_STEPS.primary),
  color: c.label.primary
})

export const spacer = style({ flex: '1 1 auto' })

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

/** The dropdown-mode view list — the ViewPane's row anatomy inside a PickerMenu. */
export const listPane = style({ minWidth: 150 })

export const body = style({ flex: '1 1 auto', minWidth: 0, minHeight: 0, overflow: 'hidden' })

/** The fixed embed zoom lands on the table's own token scope — the var is declared ON
 *  .table-view (table-tokens.css), so only a descendant-scoped redeclaration outranks it. */
globalStyle(`${body} .table-view, ${body} .table-empty`, { vars: { '--zoom': String(VIEW_EMBED_ZOOM) } })

/** Embedded tables shed the column-header band chrome — no heading fill, no divider under it;
 *  the header row reads as bare column labels over the data. */
globalStyle(`${body} .table-head`, { background: 'none', borderBottom: 'none' })
