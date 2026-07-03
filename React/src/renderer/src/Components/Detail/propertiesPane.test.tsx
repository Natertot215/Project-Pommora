// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { PropertyDefinition } from '@shared/properties'
import { firePointer, stubPointerCapture, stubRect } from '@renderer/testing/pointerHarness'
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

const defs: PropertyDefinition[] = [
  { id: 'prop_status', name: 'Status', type: 'status' },
  { id: 'prop_n', name: 'Count', type: 'number' }
]

let host: HTMLDivElement
let root: Root
let loadSpy: ReturnType<typeof vi.fn>
let assignSpy: ReturnType<typeof vi.fn>
let renameSpy: ReturnType<typeof vi.fn>
let propertyMenuSpy: ReturnType<typeof vi.fn>
let destroySpy: ReturnType<typeof vi.fn>

beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  loadSpy = vi.fn(async () => {})
  assignSpy = vi.fn(async () => ({ ok: true }))
  renameSpy = vi.fn(async () => ({ ok: true }))
  propertyMenuSpy = vi.fn(async () => null)
  destroySpy = vi.fn(async () => ({ ok: true }))
  ;(window as unknown as { nexus: unknown }).nexus = {
    schema: {
      add: vi.fn(async () => ({ ok: true, id: 'prop_new' })),
      rename: renameSpy,
      reorder: vi.fn(async () => ({ ok: true })),
      delete: vi.fn(async () => ({ ok: true })),
      assign: assignSpy,
      changeType: vi.fn(async () => ({ ok: true }))
    },
    property: { delete: destroySpy },
    propertyMenu: propertyMenuSpy,
    showError: vi.fn(async () => {})
  }
  useSession.setState({ load: loadSpy as never, tree: { registry: [] } as never, renamingProperty: null })
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

describe('the two-region drag (T6) — state-level; geometry truth lives in the live pass', () => {
  const deleteSpy = (): ReturnType<typeof vi.fn> =>
    (window as unknown as { nexus: { schema: { delete: ReturnType<typeof vi.fn> } } }).nexus.schema.delete

  /** Rects: assigned rows at 10-30 / 30-50 (region 10-50); all block at 70-110 with x1 at 70-90. */
  const stubGeometry = (): void => {
    stubRect(host.querySelector('[data-group="assigned"]')!, { top: 10, bottom: 50 })
    stubRect(host.querySelector('[data-group="all"]')!, { top: 70, bottom: 110 })
    stubRect(host.querySelector('[data-prop="prop_status"]')!, { top: 10, bottom: 30 })
    stubRect(host.querySelector('[data-prop="prop_n"]')!, { top: 30, bottom: 50 })
    const x1 = host.querySelector('[data-prop="prop_x"]')
    if (x1) stubRect(x1, { top: 70, bottom: 90 })
  }

  it('assigned → all commits the Remove (schema.delete) after an area-highlight hover', async () => {
    useSession.setState({ tree: { registry: [effortDef] } as never })
    await mountPane()
    await act(async () => {
      rowFor('All Properties').click()
    })
    stubGeometry()
    const row = host.querySelector('[data-prop="prop_status"]')!
    await act(async () => {
      firePointer(row, 'pointerdown', { x: 100, y: 20 })
      firePointer(window, 'pointermove', { x: 100, y: 40 }) // past activation
      firePointer(window, 'pointermove', { x: 100, y: 80 }) // into the all region
    })
    expect(host.querySelector('[data-group="all"]')?.className).toContain('allHighlight')
    await act(async () => {
      firePointer(window, 'pointerup', { x: 100, y: 80 })
    })
    expect(deleteSpy()).toHaveBeenCalledWith('Col', 'prop_status')
  })

  it('all → assigned commits the atomic assign at the slot index', async () => {
    useSession.setState({ tree: { registry: [effortDef] } as never })
    await mountPane()
    await act(async () => {
      rowFor('All Properties').click()
    })
    stubGeometry()
    const row = host.querySelector('[data-prop="prop_x"]')!
    await act(async () => {
      firePointer(row, 'pointerdown', { x: 100, y: 80 })
      firePointer(window, 'pointermove', { x: 100, y: 60 })
      firePointer(window, 'pointermove', { x: 100, y: 15 }) // top half of the first assigned row
      firePointer(window, 'pointerup', { x: 100, y: 15 })
    })
    expect(assignSpy).toHaveBeenCalledWith('Col', 'prop_x', 0)
  })

  it('Escape aborts an active drag without committing', async () => {
    useSession.setState({ tree: { registry: [effortDef] } as never })
    await mountPane()
    await act(async () => {
      rowFor('All Properties').click()
    })
    stubGeometry()
    const row = host.querySelector('[data-prop="prop_status"]')!
    await act(async () => {
      firePointer(row, 'pointerdown', { x: 100, y: 20 })
      firePointer(window, 'pointermove', { x: 100, y: 80 })
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))
      firePointer(window, 'pointerup', { x: 100, y: 80 })
    })
    expect(deleteSpy()).not.toHaveBeenCalled()
  })

  it('the all region owns its FIELD — a release in the empty space below the rows still unassigns', async () => {
    useSession.setState({ tree: { registry: [effortDef] } as never })
    await mountPane()
    await act(async () => {
      rowFor('All Properties').click()
    })
    stubGeometry()
    // The pane box runs far past the all-block's rendered rows; the region must extend with it.
    stubRect(host.querySelector('[class*="paneDnd"]')!, { top: 0, bottom: 300 })
    const row = host.querySelector('[data-prop="prop_status"]')!
    await act(async () => {
      firePointer(row, 'pointerdown', { x: 100, y: 20 })
      firePointer(window, 'pointermove', { x: 100, y: 40 })
      firePointer(window, 'pointermove', { x: 100, y: 250 }) // well below the last rendered row
      firePointer(window, 'pointerup', { x: 100, y: 250 })
    })
    expect(deleteSpy()).toHaveBeenCalledWith('Col', 'prop_status')
  })

  it("a press on the row's + button never arms a drag (begin guard)", async () => {
    useSession.setState({ tree: { registry: [effortDef] } as never })
    await mountPane()
    await act(async () => {
      rowFor('All Properties').click()
    })
    stubGeometry()
    const plus = host.querySelector<HTMLButtonElement>('[aria-label="Assign Effort"]')!
    await act(async () => {
      firePointer(plus, 'pointerdown', { x: 100, y: 80 })
      firePointer(window, 'pointermove', { x: 100, y: 20 })
      firePointer(window, 'pointerup', { x: 100, y: 20 })
    })
    expect(assignSpy).not.toHaveBeenCalledWith('Col', 'prop_x', expect.anything())
  })
})

