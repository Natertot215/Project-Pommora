import { globalStyle, keyframes, style } from '@vanilla-extract/css'
import { vars as colorVars } from '../design-system/tokens/color.css'
import { text } from '../design-system/tokens/typography.css'
import { VIEW_EMBED_ZOOM } from '../Embeds/embedScale'

const c = colorVars.color

// KNOBS — the switcher pill's box: a fixed height with a wider horizontal padding gives the ViewDropdown
// button's slightly-rectangular ratio at the pill's own (smaller) size. PILL_MIN_W floors the width (0 =
// sized to content); PILL_ICON is the leading glyph size (px, consumed by ViewEmbedBlock).
const PILL_H = '24px'
const PILL_PAD_X = '12px'
const PILL_MIN_W = '0px'
export const PILL_ICON = 13

// The header's horizontal insets — shared by the title row, the switcher row, and the title divider,
// so the divider aligns with the content instead of bleeding to the block edges.
const HEAD_PAD_L = '14px'
const HEAD_PAD_R = '12px'

// KNOB — how far the scroll region rises BEHIND the switcher so the top scroll-fade's disappear point
// (the mask's transparent edge) lands at the pill midline. ≈ half the switcher height; tune to taste.
const FADE_RISE = '18px'

export const tile = style({ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0 })

/** H-5's title row — the editable heading over the switcher; its bottom hairline is the header's
 *  ONLY divider (none under the pills, none once the title row is hidden). The row establishes
 *  markdownPM's editor font-size as the em base, so the `.md-hN` class on the title resolves its
 *  `1.2em` (etc.) to the exact px a markdownPM heading would — same code, uniform result. */
export const titleRow = style({
  display: 'flex',
  alignItems: 'center',
  gap: '8px',
  padding: `13px ${HEAD_PAD_R} 8px ${HEAD_PAD_L}`,
  flex: 'none',
  fontSize: 'var(--editor-font-size, 15px)',
  position: 'relative',
  // The divider inset to the header padding (not a full-bleed border), so it aligns with the content.
  '::after': {
    content: '""',
    position: 'absolute',
    bottom: 0,
    left: HEAD_PAD_L,
    right: HEAD_PAD_R,
    height: '1px',
    background: c.separator.segment
  }
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
  padding: `6px ${HEAD_PAD_R} 6px ${HEAD_PAD_L}`,
  flex: 'none',
  position: 'relative',
  zIndex: 1 // paints over the scroll region that rises behind it (FADE_RISE)
})

/** A view pill: icon + label-control title on the quaternary fill, hairline-bordered — a fixed height
 *  with wider horizontal padding for the ViewDropdown button's slightly-rectangular ratio (PILL_H /
 *  PILL_PAD_X). The active view's pill lifts on the selected-state fill (surfacepm idiom, not outline). */
export const pill = style([
  text.control.emphasized,
  {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '5px',
    flexShrink: 0,
    boxSizing: 'border-box',
    height: PILL_H,
    minWidth: PILL_MIN_W,
    paddingInline: PILL_PAD_X,
    borderRadius: '8px',
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

// View-switch slide (the sidebar mode-switch's translate + the shell-move tokens): the incoming view
// slides in from the clicked pill's side — `--slide-from` carries the signed offset (+ from the right,
// − from the left), re-triggered by re-keying the wrapper on the active index.
const viewSwitchSlide = keyframes({
  from: { transform: 'translateX(var(--slide-from, 0px))', opacity: 0.5 },
  to: { transform: 'translateX(0)', opacity: 1 }
})
export const slideWrap = style({
  animationName: viewSwitchSlide,
  animationDuration: 'var(--duration-base)',
  animationTimingFunction: 'var(--ease-standard)'
})

export const spacer = style({ flex: '1 1 auto' })

/** The config affordance — hover chrome (G-4's top-right family), same glyph as the toolbar Settings. */
export const configBtn = style({
  border: 'none',
  background: 'none',
  padding: '2px',
  borderRadius: '4px',
  display: 'flex',
  color: c.label.tertiary,
  opacity: 0,
  transition: 'opacity 120ms ease, background 120ms ease',
  ':hover': { color: c.label.secondary }
})
globalStyle(`${tile}:hover ${configBtn}`, { opacity: 1 })

/** While the settings pane is open the button stays shown and pressed — the selected-state fill held
 *  as if hovered, so it reads as the anchor of the open pane even once the pointer leaves the tile. */
export const configBtnActive = style({
  opacity: 1,
  color: c.label.secondary,
  background: 'var(--state-selected)'
})

/** The dropdown-mode view list — the ViewPane's row anatomy inside a PickerMenu. */
export const listPane = style({ minWidth: 150 })

// The embed owns its table gutter (row grips + group chevrons strip) rather than inheriting
// --fold-gutter from a host rule — the container-table treatment no longer reaches a block surface,
// so the embedded table sets its own, the way .blk-md / .pgembed each set theirs.
//
// SCROLL MODEL (edge-release): the rows scroll vertically inside the body (the header rows stay pinned
// above it), and the default scroll-chaining releases to the page once the table bottoms out. A table
// that fits its tile has nothing to scroll, so the wheel passes straight through to the page — only a
// genuinely-overflowing table ever captures. Horizontal stays the table's own (.table-view overflow-x).
export const body = style({
  flex: '1 1 auto',
  minWidth: 0,
  minHeight: 0,
  overflowX: 'hidden',
  overflowY: 'auto',
  // Rise behind the switcher so the top scroll-fade dissolves rows AT the pill midline: the negative
  // margin pulls the scroll box up under the pills, the matching padding keeps the first row clear of them.
  marginTop: `calc(-1 * ${FADE_RISE})`,
  paddingTop: FADE_RISE,
  vars: { '--fold-gutter': '20px' }
})

/** The fixed embed zoom lands on the table's own token scope — the var is declared ON
 *  .table-view (table-tokens.css), so only a descendant-scoped redeclaration outranks it. */
globalStyle(`${body} .table-view, ${body} .table-empty`, { vars: { '--zoom': String(VIEW_EMBED_ZOOM) } })

/** Embedded tables shed the column-header band chrome — no heading fill, no divider under it;
 *  the header row reads as bare column labels over the data. */
globalStyle(`${body} .table-head`, { background: 'none', borderBottom: 'none' })

/** The heading strip's leading cap (.col-header:first-child::before) marks the gutter↔Title junction, so
 *  it sits --fold-gutter in — but the embed header insets at HEAD_PAD_L. Pull ONLY the cap out to the
 *  header inset so the strip's left edge lines up under the title + pills; the columns + gutter stay put.
 *  The col-header clips overflow (label truncation), so the first one lets its leading cap escape left. */
globalStyle(`${body} .col-header:first-child`, { overflow: 'visible' })
globalStyle(`${body} .col-header:first-child::before`, { left: `calc(${HEAD_PAD_L} - var(--fold-gutter))` })
