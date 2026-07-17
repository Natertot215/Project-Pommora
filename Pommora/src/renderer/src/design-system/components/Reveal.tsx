import { useState, useLayoutEffect, type ReactNode } from 'react'
import { duration as motionDuration, easing } from '../tokens/motion'

/**
 * Reveal — animated open/close. The content grows from 0 to its natural height
 * (`grid-template-rows: 0fr → 1fr`) on the shared motion, in sync with the disclosure
 * chevron. Children mount on open and unmount once the collapse finishes, so closed
 * subtrees stay out of the DOM (no regression to the sidebar's lazy rendering).
 * `duration` overrides the default disclosure beat — a Reveal inside a PaneSlider pins
 * to the pane's beat so the unfold and the height-resize land together (E-8).
 *
 * The inner clips only while animating/collapsed — once fully open and idle it stops
 * clipping so affordances that overhang the row (the table's gutter drag grips) aren't
 * cut off.
 *
 * `fill` constrains the implicit grid column to `minmax(0, 1fr)` so the content is capped at
 * the container's width (rows shrink + ellipsize). Without it the single grid column defaults
 * to `auto` (max-content), which a `nowrap` title balloons to its full length — right for the
 * table (content-width rows behind its own horizontal scroll), wrong for the fixed-width sidebar.
 */
export function Reveal({
  open,
  fill = false,
  duration = motionDuration.disclosure,
  children,
}: {
  open: boolean
  fill?: boolean
  duration?: string
  children: ReactNode
}): React.JSX.Element {
  const [mounted, setMounted] = useState(open)
  const [expanded, setExpanded] = useState(open)
  const [settled, setSettled] = useState(open)

  useLayoutEffect(() => {
    if (open) {
      setMounted(true) // mount at 0fr…
      const id = requestAnimationFrame(() => setExpanded(true)) // …then grow next frame so it animates
      return () => cancelAnimationFrame(id)
    }
    setExpanded(false) // collapse; unmount once the row transition lands
    setSettled(false) // clip again for the collapse
    return undefined
  }, [open])

  return (
    <div
      style={{
        display: 'grid',
        transition: `grid-template-rows ${duration} ${easing.standard}`,
        gridTemplateRows: expanded ? '1fr' : '0fr',
        gridTemplateColumns: fill ? 'minmax(0, 1fr)' : undefined,
      }}
      onTransitionEnd={(e) => {
        if (e.propertyName !== 'grid-template-rows') return
        if (open)
          setSettled(true) // open animation done → stop clipping
        else setMounted(false) // collapse done → unmount
      }}
    >
      <div style={{ overflow: settled ? 'visible' : 'hidden', minHeight: 0 }}>
        {mounted ? children : null}
      </div>
    </div>
  )
}
