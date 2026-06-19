import { useState, useLayoutEffect, type ReactNode, type CSSProperties } from 'react'
import { duration, easing } from '../tokens/motion'

// The container animates its row from 0 to the content's natural height; the inner
// clips while collapsed. Shares the fast/standard motion with the disclosure chevron.
const outer: CSSProperties = {
  display: 'grid',
  transition: `grid-template-rows ${duration.fast} ${easing.standard}`
}
const inner: CSSProperties = { overflow: 'hidden', minHeight: 0 }

/**
 * Reveal — animated open/close. The content grows from 0 to its natural height
 * (`grid-template-rows: 0fr → 1fr`) on the shared motion, in sync with the disclosure
 * chevron. Children mount on open and unmount once the collapse finishes, so closed
 * subtrees stay out of the DOM (no regression to the sidebar's lazy rendering).
 */
export function Reveal({ open, children }: { open: boolean; children: ReactNode }): React.JSX.Element {
  const [mounted, setMounted] = useState(open)
  const [expanded, setExpanded] = useState(open)

  useLayoutEffect(() => {
    if (open) {
      setMounted(true) // mount at 0fr…
      const id = requestAnimationFrame(() => setExpanded(true)) // …then grow next frame so it animates
      return () => cancelAnimationFrame(id)
    }
    setExpanded(false) // collapse; unmount once the row transition lands
    return undefined
  }, [open])

  return (
    <div
      style={{ ...outer, gridTemplateRows: expanded ? '1fr' : '0fr' }}
      onTransitionEnd={(e) => {
        if (e.propertyName === 'grid-template-rows' && !open) setMounted(false)
      }}
    >
      <div style={inner}>{mounted ? children : null}</div>
    </div>
  )
}