describe('native menus + the inline-rename channel (T7)', () => {
  const openEditor = async (): Promise<void> => {
    await mountPane()
    await act(async () => {
      rowFor('Status').click()
    })
  }

  it("the editor's ⋮ Remove routes through schema.delete and returns to the list (A-8)", async () => {
    propertyMenuSpy.mockResolvedValueOnce('property:remove')
    await openEditor()
    await act(async () => {
      host.querySelector<HTMLButtonElement>('[aria-label="Property Menu"]')!.click()
    })
    expect(propertyMenuSpy).toHaveBeenCalledWith({ kind: 'editor', name: 'Status' })
    const del = (window as unknown as { nexus: { schema: { delete: ReturnType<typeof vi.fn> } } }).nexus.schema.delete
    expect(del).toHaveBeenCalledWith('Col', 'prop_status')
  })

  it("⋮ Delete (main-confirmed) runs the global property.delete — and the footer Delete row is GONE (A-8/D-1)", async () => {
    propertyMenuSpy.mockResolvedValueOnce('property:destroy')
    await openEditor()
    expect(host.textContent).not.toContain('Delete Property') // the old footer row died
    await act(async () => {
      host.querySelector<HTMLButtonElement>('[aria-label="Property Menu"]')!.click()
    })
    expect(destroySpy).toHaveBeenCalledWith('prop_status')
  })

  it('a row right-click Rename flips the title to the inline input; Enter commits schema.rename (A-10)', async () => {
    propertyMenuSpy.mockResolvedValueOnce('property:rename')
    await mountPane()
    await act(async () => {
      host.querySelector('[data-prop="prop_status"]')!.querySelector('[class*="item"]')!.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))
    })
    expect(propertyMenuSpy).toHaveBeenCalledWith({ kind: 'assigned-row', name: 'Status' })
    const input = host.querySelector<HTMLInputElement>('.row-title-input')
    expect(input).toBeTruthy()
    await act(async () => {
      Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set?.call(input, 'Stage')
      input!.dispatchEvent(new Event('input', { bubbles: true }))
      input!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
      input!.blur()
    })
    expect(renameSpy).toHaveBeenCalledWith('Col', 'prop_status', 'Stage')
    expect(host.querySelector('.row-title-input')).toBeNull() // eager exit
  })

  it('a registry row offers Rename only (registry-row context)', async () => {
    useSession.setState({ tree: { registry: [effortDef] } as never })
    propertyMenuSpy.mockResolvedValueOnce(null)
    await mountPane()
    await act(async () => {
      rowFor('All Properties').click()
    })
    await act(async () => {
      host.querySelector('[data-prop="prop_x"]')!.querySelector('[class*="item"]')!.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }))
    })
    expect(propertyMenuSpy).toHaveBeenCalledWith({ kind: 'registry-row', name: 'Effort' })
  })
})
