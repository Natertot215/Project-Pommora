// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { ColumnStyle } from '@shared/columnStyles'
import { DateTimeEditor } from './DateTimeEditor'
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

const mount = async (style: ColumnStyle, onChange = vi.fn()): Promise<typeof onChange> => {
  await act(async () => {
    root.render(<DateTimeEditor style={style} onChange={onChange} />)
  })
  return onChange
}

/** A trigger/option button whose accessible name / text reads exactly `name`, from anywhere (the
 *  PickerMenu portals to document.body). */
const buttonFor = (name: string): HTMLButtonElement => {
  const el = [...document.querySelectorAll<HTMLButtonElement>('button')].find(
    (b) => b.getAttribute('aria-label') === name || b.textContent === name,
  )
  if (!el) throw new Error(`no button "${name}"`)
  return el
}

describe('DateTimeEditor', () => {
  it('shows the Day row only for the worded (short/full) date formats', async () => {
    await mount({ date_format: 'monthDayYear' })
    expect(host.textContent).not.toContain('Day')
    await act(async () => {
      root.render(<DateTimeEditor style={{ date_format: 'full' }} onChange={() => {}} />)
    })
    expect(host.textContent).toContain('Day')
  })

  it('emits a date_format patch on pick', async () => {
    const onChange = await mount({ date_format: 'full' })
    await act(async () => {
      buttonFor('Date format').click()
    })
    await act(async () => {
      buttonFor('Short Date').click()
    })
    expect(onChange).toHaveBeenCalledWith({ date_format: 'short' })
  })

  it('emits a weekday patch from the Day row', async () => {
    const onChange = await mount({ date_format: 'full', weekday: 'none' })
    await act(async () => {
      buttonFor('Weekday format').click()
    })
    await act(async () => {
      buttonFor('Full').click()
    })
    expect(onChange).toHaveBeenCalledWith({ weekday: 'long' })
  })
})
