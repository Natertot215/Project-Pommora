import type { HTMLAttributes, ReactNode } from 'react'
import { Glass, type GlassOptics } from '@samasante/liquid-glass'

/**
 * GlassControls — Pommora's glass for **controls** (toolbars, segmented controls,
 * the autocomplete panel). Apple "Liquid Glass" via @samasante/liquid-glass: real
 * edge refraction over the live app, not a flat frost. Layout (size / position /
 * radius) is the consumer's job via style/className; CONTROL_OPTICS is the tuned
 * control look. Note: Glass forces `display:inline-block` inline, so a flex
 * consumer must re-assert `display:flex` in its own inline style.
 */
const CONTROL_OPTICS: Partial<GlassOptics> = {
  strength: 0.5,
  depth: 0.3,
  curvature: 0.45,
  bend: 0.25,
  bendWidth: 0.16,
  dispersion: 0.25,
  frost: 3.5,
  saturate: 1,
  brightness: -0.05,
  specular: 0.7,
  glow: 0,
  glowSpread: 0.3,
  glowFalloff: 1.5,
  sheen: 0.3,
  sheenWidth: 12,
  sheenFalloff: 1.5,
  sheenAngle: 90,
  splay: 0,
  mapSize: 256,
  clipToShape: true,
  softEdge: true,
  sheenDark: false
}

export function GlassControls({
  children,
  style,
  ...rest
}: { children?: ReactNode } & HTMLAttributes<HTMLDivElement>): React.JSX.Element {
  const r = style?.borderRadius
  return (
    <Glass optics={CONTROL_OPTICS} radius={typeof r === 'number' ? r : undefined} style={style} {...rest}>
      {children}
    </Glass>
  )
}
