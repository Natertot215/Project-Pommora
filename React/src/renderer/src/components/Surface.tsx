import type { ReactNode } from 'react'
import { GlassWindow } from '@renderer/design-system/materials'

// The sidebar's glass seam. A floating glass overlay on top of the main view
// (z-index), so its backdrop-filter samples the app content — never the desktop.
// The sidebar attaches to the **window**-tier glass (GlassWindow) — the app's
// largest, backmost glass; `.surface-glass` is just the sidebar's layout
// (position + size).
export function Surface({ children }: { children: ReactNode }): React.JSX.Element {
  return <GlassWindow className="surface-glass">{children}</GlassWindow>
}
