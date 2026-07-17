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
import {
  firePointer,
  pressEscape,
  stubPointerCapture,
  stubRect,
} from '@renderer/testing/pointerHarness'
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
      options: [{ value: 'not_started', label: 'Not started', group_id: 'upcoming' }],
    },
    {
      id: 'in_progress',
      label: 'In Progress',
      color: 'blue',
      options: [{ value: 'active', label: 'Active', color: 'blue', group_id: 'in_progress' }],
    },
    {
      id: 'done',
      label: 'Done',
      color: 'green',
      options: [{ value: 'complete', label: 'Complete', color: 'green', group_id: 'done' }],
    },
  ],
}

const page = (id: string, title: string, path: string): Record<string, unknown> => ({
  kind: 'page',
  id,
  title,
  path,
})

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
        sets: [{ kind: 'set', id: 'sA1', title: 'A1', path: 'Col/A/A1', pages: [], sets: [] }],
      },
      { kind: 'set', id: 'sB', title: 'B', path: 'Col/B', pages: [], sets: [] },
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
        ...view,
      },
    ],
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
          hide_empty_groups: false,
        },
      },
    ],
  }) as unknown as CollectionNode

const VALUES = {
  p1: { id: 'p1', properties: { prop_status: { $status: 'active' } } },
  p2: { id: 'p2', properties: { prop_status: { $status: 'complete' } } },
}

let host: HTMLDivElement
let root: Root
let mutateSpy: ReturnType<typeof vi.fn>
let saveSpy: ReturnType<typeof vi.fn>
let selectSpy: ReturnType<typeof vi.fn>
let contextMenuSpy: ReturnType<typeof vi.fn>

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  mutateSpy = vi.fn(async () => true) // the reparent router gates its view write on this
  saveSpy = vi.fn(async () => ({ ok: true }))
  selectSpy = vi.fn(async () => {})
  contextMenuSpy = vi.fn(async () => {})
  ;(window as unknown as { nexus: unknown }).nexus = {
    loadValues: async () => VALUES,
    activeViews: { get: async () => ({}) },
    viewOrders: { get: async () => ({}) },
    views: { save: saveSpy },
    cellMenu: vi.fn(async () => null),
    columnMenu: vi.fn(async () => null),
    contextMenu: contextMenuSpy,
  }
  const pair = (singular: string, plural: string): { singular: string; plural: string } => ({
    singular,
    plural,
  })
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
        agendaEvent: pair('Event', 'Events'),
      },
    } as never,
    selection: { kind: 'none' } as never,
    select: selectSpy as never,
    renamingPath: null,
    mutate: mutateSpy as never,
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

const headerTexts = (): string[] =>
  [...host.querySelectorAll('.group-header')].map((el) => el.textContent ?? '')

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
  // A committed drop arms the one-tick post-drag click swallower — flush it so a test's
  // follow-up click isn't eaten (real clicks land a tick later anyway).
  await act(async () => {
    await new Promise((r) => setTimeout(r, 1))
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
    // Bands in configured schema order — Not started leads as an EMPTY band (no rows, hide off).
    await mountTable(propertySource())
    expect(headerTexts()[0]).toContain('Not started')
    expect(headerTexts()[1]).toContain('Active')
    await dragBand(2, 26) // Complete above Active
    await drop()
    expect(saveSpy).toHaveBeenCalledOnce()
    expect(lastSavedView().group).toEqual({
      kind: 'property',
      property_id: 'prop_status',
      order_mode: 'manual',
      order: ['not_started', 'complete', 'active'],
      empty_placement: 'bottom',
      hide_empty_groups: false,
    })
    expect(lastSavedView().group_order).toBeUndefined()
    expect(mutateSpy).not.toHaveBeenCalled()
    expect(headerTexts()[1]).toContain('Complete')
  })
})

describe('location order mode (structural_order_mode: location)', () => {
  it('same-parent band reorder writes reorderChildren — group_order untouched', async () => {
    await mountTable(
      structuralSource({ collapsed_groups: ['sA'], structural_order_mode: 'location' }),
    ) // bands: A (collapsed), B
    await dragBand(1, 2) // B above A
    await drop()
    expect(mutateSpy).toHaveBeenCalledExactlyOnceWith({
      op: 'reorderChildren',
      parentPath: 'Col',
      key: 'set_order',
      order: ['sB', 'sA'],
    })
    expect(saveSpy).not.toHaveBeenCalled()
  })

  it('cross-tree reparent still writes group_order after moveSet (slot preservation, mode-blind)', async () => {
    await mountTable(structuralSource({ structural_order_mode: 'location' })) // bands: A, A1, B
    await dragBand(2, 12) // nest B into A
    await drop()
    expect(mutateSpy).toHaveBeenCalledExactlyOnceWith({
      op: 'moveSet',
      path: 'Col/B',
      newParentPath: 'Col/A',
      order: ['sA1', 'sB'],
    })
    expect(saveSpy).toHaveBeenCalledOnce()
    expect(lastSavedView().group_order).toEqual(['sA', 'sA1', 'sB'])
  })
})

