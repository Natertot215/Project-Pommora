import type { HTMLAttributes, ReactNode } from 'react'
import { frostMaterial } from './glass-material'

/**
 * GlassControls — Pommora's glass for **controls** (buttons, toolbars, segmented
 * controls). Shares the same CSS frost material as GlassSurface for now; kept its
 * own component so control glass can pick up a tighter treatment later without
 * touching surfaces. Layout is the consumer's job via style/className.
 */
export function GlassControls({
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
