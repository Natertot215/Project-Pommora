import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../tokens/color.css'
import { text, truncateHoverScroll } from '../../tokens/typography.css'

const c = colorVars.color

/**
 * Menu Item row — the menu / sidebar row primitive. ~28px (6px vertical padding),
 * flush (rows touch), 8px sides, 8px icon↔text gap, 8px-radius selection pill —
 * matching the Swift build's sidebar row (SelectableRow). Composes Body/Standard so
 * the title is 13px (the macOS standard content size, NSFont.systemFontSize). Row
 * content icons are set to 16px by consumers — the Swift build sizes row icons
 * larger than their label, so they don't follow the text 1:1.
 */
export const item = style([
  text.body.standard,
  {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    minHeight: '24px',
    padding: '6px 8px',
    borderRadius: '8px',
    color: c.label.primary,
    cursor: 'default',
    userSelect: 'none',
    selectors: {
      '&:hover': { background: c.state.hover }
    }
  }
])

/** Selected pill — holds under :hover so a selected row doesn't lighten further. */
export const itemSelected = style({
  background: c.state.selected,
  selectors: { '&:hover': { background: c.state.selected } }
})

/** Heading row — Headline/Emphasized (13px Semibold), label-secondary; same
 *  geometry as an item, so its icon follows at 1em → 13px. */
export const heading = style([
  text.headline.emphasized,
  {
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
    minHeight: '24px',
    padding: '0 8px',
    color: c.label.secondary,
    userSelect: 'none'
  }
])

/** A leading / trailing glyph cluster — label-secondary (the shared icon tone), doesn't grow, its own
 *  4px gap so a disclosure + icon (or detail + chevron) keep the row rhythm. Bound to the stable
 *  --label-secondary CSS var, not the vanilla-extract ref, so an HMR token-hash shift can't blank it. */
export const side = style({
  display: 'flex',
  alignItems: 'center',
  gap: '4px',
  flex: '0 0 auto',
  color: 'var(--label-secondary)'
})

/** The flexible spine — pins leading left, trailing right; stacks title + sub-label. */
export const titleWrap = style({
  flex: '1 1 auto',
  minWidth: 0,
  display: 'flex',
  flexDirection: 'column',
  justifyContent: 'center',
  gap: '2px'
})

/** Title line — inherits the row's size (13px item / 13px heading) + colour; ellipsis at rest, scrolls
 *  the full value on hover (shared `truncateHoverScroll`, the chip-label behaviour). */
export const titleText = style([truncateHoverScroll])

/** Sub-label — Caption/Standard (11px), label-secondary, under the title. */
export const subLabel = style([
  text.caption.standard,
  { color: c.label.secondary, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }
])

/** Trailing detail — Footnote/Emphasized (10px Semibold); colour inherited from `side`. */
export const detail = style([text.footnote.emphasized])

/** Separator — an 11px band with a centered hairline (Apple's menu separator height). */
export const separator = style({ height: '11px', display: 'flex', alignItems: 'center', padding: '0 8px' })
export const separatorLine = style({ height: '1px', width: '100%', background: c.separator.line })

/** Flush variant — no side inset, so the hairline spans the surface gutter edge-to-edge. */
export const separatorFlush = style({ padding: 0 })

/** Gutter-flush affordance — the shared geometry/colour for the back-row heading nav and the pane
 *  footer actions: no item inset (so the ‹ heading and the +/Delete footer line up at one left edge),
 *  a tight 4px icon↔label gap, and label-secondary text. Each consumer sets its own type; the
 *  destructive footer (Delete) re-overrides the colour. */
export const flushAffordance = style({ paddingLeft: 0, gap: '4px', color: c.label.secondary })

/** Flush-trailing row — the trailing cluster (chevron, detail) sits against the gutter edge where
 *  the flush divider ends, instead of floating in on the row's right padding (Nathan's call). */
export const flushTrailing = style({ paddingRight: 0 })

/** Back row — flush affordance + footnote type. */
export const backRow = style([text.caption.standard, flushAffordance])

/** Non-interactive caption / empty-state line — body text, centered + secondary (no row geometry). */
export const caption = style([
  text.body.standard,
  { padding: '28px 8px', textAlign: 'center', color: c.label.secondary, userSelect: 'none' }
])

/** Menu container — a flush vertical stack with 6px top/bottom breathing room. */
export const menu = style({ display: 'flex', flexDirection: 'column', padding: '6px 0' })
