import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type ReactNode
} from 'react'
import { createPortal } from 'react-dom'
import { text } from '@renderer/design-system/tokens'
import { ACTIVATION, suppressNextClick } from '@renderer/design-system/interactions/shared'
import { announce } from '@renderer/design-system/interactions/a11y'
import type { FolderPlacement, NexusTree } from '@shared/types'
import type { MutateRequest } from '@shared/mutate'
import { buildIndex, nextOrder, setContainerOf, isSelfOrDescendant, slotInGroup, type Entry, type Index, type MeasuredRow } from './sidebarDndModel'

// Sidebar drag-and-drop — the "sidebar" behavior (chosen 2026-06-19): an Apple-style insertion
// LINE marks the exact drop, the picked-up row stays muted in place, and a ghost rides the cursor.
// No row displacement. EVERY sidebar entity is draggable and reorders within its parent heading —
// pages (within a folder; also reparent across folders), Sets (reorder/reparent across Collections
// and Sets), top-level Collections, and the three context tiers. The commit routes to the right
// order store.

const LINE_INSET_RIGHT = 12
const BASE_INDENT = 8 // MenuItem's base left padding
const STEP_INDENT = 14 // MenuItem's per-depth inset

type DropTarget = {
  depth: number // indent depth of the landing slot (the line)
  lineY: number // relative to the content wrapper
  commit: MutateRequest // the write this drop resolves to — handed straight to store.mutate
  noop: boolean // the drop wouldn't change anything → skip the write
}

type DragState = { id: string | null; ghostX: number; ghostY: number; target: DropTarget | null }
const IDLE: DragState = { id: null, ghostX: 0, ghostY: 0, target: null }

// Gesture lifecycle: idle → pending (pressed, not yet past the activation threshold) →
// active (dragging). pending and active carry the same fields; idle carries none.
type Handlers = { move: (e: PointerEvent) => void; up: () => void; cancel: () => void; key: (e: KeyboardEvent) => void }
type Gesture =
  | { kind: 'idle' }
  | { kind: 'pending' | 'active'; id: string; el: HTMLElement; pid: number; startX: number; startY: number; grabX: number; handlers: Handlers }

type Value = {
  draggingId: string | null
  registerRow: (id: string, el: HTMLElement | null) => void
  begin: (id: string, e: ReactPointerEvent) => void
}
const Ctx = createContext<Value | null>(null)

