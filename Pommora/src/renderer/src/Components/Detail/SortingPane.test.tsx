// @vitest-environment jsdom
// State-level pane tests: the row stack per sort state + the wholesale write shapes. Visual truth = CDP.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { CollectionNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type { SavedView } from '@shared/views'
import { useSession } from '../../store'
import { SortingPane } from './SortingPane'
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
      id: 'g1',
      label: 'Open',
      color: 'gray',
      options: [
        { value: 'todo', label: 'Todo', group_id: 'g1' },
        { value: 'done', label: 'Done', group_id: 'g1' },
      ],
    },
  ],
}
const dateDef: PropertyDefinition = { id: 'prop_when', name: 'When', type: 'datetime' }
const fileDef: PropertyDefinition = { id: 'prop_file', name: 'Attachment', type: 'file' }
const checkDef: PropertyDefinition = { id: 'prop_check', name: 'Checked', type: 'checkbox' }
const schema = [statusDef, dateDef, fileDef, checkDef]

const view = (over?: Partial<SavedView>): SavedView => ({
  id: 'view_1',
  name: 'Table',
  type: 'table',
  property_order: ['_title'],
  hidden_properties: [],
  ...over,
})

const source = {
  kind: 'collection',
  id: 'col1',
  title: 'Col',
  path: 'Col',
  sets: [],
  pages: [],
  properties: schema,
} as unknown as CollectionNode

let host: HTMLDivElement
let root: Root
let saveSpy: ReturnType<typeof vi.fn>

const mount = async (v: SavedView): Promise<void> => {
  await act(async () => {
    root.render(
      <SortingPane source={source} view={v} schema={schema} label="Settings" onBack={() => {}} />,
    )
  })
}
const texts = (): string => host.textContent ?? ''
const click = async (el: Element | null | undefined): Promise<void> => {
  await act(async () => {
    ;(el as HTMLElement).click()
  })
}
const rowWithText = (t: string): Element | undefined =>
  [...host.querySelectorAll('*')].filter((el) => el.textContent === t).at(-1)

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  saveSpy = vi.fn(async () => ({ ok: true }))
  ;(window as unknown as { nexus: unknown }).nexus = {
    views: { save: saveSpy },
    activeViews: { set: vi.fn(async () => {}) },
  }
  useSession.setState({ load: vi.fn(async () => {}) as never })
})
afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

const lastSaved = (): SavedView => saveSpy.mock.calls.at(-1)?.[2] as SavedView

