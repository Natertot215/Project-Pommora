import type { HTMLAttributes, ReactNode } from 'react'
import { glassMaterial } from './glass-material'

/**
 * GlassControls — Pommora's glass material for **controls** (buttons, toolbars,
 * segmented controls). Spreads the same shared `glassMaterial` as GlassSurface
 * for now; kept as its own component so control glass can pick up a tighter
 * treatment later (override props after the spread) without touching surfaces.
 */
export function GlassControls({
  children,
  style,
  ...rest
}: { children?: ReactNode } & HTMLAttributes<HTMLDivElement>): React.JSX.Element {
  return (
    <div style={{ ...glassMaterial, ...style }} {...rest}>
      {children}
    </div>
  )
}
