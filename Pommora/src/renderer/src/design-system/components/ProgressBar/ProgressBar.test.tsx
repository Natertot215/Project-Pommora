// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { ProgressBar } from './ProgressBar'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

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

const mount = (fill: number): void => {
  act(() => root.render(<ProgressBar fill={fill} />))
}
const width = (): string =>
  (host.querySelector('[role="progressbar"] > *') as HTMLElement).style.width

describe('ProgressBar', () => {
  it('maps a mid fill to a percent width', () => {
    mount(0.3)
    expect(width()).toBe('30%')
  })
  it('clamps an over-1 fill to 100%', () => {
    mount(1.5)
    expect(width()).toBe('100%')
  })
  it('clamps a negative fill to 0%', () => {
    mount(-1)
    expect(width()).toBe('0%')
  })
  it('treats a non-finite fill as 0%', () => {
    mount(Number.NaN)
    expect(width()).toBe('0%')
  })
})
