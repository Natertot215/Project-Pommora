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

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  loadSpy = vi.fn(async () => {})
  ;(window as unknown as { nexus: unknown }).nexus = {
    schema: {
      add: vi.fn(async () => ({ ok: true, id: 'prop_new' })),
      rename: vi.fn(async () => ({ ok: true })),
      reorder: vi.fn(async () => ({ ok: true })),
      delete: vi.fn(async () => ({ ok: true })),
      assign: vi.fn(async () => ({ ok: true })),
      changeType: vi.fn(async () => ({ ok: true }))
    },
    showError: vi.fn(async () => {})
  }
  useSession.setState({ load: loadSpy as never })
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
      rowFor('New Property').click()
    })
    expect(host.querySelectorAll('[inert]').length).toBe(1)
    expect(host.textContent).toContain('Checkbox') // a CREATABLE_TYPES row is live
  })
})
