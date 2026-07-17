// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { stubPointerCapture } from '@renderer/testing/pointerHarness'
import type { PropertyDefinition } from '@shared/properties'
import { useSession } from '../../store'
import { PropertiesPane } from './PropertiesPane'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

stubPointerCapture()

class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
;(globalThis as { ResizeObserver?: unknown }).ResizeObserver = ResizeObserverStub

// A datetime property with no saved column_styles → the editor reflects the resolved type default.
const dateDef: PropertyDefinition = { id: 'prop_due', name: 'Due', type: 'datetime' }
const source = { id: 'col1', kind: 'collection', path: 'Col', title: 'Col', views: [] } as never

let host: HTMLDivElement
let root: Root
let saveSpy: ReturnType<typeof vi.fn>

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  saveSpy = vi.fn(async () => ({ ok: true, id: 'v1' }))
  ;(window as unknown as { nexus: unknown }).nexus = {
    schema: {
      add: vi.fn(async () => ({ ok: true, id: 'x' })),
      rename: vi.fn(async () => ({ ok: true })),
      reorder: vi.fn(async () => ({ ok: true })),
      delete: vi.fn(async () => ({ ok: true })),
      assign: vi.fn(async () => ({ ok: true })),
      changeType: vi.fn(async () => ({ ok: true })),
    },
    property: { delete: vi.fn(async () => ({ ok: true })) },
    views: { save: saveSpy },
    activeViews: { set: vi.fn(async () => {}) },
    propertyMenu: vi.fn(async () => null),
    showError: vi.fn(async () => {}),
  }
  useSession.setState({
    load: vi.fn(async () => {}) as never,
    tree: { registry: [] } as never,
    renamingProperty: null,
    activeViews: {},
  })
})
afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

const buttonFor = (name: string): HTMLButtonElement => {
  const el = [...document.querySelectorAll<HTMLButtonElement>('button')].find(
    (b) => b.getAttribute('aria-label') === name || b.textContent === name,
  )
  if (!el) throw new Error(`no button "${name}"`)
  return el
}

describe('the datetime Format editor writes the ACTIVE view (A-3)', () => {
  it('picking Short Date saves column_styles on the source node, not the schema', async () => {
    await act(async () => {
      root.render(
        <PropertiesPane
          collectionPath="Col"
          schema={[dateDef]}
          onBack={() => {}}
          source={source}
        />,
      )
    })
    // Open the Due property's editor.
    const dueRow = [...host.querySelectorAll<HTMLElement>('span')].find(
      (el) => el.textContent === 'Due' && el.children.length === 0,
    )
    await act(async () => {
      dueRow!.click()
    })
    await act(async () => {
      await new Promise((r) => requestAnimationFrame(() => r(undefined)))
    })
    // Pick Date → Short Date.
    await act(async () => {
      buttonFor('Date format').click()
    })
    await act(async () => {
      buttonFor('Short Date').click()
    })
    expect(saveSpy).toHaveBeenCalledWith(
      'Col',
      'collection',
      expect.objectContaining({ column_styles: { prop_due: { date_format: 'short' } } }),
    )
  })
})
