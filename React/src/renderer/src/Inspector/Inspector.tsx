import { GlassSurface } from '@renderer/design-system/materials'
import './inspector.css'

/**
 * The trailing window pane (Swift's `.inspector`) — the structural twin of the
 * leading Sidebar. Empty placeholder this pass: it slides in from the right edge
 * when toggled; content (frontmatter → properties → page info) lands later.
 */
export function Inspector({ open }: { open: boolean }): React.JSX.Element {
  return (
    <aside className={open ? 'inspector open' : 'inspector'} aria-hidden={!open}>
      <GlassSurface className="inspector-panel" />
    </aside>
  )
}