describe('SortingPane rows', () => {
  it('unsorted: Sort By reads None; no Order or Sub-Sort rows', async () => {
    await mount(view())
    expect(texts()).toContain('Sort By')
    expect(texts()).toContain('None')
    expect(texts()).not.toContain('Order')
    expect(texts()).not.toContain('Sub-Sort')
  })

  it('the disclosure lists None + Title + Modified + sortable defs, excluding file, and a pick writes slot 0', async () => {
    await mount(view())
    await click(rowWithText('Sort By')?.closest('[class]'))
    expect(texts()).toContain('Title')
    expect(texts()).toContain('Modified')
    expect(texts()).toContain('Status')
    expect(texts()).toContain('When')
    expect(texts()).not.toContain('Attachment') // file sorts to a no-op — never offered
    await click(rowWithText('Status')?.closest('[class]'))
    expect(lastSaved().sort).toEqual([{ property_id: 'prop_status', direction: 'ascending' }])
  })

  it('per-type Order labels: status reads Default, datetime reads Ascending', async () => {
    await mount(view({ sort: [{ property_id: 'prop_status', direction: 'ascending' }] }))
    expect(texts()).toContain('Order')
    expect(texts()).toContain('Default')
    await mount(view({ sort: [{ property_id: 'prop_when', direction: 'ascending' }] }))
    expect(texts()).toContain('Ascending')
  })

  it('a Sub-Sort pick writes slot 1 and its sub Order reads Default/Reversed', async () => {
    await mount(view({ sort: [{ property_id: 'prop_when', direction: 'ascending' }] }))
    const trigger = host.querySelector('button[aria-label="Sub-Sort"]') as HTMLElement
    await click(trigger)
    await click(
      [...document.querySelectorAll('button')].find((el) => el.textContent?.includes('Status')),
    )
    expect(lastSaved().sort).toEqual([
      { property_id: 'prop_when', direction: 'ascending' },
      { property_id: 'prop_status', direction: 'ascending' },
    ])
    await mount(
      view({
        sort: [
          { property_id: 'prop_when', direction: 'ascending' },
          { property_id: 'prop_status', direction: 'descending' },
        ],
      }),
    )
    expect(texts()).toContain('Reversed') // the sub Order shares the primary's per-type vocabulary
    await mount(
      view({
        sort: [
          { property_id: 'prop_when', direction: 'ascending' },
          { property_id: 'prop_check', direction: 'descending' },
        ],
      }),
    )
    expect(texts()).toContain('Descending') // a checkbox sub reads the value vocabulary
  })

  it('None on Sort By writes sort: undefined — never []', async () => {
    await mount(view({ sort: [{ property_id: 'prop_status', direction: 'ascending' }] }))
    await click(rowWithText('Sort By')?.closest('[class]'))
    await click(rowWithText('None')?.closest('[class]'))
    expect(saveSpy).toHaveBeenCalled()
    expect(lastSaved().sort).toBeUndefined()
  })

  it('a pane write over a foreign 3-key array replaces the slot wholesale', async () => {
    await mount(
      view({
        sort: [
          { property_id: 'prop_when', direction: 'ascending' },
          { property_id: 'prop_status', direction: 'ascending' },
          { property_id: '_title', direction: 'descending' },
        ],
      }),
    )
    await click(rowWithText('Sort By')?.closest('[class]'))
    await click(rowWithText('Title')?.closest('[class]'))
    expect(lastSaved().sort).toEqual([
      { property_id: '_title', direction: 'ascending' },
      { property_id: 'prop_status', direction: 'ascending' },
    ])
  })

  it('a _title primary renders its name + Order row, not the dead-def fallback', async () => {
    await mount(view({ sort: [{ property_id: '_title', direction: 'ascending' }] }))
    expect(texts()).toContain('Title')
    expect(texts()).toContain('A → Z')
    expect(texts()).not.toContain('_title')
  })

  it('Custom on an option primary seeds the current sequence; the middle becomes the draggable Options list', async () => {
    await mount(view({ sort: [{ property_id: 'prop_status', direction: 'descending' }] }))
    const trigger = host.querySelectorAll('button[aria-label="Order"]')[0] as HTMLElement
    await click(trigger)
    await click([...document.querySelectorAll('button')].find((el) => el.textContent === 'Custom'))
    expect(lastSaved().sort).toEqual([
      { property_id: 'prop_status', direction: 'descending', order: ['done', 'todo'] }, // seeded reversed
    ])
    await mount(
      view({
        sort: [{ property_id: 'prop_status', direction: 'ascending', order: ['done', 'todo'] }],
      }),
    )
    expect(texts()).toContain('Custom')
    expect(texts()).toContain('Options') // the draggable CustomList heading
    expect(texts().indexOf('Done')).toBeLessThan(texts().indexOf('Todo'))
  })

  it('Default strips a custom order back off the criterion', async () => {
    await mount(
      view({
        sort: [{ property_id: 'prop_status', direction: 'ascending', order: ['done', 'todo'] }],
      }),
    )
    const trigger = host.querySelectorAll('button[aria-label="Order"]')[0] as HTMLElement
    await click(trigger)
    await click([...document.querySelectorAll('button')].find((el) => el.textContent === 'Default'))
    expect(lastSaved().sort).toEqual([{ property_id: 'prop_status', direction: 'ascending' }])
  })

  it('a status primary shows the example order; Reversed flips the run', async () => {
    await mount(view({ sort: [{ property_id: 'prop_status', direction: 'ascending' }] }))
    expect(texts()).toContain('Open') // the status group heading
    expect(texts().indexOf('Todo')).toBeLessThan(texts().indexOf('Done'))
    await mount(view({ sort: [{ property_id: 'prop_status', direction: 'descending' }] }))
    expect(texts().indexOf('Done')).toBeLessThan(texts().indexOf('Todo'))
  })

  it('a datetime primary collapses the example middle', async () => {
    await mount(view({ sort: [{ property_id: 'prop_when', direction: 'ascending' }] }))
    expect(texts()).not.toContain('Todo')
    expect(texts()).not.toContain('Open')
  })

  it('a dead primary shows its raw id and None still clears it', async () => {
    await mount(view({ sort: [{ property_id: 'prop_gone', direction: 'ascending' }] }))
    expect(texts()).toContain('prop_gone')
    await click(rowWithText('Sort By')?.closest('[class]'))
    await click(rowWithText('None')?.closest('[class]'))
    expect(lastSaved().sort).toBeUndefined()
  })
})
