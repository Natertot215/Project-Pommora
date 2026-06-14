import type { ReactNode } from 'react'

// The swappable glass seam. Phase 1: the sidebar is a glass panel with NO fill —
// it's a rounded "hole" (inset 2px, 26px radius) revealing the native macOS
// window vibrancy, while a large spread box-shadow paints the #1C1C1F frame
// around it (see `.sidebar-col` / `.surface-glass`). liquid-glass-react (shader
// refraction) is reserved for floating chrome where its content-sized model fits.
export function Surface({ children }: { children: ReactNode }): React.JSX.Element {
  return (
    <div className="sidebar-col">
      <div className="surface-glass">{children}</div>
    </div>
  )
}
