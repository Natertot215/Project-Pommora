// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { PropertyDefinition } from '@shared/properties'
import { useSession } from '../../store'
import { PropertiesPane } from './PropertiesPane'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
;(globalThis as { ResizeObserver?: unknown }).ResizeObserver = ResizeObserverStub

const defs: PropertyDefinition[] = [
  { id: 'prop_status', name: 'Status', type: 'status' },
  { id: 'prop_n', name: 'Count', type: 'number' }
]

let host: HTMLDivElement
let root: Root
let loadSpy: ReturnType<typeof vi.fn>
let assignSpy: ReturnType<typeof vi.fn>

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  loadSpy = vi.fn(async () => {})
  assignSpy = vi.fn(async () => ({ ok: true }))
  ;(window as unknown as { nexus: unknown }).nexus = {
    schema: {
      add: vi.fn(async () => ({ ok: true, id: 'prop_new' })),
      rename: vi.fn(async () => ({ ok: true })),
      reorder: vi.fn(async () => ({ ok: true })),
      delete: vi.fn(async () => ({ ok: true })),
      assign: assignSpy,
      changeType: vi.fn(async () => ({ ok: true }))
    },
    showError: vi.fn(async () => {})
  }
  useSession.setState({ load: loadSpy as never, tree: { registry: [] } as never })
})
afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

const mountPane = async (schema: PropertyDefinition[] = defs): Promise<void> => {
  await act(async () => {
    root.render(<PropertiesPane collectionPath="Col" schema={schema} onBack={() => {}} />)
  })
}

/** The row whose title span reads exactly `name` (clicks bubble to the MenuItem div). */
const rowFor = (name: string): HTMLElement => {
  const span = [...host.querySelectorAll<HTMLElement>('span')].find((el) => el.textContent === name && el.children.length === 0)
  if (!span) throw new Error(`no row titled "${name}"`)
  return span
}

describe('the DRY nested slide (A-7)', () => {
  it('list → editor renders BOTH slots (inner PaneSlider keeps them mounted) with the editor active', async () => {
    await mountPane()
    await act(async () => {
      rowFor('Status').click()
    })
    const inertSlots = host.querySelectorAll('[inert]')
    expect(inertSlots.length).toBe(1) // exactly one inert slot = slider semantics, list mounted beneath
    expect(inertSlots[0].textContent).toContain('Count') // the inert slot IS the list
    expect(host.textContent).toContain('options — pending') // the editor is live in the active slot
  })

  it('the type picker rides the same slide', async () => {
    await mountPane()
    await act(async () => {
      host.querySelector<HTMLButtonElement>('[aria-label="New Property"]')!.click()
    })
    expect(host.querySelectorAll('[inert]').length).toBe(1)
    expect(host.textContent).toContain('Checkbox') // a CREATABLE_TYPES row is live
  })
})

const effortDef: PropertyDefinition = { id: 'prop_x', name: 'Effort', type: 'number' }
const titleDef: PropertyDefinition = { id: '_title', name: 'Title', type: 'url' }

describe('the All Properties section (T5)', () => {
  it('lists only unassigned, unreserved registry defs (A-4/E-5), in registry order (B-1)', async () => {
    useSession.setState({ tree: { registry: [effortDef, defs[0], titleDef] } as never })
    await mountPane([defs[0]]) // Status is assigned
    await act(async () => {
      rowFor('All Properties').click()
    })
    const all = host.querySelector('[data-group="all"]')
    expect(all).not.toBeNull()
    expect(all?.textContent).toContain('Effort')
    expect(all?.textContent).not.toContain('Status') // assigned — never in both groups
    expect(all?.textContent).not.toContain('Title') // reserved
  })

  it('+ assigns through the IPC and the row promotes on the refreshed schema', async () => {
    useSession.setState({ tree: { registry: [effortDef] } as never })
    await mountPane([])
    await act(async () => {
      rowFor('All Properties').click()
    })
    await act(async () => {
      host.querySelector<HTMLButtonElement>('[aria-label="Assign Effort"]')!.click()
    })
    expect(assignSpy).toHaveBeenCalledWith('Col', 'prop_x')
    expect(loadSpy).toHaveBeenCalled()
  })

  it('header ⊕ opens the type picker; the footer create-row is gone (A-9)', async () => {
    await mountPane()
    expect(host.textContent).not.toContain('New Property')
    await act(async () => {
      host.querySelector<HTMLButtonElement>('[aria-label="New Property"]')!.click()
    })
    expect(host.textContent).toContain('Checkbox')
  })

  it('the assigned group renders inside its region wrapper (T6 hangs rects on it)', async () => {
    await mountPane()
    const assigned = host.querySelector('[data-group="assigned"]')
    expect(assigned?.textContent).toContain('Status')
    expect(assigned?.textContent).toContain('Count')
  })
})
