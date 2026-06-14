import type { ReactNode } from 'react'

// The ONE swappable glass seam. Every chrome surface routes through here so the
// material is a single swap-point (not scattered CSS).
//
// Phase 1 — the sidebar PANE is a full-height edge-to-edge surface, so it uses
// the native macOS window vibrancy ('sidebar', set on the BrowserWindow) layered
// with a CSS backdrop-filter glass (see `.surface-glass`). `liquid-glass-react`
// (shader refraction) is content-sized / centered / drop-shadowed — built for
// FLOATING chrome (toolbar pills, popovers, selection capsule) — so it's reserved
// for those, not the pane. Swapping the material later = editing only this file.
export function Surface({
  className,
  children
}: {
  className?: string
  children: ReactNode
}): React.JSX.Element {
  return <div className={`surface-glass ${className ?? ''}`}>{children}</div>
}
