// @vitest-environment jsdom
import { describe, it, expect, afterEach } from 'vitest'
import { createElement, act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { TableView } from './TableView'
import type { TableModel } from './model'

// jsdom lacks ResizeObserver (TableView measures cell geometry with it); a no-op stub is enough — the
// test asserts focus/activation, not pixel geometry. The flag enables React's act() in this env.
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true
if (!('ResizeObserver' in globalThis)) {
  ;(globalThis as { ResizeObserver?: unknown }).ResizeObserver = class {
    observe(): void {}
    unobserve(): void {}
    disconnect(): void {}
  }
}

const model: TableModel = {
  columns: [
    { align: null, dashes: 3 },
    { align: null, dashes: 3 }
  ],
  header: ['A', 'B'],
  rows: [
    ['c1', 'c2'],
    ['d1', 'd2']
  ]
}

const noop = (): void => {}
const props = {
  model,
  onCellCommit: noop,
  onExit: noop,
  onReorder: () => false,
  onResize: () => false,
  onMenu: noop,
  onUndo: noop,
  onRedo: noop
}

let container: HTMLDivElement
let root: Root

async function mount(): Promise<void> {
  container = document.createElement('div')
  document.body.appendChild(container)
  root = createRoot(container)
  await act(async () => {
    root.render(createElement(TableView, props))
  })
}

afterEach(async () => {
  await act(async () => root.unmount())
  container.remove()
})

function cellEl(row: number, col: number): HTMLElement {
  const table = container.querySelector('table.mdpm-tbl')!
  if (row === 0) return table.querySelector('thead tr')!.children[col] as HTMLElement
  const tr = table.querySelector('tbody')!.children[row - 1] as HTMLElement
  return tr.children[col] as HTMLElement
}

// Imitate a real click on a resting cell: a pointerdown (the clear-listener watches this) then the
// mousedown StaticCell activates on.
async function clickCell(row: number, col: number): Promise<void> {
  const div = cellEl(row, col).querySelector('.mdpm-tbl-cell-static') as HTMLElement
  await act(async () => {
    div.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, cancelable: true, button: 0, clientX: 4, clientY: 4 }))
    div.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0, clientX: 4, clientY: 4 }))
  })
}

const editors = (): NodeListOf<Element> => container.querySelectorAll('.cm-editor')
const activeText = (): string | undefined =>
  (container.querySelector('.cm-editor.cm-focused .cm-content') as HTMLElement | null)?.textContent ?? undefined
const focusInEditor = (): boolean => {
  const ed = container.querySelector('.cm-editor')
  return !!ed && !!document.activeElement && ed.contains(document.activeElement)
}

describe('table single-live-cell navigation', () => {
  it('mounts a table with ZERO editors (perf: no R×C CodeMirror instances)', async () => {
    await mount()
    expect(editors().length).toBe(0)
    expect(container.querySelectorAll('.mdpm-tbl-cell-static').length).toBe(6)
  })

  it('one click promotes a cell to the single live editor, focused', async () => {
    await mount()
    await clickCell(1, 0)
    expect(editors().length).toBe(1)
    expect(focusInEditor()).toBe(true)
    expect(activeText()).toBe('c1')
  })

  it('clicking a DIFFERENT cell moves the editor in ONE click and keeps it focused', async () => {
    await mount()
    await clickCell(1, 0)
    expect(activeText()).toBe('c1')
    // The regression: clicking another cell used to need multiple clicks (old cell tore down and
    // stole focus back). After one click the editor must be the new cell AND focused.
    await clickCell(1, 1)
    expect(editors().length).toBe(1) // still exactly one — never R×C
    expect(focusInEditor()).toBe(true)
    expect(activeText()).toBe('c2')
  })

  it('the activating mousedown is preventDefault-ed so the browser cannot steal focus (the two-click bug)', async () => {
    await mount()
    const div = cellEl(1, 0).querySelector('.mdpm-tbl-cell-static') as HTMLElement
    const ev = new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0, clientX: 4, clientY: 4 })
    await act(async () => {
      div.dispatchEvent(ev)
    })
    expect(ev.defaultPrevented).toBe(true)
  })

  it('clicking outside the table demotes the active cell back to static', async () => {
    await mount()
    await clickCell(1, 0)
    expect(editors().length).toBe(1)
    await act(async () => {
      document.body.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, button: 0 }))
    })
    expect(editors().length).toBe(0)
  })
})
