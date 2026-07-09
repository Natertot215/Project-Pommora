import type { SidebarMode } from '@shared/types'
import { Icon, defaultEntityIcon } from '@renderer/design-system/symbols'
import { reorder, SortableZone, useDragItem } from '@renderer/design-system/interactions/drag'
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

  // Drag-to-order the launcher icons (Homepage stays pinned, outside the zone). The reordered keys
  // persist to ribbonOrder; the id-wrap mirrors the shared reorder helper's object contract.
  const reorderIcons = (activeId: string, overId: string): void => {
    const next = reorder(keys.map((id) => ({ id })), activeId, overId).map((x) => x.id)
    setPersonalization('ribbonOrder', next)
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
      <SortableZone items={keys} layout="list" axis="y" onReorder={reorderIcons}>
        {keys.map((k) => (
          <RibbonTab key={k} tabKey={k} icon={iconFor(k)} active={MODE_FOR[k] != null && MODE_FOR[k] === mode} onClick={() => onIcon(k)} />
        ))}
      </SortableZone>
    </div>
  )
}

function RibbonTab({
  tabKey,
  icon,
  active,
  onClick
}: {
  tabKey: RibbonKey
  icon: string
  active: boolean
  onClick: () => void
}): React.JSX.Element {
  const { setNodeRef, style, handle } = useDragItem(tabKey)
  return (
    <button
      ref={setNodeRef}
      style={style}
      {...handle}
      type="button"
      className="ribbon-icon"
      aria-label={tabKey}
      aria-selected={active}
      onClick={onClick}
    >
      <Icon name={icon} size={18} />
    </button>
  )
}
