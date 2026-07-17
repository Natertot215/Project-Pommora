// @vitest-environment jsdom
// State-level gesture tests over the pointer harness — geometry truth lives in the CDP pass.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { ResolvedGroup } from '@shared/types'
import type { SavedView } from '@shared/views'
import {
  firePointer,
  pressEscape,
  stubPointerCapture,
  stubRect,
} from '@renderer/testing/pointerHarness'
import type { Band } from './bandDndModel'
import { BandDnd, useBandDrag, type BandDrop } from './bandDnd'
import { GroupHeader } from './GroupHeader'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

stubPointerCapture()

// A[A1], B — the glyph span is the drag surface, the header div is the measured band row.
const BANDS: Band[] = [
  { id: 'A', kind: 'set', depth: 0, parentId: null },
  { id: 'A1', kind: 'set', depth: 1, parentId: 'A' },
  { id: 'B', kind: 'set', depth: 0, parentId: null },
]

function Header({ id }: { id: string }): React.JSX.Element {
  const { ref, handle, isDragging, isNestTarget } = useBandDrag(id)
  return (
    <div
      ref={ref}
      data-band={id}
      data-dragging={isDragging || undefined}
      data-nest={isNestTarget || undefined}
    >
      <span data-glyph={id} {...handle} />
    </div>
  )
}

let host: HTMLDivElement
let root: Root
let dropSpy: ReturnType<typeof vi.fn<(draggedId: string, drop: BandDrop) => void>>

beforeEach(async () => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  dropSpy = vi.fn()
  await act(async () => {
    root.render(
      <BandDnd bands={BANDS} labelFor={(id) => id} onDrop={dropSpy}>
        <Header id="A" />
        <Header id="A1" />
        <Header id="B" />
      </BandDnd>,
    )
  })
  const box = host.querySelector('.band-dnd')
  if (box) stubRect(box, { top: 0, bottom: 72 })
  for (const [i, id] of ['A', 'A1', 'B'].entries()) {
    const el = host.querySelector(`[data-band="${id}"]`)
    if (el) stubRect(el, { top: i * 24, bottom: i * 24 + 24 })
  }
})
afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

const glyph = (id: string): HTMLElement => host.querySelector(`[data-glyph="${id}"]`) as HTMLElement
const line = (): Element | null => host.querySelector('.table-drop-line')

const drag = async (id: string, toY: number): Promise<void> => {
  await act(async () => {
    firePointer(glyph(id), 'pointerdown', { x: 10, y: 10 })
  })
  await act(async () => {
    firePointer(window, 'pointermove', { x: 10, y: toY })
  })
}

describe('band drag gesture', () => {
  it('activation mounts the insertion line and mutes the source band', async () => {
    await drag('A1', 2)
    expect(line()).not.toBeNull()
    expect(host.querySelector('[data-band="A1"]')?.getAttribute('data-dragging')).toBe('true')
  })

  it('Escape clears the line + mute and commits nothing', async () => {
    await drag('A1', 2)
    await act(async () => {
      pressEscape()
    })
    expect(line()).toBeNull()
    expect(host.querySelector('[data-band="A1"]')?.getAttribute('data-dragging')).toBeNull()
    await act(async () => {
      firePointer(window, 'pointerup')
    })
    expect(dropSpy).not.toHaveBeenCalled()
  })

  it('a sub-threshold glyph press-release is a no-op', async () => {
    await act(async () => {
      firePointer(glyph('A'), 'pointerdown', { x: 10, y: 10 })
    })
    await act(async () => {
      firePointer(window, 'pointerup')
    })
    expect(dropSpy).not.toHaveBeenCalled()
    expect(line()).toBeNull()
  })

  it('classifies a same-parent drop as reorder', async () => {
    await drag('B', 2) // above A: implied parent root == B's parent
    await act(async () => {
      firePointer(window, 'pointerup')
    })
    expect(dropSpy).toHaveBeenCalledExactlyOnceWith('B', { kind: 'reorder', beforeId: 'A' })
  })

  it('classifies a parent-changing between-slot as reparent (HIGH-1)', async () => {
    await drag('A1', 2) // above A: implied parent root ≠ A1's parent A
    await act(async () => {
      firePointer(window, 'pointerup')
    })
    expect(dropSpy).toHaveBeenCalledExactlyOnceWith('A1', {
      kind: 'reparent',
      targetParentId: null,
      beforeId: 'A',
    })
  })

  it('twisty pointerdown never arms the gesture — a follow-up click still toggles (C-6 isolation)', async () => {
    const toggleSpy = vi.fn()
    const group: ResolvedGroup = { key: 'A', kind: 'structural-set', items: [], isCollapsed: false }
    const view: SavedView = {
      id: 'v',
      name: 'V',
      type: 'table',
      property_order: [],
      hidden_properties: [],
      group: { kind: 'structural' },
    }
    await act(async () => {
      root.render(
        <BandDnd bands={BANDS} labelFor={(id) => id} onDrop={dropSpy}>
          <GroupHeader
            group={group}
            view={view}
            ctx={{ schema: [] } as never}
            setNames={new Map([['A', 'A']])}
            setIcons={new Map()}
            collapsed={false}
            onToggle={toggleSpy}
          />
        </BandDnd>,
      )
    })
    const twisty = host.querySelector('.group-twisty') as HTMLElement
    await act(async () => {
      firePointer(twisty, 'pointerdown', { x: 5, y: 5 })
    })
    await act(async () => {
      firePointer(window, 'pointermove', { x: 60, y: 60 })
    })
    expect(line()).toBeNull()
    await act(async () => {
      twisty.click()
    })
    expect(toggleSpy).toHaveBeenCalledOnce()
    expect(dropSpy).not.toHaveBeenCalled()
  })

  it('classifies a middle-zone hover as nest-into with the target highlighted', async () => {
    await drag('B', 36) // middle of A1 (24–48; zone 31.2–40.8)
    expect(host.querySelector('[data-band="A1"]')?.getAttribute('data-nest')).toBe('true')
    expect(line()).toBeNull() // the highlight replaces the line
    await act(async () => {
      firePointer(window, 'pointerup')
    })
    expect(dropSpy).toHaveBeenCalledExactlyOnceWith('B', {
      kind: 'reparent',
      targetParentId: 'A1',
      beforeId: null,
    })
  })
})
