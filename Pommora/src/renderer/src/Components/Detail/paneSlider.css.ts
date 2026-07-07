import { style } from '@vanilla-extract/css'
import { duration, easing } from '../../design-system/tokens/motion'

/** Clips the off-screen slot so the sliding panes stay inside the glass bounds. */
export const viewport = style({ position: 'relative', overflow: 'hidden' })

/** Idle: only WIDTH eases. Height tracks the measured content instantly, so an in-place growth (a
 *  Reveal unfolding, the elastic spacer collapsing) is owned by the child's own animation — the
 *  viewport just wraps it each frame instead of chasing a moving target with a lagging transition
 *  (the bounce). */
export const viewportAnimated = style({
  transition: `width ${duration.base} ${easing.standard}`
})

/** Navigation window only: height joins the ease so a slot-flip resizes in lockstep with the slide.
 *  Defined after `viewportAnimated` so, applied together, its width+height transition wins the tie. */
export const viewportNav = style({
  transition: `width ${duration.base} ${easing.standard}, height ${duration.base} ${easing.standard}`
})

/** Slots laid out left-to-right at their own size; top-aligned so each keeps its own height (not the taller one's). */
export const track = style({ display: 'flex', alignItems: 'flex-start' })
export const trackAnimated = style({ transition: `transform ${duration.base} ${easing.standard}` })

/** Each slot shrink-wraps its content (a column whose rows/dividers stretch to the widest row). */
export const slot = style({ flex: '0 0 auto', display: 'flex', flexDirection: 'column' })

/** The measured content box — the ResizeObserver watches this, so the min floors ride it (never the
 *  slot), and a slot's own MenuScrollFrame caps/scrolls within it. */
export const slotContent = style({ flex: '0 0 auto', display: 'flex', flexDirection: 'column' })
