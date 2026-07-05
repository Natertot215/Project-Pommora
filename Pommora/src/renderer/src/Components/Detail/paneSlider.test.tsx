// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { PaneSlider } from './PaneSlider'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
;(globalThis as { ResizeObserver?: unknown }).ResizeObserver = ResizeObserverStub

let host: HTMLDivElement
let root: Root
beforeEach(() => {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
})
afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

describe('PaneSlider maxHeight (A-6)', () => {
  it('caps each slot, makes it scrollable, and masks it with the shared edge fade', async () => {
    await act(async () => {
      root.render(<PaneSlider active="a" slotA={<div>alpha</div>} slotB={<div>beta</div>} maxHeight={350} />)
    })
    const slots = [...host.querySelectorAll<HTMLElement>('.scroll-edge-fade')]
    expect(slots).toHaveLength(2)
    for (const slot of slots) expect(slot.style.maxHeight).toBe('350px')
  })

  it('without maxHeight the slots stay uncapped and unmasked', async () => {
    await act(async () => {
      root.render(<PaneSlider active="a" slotA={<div>alpha</div>} slotB={<div>beta</div>} />)
    })
    expect(host.querySelectorAll('.scroll-edge-fade')).toHaveLength(0)
  })

  it('the min floors ride the measured content, not the capped slot', async () => {
    await act(async () => {
      root.render(<PaneSlider active="a" slotA={<div>alpha</div>} slotB={<div>beta</div>} minWidth={225} minHeight={245} maxHeight={350} />)
    })
    // The floor must sit on the ResizeObserver-measured inner div — a floor on the scroll-capped
    // slot box would be invisible to the measurement and clip a sparse pane.
    const floored = [...host.querySelectorAll<HTMLElement>('div')].filter((el) => el.style.minHeight === '245px')
    expect(floored).toHaveLength(2)
    for (const el of floored) expect(el.classList.contains('scroll-edge-fade')).toBe(false)
  })
})
