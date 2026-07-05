import { style } from '@vanilla-extract/css'
import { duration, easing } from '../../design-system/tokens/motion'

/** Clips the off-screen slot so the sliding panes stay inside the glass bounds. */
export const viewport = style({ position: 'relative', overflow: 'hidden' })

/** Width + height + slide share one duration/easing so the resize and the horizontal move stay locked. */
export const viewportAnimated = style({
  transition: `width ${duration.base} ${easing.standard}, height ${duration.base} ${easing.standard}`
})

/** Slots laid out left-to-right at their own size; top-aligned so each keeps its own height (not the taller one's). */
export const track = style({ display: 'flex', alignItems: 'flex-start' })
export const trackAnimated = style({ transition: `transform ${duration.base} ${easing.standard}` })

/** Each slot shrink-wraps its content (a column whose rows/dividers stretch to the widest row). */
export const slot = style({ flex: '0 0 auto', display: 'flex', flexDirection: 'column' })

/** A capped slot scrolls internally under the shared edge fade; the ResizeObserver measures the
 *  inner slotContent, so the cap never feeds back into the animated viewport height. */
export const slotScrollable = style({ overflowY: 'auto' })
export const slotContent = style({ flex: '0 0 auto', display: 'flex', flexDirection: 'column' })
