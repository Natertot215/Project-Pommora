// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { PropertyDefinition } from '@shared/properties'
import type { CollectionNode } from '@shared/types'
import { useSession } from '../../../store'
import { PropertyPicker } from '../PropertyEditing/PropertyPicker'
import { TableView } from './TableView'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
;(globalThis as { ResizeObserver?: unknown }).ResizeObserver = ResizeObserverStub

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
const checkboxDef: PropertyDefinition = { id: 'prop_done', name: 'Done', type: 'checkbox' }
const multiDef: PropertyDefinition = {
  id: 'prop_tags',
  name: 'Tags',
  type: 'multi_select',
  select_options: [
    { value: 'a', label: 'Alpha' },
    { value: 'b', label: 'Beta' }
  ]
}

const sourceWith = (columnStyles?: Record<string, { look?: string }>): CollectionNode =>
  ({
    kind: 'collection',
    id: 'col1',
    title: 'Col',
    path: 'Col',
    sets: [],
    pages: [{ kind: 'page', id: 'p1', title: 'Page One', path: 'Col/Page One.md' }],
    properties: [statusDef, checkboxDef],
    views: [
      {
        id: 'view_1',
        name: 'Table',
        type: 'table',
        property_order: ['_title', 'prop_status', 'prop_done'],
        hidden_properties: ['_modified_at'],
        ...(columnStyles ? { column_styles: columnStyles } : {})
      }
    ]
  }) as unknown as CollectionNode

const VALUES = {
  p1: { id: 'p1', properties: { prop_status: { $status: 'active' }, prop_done: false } }
}

let host: HTMLDivElement
let root: Root
let mutateSpy: ReturnType<typeof vi.fn>

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  mutateSpy = vi.fn(async () => {})
  ;(window as unknown as { nexus: unknown }).nexus = {
    loadValues: async () => VALUES,
    activeViews: { get: async () => ({}) },
    viewOrders: { get: async () => ({}) },
    views: { save: vi.fn(async () => ({ ok: true })) },
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
    select: vi.fn(async () => {}) as never,
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
  await act(async () => {}) // flush the loadValues/activeViews promises
}

const statusCell = (): HTMLElement => {
  const cells = host.querySelectorAll<HTMLElement>('.data-cell')
  return cells[1] // property_order: _title, prop_status, prop_done
}

describe('status cell gestures', () => {
  it('single-click opens the PropertyPicker with every option as a chip', async () => {
    await mountTable(sourceWith())
    await act(async () => {
      statusCell().click()
    })
    expect(host.textContent).toContain('Not started')
    expect(host.textContent).toContain('Complete')
    expect(mutateSpy).not.toHaveBeenCalled()
  })

  it('picking an option writes the status optimistically through setProperty', async () => {
    await mountTable(sourceWith())
    await act(async () => {
      statusCell().click()
    })
    const option = [...host.querySelectorAll('button')].find((b) => b.textContent?.includes('Complete'))
    expect(option).toBeTruthy()
    await act(async () => {
      option?.click()
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_status',
      value: { kind: 'status', value: 'complete' }
    })
  })

  it('a checkbox-look status cell cycles the group directly — no picker', async () => {
    await mountTable(sourceWith({ prop_status: { look: 'checkbox' } }))
    await act(async () => {
      statusCell().click()
    })
    expect(host.textContent).not.toContain('Not started') // no picker options
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_status',
      value: { kind: 'status', value: 'complete' } // active (in_progress) → done's first option
    })
  })
})

describe('checkbox cell gestures', () => {
  it('single-click toggles the checkbox value', async () => {
    await mountTable(sourceWith())
    const cells = host.querySelectorAll<HTMLElement>('.data-cell')
    await act(async () => {
      cells[2].click()
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_done',
      value: { kind: 'checkbox', value: true }
    })
  })
})

describe('PropertyPicker (direct mount) — multi-select', () => {
  it('toggles values, staying open, committing the full array each time', async () => {
    const onCommit = vi.fn()
    const onDismiss = vi.fn()
    await act(async () => {
      root.render(
        <PropertyPicker
          def={multiDef}
          current={{ kind: 'multiSelect', value: ['a'] }}
          closing={false}
          onCommit={onCommit}
          onDismiss={onDismiss}
        />
      )
    })
    const beta = [...host.querySelectorAll('button')].find((b) => b.textContent?.includes('Beta'))
    await act(async () => {
      beta?.click()
    })
    expect(onCommit).toHaveBeenCalledWith({ kind: 'multiSelect', value: ['a', 'b'] })
    expect(onDismiss).not.toHaveBeenCalled() // multi stays open

    const alpha = [...host.querySelectorAll('button')].find((b) => b.textContent?.includes('Alpha'))
    await act(async () => {
      alpha?.click()
    })
    expect(onCommit).toHaveBeenLastCalledWith({ kind: 'multiSelect', value: [] })
  })
})
