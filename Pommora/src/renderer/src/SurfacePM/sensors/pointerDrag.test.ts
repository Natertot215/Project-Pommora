// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { ACTIVATION } from '@renderer/design-system/interactions/shared'
import { startPointerDrag } from './pointerDrag'

function harness(threshold?: number) {
  const el = document.createElement('div')
  el.setPointerCapture = vi.fn()
  el.releasePointerCapture = vi.fn()
  el.hasPointerCapture = vi.fn(() => true)
  document.body.appendChild(el)
  const moves: Array<[number, number]> = []
  let ended: boolean | null = null
  startPointerDrag(
    {
      currentTarget: el,
      pointerId: 1,
      clientX: 100,
      clientY: 100,
    } as unknown as React.PointerEvent,
    {
      ...(threshold === undefined ? {} : { threshold }),
      onMove: (dx, dy) => moves.push([dx, dy]),
      onEnd: (c) => {
        ended = c
      },
    },
  )
  const fire = (type: string, x: number, y: number): void => {
    el.dispatchEvent(Object.assign(new Event(type), { clientX: x, clientY: y, pointerId: 1 }))
  }
  return { el, moves, ended: () => ended, fire }
}

const syncRaf = (): void => {
  vi.stubGlobal('requestAnimationFrame', (cb: FrameRequestCallback) => {
    cb(0)
    return 1
  })
  vi.stubGlobal('cancelAnimationFrame', () => {})
}

afterEach(() => {
  vi.unstubAllGlobals()
  document.body.innerHTML = ''
})

describe('startPointerDrag', () => {
  it('defaults the arm threshold to the engine ACTIVATION', () => {
    syncRaf()
    const h = harness()
    h.fire('pointermove', 100 + ACTIVATION - 1, 100)
    expect(h.moves).toEqual([])
    h.fire('pointermove', 100 + ACTIVATION, 100)
    expect(h.moves.at(-1)).toEqual([ACTIVATION, 0])
  })

  it('reports an unarmed release as an abort and stops listening', () => {
    const h = harness()
    h.fire('pointermove', 101, 101)
    h.fire('pointerup', 101, 101)
    expect(h.moves).toEqual([])
    expect(h.ended()).toBe(false)
    h.fire('pointermove', 200, 200)
    expect(h.moves).toEqual([])
  })

  it('coalesces moves through rAF and commits on an armed release', () => {
    syncRaf()
    const h = harness(3)
    h.fire('pointermove', 120, 100)
    h.fire('pointerup', 120, 100)
    expect(h.moves.at(-1)).toEqual([20, 0])
    expect(h.ended()).toBe(true)
  })

  it('registers the post-drop click suppressor on an armed commit', () => {
    syncRaf()
    const h = harness(3)
    h.fire('pointermove', 130, 100)
    h.fire('pointerup', 130, 100)
    const click = new MouseEvent('click', { bubbles: true, cancelable: true })
    h.el.dispatchEvent(click)
    expect(click.defaultPrevented).toBe(true)
    const second = new MouseEvent('click', { bubbles: true, cancelable: true })
    h.el.dispatchEvent(second)
    expect(second.defaultPrevented).toBe(false)
  })

  it('aborts on Escape and goes deaf afterward', () => {
    syncRaf()
    const h = harness(3)
    h.fire('pointermove', 130, 100)
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
    expect(h.ended()).toBe(false)
    h.fire('pointermove', 200, 100)
    expect(h.moves.at(-1)).toEqual([30, 0])
  })

  it('treats lostpointercapture as an abort — capture torn away can never zombie', () => {
    syncRaf()
    const h = harness(3)
    h.fire('pointermove', 140, 100)
    h.fire('lostpointercapture', 140, 100)
    expect(h.ended()).toBe(false)
  })

  it('lostpointercapture after a normal release is a no-op', () => {
    syncRaf()
    const h = harness(3)
    h.fire('pointermove', 140, 100)
    h.fire('pointerup', 140, 100)
    expect(h.ended()).toBe(true)
    h.fire('lostpointercapture', 140, 100)
    expect(h.ended()).toBe(true)
  })

  it('aborts on pointercancel', () => {
    syncRaf()
    const h = harness(3)
    h.fire('pointermove', 140, 100)
    h.fire('pointercancel', 140, 100)
    expect(h.ended()).toBe(false)
  })
})
