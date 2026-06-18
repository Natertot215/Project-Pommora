import { GlassSurface } from '@renderer/design-system/materials'
import { Icon } from '@renderer/design-system/symbols'
import { NavSections } from './NavSections'

// The showcase navigation — a visual mirror of the app's glass sidebar (shared
// GlassSurface material + the same section-header / selectable-row language). The
// nav rows themselves come from NavSections (shared with the mobile dropdown).
export function ShowcaseSidebar({
  activeId,
  onSelect,
  onCollapse
}: {
  activeId: string
  onSelect: (id: string) => void
  onCollapse: () => void
}): React.JSX.Element {
  return (
    <GlassSurface className="sc-sidebar">
      <div className="sc-sidebar-head">
        <span className="sc-brand">Pommora</span>
        <button type="button" className="sc-icon-btn" title="Collapse sidebar" aria-label="Collapse sidebar" onClick={onCollapse}>
          <Icon name="log-out" size={16} className="flip-x" />
        </button>
      </div>
      <nav className="sc-nav">
        <NavSections activeId={activeId} onSelect={onSelect} />
      </nav>
    </GlassSurface>
  )
}
