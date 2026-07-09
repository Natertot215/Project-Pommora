import type { SidebarMode } from '@shared/types'
import { Icon, defaultEntityIcon } from '@renderer/design-system/symbols'
import { useSession } from '../store'
import { NexusPhoto } from './NexusPhoto'
import './Sidebar.css'

// The ribbon's launcher icons below the pinned Homepage. Three switch sidebarMode (the content
// column); navigation/settings are placeholders for future glass-window surfaces (no-op for now).
type RibbonKey = 'navigation' | 'agenda' | 'contexts' | 'collections' | 'settings'
const MODE_FOR: Partial<Record<RibbonKey, SidebarMode>> = {
  collections: 'collections',
  contexts: 'contexts',
  agenda: 'agenda'
}
// The mode icons reuse the entity defaults (a Collection's icon is a Collection's icon), so they
// track any personalization override; agenda/nav/settings have no entity kind and stay literal.
const STATIC_ICON: Record<'agenda' | 'navigation' | 'settings', string> = {
  agenda: 'calendar',
  navigation: 'map',
  settings: 'sliders-horizontal'
}
const DEFAULT_ORDER: RibbonKey[] = ['navigation', 'agenda', 'contexts', 'collections', 'settings']

/** Resolve the display order from a persisted (possibly partial or stale) ribbonOrder, always
 *  ending with every known key so a newly-added icon never vanishes. */
function resolveOrder(persisted: string[] | undefined): RibbonKey[] {
  const known = new Set<string>(DEFAULT_ORDER)
  const keys = (persisted ?? []).filter((k): k is RibbonKey => known.has(k))
  for (const k of DEFAULT_ORDER) if (!keys.includes(k)) keys.push(k)
  return keys
}

export function Ribbon(): React.JSX.Element {
  const select = useSession((s) => s.select)
  const mode = useSession((s) => s.personalization.sidebarMode ?? 'collections')
  const order = useSession((s) => s.personalization.ribbonOrder)
  const defaultIcons = useSession((s) => s.personalization.defaultIcons)
  const setPersonalization = useSession((s) => s.setPersonalization)
  const keys = resolveOrder(order)

  const iconFor = (k: RibbonKey): string =>
    k === 'collections'
      ? defaultEntityIcon('collection', defaultIcons)
      : k === 'contexts'
        ? defaultEntityIcon('area', defaultIcons)
        : STATIC_ICON[k]

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
            <Icon name={iconFor(k)} size={18} />
          </button>
        )
      })}
    </div>
  )
}
