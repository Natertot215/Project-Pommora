import type { SidebarMode } from '@shared/types'
import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../store'
import { NexusPhoto } from './NexusPhoto'
import './Sidebar.css'

// The ribbon's launcher icons below the pinned Homepage. Three switch sidebarMode (the content
// column); navigation/settings are placeholders for future glass-window surfaces (no-op for now).
type RibbonKey = 'collections' | 'contexts' | 'agenda' | 'navigation' | 'settings'
const MODE_FOR: Partial<Record<RibbonKey, SidebarMode>> = {
  collections: 'collections',
  contexts: 'contexts',
  agenda: 'agenda'
}
const RIBBON_ICON: Record<RibbonKey, string> = {
  collections: 'folder',
  contexts: 'layout-grid',
  agenda: 'calendar',
  navigation: 'map',
  settings: 'sliders-horizontal'
}
const DEFAULT_ORDER: RibbonKey[] = ['collections', 'contexts', 'agenda', 'navigation', 'settings']

/** Resolve the display order from a persisted (possibly partial or stale) ribbonOrder, always
 *  ending with every known key so a newly-added icon never vanishes. */
function resolveOrder(persisted: string[] | undefined): RibbonKey[] {
  const keys = (persisted ?? []).filter((k): k is RibbonKey => k in RIBBON_ICON)
  for (const k of DEFAULT_ORDER) if (!keys.includes(k)) keys.push(k)
  return keys
}

export function Ribbon(): React.JSX.Element {
  const select = useSession((s) => s.select)
  const mode = useSession((s) => s.personalization.sidebarMode ?? 'collections')
  const order = useSession((s) => s.personalization.ribbonOrder)
  const setPersonalization = useSession((s) => s.setPersonalization)
  const keys = resolveOrder(order)

  const onIcon = (k: RibbonKey): void => {
    const m = MODE_FOR[k]
    if (m) setPersonalization('sidebarMode', m)
    // navigation / settings: future glass windows — no-op for now.
  }

  return (
    <div className="sidebar-ribbon" role="tablist" aria-label="Sidebar sections">
      <button
        type="button"
        className="ribbon-icon ribbon-home"
        aria-label="Homepage"
        onClick={() => void select({ kind: 'homepage' })}
      >
        <NexusPhoto size={24} />
      </button>
      {keys.map((k) => {
        const m = MODE_FOR[k]
        const active = m != null && m === mode
        return (
          <button
            key={k}
            type="button"
            className="ribbon-icon"
            aria-label={k}
            aria-selected={active}
            onClick={() => onIcon(k)}
          >
            <Icon name={RIBBON_ICON[k]} size={18} />
          </button>
        )
      })}
    </div>
  )
}
