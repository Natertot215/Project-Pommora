import type { HTMLAttributes, ReactNode } from 'react'
import { glassMaterial } from './glass-material'

/**
 * GlassSurface — Pommora's glass material for **surfaces** (sidebar, panels,
 * popovers). Spreads the shared `glassMaterial` (liquidGL "Tinted Lens" at zero
 * tint: blur 5 + brightness 90%, faint edge, top specular, soft shadow).
 *
 * Its own component so surface glass can diverge from control glass later (just
 * override props after the spread). Layout (size / position / radius) is the
 * consumer's job — pass it via `style` or `className`.
 */
export function GlassSurface({
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
