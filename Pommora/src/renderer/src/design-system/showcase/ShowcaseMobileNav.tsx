import { useState } from 'react'
import { frostMaterial } from '@renderer/design-system/materials'
import { Icon } from '@renderer/design-system/symbols'
import { leafById } from './leaves/registry'
import { NavSections } from './NavSections'

// Mobile navigation — a top-right glass button that drops the same registry leaves
// (via NavSections). CSS hides this above the breakpoint and hides the sidebar below
// it, so the two never show at once. Glass comes from the shared frost material.
export function ShowcaseMobileNav({
  activeId,
  onSelect,
}: {
  activeId: string
  onSelect: (id: string) => void
}): React.JSX.Element {
  const [open, setOpen] = useState(false)
  const active = leafById(activeId)
  const choose = (id: string): void => {
    onSelect(id)
    setOpen(false)
  }
  return (
    <div className="sc-mobile">
      <button
        type="button"
        className="sc-mobile-trigger"
        style={frostMaterial}
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
      >
        <Icon name={active.icon} size={15} />
        <span className="sc-mobile-active">{active.label}</span>
        <Icon name={open ? 'chevron-up' : 'chevron-down'} size={15} />
      </button>
      {open && (
        <div className="sc-mobile-menu" style={frostMaterial}>
          <NavSections activeId={activeId} onSelect={choose} />
        </div>
      )}
    </div>
  )
}
