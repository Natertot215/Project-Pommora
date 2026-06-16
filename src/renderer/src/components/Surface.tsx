import type { ReactNode } from 'react'
import { GlassSurface } from '@renderer/design-system/materials/glass-surface'

// The sidebar's glass seam. Phase 1: a floating glass overlay on top of the
// main view (z-index), so its backdrop-filter samples the app content — never
// the desktop. The glass *material* now lives in GlassSurface (design-system/
// materials); `.surface-glass` is just the sidebar's layout (position + size).
export function Surface({ children }: { children: ReactNode }): React.JSX.Element {
  return <GlassSurface className="surface-glass">{children}</GlassSurface>
}
