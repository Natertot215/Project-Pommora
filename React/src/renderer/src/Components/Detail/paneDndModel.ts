// Pure model behind the Properties pane's two-region drag — no React, no DOM. One gesture
// surface, two persistence targets: the pointer's REGION decides everything (E-4); the rows
// only refine the insertion slot within it. Slot indexes land in the persisted arrays'
// without-dragged coordinates — the filter-then-splice idiom both reorder ops share.

import type { MeasuredRow } from '@renderer/Sidebar/sidebarDndModel'

export type PaneRow = { id: string; group: 'assigned' | 'all' }

export type PaneDrop =
  | { kind: 'reorder-assigned'; propId: string; toIndex: number } // → schema.reorder (C-5)
  | { kind: 'reorder-nexus'; propId: string; toIndex: number } // → registry.reorder (C-1)
  | { kind: 'assign'; propId: string; toIndex: number } // all → assigned at the slot (C-2)
  | { kind: 'unassign'; propId: string } // assigned → all; area highlight, natural slot (C-3/C-4)

export type PaneSlot = { drop: PaneDrop; lineY: number | null; highlightAll: boolean }
export type Region = { top: number; bottom: number }

export function paneSlot(
  rows: MeasuredRow[],
  byId: Map<string, PaneRow>,
  regions: { assigned: Region; all: Region },
  pointerY: number,
  draggedId: string
): PaneSlot | null {
  const dragged = byId.get(draggedId)
  if (!dragged) return null
  const within = (r: Region): boolean => pointerY >= r.top && pointerY <= r.bottom
  const region = within(regions.assigned) ? 'assigned' : within(regions.all) ? 'all' : null
  if (region === null) return null // outside both — release is a no-op

  if (region === 'all' && dragged.group === 'assigned') {
    return { drop: { kind: 'unassign', propId: draggedId }, lineY: null, highlightAll: true }
  }

  const groupRows = rows.filter((r) => byId.get(r.id)?.group === region && r.id !== draggedId)
  let i = 0
  while (i < groupRows.length && pointerY >= groupRows[i].mid) i++
  const last = groupRows[groupRows.length - 1]
  const lineY = i < groupRows.length ? groupRows[i].top : last ? last.bottom : regions[region].top
  const drop: PaneDrop =
    region === 'assigned'
      ? dragged.group === 'assigned'
        ? { kind: 'reorder-assigned', propId: draggedId, toIndex: i }
        : { kind: 'assign', propId: draggedId, toIndex: i }
      : { kind: 'reorder-nexus', propId: draggedId, toIndex: i }
  return { drop, lineY, highlightAll: false }
}