export function SidebarDnd({
  tree,
  onCommit,
  setPlacement = 'top',
  subSetPlacement = 'top',
  children
}: {
  tree: NexusTree
  onCommit: (commit: MutateRequest) => void
  setPlacement?: FolderPlacement
  subSetPlacement?: FolderPlacement
  children: ReactNode
}): React.JSX.Element {
  const index = useMemo(() => buildIndex(tree), [tree])
  const indexRef = useRef(index)
  indexRef.current = index
  // Placement drives where an empty Sets block lands when a Set is dropped onto a container header —
  // above its pages (top) or below them (bottom). Ref'd so the frozen-snapshot resolver reads current.
  const placements = useRef({ set: setPlacement, subSet: subSetPlacement })
  placements.current = { set: setPlacement, subSet: subSetPlacement }
  // A mid-drag tree swap (watcher push) can re-render rows — stale rects must not survive it.
  useEffect(() => {
    snapshotDirty.current = true
  }, [index])
  const onCommitRef = useRef(onCommit)
  onCommitRef.current = onCommit

  const rows = useRef(new Map<string, HTMLElement>())
  const contentRef = useRef<HTMLDivElement | null>(null)
  const live = useRef<DropTarget | null>(null)
  const [drag, setDrag] = useState<DragState>(IDLE)

  const gesture = useRef<Gesture>({ kind: 'idle' })

  // Geometry snapshot — measured ONCE at drag activation, not per pointermove. No row displaces
  // mid-drag (the insertion-line treatment), so frozen rects stay valid; only a scroll moves them,
  // which marks the snapshot dirty and the next move re-measures once (coalescing a scroll's
  // event burst into a single layout read). Never O(rows) rect reads on a high-frequency trigger.
  type Snapshot = { contentTop: number; measured: MeasuredRow[] }
  const snapshot = useRef<Snapshot | null>(null)
  const snapshotDirty = useRef(false)

  const takeSnapshot = (excludeId: string): Snapshot | null => {
    const content = contentRef.current
    if (!content) return null
    const contentTop = content.getBoundingClientRect().top
    const measured: MeasuredRow[] = []
    for (const [id, el] of rows.current) {
      if (id === excludeId) continue
      const r = el.getBoundingClientRect()
      measured.push({ id, top: r.top, bottom: r.bottom, mid: r.top + r.height / 2 })
    }
    measured.sort((a, b) => a.top - b.top)
    return { contentTop, measured }
  }

  const registerRow = (id: string, el: HTMLElement | null): void => {
    if (el) rows.current.set(id, el)
    else rows.current.delete(id)
  }

  // Hit-test the frozen snapshot → the landing slot.
  const computeTarget = (clientY: number): DropTarget | null => {
    const g = gesture.current
    if (g.kind === 'idle') return null
    const idx = indexRef.current
    const dragged = idx.byId.get(g.id)
    if (!dragged) return null
    if (snapshotDirty.current || !snapshot.current) {
      snapshot.current = takeSnapshot(g.id)
      snapshotDirty.current = false
    }
    if (!snapshot.current) return null
    const { contentTop, measured } = snapshot.current
    if (measured.length === 0) return null
    const nearest = (rowsByTop: MeasuredRow[]): MeasuredRow => {
      let over = rowsByTop[0]
      for (const m of rowsByTop) {
        if (clientY >= m.top) over = m
        else break
      }
      return over
    }

    // Pages: reorder within a container, or reparent into one.
    if (dragged.kind === 'page') {
      const over = nearest(measured)
      const entry = idx.byId.get(over.id)
      if (!entry) return null
      if (entry.kind === 'page') {
        const container = entry.parentId ? idx.byId.get(entry.parentId) : null
        if (!container || !entry.parentId || !entry.parentPath) return null
        const { beforeId, edge } = slotInGroup(container.pageIds, over, clientY, g.id)
        const order = nextOrder(container.pageIds, g.id, beforeId)
        return {
          depth: entry.depth,
          lineY: edge - contentTop,
          commit: { op: 'movePage', path: dragged.path, newParentPath: entry.parentPath, order },
          noop: entry.parentId === dragged.parentId && sameOrder(order, container.pageIds)
        }
      }
      // Over a container header → drop in at the top of its pages.
      const beforeId = entry.pageIds.find((id) => id !== g.id) ?? null
      const order = nextOrder(entry.pageIds, g.id, beforeId)
      return {
        depth: entry.depth + 1,
        lineY: over.bottom - contentTop,
        commit: { op: 'movePage', path: dragged.path, newParentPath: entry.path, order },
        noop: over.id === dragged.parentId && sameOrder(order, entry.pageIds)
      }
    }

    // Sets: reorder within their container, or reparent into any Collection or Set (except the
    // dragged set's own subtree → cycle). A Set may never land on a context or the top level.
    if (dragged.kind === 'set') {
      const over = nearest(measured)
      const overEntry = idx.byId.get(over.id)
      if (!overEntry) return null
      const target = setContainerOf(overEntry, idx)
      if (!target) return null
      if (isSelfOrDescendant(target.id, g.id, idx)) return null // no cycles
      const group = target.containerIds // the target container's child Sets, in order
      let beforeId: string | null
      let lineY: number
      if (overEntry.kind === 'set') {
        const slot = slotInGroup(group, over, clientY, g.id)
        beforeId = slot.beforeId
        lineY = slot.edge - contentTop
      } else {
        // Over the container header or one of its pages → land at the near edge of its Sets block.
        // The block sits above or below the pages per placement, so derive the line from real
        // geometry: an existing block's first-row top (correct either way), else — an empty block —
        // just under the header (top) or after the container's last page (bottom).
        beforeId = group.find((id) => id !== g.id) ?? null
        const headerRect = measured.find((m) => m.id === target.id)
        const headEdge = headerRect ? headerRect.bottom : over.bottom
        if (beforeId) {
          const firstRow = measured.find((m) => m.id === beforeId)
          lineY = (firstRow ? firstRow.top : headEdge) - contentTop
        } else {
          const placement = target.kind === 'collection' ? placements.current.set : placements.current.subSet
          const pageBottoms = target.pageIds.map((id) => measured.find((m) => m.id === id)?.bottom).filter((b): b is number => b != null)
          const edge = placement === 'bottom' && pageBottoms.length ? Math.max(...pageBottoms) : headEdge
          lineY = edge - contentTop
        }
      }
      const order = nextOrder(group, g.id, beforeId)
      return {
        depth: target.depth + 1,
        lineY,
        commit: { op: 'moveSet', path: dragged.path, newParentPath: target.path, order },
        noop: target.id === dragged.parentId && sameOrder(order, group)
      }
    }

    // Collections / contexts: reorder among same-kind siblings under the same parent.
    const siblings = measured.filter((m) => {
      const e = idx.byId.get(m.id)
      return e !== undefined && e.kind === dragged.kind && e.parentId === dragged.parentId
    })
    if (siblings.length === 0) return null
    const over = nearest(siblings)
    const overEntry = idx.byId.get(over.id)
    if (!overEntry) return null
    const group = siblingGroup(dragged, idx)
    const { beforeId, edge } = slotInGroup(group, over, clientY, g.id)
    const order = nextOrder(group, g.id, beforeId)
    const commit = reorderCommit(dragged, idx, order)
    if (!commit) return null
    return { depth: overEntry.depth, lineY: edge - contentTop, commit, noop: sameOrder(order, group) }
  }

  const markSnapshotDirty = (): void => {
    snapshotDirty.current = true
  }

  const detach = (): void => {
    const g = gesture.current
    if (g.kind === 'idle') return
    g.el.removeEventListener('pointermove', g.handlers.move)
    g.el.removeEventListener('pointerup', g.handlers.up)
    g.el.removeEventListener('pointercancel', g.handlers.cancel)
    window.removeEventListener('keydown', g.handlers.key)
    window.removeEventListener('scroll', markSnapshotDirty, { capture: true })
    try {
      g.el.releasePointerCapture(g.pid)
    } catch {
      // already released
    }
  }

  const reset = (): void => {
    gesture.current = { kind: 'idle' }
    live.current = null
    snapshot.current = null
    snapshotDirty.current = false
    setDrag(IDLE)
  }


  const begin = (id: string, e: ReactPointerEvent): void => {
    if (e.button !== 0 || !e.isPrimary || gesture.current.kind !== 'idle') return
    if ((e.target as HTMLElement).closest?.('input, textarea, [contenteditable="true"]')) return
    const el = rows.current.get(id)
    if (!el) return
    const r = el.getBoundingClientRect()
    const handlers: Handlers = { move: onMovePtr, up: onUp, cancel: onCancel, key: onKey }
    gesture.current = { kind: 'pending', id, el, pid: e.pointerId, startX: e.clientX, startY: e.clientY, grabX: e.clientX - r.left, handlers }
    // Capture is deferred to activation (onMovePtr). Capturing on pointerdown would consume the
    // click, so a tap could never toggle a disclosure or select a row — it'd always be a drag.
    el.addEventListener('pointermove', handlers.move)
    el.addEventListener('pointerup', handlers.up)
    el.addEventListener('pointercancel', handlers.cancel)
    // Escape rides the window — the row never holds focus, so a key event can't reach it.
    window.addEventListener('keydown', handlers.key)
  }

  function onMovePtr(e: PointerEvent): void {
    const g = gesture.current
    if (g.kind === 'idle') return
    if (g.kind === 'pending') {
      if (Math.hypot(e.clientX - g.startX, e.clientY - g.startY) < ACTIVATION) return
      try {
        g.el.setPointerCapture(g.pid) // capture only now — a real drag has started; taps stay clicks
      } catch {
        // capture unavailable
      }
      gesture.current = { ...g, kind: 'active' }
      // Any scroll (nav, ancestors) shifts viewport-relative rects → invalidate, re-measure lazily.
      window.addEventListener('scroll', markSnapshotDirty, { capture: true, passive: true })
      announce(`Picked up ${base(indexRef.current.byId.get(g.id)?.path ?? '')}.`)
    }
    const target = computeTarget(e.clientY)
    live.current = target
    setDrag({ id: g.id, ghostX: e.clientX - g.grabX, ghostY: e.clientY, target })
  }

  function onUp(): void {
    detach()
    const g = gesture.current
    if (g.kind !== 'active') {
      reset()
      return // a click, never a drag
    }
    const t = live.current
    if (t && !t.noop) {
      onCommitRef.current(t.commit)
      announce(`Moved ${base(indexRef.current.byId.get(g.id)?.path ?? '')}.`)
      suppressNextClick() // only swallow the click when a drag actually moved something
    }
    reset()
  }

  function onCancel(): void {
    detach()
    reset()
  }

  function onKey(e: KeyboardEvent): void {
    if (e.key === 'Escape') onCancel()
  }

  useEffect(() => () => detach(), [])

  const value = useMemo<Value>(() => ({ draggingId: drag.id, registerRow, begin }), [drag.id]) // eslint-disable-line react-hooks/exhaustive-deps

  const draggedLabel = drag.id ? base(index.byId.get(drag.id)?.path ?? '') : ''

  return (
    <Ctx.Provider value={value}>
      <div ref={contentRef} style={{ position: 'relative' }}>
        {children}
        {drag.target && (
          <div
            aria-hidden
            style={{
              position: 'absolute',
              top: drag.target.lineY,
              left: BASE_INDENT + drag.target.depth * STEP_INDENT,
              right: LINE_INSET_RIGHT,
              height: 2,
              borderRadius: 2,
              background: 'var(--accent)',
              pointerEvents: 'none',
              zIndex: 20
            }}
          >
            <span style={{ position: 'absolute', left: -3, top: -2.5, width: 7, height: 7, borderRadius: '50%', background: 'var(--accent)' }} />
          </div>
        )}
      </div>
      {drag.id &&
        createPortal(
          <div
            aria-hidden
            className={text.body.standard}
            style={{
              position: 'fixed',
              top: drag.ghostY,
              left: drag.ghostX,
              padding: '4px 12px',
              borderRadius: 8,
              color: 'var(--label-primary)',
              background: 'color-mix(in srgb, var(--bg-window) 78%, transparent)',
              backdropFilter: 'blur(6px)',
              WebkitBackdropFilter: 'blur(6px)',
              boxShadow: '0 14px 34px #00000073',
              pointerEvents: 'none',
              zIndex: 1000
            }}
          >
            {draggedLabel}
          </div>,
          document.body
        )}
    </Ctx.Provider>
  )
}

