import type { CSSProperties, HTMLAttributes, ReactNode } from 'react'

/**
 * GlassControls — Pommora's glass material for **controls** (buttons, toolbars,
 * segmented controls). Identical to `GlassSurface` for now (liquidGL "Tinted
 * Lens" at zero tint: blur 5 + brightness 90%, faint edge, top specular, soft
 * shadow).
 *
 * Kept as its own full component so control glass can pick up its own treatment
 * later (tighter blur, stronger edge, etc.) without touching surface glass.
 */
const controlMaterial: CSSProperties = {
  background: 'transparent',
  backdropFilter: 'blur(5px) brightness(90%)',
  WebkitBackdropFilter: 'blur(5px) brightness(90%)',
  border: '1px solid rgba(255, 255, 255, 0.16)',
  boxShadow: 'inset 0 1px 0 rgba(255, 255, 255, 0.25), 0 8px 26px rgba(0, 0, 0, 0.28)'
}

export function GlassControls({
  children,
  style,
  ...rest
}: { children?: ReactNode } & HTMLAttributes<HTMLDivElement>): React.JSX.Element {
  return (
    <div style={{ ...controlMaterial, ...style }} {...rest}>
      {children}
    </div>
  )
}
