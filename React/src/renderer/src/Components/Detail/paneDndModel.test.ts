import { describe, expect, it } from 'vitest'
import type { MeasuredRow } from '@renderer/Sidebar/sidebarDndModel'
import { paneSlot, type PaneRow, type PaneSlot } from './paneDndModel'

const r = (id: string, top: number, bottom: number): MeasuredRow => ({ id, top, bottom, mid: (top + bottom) / 2 })

// a* = assigned, x* = all (registry)
const rows = [r('a1', 10, 30), r('a2', 30, 50), r('x1', 70, 90), r('x2', 90, 110)]
const byId = new Map<string, PaneRow>([
  ['a1', { id: 'a1', group: 'assigned' }],
  ['a2', { id: 'a2', group: 'assigned' }],
  ['x1', { id: 'x1', group: 'all' }],
  ['x2', { id: 'x2', group: 'all' }]
])
const regions = { assigned: { top: 10, bottom: 50 }, all: { top: 70, bottom: 110 } }

const slot = (y: number, draggedId: string): PaneSlot | null => paneSlot(rows, byId, regions, y, draggedId)

describe('paneSlot — region-owned classification (E-4)', () => {
  it('assigned→assigned reorders at the slot (C-5)', () => {
    expect(slot(15, 'a2')?.drop).toEqual({ kind: 'reorder-assigned', propId: 'a2', toIndex: 0 })
    expect(slot(15, 'a2')?.lineY).toBe(10)
  })

  it('assigned→all is unassign with the area highlight and NO line (C-3/C-4)', () => {
    const s = slot(80, 'a1')
    expect(s?.drop).toEqual({ kind: 'unassign', propId: 'a1' })
    expect(s?.highlightAll).toBe(true)
    expect(s?.lineY).toBeNull()
  })

  it('all→assigned assigns at the slot with a line (C-2)', () => {
    const s = slot(30, 'x1')
    expect(s?.drop).toEqual({ kind: 'assign', propId: 'x1', toIndex: 1 })
    expect(s?.lineY).toBe(30)
  })

  it('all→all reorders the nexus order (C-1)', () => {
    expect(slot(105, 'x1')?.drop).toEqual({ kind: 'reorder-nexus', propId: 'x1', toIndex: 1 })
  })

  it('outside both regions → null (release is a no-op)', () => {
    expect(slot(200, 'a1')).toBeNull()
    expect(slot(60, 'a1')).toBeNull() // the gap between the regions
  })

  it('an empty target region still yields the slot at its top (assign into a bare collection)', () => {
    const only = [r('x1', 70, 90)]
    const ids = new Map<string, PaneRow>([['x1', { id: 'x1', group: 'all' }]])
    const s = paneSlot(only, ids, { assigned: { top: 10, bottom: 50 }, all: { top: 70, bottom: 110 } }, 20, 'x1')
    expect(s?.drop).toEqual({ kind: 'assign', propId: 'x1', toIndex: 0 })
    expect(s?.lineY).toBe(10)
  })
})