/** A[pA1 active, pA2 complete], B[pB active] — sub-grouped by status. */
const subGroupSource = (view?: Partial<SavedView>): CollectionNode =>
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
        pages: [page('pA1', 'A One', 'Col/A/A One.md'), page('pA2', 'A Two', 'Col/A/A Two.md')],
        sets: [],
      },
      {
        kind: 'set',
        id: 'sB',
        title: 'B',
        path: 'Col/B',
        pages: [page('pB', 'B One', 'Col/B/B One.md')],
        sets: [],
      },
    ],
    pages: [],
    properties: [statusDef],
    views: [
      {
        id: 'view_1',
        name: 'Table',
        type: 'table',
        property_order: ['_title', 'prop_status'],
        hidden_properties: [],
        group: { kind: 'structural' },
        sub_group: { property_id: 'prop_status', order_mode: 'manual' },
        ...view,
      },
    ],
  }) as unknown as CollectionNode

const SUB_VALUES = {
  pA1: { id: 'pA1', properties: { prop_status: { $status: 'active' } } },
  pA2: { id: 'pA2', properties: { prop_status: { $status: 'complete' } } },
  pB: { id: 'pB', properties: { prop_status: { $status: 'active' } } },
}

describe('sub-group bucket band drag', () => {
  beforeEach(() => {
    ;(window as unknown as { nexus: { loadValues: () => Promise<unknown> } }).nexus.loadValues =
      async () => SUB_VALUES
  })

  // bands: A(0), A/active(1), A/complete(2), B(3), B/active(4)
  it('manual mode: same-set bucket reorder writes the view-level global sub_group.order', async () => {
    await mountTable(subGroupSource())
    await dragBand(2, 26) // A/complete above A/active (top zone of band 1)
    await drop()
    expect(saveSpy).toHaveBeenCalledOnce()
    expect(lastSavedView().sub_group).toEqual({
      property_id: 'prop_status',
      order_mode: 'manual',
      order: ['complete', 'active'],
    })
    expect(mutateSpy).not.toHaveBeenCalled()
  })

  it('CROSS-SET bucket drag (arrives as reparent) still writes the global sub-order — no moveSet', async () => {
    await mountTable(subGroupSource())
    await dragBand(2, 98) // A/complete before B/active (top zone of band 4)
    await drop()
    expect(saveSpy).toHaveBeenCalledOnce()
    expect(lastSavedView().sub_group).toEqual({
      property_id: 'prop_status',
      order_mode: 'manual',
      order: ['complete', 'active'],
    })
    expect(mutateSpy).not.toHaveBeenCalled()
  })

  it('outside manual mode the bucket drag is inert', async () => {
    await mountTable(
      subGroupSource({ sub_group: { property_id: 'prop_status', order_mode: 'configured' } }),
    )
    await dragBand(2, 26)
    await drop()
    expect(saveSpy).not.toHaveBeenCalled()
    expect(mutateSpy).not.toHaveBeenCalled()
  })
})

