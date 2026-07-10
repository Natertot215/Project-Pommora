// @vitest-environment jsdom
// State-level pane tests: decode → row stack, the wholesale write shapes, disable + lock. Visual
// truth = CDP.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { CollectionNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type { SavedView } from '@shared/views'
import { useSession } from '../../store'
import { FilterPane } from './FilterPane'
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
        { value: 'done', label: 'Done', group_id: 'g1' }
      ]
    }
  ]
}
const checkDef: PropertyDefinition = { id: 'prop_check', name: 'Archived', type: 'checkbox' }
const schema = [statusDef, checkDef]

const view = (over?: Partial<SavedView>): SavedView => ({
  id: 'view_1',
  name: 'Table',
  type: 'table',
  property_order: ['_title'],
  hidden_properties: [],
  ...over
})

const source = {
  kind: 'collection',
  id: 'col1',
  title: 'Col',
  path: 'Col',
  sets: [],
  pages: [],
  properties: schema
} as unknown as CollectionNode

let host: HTMLDivElement
let root: Root
let saveSpy: ReturnType<typeof vi.fn>

const mount = async (v: SavedView): Promise<void> => {
  await act(async () => {
    root.render(<FilterPane source={source} view={v} schema={schema} tree={null} label="Settings" onBack={() => {}} />)
  })
}
const texts = (): string => host.textContent ?? ''
const click = async (el: Element | null | undefined): Promise<void> => {
  await act(async () => {
    ;(el as HTMLElement).click()
  })
}
// PickerMenu portals to body — options are queried document-wide.
const optionWithText = (t: string): Element | undefined =>
  [...document.querySelectorAll('[data-picker-portal] button, [data-picker-portal] [role]')]
    .concat([...document.body.querySelectorAll('button')])
    .filter((el) => el.textContent === t)
    .at(-1)

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
  document.body.innerHTML = ''
})

const lastSaved = (): SavedView => saveSpy.mock.calls.at(-1)?.[2] as SavedView

const twoRules = (): SavedView =>
  view({
    filter: {
      match: 'all',
      rules: [
        { property_id: 'prop_status', op: 'is', values: ['todo'] },
        { property_id: 'prop_check', op: 'is', value: 'true' }
      ]
    }
  })

describe('FilterPane', () => {
  it('renders Matches All + a row per decoded rule', async () => {
    await mount(twoRules())
    expect(texts()).toContain('Matches')
    expect(texts()).toContain('All')
    expect(texts()).toContain('Status')
    expect(texts()).toContain('Archived')
    expect(texts()).toContain('Is Checked')
  })

  it('Matches → None writes the lossless wrap and dims the region', async () => {
    await mount(twoRules())
    await click([...host.querySelectorAll('button')].find((b) => b.getAttribute('aria-label') === 'Matches'))
    await click(optionWithText('None'))
    const filter = lastSaved().filter
    expect(filter?.match).toBe('none')
    expect(filter?.rules).toHaveLength(1)
    await mount(view({ filter: lastSaved().filter }))
    expect([...host.querySelectorAll('div')].some((d) => d.className.includes('disabled'))).toBe(true)
  })

  it('toggling a connector And→Or re-serializes to any-of-runs', async () => {
    await mount(twoRules())
    await click([...host.querySelectorAll('button')].find((b) => b.getAttribute('aria-label') === 'Toggle connector'))
    expect(lastSaved().filter).toEqual({
      match: 'any',
      rules: [
        { property_id: 'prop_status', op: 'is', values: ['todo'] },
        { property_id: 'prop_check', op: 'is', value: 'true' }
      ]
    })
  })

  it('a locked tree renders Reset and no rule grid; Reset clears the slot', async () => {
    await mount(
      view({
        filter: {
          match: 'all',
          rules: [{ property_id: 'prop_status', op: 'is', value: 'todo' }, { match: 'any', rules: [{ property_id: 'prop_check', op: 'is', value: 'true' }] }]
        }
      })
    )
    expect(texts()).toContain('Hand-authored filter')
    expect(texts()).toContain('Reset Filter')
    await click([...host.querySelectorAll('*')].find((el) => el.textContent === 'Reset Filter'))
    expect(lastSaved().filter).toBeUndefined()
  })

  it('"+" adds a draft without writing; picking a property writes the first operator', async () => {
    await mount(view())
    const plus = [...host.querySelectorAll('svg.lucide-plus')].at(0)?.closest('span')
    await click(plus)
    expect(saveSpy).not.toHaveBeenCalled()
    expect(texts()).toContain('Property')
    await click([...host.querySelectorAll('button')].find((b) => b.getAttribute('aria-label') === 'Filter property'))
    await click(optionWithText('Archived') ?? [...document.querySelectorAll('*')].filter((el) => el.textContent === 'Archived').at(-1))
    expect(lastSaved().filter).toEqual({
      match: 'all',
      rules: [{ property_id: 'prop_check', op: 'is', value: 'true' }]
    })
  })

  it('removing the first of two rows promotes the second to the lead slot', async () => {
    await mount(twoRules())
    await click([...host.querySelectorAll('button')].filter((b) => b.getAttribute('aria-label') === 'Remove filter').at(0))
    expect(lastSaved().filter).toEqual({
      match: 'all',
      rules: [{ property_id: 'prop_check', op: 'is', value: 'true' }]
    })
  })
})

describe('FilterPane value editors', () => {
  it('the chips picker toggles values[] and stays open — never a value key', async () => {
    await mount(view({ filter: { match: 'all', rules: [{ property_id: 'prop_status', op: 'is' }] } }))
    await click([...host.querySelectorAll('button')].find((b) => b.getAttribute('aria-label') === 'Filter values'))
    await click([...document.querySelectorAll('*')].filter((el) => el.textContent === 'Todo').at(-1))
    let rule = (lastSaved().filter as { rules: unknown[] }).rules[0] as Record<string, unknown>
    expect(rule.values).toEqual(['todo'])
    expect('value' in rule).toBe(false)
    // Stays open: the second option is still clickable without reopening.
    await mount(view({ filter: lastSaved().filter }))
    await click([...host.querySelectorAll('button')].find((b) => b.getAttribute('aria-label') === 'Filter values'))
    await click([...document.querySelectorAll('*')].filter((el) => el.textContent === 'Done').at(-1))
    rule = (lastSaved().filter as { rules: unknown[] }).rules[0] as Record<string, unknown>
    expect(rule.values).toEqual(['todo', 'done'])
  })

  it('a checkbox rule renders no value editor and its operator carries the clause', async () => {
    await mount(view({ filter: { match: 'all', rules: [{ property_id: 'prop_check', op: 'is', value: 'false' }] } }))
    expect(texts()).toContain("Isn't Checked")
    expect([...host.querySelectorAll('input')]).toHaveLength(0)
    expect([...host.querySelectorAll('button')].some((b) => b.getAttribute('aria-label') === 'Filter values')).toBe(false)
  })

  it('a text rule commits its input on Enter', async () => {
    await mount(view({ filter: { match: 'all', rules: [{ property_id: '_title', op: 'contains' }] } }))
    const input = host.querySelector('input')
    expect(input).toBeTruthy()
    await act(async () => {
      if (input) {
        input.value = 'idea'
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
      }
    })
    const rule = (lastSaved().filter as { rules: unknown[] }).rules[0] as Record<string, unknown>
    expect(rule.value).toBe('idea')
  })
})
