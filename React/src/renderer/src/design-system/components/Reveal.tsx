import { useState, useLayoutEffect, type ReactNode, type CSSProperties } from 'react'
import { duration, easing } from '../tokens/motion'

// The container animates its row from 0 to the content's natural height; the inner
// clips while collapsed. Shares the disclosure motion with the chevron (the twisty).
const outer: CSSProperties = {
  display: 'grid',
  transition: `grid-template-rows ${duration.disclosure} ${easing.standard}`
}

/**
 * Reveal — animated open/close. The content grows from 0 to its natural height
 * (`grid-template-rows: 0fr → 1fr`) on the shared motion, in sync with the disclosure
 * chevron. Children mount on open and unmount once the collapse finishes, so closed
 * subtrees stay out of the DOM (no regression to the sidebar's lazy rendering).
 *
 * The inner clips only while animating/collapsed — once fully open and idle it stops
 * clipping so affordances that overhang the row (the table's gutter drag grips) aren't
 * cut off.
 */
export function Reveal({ open, children }: { open: boolean; children: ReactNode }): React.JSX.Element {
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
      style={{ ...outer, gridTemplateRows: expanded ? '1fr' : '0fr' }}
      onTransitionEnd={(e) => {
        if (e.propertyName !== 'grid-template-rows') return
        if (open) setSettled(true) // open animation done → stop clipping
        else setMounted(false) // collapse done → unmount
      }}
    >
      <div style={{ overflow: settled ? 'visible' : 'hidden', minHeight: 0 }}>{mounted ? children : null}</div>
    </div>
  )
}
