import type { CSSProperties, HTMLAttributes, ReactNode } from 'react'

/**
 * GlassSurface — Pommora's glass material for **surfaces** (sidebar, panels,
 * popovers). liquidGL "Tinted Lens" at zero tint: a clear, slightly-darkened
 * frost (blur 5 + brightness 90%) with a faint edge, a top specular, and a soft
 * drop shadow. Chosen in the glass lab.
 *
 * Self-contained on purpose — `GlassControls` is an identical copy for now, so
 * surface vs control glass can diverge later without untangling a shared base.
 * Layout (size / position / radius) is the consumer's job; pass it via `style`
 * or `className` (e.g. the sidebar's `.surface-glass`).
 */
const surfaceMaterial: CSSProperties = {
  background: 'transparent',
  backdropFilter: 'blur(5px) brightness(90%)',
  WebkitBackdropFilter: 'blur(5px) brightness(90%)',
  border: '1px solid rgba(255, 255, 255, 0.16)',
  boxShadow: 'inset 0 1px 0 rgba(255, 255, 255, 0.25), 0 8px 26px rgba(0, 0, 0, 0.28)'
}

export function GlassSurface({
  children,
  style,
  ...rest
}: { children?: ReactNode } & HTMLAttributes<HTMLDivElement>): React.JSX.Element {
  return (
    <div style={{ ...surfaceMaterial, ...style }} {...rest}>
      {children}
    </div>
  )
}
