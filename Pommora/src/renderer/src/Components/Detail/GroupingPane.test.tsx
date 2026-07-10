// @vitest-environment jsdom
// State-level pane tests: the row stack per grouping mode + the write shapes. Visual truth = CDP.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { CollectionNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type { SavedView } from '@shared/views'
import { useSession } from '../../store'
import { GroupingPane } from './GroupingPane'
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
    { id: 'g1', label: 'Open', color: 'gray', options: [{ value: 'todo', label: 'Todo', group_id: 'g1' }] }
  ]
}
const dateDef: PropertyDefinition = { id: 'prop_when', name: 'When', type: 'datetime' }

const view = (over?: Partial<SavedView>): SavedView => ({
  id: 'view_1',
  name: 'Table',
  type: 'table',
  property_order: ['_title'],
  hidden_properties: [],
  group: { kind: 'structural' },
  ...over
})

const source = {
  kind: 'collection',
  id: 'col1',
  title: 'Col',
  path: 'Col',
  sets: [],
  pages: [],
  properties: [statusDef, dateDef]
} as unknown as CollectionNode

let host: HTMLDivElement
let root: Root
let saveSpy: ReturnType<typeof vi.fn>

const mount = async (v: SavedView): Promise<void> => {
  await act(async () => {
    root.render(<GroupingPane source={source} view={v} schema={[statusDef, dateDef]} label="Settings" onBack={() => {}} />)
  })
}
const texts = (): string => host.textContent ?? ''

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  saveSpy = vi.fn(async () => ({ ok: true }))
  ;(window as unknown as { nexus: unknown }).nexus = {
    views: { save: saveSpy },
    activeViews: { set: vi.fn(async () => {}) }
  }
  useSession.setState({ load: vi.fn(async () => {}) as never })
})
afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

const lastSaved = (): SavedView => saveSpy.mock.calls.at(-1)?.[2] as SavedView

