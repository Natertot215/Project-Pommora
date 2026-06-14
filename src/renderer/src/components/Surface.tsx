import type { ReactNode } from 'react'

// The swappable glass seam. Phase 1: the sidebar is a floating glass overlay
// that sits ON TOP of the main view (z-index), so its backdrop-filter samples
// the app content behind it — never the desktop. No fill; inset + radius are
// CSS variables (see `.surface-glass`). liquid-glass-react (shader refraction)
// is reserved for floating chrome where its content-sized model fits.
export function Surface({ children }: { children: ReactNode }): React.JSX.Element {
  return <div className="surface-glass">{children}</div>
}
