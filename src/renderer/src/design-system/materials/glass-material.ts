import type { CSSProperties } from 'react'

/**
 * The shared Pommora glass recipe — liquidGL "Tinted Lens" at zero tint: a clear,
 * slightly-darkened frost (blur 5 + brightness 90%) with a faint edge, a top
 * specular, and a soft drop shadow. `GlassSurface` and `GlassControls` both
 * spread this (one source); either can override individual props later to diverge.
 */
export const glassMaterial: CSSProperties = {
  background: 'transparent',
  backdropFilter: 'blur(5px) brightness(90%)',
  WebkitBackdropFilter: 'blur(5px) brightness(90%)',
  border: '1px solid rgba(255, 255, 255, 0.16)',
  boxShadow: 'inset 0 1px 0 rgba(255, 255, 255, 0.25), 0 8px 26px rgba(0, 0, 0, 0.28)'
}