describe('GroupingPane rows', () => {
  it('structural: Group By Location + Order (Custom) + Sub-Group; no Date By', async () => {
    await mount(view())
    expect(texts()).toContain('Group By')
    expect(texts()).toContain('Location')
    expect(texts()).toContain('Order')
    expect(texts()).toContain('Sub-Group')
    expect(texts()).toContain('Custom')
    expect(texts()).not.toContain('Date By')
  })

  it('date property grouping: Date By renders with Month; Sub-Group hides', async () => {
    await mount(
      view({
        group: { kind: 'property', property_id: 'prop_when', order_mode: 'configured', empty_placement: 'bottom', hide_empty_groups: false }
      })
    )
    expect(texts()).toContain('Date By')
    expect(texts()).toContain('Month')
    expect(texts()).not.toContain('Sub-Group')
  })

  it('sub-grouped: the Sub-Order row appears and a date sub-group grows its own Date By', async () => {
    await mount(view({ sub_group: { property_id: 'prop_when', order_mode: 'configured' } }))
    expect(texts()).toContain('Sub-Group')
    expect(texts()).toContain('Date By')
    expect(texts()).toContain('Ascending')
  })

  it('the Group By disclosure lists Location + groupable properties and a pick writes the group', async () => {
    await mount(view())
    const groupByRow = [...host.querySelectorAll('*')].find((el) => el.textContent === 'Group By')
    await act(async () => {
      ;(groupByRow!.closest('[class]') as HTMLElement).click()
    })
    expect(texts()).toContain('Status')
    expect(texts()).toContain('When')
    const statusOption = [...host.querySelectorAll('*')].filter((el) => el.textContent === 'Status').at(-1)
    await act(async () => {
      ;(statusOption!.closest('[class]') as HTMLElement).click()
    })
    expect(lastSaved().group).toMatchObject({ kind: 'property', property_id: 'prop_status', order_mode: 'configured' })
  })

  it('structural: the middle region lists the set hierarchy; sub-grouped flattens it', async () => {
    const nested = {
      ...source,
      sets: [
        { kind: 'set', id: 'sA', title: 'Alpha', path: 'Col/Alpha', pages: [], sets: [{ kind: 'set', id: 'sA1', title: 'Nested', path: 'Col/Alpha/Nested', pages: [], sets: [] }] },
        { kind: 'set', id: 'sB', title: 'Beta', path: 'Col/Beta', pages: [], sets: [] }
      ]
    } as unknown as CollectionNode
    await act(async () => {
      root.render(<GroupingPane source={nested} view={view()} schema={[statusDef, dateDef]} label="Settings" onBack={() => {}} />)
    })
    expect(texts()).toContain('Alpha')
    expect(texts()).not.toContain('Nested') // sub-groups hidden by default — disclose on demand
    expect(texts()).toContain('Beta')
    const alphaRow = [...host.querySelectorAll('*')].filter((el) => el.textContent === 'Alpha').at(-1)
    await act(async () => {
      ;(alphaRow!.closest('[class]') as HTMLElement).click()
    })
    expect(texts()).toContain('Nested') // disclosed
    await act(async () => {
      root.render(
        <GroupingPane
          source={nested}
          view={view({ sub_group: { property_id: 'prop_status', order_mode: 'configured' } })}
          schema={[statusDef, dateDef]}
          label="Settings"
          onBack={() => {}}
        />
      )
    })
    expect(texts()).toContain('Alpha')
    expect(texts()).not.toContain('Nested') // F-3: flat set list under sub-grouping
  })

  it('footings: Ungrouped always; Hide Empty Groups under property grouping; Separation under numeric date formats', async () => {
    await mount(view())
    expect(texts()).toContain('Ungrouped')
    expect(texts()).not.toContain('Hide Empty Groups')
    expect(texts()).not.toContain('Separation')
    await mount(
      view({
        group: { kind: 'property', property_id: 'prop_status', order_mode: 'configured', empty_placement: 'bottom', hide_empty_groups: false }
      })
    )
    expect(texts()).toContain('Hide Empty Groups')
    await mount(
      view({
        group: { kind: 'property', property_id: 'prop_when', order_mode: 'configured', empty_placement: 'bottom', hide_empty_groups: false },
        column_styles: { prop_when: { date_format: 'monthDayYear' } }
      })
    )
    expect(texts()).toContain('Separation')
  })

  it('the Ungrouped footing writes ungrouped_placement through its picker', async () => {
    await mount(view())
    const trigger = host.querySelector('button[aria-label="Ungrouped"]') as HTMLElement
    await act(async () => {
      trigger.click()
    })
    const top = [...document.querySelectorAll('button')].find((el) => el.textContent === 'Top')
    await act(async () => {
      top!.click()
    })
    expect(lastSaved().ungrouped_placement).toBe('top')
  })

  it('status default order shows the grouped read-only preview; custom shows the flat Options list', async () => {
    await mount(
      view({
        group: { kind: 'property', property_id: 'prop_status', order_mode: 'configured', empty_placement: 'bottom', hide_empty_groups: false }
      })
    )
    expect(texts()).toContain('Open') // the status group heading
    expect(texts()).toContain('Todo')
    expect(texts()).not.toContain('Options')
    await mount(
      view({
        group: { kind: 'property', property_id: 'prop_status', order_mode: 'manual', empty_placement: 'bottom', hide_empty_groups: false }
      })
    )
    expect(texts()).toContain('Options')
    expect(texts()).toContain('Todo')
  })

  it('a dead-property grouping wears the structural chrome (the pipeline fallback, mirrored)', async () => {
    await mount(
      view({
        group: { kind: 'property', property_id: 'prop_gone', order_mode: 'configured', empty_placement: 'bottom', hide_empty_groups: false }
      })
    )
    expect(texts()).toContain('Location') // the truthful label — the table IS structural
    expect(texts()).toContain('Sub-Group')
    expect(texts()).not.toContain('Hide Empty Groups')
  })

  it('switching Group By away and back preserves sub_group (view-level survival)', async () => {
    const v = view({ sub_group: { property_id: 'prop_status', order_mode: 'manual', order: ['todo'] } })
    await mount(v)
    const groupByRow = [...host.querySelectorAll('*')].find((el) => el.textContent === 'Group By')
    await act(async () => {
      ;(groupByRow!.closest('[class]') as HTMLElement).click()
    })
    const statusOption = [...host.querySelectorAll('*')].filter((el) => el.textContent === 'Status').at(-1)
    await act(async () => {
      ;(statusOption!.closest('[class]') as HTMLElement).click()
    })
    // the write replaced only `group`; the view-level sub_group rode through untouched
    expect(lastSaved().sub_group).toEqual({ property_id: 'prop_status', order_mode: 'manual', order: ['todo'] })
  })
})
