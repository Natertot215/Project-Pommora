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

describe('PaneSlider', () => {
  it('keeps both slots mounted (so each is measured for the resize)', async () => {
    await act(async () => {
      root.render(<PaneSlider open={false} root={<div>alpha</div>} detail={<div>beta</div>} />)
    })
    expect(host.textContent).toContain('alpha')
    expect(host.textContent).toContain('beta')
  })

  it('never caps or scrolls a slot itself — a slot MenuScrollFrame owns that', async () => {
    await act(async () => {
      root.render(<PaneSlider open={false} root={<div>alpha</div>} detail={<div>beta</div>} />)
    })
    expect(host.querySelectorAll('.scroll-edge-fade')).toHaveLength(0)
    for (const el of host.querySelectorAll<HTMLElement>('div')) expect(el.style.overflowY).toBe('')
  })

  it('rides the min floors on the measured content div', async () => {
    await act(async () => {
      root.render(<PaneSlider open={false} root={<div>alpha</div>} detail={<div>beta</div>} minWidth={225} minHeight={245} />)
    })
    const floored = [...host.querySelectorAll<HTMLElement>('div')].filter((el) => el.style.minHeight === '245px')
    expect(floored).toHaveLength(2)
  })
})
