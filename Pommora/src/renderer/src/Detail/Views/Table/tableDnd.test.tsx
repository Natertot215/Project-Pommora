// @vitest-environment jsdom
// State-level gesture tests over the pointer harness — geometry truth lives in the CDP pass.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import {
  firePointer,
  pressEscape,
  stubPointerCapture,
  stubRect,
} from '@renderer/testing/pointerHarness'
import { TableRowDnd, useTableRowDrag } from './tableDnd'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

stubPointerCapture()

function Row({ id }: { id: string }): React.JSX.Element {
  const { ref, handle, isDragging } = useTableRowDrag(id)
  return <div ref={ref} data-row={id} data-dragging={isDragging || undefined} {...handle} />
}

let host: HTMLDivElement
let root: Root
let reorderSpy: ReturnType<typeof vi.fn<(orderIds: string[], groupKey: string) => void>>
let reassignSpy: ReturnType<typeof vi.fn<(activeId: string, targetGroupKey: string) => void>>

const ROWS = [
  { id: 'r1', groupKey: 'g' },
  { id: 'r2', groupKey: 'g' },
  { id: 'r3', groupKey: 'g' },
]

beforeEach(async () => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  reorderSpy = vi.fn()
  reassignSpy = vi.fn()
  await act(async () => {
    root.render(
      <TableRowDnd
        rows={ROWS}
        disabled={false}
        canReorderWithin
        canReassign={false}
        reorderTo={reorderSpy}
        reassign={reassignSpy}
      >
        <Row id="r1" />
        <Row id="r2" />
        <Row id="r3" />
      </TableRowDnd>,
    )
  })
  const content = host.querySelector('.table-dnd')
  if (content) stubRect(content, { top: 0, bottom: 72 })
  for (const [i, r] of ROWS.entries()) {
    const el = host.querySelector(`[data-row="${r.id}"]`)
    if (el) stubRect(el, { top: i * 24, bottom: i * 24 + 24 })
  }
})
afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

const row = (id: string): HTMLElement => host.querySelector(`[data-row="${id}"]`) as HTMLElement

const startDrag = async (): Promise<void> => {
  await act(async () => {
    firePointer(row('r1'), 'pointerdown', { x: 4, y: 12 })
  })
  await act(async () => {
    firePointer(window, 'pointermove', { x: 4, y: 40 })
  })
}

describe('table row drag — Esc abort', () => {
  it('drops the insertion line and commits nothing on Escape', async () => {
    await startDrag()
    expect(host.querySelector('.table-drop-line')).not.toBeNull()
    await act(async () => {
      pressEscape()
    })
    expect(host.querySelector('.table-drop-line')).toBeNull()
    await act(async () => {
      firePointer(window, 'pointerup')
    })
    expect(reorderSpy).not.toHaveBeenCalled()
    expect(reassignSpy).not.toHaveBeenCalled()
  })

  it('is a no-op while idle and still commits a normal drop afterwards', async () => {
    await act(async () => {
      pressEscape()
    })
    await startDrag()
    await act(async () => {
      firePointer(window, 'pointerup')
    })
    expect(reorderSpy).toHaveBeenCalledExactlyOnceWith(['r2', 'r1', 'r3'], 'g', 'r1')
  })

  it('detaches the keydown listener after the gesture settles', async () => {
    const adds = vi.spyOn(window, 'addEventListener')
    const removes = vi.spyOn(window, 'removeEventListener')
    await startDrag()
    await act(async () => {
      pressEscape()
    })
    const added = adds.mock.calls.filter(([t]) => t === 'keydown').length
    const removed = removes.mock.calls.filter(([t]) => t === 'keydown').length
    expect(added).toBeGreaterThan(0)
    expect(removed).toBe(added)
  })
})
