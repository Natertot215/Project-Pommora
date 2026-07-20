// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { CheckboxEditor, type CheckboxLook } from './CheckboxEditor'
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

const mount = async (
  props: {
    color?: string
    look?: CheckboxLook
    accent?: string
    onSetColor?: (c: string | undefined) => void
    onSetStyle?: (l: CheckboxLook) => void
  } = {},
): Promise<void> => {
  await act(async () => {
    root.render(
      <CheckboxEditor
        color={props.color}
        look={props.look ?? 'checkbox'}
        accent={props.accent}
        onSetColor={props.onSetColor ?? (() => {})}
        onSetStyle={props.onSetStyle ?? (() => {})}
      />,
    )
  })
}

/** A trigger/option/swatch button whose accessible name or text reads exactly `name`, from anywhere
 *  (the PickerMenu portals to document.body). */
const buttonFor = (name: string): HTMLButtonElement => {
  const el = [...document.querySelectorAll<HTMLButtonElement>('button')].find(
    (b) => b.getAttribute('aria-label') === name || b.textContent === name,
  )
  if (!el) throw new Error(`no button "${name}"`)
  return el
}

describe('CheckboxEditor', () => {
  it('shows Color and Style rows, the color reading Accent when unset', async () => {
    await mount({ accent: 'cyan' })
    expect(host.textContent).toContain('Color')
    expect(host.textContent).toContain('Style')
    expect(host.textContent).toContain('Accent')
  })

  it('labels a chosen color that equals the accent as Accent too', async () => {
    await mount({ color: 'cyan', accent: 'cyan' })
    expect(host.textContent).toContain('Accent')
  })

  it('labels a chosen color that differs from the accent by its palette name', async () => {
    await mount({ color: 'blue', accent: 'cyan' })
    expect(host.textContent).toContain('Blue')
  })

  it('reflects the current look in the Style trigger', async () => {
    await mount({ look: 'switch' })
    expect(buttonFor('Checkbox style').textContent).toContain('Switch')
  })

  it('toggles the look from the Style row (dual-option control)', async () => {
    const onSetStyle = vi.fn()
    await mount({ look: 'checkbox', onSetStyle })
    // Checkbox/Switch is two options → a toggle: one click flips 'checkbox' to 'switch'.
    await act(async () => buttonFor('Checkbox style').click())
    expect(onSetStyle).toHaveBeenCalledWith('switch')
  })

  it('emits a color key when a new swatch is picked', async () => {
    const onSetColor = vi.fn()
    await mount({ accent: 'cyan', onSetColor })
    // open the picker (the color chip button wraps the "Accent" chip)
    await act(async () => buttonFor('Accent').click())
    await act(async () => buttonFor('blue').click())
    expect(onSetColor).toHaveBeenCalledWith('blue')
  })
})