const base = (p: string): string => {
  const n = p.slice(p.lastIndexOf('/') + 1)
  return n.endsWith('.md') ? n.slice(0, -3) : n
}
const sameOrder = (a: string[], b: string[]): boolean => a.length === b.length && a.every((x, i) => x === b[i])

// The ordered sibling group a Collection / context entity reorders within — all top-level groups
// held in `.nexus/state.json`. (Sets have their own reparent-aware branch in computeTarget and
// never reach here.)
function siblingGroup(dragged: Entry, idx: Index): string[] {
  switch (dragged.kind) {
    case 'collection':
      return idx.collectionIds
    case 'area':
      return idx.areaIds
    case 'topic':
      return idx.topicIds
    case 'project':
      return idx.projectIds
    default:
      return []
  }
}

// The commit for a non-page reorder — every top-level group is held in `.nexus/state.json`.
// (Sets reorder/move via the moveSet branch in computeTarget, not here.)
function reorderCommit(dragged: Entry, _idx: Index, order: string[]): MutateRequest | null {
  switch (dragged.kind) {
    case 'collection':
      return { op: 'reorderTop', key: 'collection_order', order }
    case 'area':
      return { op: 'reorderTop', key: 'area_order', order }
    case 'topic':
      return { op: 'reorderTop', key: 'topic_order', order }
    case 'project':
      return { op: 'reorderTop', key: 'project_order', order }
    default:
      return null
  }
}

/** Make any sidebar row draggable + registered for hit-testing: spread `handle`, put `ref` on
 *  the row element. The engine decides what the drop means from the row's kind. */
export function useSidebarDrag(id: string): {
  ref: (el: HTMLElement | null) => void
  handle: { onPointerDown: (e: ReactPointerEvent) => void }
  isDragging: boolean
} {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useSidebarDrag must be used inside <SidebarDnd>')
  return {
    ref: (el) => ctx.registerRow(id, el),
    handle: { onPointerDown: (e) => ctx.begin(id, e) },
    isDragging: ctx.draggingId === id
  }
}
