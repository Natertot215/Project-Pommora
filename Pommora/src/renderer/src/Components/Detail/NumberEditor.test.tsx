// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { NumberConfig } from '@shared/properties'
import { NumberEditor } from './NumberEditor'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

// The Switch's GlassSegment measures itself; jsdom has no ResizeObserver.
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

const mount = (config: NumberConfig): void => {
  act(() =>
    root.render(
      <NumberEditor config={config} look="number" onSetConfig={vi.fn()} onSetStyle={vi.fn()} />,
    ),
  )
}
const labels = (): string[] =>
  Array.from(host.querySelectorAll('span')).map((s) => s.textContent ?? '')

describe('NumberEditor', () => {
  it('shows the Currency row only when the family is currency', () => {
    mount({ number_family: 'number' })
    expect(labels()).not.toContain('Currency')
    mount({ number_family: 'currency' })
    expect(labels()).toContain('Currency')
  })

  it('hides Separators + Fraction for percent and shows the Style row', () => {
    mount({ number_family: 'percent' })
    const l = labels()
    expect(l).not.toContain('Separators')
    expect(l).not.toContain('Fraction')
    expect(l).toContain('Style')
  })

  it('reveals the Value row only when fraction is on', () => {
    mount({ number_family: 'number', number_fraction: false })
    expect(labels()).not.toContain('Value')
    mount({ number_family: 'number', number_fraction: true, number_denominator: 10 })
    expect(labels()).toContain('Value')
  })
})
