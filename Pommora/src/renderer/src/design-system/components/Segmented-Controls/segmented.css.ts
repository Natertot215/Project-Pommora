import { style } from '@vanilla-extract/css'
import { titleReveal } from '../../animations.css'
import { text, vars } from '../../tokens'

/**
 * Segmented control — the icon-only (Symbol) and icon+label (Button) variants
 * share these. Geometry (height / radius / padding / divider / icon size) is
 * applied per-instance from the size-token bundle; this file holds only the
 * token-bound look that doesn't vary by size.
 */

// The pill — glass comes from the GlassControls wrapper; this adds the flex row.
export const container = style({
  display: 'flex',
  alignItems: 'center',
  width: 'fit-content',
  overflow: 'hidden'
})

// One segment. No persistent active/pressed fill (Apple toolbar behaviour) — the
// only feedback is a faint hover (state.hover). Disabled dims the glyph.
export const segment = style({
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  gap: '4px',
  flexShrink: 0,
  padding: 0,
  border: 'none',
  // Toolbar chrome — no focus ring (clicking then pressing a key would otherwise reveal one).
  outline: 'none',
  background: 'transparent',
  color: vars.color.label.primary,
  cursor: 'default',
  transition: 'background var(--duration-fast) var(--ease-standard)',
  selectors: {
    '&:hover:not(:disabled)': { background: vars.color.state.hover },
    '&:disabled': { color: vars.color.label.tertiary }
  }
})

// Inset hairline between adjacent segments — the segment separator token. Rounded caps
// (pill ends) so the little line never reads as a sharp-cornered rectangle.
export const divider = style({
  flexShrink: 0,
  alignSelf: 'center',
  // Width is fixed (constant across every control size); only the height varies per instance.
  width: '2px',
  // The stable CSS var (theme-vars), not the vanilla-extract object ref — the var name never rehashes, so
  // an HMR token-hash shift can't leave the divider colourless (the toolbar-segment regression).
  background: 'var(--separator-segment)',
  borderRadius: '999px'
})

// The label's collapsible slot — an inline grid track that morphs 1fr → 0fr so the title slides in/out
// (content-width both directions) as the button toggles labeled/icon-only. The leading gap collapses
// with it, so the hidden state is pixel-identical to a bare icon segment. `labelText` clips inside.
export const labelSlot = style({
  display: 'inline-grid',
  gridTemplateColumns: '1fr',
  marginLeft: '6px',
  minWidth: 0,
  transition: `grid-template-columns ${titleReveal}, margin-left ${titleReveal}, opacity ${titleReveal}`
})

export const labelSlotHidden = style({ gridTemplateColumns: '0fr', marginLeft: 0, opacity: 0 })

export const labelText = style([text.control.standard, { overflow: 'hidden', whiteSpace: 'nowrap', fontWeight: 500 }])
