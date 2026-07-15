import { useEffect, useMemo, useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent } from 'react'
import { GlassWindow } from '@renderer/design-system/materials'
import { Icon } from '@renderer/design-system/symbols'
import type { NavTarget } from '@shared/types'
import { useExitPresence } from '../design-system/useExitPresence'
import { useSession } from '../store'
import { navKey } from '../Navigation/navRecents'
import { splitSearch, useNavData } from '../Navigation/useNavData'
import { NavList } from '../Navigation/NavList'
import './navpane.css'

const WIN = { minW: 360, minH: 280, defW: 640, defH: 460 }
const RAIL = { min: 120, def: 200, max: 320 }

// Module-scope so geometry survives the useExitPresence unmount (reopen restores last position/size).
const geo = { x: null as number | null, y: null as number | null, w: WIN.defW, h: WIN.defH, rail: RAIL.def }

const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v))

// Keep the (module-persisted) geometry inside the current viewport — on reopen or a window resize
// it could otherwise render off-screen with no grabbable chrome.
function clampGeo(): void {
  geo.w = Math.min(geo.w, window.innerWidth)
  geo.h = Math.min(geo.h, window.innerHeight)
  geo.x = clamp(geo.x ?? 0, 0, Math.max(0, window.innerWidth - 80))
  geo.y = clamp(geo.y ?? 0, 0, Math.max(0, window.innerHeight - 40))
}

export function NavPane(): React.JSX.Element | null {
  const navOpen = useSession((s) => s.navOpen)
  const { mounted, closing } = useExitPresence(navOpen)
  if (!mounted) return null
  return <NavPaneBody closing={closing} />
}

function NavPaneBody({ closing }: { closing: boolean }): React.JSX.Element {
  const { resolvedRecents, resolvedFavorites, search, go } = useNavData()
  const favorites = useSession((s) => s.favorites)
  const closeNav = useSession((s) => s.closeNav)
  const togglePin = useSession((s) => s.togglePin)
  const addFavorite = useSession((s) => s.addFavorite)
  const removeFavorite = useSession((s) => s.removeFavorite)

  const [query, setQuery] = useState('')
  const [, force] = useState(0) // re-render on geometry mutation (geo is a module ref)
  const searchRef = useRef<HTMLInputElement>(null)

  // Center on first-ever open; on later opens just re-clamp into the current viewport. Re-clamp on
  // resize too. H-2: focus the search on open (a command-palette focus, not a modal focus-trap).
  useEffect(() => {
    if (geo.x === null || geo.y === null) {
      geo.w = Math.min(geo.w, window.innerWidth)
      geo.h = Math.min(geo.h, window.innerHeight)
      geo.x = Math.max(0, Math.round((window.innerWidth - geo.w) / 2))
      geo.y = Math.max(0, Math.round((window.innerHeight - geo.h) / 3))
    } else {
      clampGeo()
    }
    force((n) => n + 1)
    searchRef.current?.focus()
    const onResize = (): void => {
      clampGeo()
      force((n) => n + 1)
    }
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [])

  useEffect(() => {
    // Skip an Escape a focused surface already handled (mirrors App.tsx's command handler).
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape' && !e.defaultPrevented) closeNav()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [closeNav])

  const favoriteKeys = useMemo(() => new Set(favorites.map(navKey)), [favorites])
  const results = useMemo(() => (query.trim() ? splitSearch(search(query)) : null), [query, search])
  const goClose = (target: NavTarget): void => go(target, closeNav)

  // Capture the pointer on the pressed element (house pattern) so a drag that releases OUTSIDE the
  // window still gets its pointerup/pointercancel — the listeners live on the captured element, so an
  // unmount mid-drag frees them with it (no window-level leak).
  const startDrag = (mode: 'move' | 'se' | 'rail', e: ReactPointerEvent<HTMLElement>): void => {
    e.preventDefault()
    const el = e.currentTarget
    const pid = e.pointerId
    el.setPointerCapture(pid)
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
    const end = (): void => {
      if (el.hasPointerCapture(pid)) el.releasePointerCapture(pid)
      el.removeEventListener('pointermove', move)
      el.removeEventListener('pointerup', end)
      el.removeEventListener('pointercancel', end)
    }
    el.addEventListener('pointermove', move)
    el.addEventListener('pointerup', end)
    el.addEventListener('pointercancel', end)
  }
  // Move from bare chrome only — presses on a control keep it interactive.
  const onWindowDown = (e: ReactPointerEvent<HTMLElement>): void => {
    if ((e.target as HTMLElement).closest('button, input, .navpane-rail-resize, .navpane-resize-se')) return
    startDrag('move', e)
  }

  const style = { left: geo.x ?? 0, top: geo.y ?? 0, width: geo.w, height: geo.h, '--navpane-rail': `${geo.rail}px` } as CSSProperties

  return (
    <GlassWindow className={`navpane${closing ? ' closing' : ''}`} style={style} role="dialog" aria-label="Navigation" onPointerDown={onWindowDown}>
      <GlassWindow className="navpane-rail">
        <NavList items={resolvedFavorites} onSelect={goClose} onRemoveFavorite={removeFavorite} />
      </GlassWindow>
      <div className="navpane-rail-resize" onPointerDown={(e) => startDrag('rail', e)} role="separator" aria-orientation="vertical" aria-label="Resize favorites" />
      <div className="navpane-main">
        <div className="navpane-search">
          <Icon name="search" size={14} />
          <input ref={searchRef} value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search…" spellCheck={false} />
        </div>
        <div className="navpane-main-scroll">
          {results ? (
            <NavList items={results.items} extras={results.extras} onSelect={goClose} empty="No matches" />
          ) : (
            <NavList
              items={resolvedRecents}
              onSelect={goClose}
              onTogglePin={togglePin}
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
