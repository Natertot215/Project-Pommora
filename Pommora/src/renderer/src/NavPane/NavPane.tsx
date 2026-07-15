import { useEffect, useMemo, useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent } from 'react'
import { GlassWindow } from '@renderer/design-system/materials'
import { Icon } from '@renderer/design-system/symbols'
import type { NavTarget } from '@shared/types'
import { useExitPresence } from '../design-system/useExitPresence'
import { useSession, type SelectTarget } from '../store'
import { buildResolveIndex, resolveFavorites, resolveRecents, resolveWith, type ResolvedNav } from '../Navigation/navResolve'
import { buildNavIndex, filterNav } from '../Navigation/navSearch'
import { navKey } from '../Navigation/navRecents'
import './navpane.css'

const WIN = { minW: 360, minH: 280, defW: 640, defH: 460 }
const RAIL = { min: 120, def: 200, max: 320 }

// Module-scope so geometry survives the useExitPresence unmount (reopen restores last position/size).
const geo = { x: null as number | null, y: null as number | null, w: WIN.defW, h: WIN.defH, rail: RAIL.def }

const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v))
// Agenda kinds (task/event) route nowhere until Agenda ships (E-9b) — search-listable, not selectable.
const isTreeTarget = (t: NavTarget): t is SelectTarget => t.kind !== 'task' && t.kind !== 'event'

export function NavPane(): React.JSX.Element | null {
  const navOpen = useSession((s) => s.navOpen)
  const { mounted, closing } = useExitPresence(navOpen)
  if (!mounted) return null
  return <NavPaneBody closing={closing} />
}

