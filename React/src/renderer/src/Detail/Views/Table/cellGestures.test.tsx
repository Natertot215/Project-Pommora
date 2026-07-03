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
const numberDef: PropertyDefinition = { id: 'prop_n', name: 'Count', type: 'number' }
const urlDef: PropertyDefinition = { id: 'prop_link', name: 'Link', type: 'url' }
const fileDef: PropertyDefinition = { id: 'prop_files', name: 'Files', type: 'file' }
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
    pages: [
      { kind: 'page', id: 'p1', title: 'Page One', path: 'Col/Page One.md' },
      { kind: 'page', id: 'p2', title: 'Page Two', path: 'Col/Page Two.md' }
    ],
    properties: [statusDef, checkboxDef, numberDef, urlDef, fileDef],
    views: [
      {
        id: 'view_1',
        name: 'Table',
        type: 'table',
        property_order: ['_title', 'prop_status', 'prop_done', 'prop_n', 'prop_link', 'prop_files', '_tier1'],
        hidden_properties: ['_modified_at'],
        ...(columnStyles ? { column_styles: columnStyles } : {})
      }
    ]
  }) as unknown as CollectionNode

const VALUES = {
  p1: {
    id: 'p1',
    properties: {
      prop_status: { $status: 'active' },
      prop_done: false,
      prop_n: 42,
      prop_link: 'https://old.com',
      prop_files: [{ path: 'Assets/trip.png' }]
    }
  },
  p2: { id: 'p2', properties: {} }
}

// React intercepts the value property — commit through the native setter so the change event carries.
const typeInto = (input: HTMLInputElement, value: string): void => {
  Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set?.call(input, value)
  input.dispatchEvent(new Event('input', { bubbles: true }))
}
const key = (input: HTMLElement, k: string): void => {
  input.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true }))
}

