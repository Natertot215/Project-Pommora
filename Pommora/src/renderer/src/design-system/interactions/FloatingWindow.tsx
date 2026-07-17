import {
  useEffect,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
} from 'react'
import './floatingWindow.css'

// The shared floating-window chrome engine — the NavWindow move/resize pattern extracted for every
// in-app floating window (NavWindow rebases onto it at the Page Previews implementation pass).

export interface FloatingBounds {
  minW: number
  minH: number
  defW: number
  defH: number
}

export type FloatingDragMode = 'move' | 'nw' | 'ne' | 'sw' | 'se'

interface Geo {
  x: number
  y: number
  w: number
  h: number
}

// Geometry survives each window's exit-presence unmount, keyed per window id — never a bare module
// singleton (the multi-preview A-B needs windows that don't share one slot).
const geoStore = new Map<string, Geo>()

const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v))

export function useFloatingWindow(
  id: string,
  bounds: FloatingBounds,
  dragSurfaces: string,
): {
  style: CSSProperties
  onWindowDown: (e: ReactPointerEvent<HTMLElement>) => void
  startDrag: (mode: FloatingDragMode, e: ReactPointerEvent<HTMLElement>) => void
} {
  let stored = geoStore.get(id)
  if (!stored) {
    stored = { x: 0, y: 0, w: bounds.defW, h: bounds.defH }
    geoStore.set(id, stored)
  }
  const g = stored
  const [, force] = useState(0)

  // Always open centered — size persists across opens, position doesn't (the NavWindow contract).
  // Re-clamp on window resize so the chrome never strands off-screen.
  useEffect(() => {
    g.w = Math.min(g.w, window.innerWidth)
    g.h = Math.min(g.h, window.innerHeight)
    g.x = Math.max(0, Math.round((window.innerWidth - g.w) / 2))
    g.y = Math.max(0, Math.round((window.innerHeight - g.h) / 3))
    force((n) => n + 1)
    const onResize = (): void => {
      g.w = Math.min(g.w, window.innerWidth)
      g.h = Math.min(g.h, window.innerHeight)
      g.x = clamp(g.x, 0, Math.max(0, window.innerWidth - 80))
      g.y = clamp(g.y, 0, Math.max(0, window.innerHeight - 40))
      force((n) => n + 1)
    }
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [g])

  // Capture the pointer on the pressed element (house pattern) so a drag that releases OUTSIDE the
  // window still gets its pointerup/pointercancel — listeners die with the element on unmount.
  const startDrag = (mode: FloatingDragMode, e: ReactPointerEvent<HTMLElement>): void => {
    e.preventDefault()
    const el = e.currentTarget
    const pid = e.pointerId
    el.setPointerCapture(pid)
    const s = { x: e.clientX, y: e.clientY, gx: g.x, gy: g.y, gw: g.w, gh: g.h }
    const move = (ev: PointerEvent): void => {
      const dx = ev.clientX - s.x
      const dy = ev.clientY - s.y
      if (mode === 'move') {
        g.x = clamp(s.gx + dx, 0, window.innerWidth - 80)
        g.y = clamp(s.gy + dy, 0, window.innerHeight - 40)
      } else {
        // Corner resize — a west/north corner drags its own edge, holding the opposite edge fixed.
        if (mode === 'nw' || mode === 'sw') {
          const w = clamp(s.gw - dx, bounds.minW, s.gx + s.gw)
          g.w = w
          g.x = s.gx + (s.gw - w)
        } else {
          g.w = clamp(s.gw + dx, bounds.minW, window.innerWidth - s.gx)
        }
        if (mode === 'nw' || mode === 'ne') {
          const h = clamp(s.gh - dy, bounds.minH, s.gy + s.gh)
          g.h = h
          g.y = s.gy + (s.gh - h)
        } else {
          g.h = clamp(s.gh + dy, bounds.minH, window.innerHeight - s.gy)
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

  // Window-move is RESERVED to the bare surfaces (the allow-list, matched against the press target
  // itself) — anything else owns its pointer, so row/reorder captures are never stolen mid-press.
  const onWindowDown = (e: ReactPointerEvent<HTMLElement>): void => {
    if ((e.target as HTMLElement).matches(dragSurfaces)) startDrag('move', e)
  }

  return {
    style: { left: g.x, top: g.y, width: g.w, height: g.h },
    onWindowDown,
    startDrag,
  }
}

export function FloatingResizeCorners({
  startDrag,
}: {
  startDrag: (mode: FloatingDragMode, e: ReactPointerEvent<HTMLElement>) => void
}): React.JSX.Element {
  return (
    <>
      {(['nw', 'ne', 'sw', 'se'] as const).map((c) => (
        <div
          key={c}
          className={`fwin-resize fwin-resize-${c}`}
          onPointerDown={(e) => startDrag(c, e)}
          aria-label="Resize"
        />
      ))}
    </>
  )
}