function NavPaneBody({ closing }: { closing: boolean }): React.JSX.Element {
  const tree = useSession((s) => s.tree)
  const recents = useSession((s) => s.recents)
  const favorites = useSession((s) => s.favorites)
  const agenda = useSession((s) => s.agendaSnapshot)
  const select = useSession((s) => s.select)
  const closeNav = useSession((s) => s.closeNav)
  const togglePin = useSession((s) => s.togglePin)
  const addFavorite = useSession((s) => s.addFavorite)
  const removeFavorite = useSession((s) => s.removeFavorite)

  const [query, setQuery] = useState('')
  const [, force] = useState(0) // re-render on geometry mutation (geo is a module ref)
  const searchRef = useRef<HTMLInputElement>(null)

  // Center on first-ever open, then persist wherever the user drags it.
  useEffect(() => {
    if (geo.x === null || geo.y === null) {
      geo.x = Math.max(0, Math.round((window.innerWidth - geo.w) / 2))
      geo.y = Math.max(0, Math.round((window.innerHeight - geo.h) / 3))
      force((n) => n + 1)
    }
    searchRef.current?.focus()
  }, [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') closeNav()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [closeNav])

  const favoriteKeys = useMemo(() => new Set(favorites.map(navKey)), [favorites])
  const resolvedRecents = useMemo(() => (tree ? resolveRecents(tree, recents) : []), [tree, recents])
  const resolvedFavorites = useMemo(() => (tree ? resolveFavorites(tree, favorites) : []), [tree, favorites])
  const results = useMemo(() => {
    if (!tree || !query.trim()) return null
    const index = buildNavIndex(tree, agenda ?? undefined)
    const resolveIx = buildResolveIndex(tree)
    return filterNav(index, query).map((e) => ({ entry: e, resolved: resolveWith(resolveIx, e.target) }))
  }, [tree, agenda, query])

  const go = (target: NavTarget): void => {
    if (!isTreeTarget(target)) return
    void select(target)
    closeNav()
  }

  const startDrag = (mode: 'move' | 'se' | 'rail', e: ReactPointerEvent): void => {
    e.preventDefault()
    const s = { x: e.clientX, y: e.clientY, gx: geo.x ?? 0, gy: geo.y ?? 0, gw: geo.w, gh: geo.h, rail: geo.rail }
    const move = (ev: PointerEvent): void => {
      const dx = ev.clientX - s.x
      const dy = ev.clientY - s.y
      if (mode === 'move') {
        geo.x = clamp(s.gx + dx, 0, window.innerWidth - 80)
        geo.y = clamp(s.gy + dy, 0, window.innerHeight - 40)
      } else if (mode === 'se') {
        geo.w = clamp(s.gw + dx, WIN.minW, window.innerWidth)
        geo.h = clamp(s.gh + dy, WIN.minH, window.innerHeight)
      } else {
        geo.rail = clamp(s.rail + dx, RAIL.min, RAIL.max)
      }
      force((n) => n + 1)
    }
    const up = (): void => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
    }
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
  }
  // Move from bare chrome only — presses on a control keep it interactive.
  const onWindowDown = (e: ReactPointerEvent): void => {
    if ((e.target as HTMLElement).closest('button, input, .navpane-rail-resize, .navpane-resize-se')) return
    startDrag('move', e)
  }

  const style = { left: geo.x ?? 0, top: geo.y ?? 0, width: geo.w, height: geo.h, '--navpane-rail': `${geo.rail}px` } as CSSProperties

  return (
    <GlassWindow className={`navpane${closing ? ' closing' : ''}`} style={style} role="dialog" aria-label="Navigation" onPointerDown={onWindowDown}>
      <GlassWindow className="navpane-rail">
        <NavList items={resolvedFavorites} onSelect={go} onRemoveFavorite={(k) => removeFavorite(k)} />
      </GlassWindow>
      <div className="navpane-rail-resize" onPointerDown={(e) => startDrag('rail', e)} role="separator" aria-orientation="vertical" aria-label="Resize favorites" />
      <div className="navpane-main">
        <div className="navpane-search">
          <Icon name="search" size={14} />
          <input ref={searchRef} value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search…" spellCheck={false} />
        </div>
        <div className="navpane-main-scroll">
          {results ? (
            <NavList
              items={results.map((r) => r.resolved).filter((r): r is ResolvedNav => r !== null)}
              extras={results.filter((r) => r.resolved === null).map((r) => ({ key: r.entry.key, title: r.entry.title, kind: r.entry.target.kind }))}
              onSelect={go}
            />
          ) : (
            <NavList
              items={resolvedRecents}
              onSelect={go}
              onTogglePin={(k) => togglePin(k)}
              onToggleFavorite={(t) => (favoriteKeys.has(navKey(t)) ? removeFavorite(navKey(t)) : addFavorite(t))}
              favoriteKeys={favoriteKeys}
            />
          )}
        </div>
      </div>
      <div className="navpane-resize-se" onPointerDown={(e) => startDrag('se', e)} aria-label="Resize" />
    </GlassWindow>
  )
}

// A flat functional list of resolved entries — the STUB rendering; the Figma gallery replaces it.
function NavList({
  items,
  extras,
  onSelect,
  onTogglePin,
  onToggleFavorite,
  onRemoveFavorite,
  favoriteKeys
}: {
  items: ResolvedNav[]
  extras?: { key: string; title: string; kind: string }[]
  onSelect: (target: NavTarget) => void
  onTogglePin?: (key: string) => void
  onToggleFavorite?: (target: NavTarget) => void
  onRemoveFavorite?: (key: string) => void
  favoriteKeys?: Set<string>
}): React.JSX.Element {
  if (items.length === 0 && !extras?.length) return <div className="navpane-empty">Nothing here yet</div>
  return (
    <ul className="navpane-list">
      {items.map((it) => (
        <li key={it.key} className="navpane-item">
          <button type="button" className="navpane-item-main" onClick={() => onSelect(it.target)}>
            <span className="navpane-item-title">
              {it.pinned && <Icon name="pin" size={11} />}
              {it.title}
            </span>
            {it.location && <span className="navpane-item-loc">{it.location}</span>}
          </button>
          {onTogglePin && (
            <button type="button" className="navpane-item-act" aria-label="Pin" onClick={() => onTogglePin(it.key)}>
              <Icon name="pin" size={12} />
            </button>
          )}
          {onToggleFavorite && (
            <button type="button" className="navpane-item-act" aria-label="Favorite" onClick={() => onToggleFavorite(it.target)}>
              <Icon name={favoriteKeys?.has(it.key) ? 'star' : 'star-off'} size={12} />
            </button>
          )}
          {onRemoveFavorite && (
            <button type="button" className="navpane-item-act" aria-label="Remove favorite" onClick={() => onRemoveFavorite(it.key)}>
              <Icon name="x" size={12} />
            </button>
          )}
        </li>
      ))}
      {extras?.map((e) => (
        <li key={e.key} className="navpane-item navpane-item-inert" title="Agenda navigation isn't wired yet">
          <span className="navpane-item-title">{e.title}</span>
          <span className="navpane-item-loc">{e.kind}</span>
        </li>
      ))}
    </ul>
  )
}
