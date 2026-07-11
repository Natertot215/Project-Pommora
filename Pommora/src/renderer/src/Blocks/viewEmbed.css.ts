import { globalStyle, keyframes, style } from '@vanilla-extract/css'
import { vars as colorVars } from '../design-system/tokens/color.css'
import { text } from '../design-system/tokens/typography.css'
import { VIEW_EMBED_ZOOM } from '../Embeds/embedScale'

const c = colorVars.color

export const tile = style({ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0 })

/** H-5's title row — the editable heading over the switcher; its bottom hairline is the header's
 *  ONLY divider (none under the pills, none once the title row is hidden). The row establishes
 *  markdownPM's editor font-size as the em base, so the `.md-hN` class on the title resolves its
 *  `1.2em` (etc.) to the exact px a markdownPM heading would — same code, uniform result. */
export const titleRow = style({
  display: 'flex',
  alignItems: 'center',
  gap: '8px',
  padding: '13px 12px 8px 14px',
  borderBottom: `1px solid ${c.separator.segment}`,
  flex: 'none',
  fontSize: 'var(--editor-font-size, 15px)'
})

/** The title text + its in-place rename input. Size + weight come from the `.md-hN` class the caller
 *  appends (markdownPM's own heading code); this carries only colour, truncation, and the input reset. */
export const titleText = style({
  flex: '1 1 auto',
  minWidth: 0,
  whiteSpace: 'nowrap',
  overflow: 'hidden',
  textOverflow: 'ellipsis',
  color: c.label.primary,
  fontFamily: 'inherit',
  border: 'none',
  background: 'none',
  padding: 0,
  outline: 'none'
})

/** The switcher row — view pills (+ New View) leading, the config affordance trailing when
 *  the title row is hidden and this line is the whole header. */
export const switcherRow = style({
  display: 'flex',
  alignItems: 'center',
  gap: '6px',
  padding: '6px 12px 6px 14px',
  flex: 'none'
})

/** A view pill: icon + label-control title on the quaternary fill, hairline-bordered, 6pt. The
 *  active view's pill lifts on the selected-state fill (the surfacepm active idiom, not an outline). */
export const pill = style([
  text.control.emphasized,
  {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '5px',
    padding: '5px 8px',
    borderRadius: '6px',
    background: c.fill.quaternary,
    border: `1px solid ${c.separator.segment}`,
    color: c.label.secondary,
    whiteSpace: 'nowrap',
    cursor: 'default'
  }
])

export const pillActive = style({
  background: `linear-gradient(var(--state-selected), var(--state-selected)), ${c.fill.quaternary}`,
  color: c.label.primary
})

// Create/delete slide (H-5): a new pill grows in from the leading edge, a deleted one collapses
// out — max-width + opacity on the dropdown token, the negative margin swallowing the row gap so
// siblings close up. No house horizontal-list primitive exists; this is the pill's own.
const pillIn = keyframes({
  '0%': { opacity: 0, maxWidth: 0, marginRight: '-6px', transform: 'translateX(-4px)' },
  '100%': { opacity: 1, maxWidth: '240px', transform: 'none' }
})
const pillOut = keyframes({
  '0%': { opacity: 1, maxWidth: '240px' },
  '100%': { opacity: 0, maxWidth: 0, marginRight: '-6px', transform: 'translateX(-4px)' }
})
export const pillEntering = style({
  overflow: 'hidden',
  animationName: pillIn,
  animationDuration: 'var(--duration-dropdown)',
  animationTimingFunction: 'var(--ease-standard)'
})
export const pillExiting = style({
  overflow: 'hidden',
  pointerEvents: 'none',
  animationName: pillOut,
  animationDuration: 'var(--duration-dropdown)',
  animationTimingFunction: 'var(--ease-standard)'
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

// The embed owns its table gutter (row grips + group chevrons strip) rather than inheriting
// --fold-gutter from a host rule — the container-table treatment no longer reaches a block surface,
// so the embedded table sets its own, the way .blk-md / .pgembed each set theirs.
export const body = style({
  flex: '1 1 auto',
  minWidth: 0,
  minHeight: 0,
  overflow: 'hidden',
  vars: { '--fold-gutter': '20px' }
})

/** The fixed embed zoom lands on the table's own token scope — the var is declared ON
 *  .table-view (table-tokens.css), so only a descendant-scoped redeclaration outranks it. */
globalStyle(`${body} .table-view, ${body} .table-empty`, { vars: { '--zoom': String(VIEW_EMBED_ZOOM) } })

/** Embedded tables shed the column-header band chrome — no heading fill, no divider under it;
 *  the header row reads as bare column labels over the data. */
globalStyle(`${body} .table-head`, { background: 'none', borderBottom: 'none' })
