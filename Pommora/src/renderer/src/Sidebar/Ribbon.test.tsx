// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { Ribbon } from './Ribbon'
import { useSession } from '../store'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

let host: HTMLDivElement
let root: Root
let selectSpy: ReturnType<typeof vi.fn>
let setPersonalizationSpy: ReturnType<typeof vi.fn>

beforeEach(() => {
  selectSpy = vi.fn()
  setPersonalizationSpy = vi.fn()
  useSession.setState({
    select: selectSpy as never,
    setPersonalization: setPersonalizationSpy as never,
    personalization: { sidebarMode: 'collections' }
  })
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  act(() => root.render(<Ribbon />))
})

afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

const buttons = (): HTMLButtonElement[] => Array.from(host.querySelectorAll('button'))

describe('Ribbon', () => {
  it('renders Homepage first, then the five launcher icons', () => {
    const bs = buttons()
    expect(bs[0].getAttribute('aria-label')).toBe('Homepage')
    const labels = bs.slice(1).map((b) => b.getAttribute('aria-label'))
    expect(labels).toEqual(['collections', 'contexts', 'agenda', 'navigation', 'settings'])
  })

  it('Homepage click selects the homepage and never switches mode', () => {
    act(() => buttons()[0].click())
    expect(selectSpy).toHaveBeenCalledWith({ kind: 'homepage' })
    expect(setPersonalizationSpy).not.toHaveBeenCalled()
  })

  it('a mode icon switches sidebarMode', () => {
    const contexts = buttons().find((b) => b.getAttribute('aria-label') === 'contexts')!
    act(() => contexts.click())
    expect(setPersonalizationSpy).toHaveBeenCalledWith('sidebarMode', 'contexts')
  })

  it('navigation / settings are no-ops (no mode switch)', () => {
    const nav = buttons().find((b) => b.getAttribute('aria-label') === 'navigation')!
    act(() => nav.click())
    expect(setPersonalizationSpy).not.toHaveBeenCalled()
  })

  it('marks the active mode with the highlight class', () => {
    const collections = buttons().find((b) => b.getAttribute('aria-label') === 'collections')!
    expect(collections.className).toContain('ribbon-icon-active')
    const agenda = buttons().find((b) => b.getAttribute('aria-label') === 'agenda')!
    expect(agenda.className).not.toContain('ribbon-icon-active')
  })

  it('honors a persisted ribbonOrder, appending any missing keys', () => {
    act(() => root.unmount())
    useSession.setState({ personalization: { sidebarMode: 'collections', ribbonOrder: ['settings', 'agenda'] } })
    root = createRoot(host)
    act(() => root.render(<Ribbon />))
    const labels = buttons()
      .slice(1)
      .map((b) => b.getAttribute('aria-label'))
    expect(labels.slice(0, 2)).toEqual(['settings', 'agenda'])
    expect(labels).toContain('collections')
    expect(labels).toContain('contexts')
    expect(labels).toContain('navigation')
  })
})
