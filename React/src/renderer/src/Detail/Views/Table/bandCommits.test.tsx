// @vitest-environment jsdom
// Band drop commits through the real TableView (state-level; geometry truth = the CDP pass):
// structural reorder → view-level group_order (collapsed ids included, NO fs write) · property
// reorder → group.order + manual · reparent → moveSet with APPENDED fs order + the slot in
// group_order · the override rides liveView so a sibling persist can't clobber a fresh drag (F1)
// and survives a source-identity swap (HIGH-3).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { PropertyDefinition } from '@shared/properties'
import type { CollectionNode } from '@shared/types'
import type { SavedView } from '@shared/views'
import { firePointer, pressEscape, stubPointerCapture, stubRect } from '@renderer/testing/pointerHarness'
import { useSession } from '../../../store'
import { TableView } from './TableView'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
;(globalThis as { ResizeObserver?: unknown }).ResizeObserver = ResizeObserverStub

stubPointerCapture()

const statusDef: PropertyDefinition = {
  id: 'prop_status',
  name: 'Status',
  type: 'status',
  status_groups: [
    {
      id: 'upcoming',
      label: 'Upcoming',
      color: 'gray',
      options: [{ value: 'not_started', label: 'Not started', group_id: 'upcoming' }]
    },
    {
      id: 'in_progress',
      label: 'In Progress',
      color: 'blue',
      options: [{ value: 'active', label: 'Active', color: 'blue', group_id: 'in_progress' }]
    },
    {
      id: 'done',
      label: 'Done',
      color: 'green',
      options: [{ value: 'complete', label: 'Complete', color: 'green', group_id: 'done' }]
    }
  ]
}

const page = (id: string, title: string, path: string): Record<string, unknown> => ({ kind: 'page', id, title, path })

/** A[A1], B + a loose root page. */
const structuralSource = (view?: Partial<SavedView>): CollectionNode =>
  ({
    kind: 'collection',
    id: 'col1',
    title: 'Col',
    path: 'Col',
    sets: [
      {
        kind: 'set',
        id: 'sA',
        title: 'A',
        path: 'Col/A',
        pages: [page('pA', 'In A', 'Col/A/In A.md')],
        sets: [{ kind: 'set', id: 'sA1', title: 'A1', path: 'Col/A/A1', pages: [], sets: [] }]
      },
      { kind: 'set', id: 'sB', title: 'B', path: 'Col/B', pages: [], sets: [] }
    ],
    pages: [page('pLoose', 'Loose', 'Col/Loose.md')],
    properties: [statusDef],
    views: [
      {
        id: 'view_1',
        name: 'Table',
        type: 'table',
        property_order: ['_title', 'prop_status'],
        hidden_properties: [],
        group: { kind: 'structural' },
        ...view
      }
    ]
  }) as unknown as CollectionNode

const propertySource = (): CollectionNode =>
  ({
    kind: 'collection',
    id: 'col1',
    title: 'Col',
    path: 'Col',
    sets: [],
    pages: [page('p1', 'One', 'Col/One.md'), page('p2', 'Two', 'Col/Two.md')],
    properties: [statusDef],
    views: [
      {
        id: 'view_1',
        name: 'Table',
        type: 'table',
        property_order: ['_title', 'prop_status'],
        hidden_properties: [],
        group: {
          kind: 'property',
          property_id: 'prop_status',
          order_mode: 'configured',
          empty_placement: 'bottom',
          hide_empty_groups: false
        }
      }
    ]
  }) as unknown as CollectionNode

const VALUES = {
  p1: { id: 'p1', properties: { prop_status: { $status: 'active' } } },
  p2: { id: 'p2', properties: { prop_status: { $status: 'complete' } } }
}

let host: HTMLDivElement
let root: Root
let mutateSpy: ReturnType<typeof vi.fn>
let saveSpy: ReturnType<typeof vi.fn>

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  mutateSpy = vi.fn(async () => {})
  saveSpy = vi.fn(async () => ({ ok: true }))
  ;(window as unknown as { nexus: unknown }).nexus = {
    loadValues: async () => VALUES,
    activeViews: { get: async () => ({}) },
    viewOrders: { get: async () => ({}) },
    views: { save: saveSpy },
    cellMenu: vi.fn(async () => null),
    columnMenu: vi.fn(async () => null)
  }
  const pair = (singular: string, plural: string): { singular: string; plural: string } => ({ singular, plural })
  useSession.setState({
    tree: {
      contexts: { areas: [], topics: [], projects: [] },
      collections: [],
      userSections: [],
      labels: {
        area: pair('Area', 'Areas'),
        topic: pair('Topic', 'Topics'),
        project: pair('Project', 'Projects'),
        pageCollection: pair('Collection', 'Collections'),
        pageSet: pair('Set', 'Sets'),
        agendaTask: pair('Task', 'Tasks'),
        agendaEvent: pair('Event', 'Events')
      }
    } as never,
    selection: { kind: 'none' } as never,
    mutate: mutateSpy as never
  })
})
afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

const mountTable = async (source: CollectionNode): Promise<void> => {
  await act(async () => {
    root.render(<TableView source={source} />)
  })
  await act(async () => {}) // flush loadValues/activeViews
  stubBandRects()
}

