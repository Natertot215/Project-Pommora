import { Icon } from '@renderer/design-system/symbols'
import type { NavTarget } from '@shared/types'
import type { ResolvedNav } from './navResolve'
import './navList.css'

// The stub row list both NavPane + NavMenu render — resolved entries with per-row pin/favorite/remove
// affordances. Surface-agnostic (no window/rail chrome). The Figma gallery replaces the NavPane form.
export function NavList({
  items,
  extras,
  onSelect,
  onTogglePin,
  onToggleFavorite,
  onRemoveFavorite,
  favoriteKeys,
  empty = 'Nothing here yet'
}: {
  items: ResolvedNav[]
  /** Unresolvable hits (agenda kinds) — listed inert until Agenda routing ships. */
  extras?: { key: string; title: string; kind: string }[]
  onSelect: (target: NavTarget) => void
  onTogglePin?: (key: string) => void
  onToggleFavorite?: (target: NavTarget) => void
  onRemoveFavorite?: (key: string) => void
  favoriteKeys?: Set<string>
  empty?: string
}): React.JSX.Element {
  if (items.length === 0 && !extras?.length) return <div className="nav-empty">{empty}</div>
  return (
    <ul className="nav-list">
      {items.map((it) => (
        <li key={it.key} className="nav-item">
          <button type="button" className="nav-item-main" onClick={() => onSelect(it.target)}>
            <span className="nav-item-title">
              {it.pinned && <Icon name="pin" size={11} />}
              {it.title}
            </span>
            {it.location && <span className="nav-item-loc">{it.location}</span>}
          </button>
          {onTogglePin && (
            <button type="button" className="nav-item-act" aria-label="Pin" onClick={() => onTogglePin(it.key)}>
              <Icon name="pin" size={12} />
            </button>
          )}
          {onToggleFavorite && (
            <button type="button" className="nav-item-act" aria-label="Favorite" onClick={() => onToggleFavorite(it.target)}>
              <Icon name={favoriteKeys?.has(it.key) ? 'star' : 'star-off'} size={12} />
            </button>
          )}
          {onRemoveFavorite && (
            <button type="button" className="nav-item-act" aria-label="Remove favorite" onClick={() => onRemoveFavorite(it.key)}>
              <Icon name="x" size={12} />
            </button>
          )}
        </li>
      ))}
      {extras?.map((e) => (
        <li key={e.key} className="nav-item nav-item-inert" title="Agenda navigation isn't wired yet">
          <span className="nav-item-title">{e.title}</span>
          <span className="nav-item-loc">{e.kind}</span>
        </li>
      ))}
    </ul>
  )
}
