import { Icon } from '@renderer/design-system/symbols'
import { SECTIONS, LEAVES } from './leaves/registry'

// The grouped, selectable nav rows — shared by the sidebar and the mobile dropdown
// (one rendering, two surfaces). Derives entirely from the leaf registry.
export function NavSections({
  activeId,
  onSelect
}: {
  activeId: string
  onSelect: (id: string) => void
}): React.JSX.Element {
  return (
    <>
      {SECTIONS.map((sec) => {
        const leaves = LEAVES.filter((l) => l.section === sec.id)
        if (leaves.length === 0) return null
        return (
          <div className="sc-section" key={sec.id}>
            <div className="sc-section-header">{sec.label}</div>
            {leaves.map((l) => (
              <button
                key={l.id}
                type="button"
                className={'sc-row' + (l.id === activeId ? ' selected' : '')}
                onClick={() => onSelect(l.id)}
              >
                <Icon name={l.icon} size={15} className="sc-row-icon" />
                <span className="sc-row-title">{l.label}</span>
              </button>
            ))}
          </div>
        )
      })}
    </>
  )
}
