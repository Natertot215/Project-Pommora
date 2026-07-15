import { useEffect, useMemo, useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent } from 'react'
import { GlassPane, GlassWindow } from '@renderer/design-system/materials'
import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import type { NavTarget } from '@shared/types'
import { useExitPresence } from '../design-system/useExitPresence'
import { useSession } from '../store'
import { splitSearch, useNavData } from '../Navigation/useNavData'
import { NavList } from '../Navigation/NavList'
import './navpane.css'

// KNOB — the pane's default opening size + resize/rail bounds.
const WIN = { minW: 360, minH: 280, defW: 640, defH: 460 }
const RAIL = { min: 120, def: 200, max: 320 }

type DragMode = 'move' | 'rail' | 'nw' | 'ne' | 'sw' | 'se'

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
  const closeNav = useSession((s) => s.closeNav)

  const [query, setQuery] = useState('')
  const [, force] = useState(0) // re-render on geometry mutation (geo is a module ref)
  const searchRef = useRef<HTMLInputElement>(null)

  // Always open centered (Nathan's call) — size persists across opens, position doesn't. Re-clamp on
  // resize. H-2: focus the search on open (a command-palette focus, not a modal focus-trap).
  useEffect(() => {
    geo.w = Math.min(geo.w, window.innerWidth)
    geo.h = Math.min(geo.h, window.innerHeight)
    geo.x = Math.max(0, Math.round((window.innerWidth - geo.w) / 2))
    geo.y = Math.max(0, Math.round((window.innerHeight - geo.h) / 3))
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

  const results = useMemo(() => (query.trim() ? splitSearch(search(query)) : null), [query, search])
  const goClose = (target: NavTarget): void => go(target, closeNav)
  // Rail Style toggle — cycles the recents view; the gallery layout is Figma-pending, so v1 flips the label.
  const [viewMode, setViewMode] = useState<'list' | 'gallery'>('list')

  // Capture the pointer on the pressed element (house pattern) so a drag that releases OUTSIDE the
  // window still gets its pointerup/pointercancel — the listeners live on the captured element, so an
  // unmount mid-drag frees them with it (no window-level leak).
  const startDrag = (mode: DragMode, e: ReactPointerEvent<HTMLElement>): void => {
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
      } else if (mode === 'rail') {
        geo.rail = clamp(s.rail + dx, RAIL.min, RAIL.max)
      } else {
        // Corner resize — a west/north corner drags its own edge, holding the opposite edge fixed.
        if (mode === 'nw' || mode === 'sw') {
          const w = clamp(s.gw - dx, WIN.minW, s.gx + s.gw)
          geo.w = w
          geo.x = s.gx + (s.gw - w)
        } else {
          geo.w = clamp(s.gw + dx, WIN.minW, window.innerWidth - s.gx)
        }
        if (mode === 'nw' || mode === 'ne') {
          const h = clamp(s.gh - dy, WIN.minH, s.gy + s.gh)
          geo.h = h
          geo.y = s.gy + (s.gh - h)
        } else {
          geo.h = clamp(s.gh + dy, WIN.minH, window.innerHeight - s.gy)
        }
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
  // Move from bare chrome only — presses on a control or a resize handle keep their own behavior.
  const onWindowDown = (e: ReactPointerEvent<HTMLElement>): void => {
    if ((e.target as HTMLElement).closest('button, input, .navpane-rail-resize, [class*="navpane-resize"]')) return
    startDrag('move', e)
  }

  const style = { left: geo.x ?? 0, top: geo.y ?? 0, width: geo.w, height: geo.h, '--navpane-rail': `${geo.rail}px` } as CSSProperties

  return (
    <GlassPane className={`navpane${closing ? ' closing' : ''}`} style={style} role="dialog" aria-label="Navigation" onPointerDown={onWindowDown}>
      <button type="button" className="navpane-close" aria-label="Close" onClick={closeNav}>
        <Icon name="x" size={14} />
      </button>
      <div className="navpane-body">
        <GlassWindow className="navpane-rail">
          <div className="navpane-rail-list scroll-edge-fade">
            <NavList items={resolvedFavorites} onSelect={goClose} />
          </div>
          <button type="button" className={cx('navpane-style-toggle', text.footnote.emphasized)} onClick={() => setViewMode((m) => (m === 'list' ? 'gallery' : 'list'))}>
            <Icon name="chevrons-up-down" size={12} />
            <span>{viewMode === 'list' ? 'List' : 'Gallery'}</span>
          </button>
        </GlassWindow>
        <div className="navpane-rail-resize" onPointerDown={(e) => startDrag('rail', e)} role="separator" aria-orientation="vertical" aria-label="Resize favorites" />
        <div className="navpane-main">
          <div className="navpane-search">
            <input ref={searchRef} className={text.body.standard} value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search…" spellCheck={false} />
          </div>
          <div className="navpane-main-scroll scroll-edge-fade">
            {results ? (
              <NavList items={results.items} extras={results.extras} onSelect={goClose} />
            ) : (
              <NavList items={resolvedRecents} onSelect={goClose} />
            )}
          </div>
        </div>
      </div>
      <div className="navpane-resize navpane-resize-nw" onPointerDown={(e) => startDrag('nw', e)} aria-label="Resize" />
      <div className="navpane-resize navpane-resize-ne" onPointerDown={(e) => startDrag('ne', e)} aria-label="Resize" />
      <div className="navpane-resize navpane-resize-sw" onPointerDown={(e) => startDrag('sw', e)} aria-label="Resize" />
      <div className="navpane-resize navpane-resize-se" onPointerDown={(e) => startDrag('se', e)} aria-label="Resize" />
    </GlassPane>
  )
}