describe('sub-group row drop (F-2 — the set × bucket matrix)', () => {
  beforeEach(() => {
    ;(window as unknown as { nexus: { loadValues: () => Promise<unknown> } }).nexus.loadValues =
      async () => SUB_VALUES
  })

  /** Rects: table-dnd box + each data-row stacked at 24px from y=100 (pA1, pA2, pB in DOM order). */
  const stubRowRects = (): void => {
    const box = host.querySelector('.table-dnd')
    if (box) stubRect(box, { top: 0, bottom: 400 })
    const rows = host.querySelectorAll('.data-row')
    for (const [i, el] of [...rows].entries())
      stubRect(el, { top: 100 + i * 24, bottom: 100 + i * 24 + 24 })
  }
  const dragRow = async (index: number, toY: number): Promise<void> => {
    const grips = host.querySelectorAll('.row-grip')
    await act(async () => {
      firePointer(grips[index], 'pointerdown', { x: 5, y: 100 + index * 24 + 12 })
    })
    await act(async () => {
      firePointer(window, 'pointermove', { x: 5, y: toY })
    })
    await drop()
  }

  it('different set + different bucket → setProperty THEN movePage', async () => {
    await mountTable(subGroupSource())
    stubRowRects()
    await dragRow(1, 160) // pA2 (sA/complete) into pB's region (sB/active)
    expect(mutateSpy).toHaveBeenNthCalledWith(1, {
      op: 'setProperty',
      path: 'Col/A/A Two.md',
      propertyId: 'prop_status',
      value: { kind: 'status', value: 'active' },
    })
    expect(mutateSpy).toHaveBeenNthCalledWith(2, {
      op: 'movePage',
      path: 'Col/A/A Two.md',
      newParentPath: 'Col/B',
    })
  })

  it('same set, different bucket → setProperty alone', async () => {
    await mountTable(subGroupSource())
    stubRowRects()
    await dragRow(1, 105) // pA2 (sA/complete) into pA1's region (sA/active)
    expect(mutateSpy).toHaveBeenCalledExactlyOnceWith({
      op: 'setProperty',
      path: 'Col/A/A Two.md',
      propertyId: 'prop_status',
      value: { kind: 'status', value: 'active' },
    })
  })

  it('different set, same bucket → movePage alone', async () => {
    await mountTable(subGroupSource())
    stubRowRects()
    await dragRow(2, 105) // pB (sB/active) into pA1's region (sA/active)
    expect(mutateSpy).toHaveBeenCalledExactlyOnceWith({
      op: 'movePage',
      path: 'Col/B/B One.md',
      newParentPath: 'Col/A',
    })
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
      order: ['sA1', 'sB'], // current children + APPEND — never the visual slot (C-4)
    })
    expect(saveSpy).toHaveBeenCalledOnce()
    expect(lastSavedView().group_order).toEqual(['sA', 'sA1', 'sB'])
  })

  it('a FAILED moveSet commits nothing — no phantom group_order, no optimistic reorder (F1)', async () => {
    mutateSpy.mockImplementation(async () => false)
    await mountTable(structuralSource())
    await dragBand(2, 12) // nest B into A
    await drop()
    expect(mutateSpy).toHaveBeenCalledOnce()
    expect(saveSpy).not.toHaveBeenCalled()
    expect(headerTexts()[0]).toContain('A')
  })

  it('a persist landing during the reparent round-trip is not clobbered by the deferred commit (F3)', async () => {
    let resolveMove: (v: boolean) => void = () => {}
    mutateSpy.mockImplementation(
      () =>
        new Promise((r) => {
          resolveMove = r
        }),
    )
    await mountTable(structuralSource())
    await dragBand(2, 12) // nest B into A — the commit defers behind the fs round-trip
    await drop()
    // Mid-flight, the user collapses a group (a sibling persist with fresh state).
    const twisty = host.querySelectorAll('.group-twisty')[0]
    await act(async () => {
      ;(twisty as HTMLElement).click()
    })
    const collapsedAtToggle = (saveSpy.mock.calls.at(-1)?.[2] as SavedView).collapsed_groups
    await act(async () => {
      resolveMove(true)
    })
    const final = lastSavedView()
    expect(final.group_order).toEqual(['sA', 'sA1', 'sB'])
    expect(final.collapsed_groups).toEqual(collapsedAtToggle)
  })

  it('a de-nest between-slot reparents to the container root', async () => {
    await mountTable(structuralSource())
    await dragBand(1, 50) // A1 → bottom half of B's zone? y=50 sits in B's top zone (48–72) → before B at root
    await drop()
    expect(mutateSpy).toHaveBeenCalledExactlyOnceWith({
      op: 'moveSet',
      path: 'Col/A/A1',
      newParentPath: 'Col',
      order: ['sA', 'sB', 'sA1'],
    })
    expect(lastSavedView().group_order).toEqual(['sA', 'sA1', 'sB'])
  })
})

describe('band header — the sidebar interaction model', () => {
  const glyphOf = (label: string): HTMLElement => {
    const header = [...host.querySelectorAll('.group-header')].find((h) =>
      h.textContent?.includes(label),
    )
    return header?.querySelector('.band-glyph') as HTMLElement
  }
  const headerOf = (label: string): HTMLElement =>
    [...host.querySelectorAll('.group-header')].find((h) =>
      h.textContent?.includes(label),
    ) as HTMLElement

  it('a single glyph click toggles the disclosure (persisted)', async () => {
    await mountTable(structuralSource())
    await act(async () => {
      glyphOf('A').dispatchEvent(new MouseEvent('click', { bubbles: true }))
    })
    expect(lastSavedView().collapsed_groups ?? []).toContain('sA')
  })

  it('double-clicking an openable Set band selects it; a sub-Set band does not', async () => {
    await mountTable(structuralSource())
    await act(async () => {
      glyphOf('A').dispatchEvent(new MouseEvent('dblclick', { bubbles: true }))
    })
    expect(selectSpy).toHaveBeenCalledWith({ kind: 'set', id: 'sA', path: 'Col/A' })
    selectSpy.mockClear()
    await act(async () => {
      glyphOf('A1').dispatchEvent(new MouseEvent('dblclick', { bubbles: true }))
    })
    expect(selectSpy).not.toHaveBeenCalled()
  })

  it('right-clicking a Set band pops the native set context menu', async () => {
    await mountTable(structuralSource())
    await act(async () => {
      headerOf('B').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))
    })
    expect(contextMenuSpy).toHaveBeenCalledWith({ kind: 'set', path: 'Col/B', title: 'B' })
  })

  it('the store rename flow renders the inline input in the band and commits a rename mutate', async () => {
    await mountTable(structuralSource())
    await act(async () => {
      useSession.setState({ renamingPath: 'Col/A' })
    })
    const input = host.querySelector('.band-title-input') as HTMLInputElement
    expect(input).toBeTruthy()
    await act(async () => {
      Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set?.call(
        input,
        'Alpha',
      )
      input.dispatchEvent(new Event('input', { bubbles: true }))
      input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
      input.blur()
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'rename',
      path: 'Col/A',
      kind: 'set',
      newName: 'Alpha',
    })
  })
})