let host: HTMLDivElement
let root: Root
let mutateSpy: ReturnType<typeof vi.fn>
let selectSpy: ReturnType<typeof vi.fn>
let openFileSpy: ReturnType<typeof vi.fn>
let openExternalSpy: ReturnType<typeof vi.fn>

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  mutateSpy = vi.fn(async () => {})
  selectSpy = vi.fn(async () => {})
  openFileSpy = vi.fn(async () => ({ ok: true }))
  openExternalSpy = vi.fn(async () => {})
  ;(window as unknown as { nexus: unknown }).nexus = {
    loadValues: async () => VALUES,
    activeViews: { get: async () => ({}) },
    viewOrders: { get: async () => ({}) },
    views: { save: vi.fn(async () => ({ ok: true })) },
    cellMenu: vi.fn(async () => null),
    columnMenu: vi.fn(async () => null),
    openFile: openFileSpy,
    openExternal: openExternalSpy
  }
  const pair = (singular: string, plural: string): { singular: string; plural: string } => ({ singular, plural })
  useSession.setState({
    tree: {
      contexts: {
        areas: [
          { kind: 'area', id: 'area_work', title: 'Work', path: 'Contexts/Work', color: 'blue' },
          { kind: 'area', id: 'area_life', title: 'Personal', path: 'Contexts/Personal' }
        ],
        topics: [],
        projects: []
      },
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
    select: selectSpy as never,
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

  it('a single-value pick CLOSES the picker once its Bloom-out settles', async () => {
    await mountTable(sourceWith())
    await act(async () => {
      statusCell().click()
    })
    expect([...host.querySelectorAll('button')].some((b) => b.textContent?.includes('Complete'))).toBe(true)
    const option = [...host.querySelectorAll('button')].find((b) => b.textContent?.includes('Complete'))
    await act(async () => {
      option?.click()
    })
    // The exit presence holds the pane through its Bloom-out (380ms), then unmounts it.
    await act(async () => {
      await new Promise((r) => setTimeout(r, 450))
    })
    expect([...host.querySelectorAll('button')].some((b) => b.textContent?.includes('Not started'))).toBe(false)
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

  it('a VALUED checkbox-look status cell cycles the group directly — no picker', async () => {
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

  it('an EMPTY checkbox-look status cell never cycles — it opens the picker, options as capsules', async () => {
    await mountTable(sourceWith({ prop_status: { look: 'checkbox' } }))
    const emptyStatusCell = host.querySelectorAll<HTMLElement>('.data-row')[1].querySelectorAll<HTMLElement>('.data-cell')[1]
    await act(async () => {
      emptyStatusCell.click()
    })
    expect(mutateSpy).not.toHaveBeenCalled()
    const optionButtons = emptyStatusCell.querySelectorAll('button')
    expect(optionButtons.length).toBe(3)
    expect(emptyStatusCell.textContent).not.toContain('Active') // capsule options carry glyphs, not labels
    expect(optionButtons[0].querySelector('svg')).toBeTruthy()
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

  it('unchecking a checked box strips the property — no stored false', async () => {
    ;(window as unknown as { nexus: { loadValues: () => Promise<unknown> } }).nexus.loadValues = async () => ({
      p1: { id: 'p1', properties: { prop_done: true } },
      p2: { id: 'p2', properties: {} }
    })
    await mountTable(sourceWith())
    await act(async () => {
      host.querySelectorAll<HTMLElement>('.data-cell')[2].click()
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_done',
      value: null
    })
  })
})

describe('optimistic value persistence', () => {
  it('a just-assigned value survives a source-identity change (watcher echo) — the assign-vanish guard', async () => {
    await mountTable(sourceWith())
    const doneCell = (): HTMLElement => host.querySelectorAll<HTMLElement>('.data-cell')[2]
    // Check the box → optimistic valueOverride (prop_done: true); the check glyph shows.
    await act(async () => {
      doneCell().click()
    })
    expect(doneCell().querySelector('svg')).toBeTruthy()
    // A watcher self-echo re-mints `source`'s object identity (same id/path, so the container-open
    // effect stays put). The value override must NOT be dropped — else the glyph reverts to the frozen
    // pre-assign values, which is the ~1/10 assign-vanish this guards.
    await act(async () => {
      root.render(<TableView source={sourceWith()} />)
    })
    await act(async () => {})
    expect(doneCell().querySelector('svg')).toBeTruthy()
  })
})

describe('context tier cells', () => {
  const tierCell = (): HTMLElement => host.querySelectorAll<HTMLElement>('.data-cell')[6] // _tier1 last

  it('click opens the context picker listing the tier\'s contexts; toggling writes setTier', async () => {
    await mountTable(sourceWith())
    await act(async () => {
      tierCell().click()
    })
    expect(host.textContent).toContain('Work')
    expect(host.textContent).toContain('Personal')

    const work = [...tierCell().querySelectorAll('button')].find((b) => b.textContent?.includes('Work'))
    await act(async () => {
      work?.click()
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setTier',
      path: 'Col/Page One.md',
      tier: 1,
      contextIds: ['area_work']
    })
  })
})

describe('number cell inline editing', () => {
  const numberCell = (): HTMLElement => host.querySelectorAll<HTMLElement>('.data-cell')[3]

  const openEditor = async (): Promise<HTMLInputElement> => {
    await mountTable(sourceWith())
    await act(async () => {
      numberCell().click()
    })
    const input = numberCell().querySelector('input')
    expect(input).toBeTruthy()
    return input as HTMLInputElement
  }

  it('single-click mounts the editor seeded with the value; letters cannot be typed', async () => {
    const input = await openEditor()
    expect(input.value).toBe('42')
    await act(async () => {
      typeInto(input, '42a')
    })
    expect(input.value).toBe('42')
  })

  it('Enter commits the parsed number', async () => {
    const input = await openEditor()
    await act(async () => {
      typeInto(input, '43.5')
      key(input, 'Enter')
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_n',
      value: { kind: 'number', value: 43.5 }
    })
  })

  it('an empty commit clears the value', async () => {
    const input = await openEditor()
    await act(async () => {
      typeInto(input, '')
      key(input, 'Enter')
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_n',
      value: null
    })
  })

  it('Esc reverts without writing; blur commits', async () => {
    const input = await openEditor()
    await act(async () => {
      typeInto(input, '99')
      key(input, 'Escape')
    })
    expect(mutateSpy).not.toHaveBeenCalled()

    const again = await openEditor()
    await act(async () => {
      typeInto(again, '7')
      again.dispatchEvent(new FocusEvent('focusout', { bubbles: true }))
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_n',
      value: { kind: 'number', value: 7 }
    })
  })
})

describe('menu-entered editing', () => {
  it('url Edit normalizes a schemeless link on commit', async () => {
    await mountTable(sourceWith())
    ;(window.nexus as { cellMenu: unknown }).cellMenu = vi.fn(async () => 'cell:edit')
    const urlCell = host.querySelectorAll<HTMLElement>('.data-cell')[4]
    await act(async () => {
      urlCell.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))
    })
    const input = urlCell.querySelector('input') as HTMLInputElement
    expect(input.value).toBe('https://old.com')
    await act(async () => {
      typeInto(input, 'example.com')
      key(input, 'Enter')
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_link',
      value: { kind: 'url', value: 'https://example.com' }
    })
  })

  it('title Rename commits a rename op', async () => {
    await mountTable(sourceWith())
    ;(window.nexus as { cellMenu: unknown }).cellMenu = vi.fn(async () => 'title:rename')
    const titleCell = host.querySelectorAll<HTMLElement>('.data-cell')[0]
    await act(async () => {
      titleCell.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))
    })
    const input = titleCell.querySelector('input') as HTMLInputElement
    expect(input.value).toBe('Page One')
    await act(async () => {
      typeInto(input, 'Renamed Page')
      key(input, 'Enter')
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'rename',
      path: 'Col/Page One.md',
      kind: 'page',
      newName: 'Renamed Page'
    })
  })
})

describe('open actions + row-click narrowing (A-7)', () => {
  it('title cell click navigates; row background click does not', async () => {
    await mountTable(sourceWith())
    const cells = host.querySelectorAll<HTMLElement>('.data-cell')
    await act(async () => {
      cells[0].click()
    })
    expect(selectSpy).toHaveBeenCalledWith({ kind: 'page', id: 'p1', path: 'Col/Page One.md' })

    selectSpy.mockClear()
    const row = host.querySelector<HTMLElement>('.data-row')
    await act(async () => {
      row?.click()
    })
    expect(selectSpy).not.toHaveBeenCalled()
  })

  it('url cell click opens externally through the sanctioned IPC, not navigation', async () => {
    await mountTable(sourceWith())
    const link = host.querySelector<HTMLElement>('.cell-link')
    await act(async () => {
      link?.click()
    })
    expect(openExternalSpy).toHaveBeenCalledWith('https://old.com')
    expect(selectSpy).not.toHaveBeenCalled()
  })

  it('file chip click opens the file under the nexus root', async () => {
    await mountTable(sourceWith())
    const chip = [...host.querySelectorAll<HTMLElement>('.data-cell')[5].querySelectorAll('span')]
      .filter((s) => s.textContent?.includes('trip.png'))
      .at(-1)
    await act(async () => {
      chip?.click()
    })
    expect(openFileSpy).toHaveBeenCalledWith('Assets/trip.png')
    expect(selectSpy).not.toHaveBeenCalled()
  })
})

describe('PropertyPicker (direct mount) — untouched seed', () => {
  it('a seed-only status def pickers empty — scaffolding is not defined options', async () => {
    const { defaultStatusSeed } = await import('@shared/properties')
    const seedDef: PropertyDefinition = {
      id: 'prop_seed',
      name: 'Status',
      type: 'status',
      status_groups: defaultStatusSeed()
    }
    await act(async () => {
      root.render(
        <PropertyPicker
          def={seedDef}
          current={null}
          closing={false}
          onCommit={vi.fn()}
          onDismiss={vi.fn()}
        />
      )
    })
    expect(host.querySelectorAll('button').length).toBe(0)
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

describe('chip hover × — the per-chip remove (pill looks only)', () => {
  const chipSource = (): CollectionNode =>
    ({
      kind: 'collection',
      id: 'col1',
      title: 'Col',
      path: 'Col',
      sets: [],
      pages: [{ kind: 'page', id: 'p1', title: 'Page One', path: 'Col/Page One.md' }],
      properties: [statusDef, multiDef],
      views: [
        {
          id: 'view_1',
          name: 'Table',
          type: 'table',
          property_order: ['_title', 'prop_status', 'prop_tags', '_tier1'],
          hidden_properties: ['_modified_at']
        }
      ]
    }) as unknown as CollectionNode

  const mountChips = async (): Promise<void> => {
    ;(window.nexus as { loadValues: unknown }).loadValues = async () => ({
      p1: {
        id: 'p1',
        tier1: ['area_work', 'area_life'],
        properties: { prop_status: { $status: 'active' }, prop_tags: ['a', 'b'] }
      }
    })
    await mountTable(chipSource())
  }
  const cell = (i: number): HTMLElement => host.querySelectorAll<HTMLElement>('.data-cell')[i]
  const removesIn = (el: HTMLElement): HTMLElement[] => [...el.querySelectorAll<HTMLElement>('[aria-label="Remove"]')]

  it('a status pill × clears the property — and never opens the picker', async () => {
    await mountChips()
    const [x] = removesIn(cell(1))
    expect(x).toBeTruthy()
    await act(async () => {
      x.click()
    })
    expect(mutateSpy).toHaveBeenCalledTimes(1)
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_status',
      value: null
    })
    expect(host.textContent).not.toContain('Not started') // no picker options mounted
  })

  it('a multi-select pill × removes just THAT option', async () => {
    await mountChips()
    const removes = removesIn(cell(2))
    expect(removes.length).toBe(2) // one × per pill
    await act(async () => {
      removes[0].click()
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_tags',
      value: { kind: 'multiSelect', value: ['b'] }
    })
  })

  it('removing the LAST multi option commits the emptied value (whose write deletes the key)', async () => {
    ;(window.nexus as { loadValues: unknown }).loadValues = async () => ({
      p1: { id: 'p1', properties: { prop_tags: ['a'] } }
    })
    await mountTable(chipSource())
    const [x] = removesIn(cell(2))
    await act(async () => {
      x.click()
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setProperty',
      path: 'Col/Page One.md',
      propertyId: 'prop_tags',
      value: { kind: 'multiSelect', value: [] }
    })
  })

  it('a tier context chip × writes setTier with the remaining ids', async () => {
    await mountChips()
    const removes = removesIn(cell(3))
    expect(removes.length).toBe(2)
    await act(async () => {
      removes[0].click()
    })
    expect(mutateSpy).toHaveBeenCalledWith({
      op: 'setTier',
      path: 'Col/Page One.md',
      tier: 1,
      contextIds: ['area_life']
    })
  })

  it('capsule + checkbox status looks carry NO × — Clear lives in their menu', async () => {
    ;(window.nexus as { loadValues: unknown }).loadValues = async () => ({
      p1: { id: 'p1', properties: { prop_status: { $status: 'active' } } }
    })
    const styled = chipSource()
    ;(styled.views as Array<{ column_styles?: unknown }>)[0].column_styles = { prop_status: { look: 'capsule' } }
    await mountTable(styled)
    expect(removesIn(cell(1)).length).toBe(0)
  })
})