/** Stack the visible band headers at 24px each and give the dnd box a rect. */
function stubBandRects(): void {
  const box = host.querySelector('.band-dnd')
  if (box) stubRect(box, { top: 0, bottom: 400 })
  const headers = host.querySelectorAll('.group-header')
  for (const [i, el] of [...headers].entries()) stubRect(el, { top: i * 24, bottom: i * 24 + 24 })
}

const headerTexts = (): string[] => [...host.querySelectorAll('.group-header')].map((el) => el.textContent ?? '')

const dragBand = async (index: number, toY: number): Promise<void> => {
  const glyphs = host.querySelectorAll('.band-glyph')
  await act(async () => {
    firePointer(glyphs[index], 'pointerdown', { x: 10, y: index * 24 + 12 })
  })
  await act(async () => {
    firePointer(window, 'pointermove', { x: 10, y: toY })
  })
}
const drop = async (): Promise<void> => {
  await act(async () => {
    firePointer(window, 'pointerup')
  })
}

const lastSavedView = (): SavedView => saveSpy.mock.calls.at(-1)?.[2] as SavedView

describe('structural band reorder', () => {
  it('persists the merged group_order (collapsed ids INCLUDED), renders optimistically, and never touches the fs', async () => {
    await mountTable(structuralSource({ collapsed_groups: ['sA'] })) // bands: A (collapsed), B
    await dragBand(1, 2) // B above A
    await drop()
    expect(saveSpy).toHaveBeenCalledOnce()
    expect(lastSavedView().group_order).toEqual(['sB', 'sA', 'sA1'])
    expect(mutateSpy).not.toHaveBeenCalled()
    expect(headerTexts()[0]).toContain('B') // the override renders without waiting on the round-trip
  })

  it('a collapse toggle right after the drag persists WITH the fresh band order (the F1 clobber regression)', async () => {
    await mountTable(structuralSource())
    await dragBand(2, 2) // B above A
    await drop()
    const twisty = host.querySelectorAll('.group-twisty')[0]
    await act(async () => {
      ;(twisty as HTMLElement).click()
    })
    expect(saveSpy).toHaveBeenCalledTimes(2)
    expect(lastSavedView().group_order).toEqual(['sB', 'sA', 'sA1'])
  })

  it('the override survives a source-identity swap (HIGH-3)', async () => {
    const source = structuralSource()
    await mountTable(source)
    await dragBand(2, 2)
    await drop()
    expect(headerTexts()[0]).toContain('B')
    // The moveSet-style load() swaps source identity mid-flight — same content, new object.
    await act(async () => {
      root.render(<TableView source={structuralSource()} />)
    })
    await act(async () => {})
    expect(headerTexts()[0]).toContain('B')
  })

  it('Escape mid-drag commits nothing anywhere', async () => {
    await mountTable(structuralSource())
    await dragBand(2, 2)
    await act(async () => {
      pressEscape()
    })
    await drop()
    expect(saveSpy).not.toHaveBeenCalled()
    expect(mutateSpy).not.toHaveBeenCalled()
  })
})

describe('property band reorder', () => {
  it('persists group.order + order_mode manual and renders optimistically', async () => {
    await mountTable(propertySource()) // bands: Active, Complete (configured schema order)
    expect(headerTexts()[0]).toContain('Active')
    await dragBand(1, 2) // Complete above Active
    await drop()
    expect(saveSpy).toHaveBeenCalledOnce()
    expect(lastSavedView().group).toEqual({
      kind: 'property',
      property_id: 'prop_status',
      order_mode: 'manual',
      order: ['complete', 'active'],
      empty_placement: 'bottom',
      hide_empty_groups: false
    })
    expect(lastSavedView().group_order).toBeUndefined()
    expect(mutateSpy).not.toHaveBeenCalled()
    expect(headerTexts()[0]).toContain('Complete')
  })
})

describe('band reparent', () => {
  it('nest-into commits moveSet with the APPENDED fs order plus the group_order slot', async () => {
    await mountTable(structuralSource()) // bands: A, A1, B
    await dragBand(2, 12) // middle zone of A (0–24 → 7.2–16.8)
    await drop()
    expect(mutateSpy).toHaveBeenCalledExactlyOnceWith({
      op: 'moveSet',
      path: 'Col/B',
      newParentPath: 'Col/A',
      order: ['sA1', 'sB'] // current children + APPEND — never the visual slot (C-4)
    })
    expect(saveSpy).toHaveBeenCalledOnce()
    expect(lastSavedView().group_order).toEqual(['sA', 'sA1', 'sB'])
  })

  it('a de-nest between-slot reparents to the container root', async () => {
    await mountTable(structuralSource())
    await dragBand(1, 50) // A1 → bottom half of B's zone? y=50 sits in B's top zone (48–72) → before B at root
    await drop()
    expect(mutateSpy).toHaveBeenCalledExactlyOnceWith({
      op: 'moveSet',
      path: 'Col/A/A1',
      newParentPath: 'Col',
      order: ['sA', 'sB', 'sA1']
    })
    expect(lastSavedView().group_order).toEqual(['sA', 'sA1', 'sB'])
  })
})
