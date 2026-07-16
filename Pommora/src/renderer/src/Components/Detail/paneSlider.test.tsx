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
  it('mounts both root and detail while open (so each is measured for the resize)', async () => {
    await act(async () => {
      root.render(<PaneSlider open={true} root={<div>alpha</div>} detail={<div>beta</div>} />)
    })
    expect(host.textContent).toContain('alpha')
    expect(host.textContent).toContain('beta')
  })

  it('holds the detail through the slide-out, then drops it once closed', async () => {
    await act(async () => {
      root.render(<PaneSlider open={true} root={<div>alpha</div>} detail={<div>beta</div>} />)
    })
    // Close: the detail stays mounted through the slide (exit-presence) so it slides out at full size.
    await act(async () => {
      root.render(<PaneSlider open={false} root={<div>alpha</div>} detail={null} />)
    })
    expect(host.textContent).toContain('beta')
    // After the slide window elapses it's dropped.
    await act(async () => {
      await new Promise((r) => setTimeout(r, 320))
    })
    expect(host.textContent).not.toContain('beta')
  })

  it('never caps or scrolls a slot itself — a slot MenuScrollFrame owns that', async () => {
    await act(async () => {
      root.render(<PaneSlider open={false} root={<div>alpha</div>} detail={<div>beta</div>} />)
    })
    expect(host.querySelectorAll('.edge-fade')).toHaveLength(0)
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
