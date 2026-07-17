// @vitest-environment jsdom
// State-level gesture tests over the pointer harness — geometry truth lives in the CDP pass.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { MutateRequest } from '@shared/mutate'
import type { NexusTree } from '@shared/types'
import {
  firePointer,
  pressEscape,
  stubPointerCapture,
  stubRect,
} from '@renderer/testing/pointerHarness'
import { SidebarDnd, useSidebarDrag } from './sidebarDnd'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

stubPointerCapture()

const tree = {
  contexts: { areas: [], topics: [], projects: [] },
  collections: [
    {
      kind: 'collection',
      id: 'c1',
      title: 'C',
      path: 'C',
      sets: [],
      pages: [
        { kind: 'page', id: 'p1', title: 'P1', path: 'C/P1.md' },
        { kind: 'page', id: 'p2', title: 'P2', path: 'C/P2.md' },
      ],
    },
  ],
  userSections: [],
} as unknown as NexusTree

function Row({ id }: { id: string }): React.JSX.Element {
  const { ref, handle } = useSidebarDrag(id)
  return <div ref={ref} data-row={id} {...handle} />
}

let host: HTMLDivElement
let root: Root
let commitSpy: ReturnType<typeof vi.fn<(commit: MutateRequest) => void>>

beforeEach(async () => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  commitSpy = vi.fn()
  await act(async () => {
    root.render(
      <SidebarDnd tree={tree} onCommit={commitSpy}>
        <Row id="p1" />
        <Row id="p2" />
      </SidebarDnd>,
    )
  })
  for (const [i, id] of ['p1', 'p2'].entries()) {
    const el = host.querySelector(`[data-row="${id}"]`)
    if (el) stubRect(el, { top: i * 24, bottom: i * 24 + 24 })
  }
})
afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

const row = (id: string): HTMLElement => host.querySelector(`[data-row="${id}"]`) as HTMLElement
// The drag ghost is the portaled fixed-position node — the a11y announce live region also
// carries the title text, so a bare body-text probe would false-positive.
const ghost = (): boolean =>
  [...document.body.querySelectorAll<HTMLElement>('div[aria-hidden="true"]')].some(
    (el) => el.textContent === 'P1' && el.style.position === 'fixed',
  )

// Move/up listeners ride the row element (pointer capture in the real DOM), so the harness
// drives them on the row itself.
const startDrag = async (): Promise<void> => {
  await act(async () => {
    firePointer(row('p1'), 'pointerdown', { x: 4, y: 12 })
  })
  await act(async () => {
    firePointer(row('p1'), 'pointermove', { x: 4, y: 40 })
  })
}

describe('sidebar drag — Esc abort', () => {
  it('clears the ghost + target and commits nothing on Escape', async () => {
    await startDrag()
    expect(ghost()).toBe(true)
    await act(async () => {
      pressEscape()
    })
    expect(ghost()).toBe(false)
    await act(async () => {
      firePointer(row('p1'), 'pointerup')
    })
    expect(commitSpy).not.toHaveBeenCalled()
  })

  it('is a no-op while idle and still commits a normal drop afterwards', async () => {
    await act(async () => {
      pressEscape()
    })
    await startDrag()
    await act(async () => {
      firePointer(row('p1'), 'pointerup')
    })
    expect(commitSpy).toHaveBeenCalledExactlyOnceWith({
      op: 'movePage',
      path: 'C/P1.md',
      newParentPath: 'C',
      order: ['p2', 'p1'],
    })
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
