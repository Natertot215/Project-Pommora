import type { HTMLAttributes, ReactNode } from 'react'
import { frostMaterial } from './glass-material'

/**
 * GlassSurface — Pommora's glass for **surfaces** (sidebar, panels, popovers).
 * Spreads the shared CSS frost material. Its own component so surface glass can
 * diverge from control glass later (override props after the spread). Layout
 * (size / position / radius) is the consumer's job via style/className.
 */
export function GlassSurface({
  children,
  style,
  ...rest
}: { children?: ReactNode } & HTMLAttributes<HTMLDivElement>): React.JSX.Element {
  return (
    <div style={{ ...frostMaterial, ...style }} {...rest}>
      {children}
    </div>
  )
}
