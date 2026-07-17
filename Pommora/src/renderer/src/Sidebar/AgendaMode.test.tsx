// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { AgendaListResult } from '@shared/types'
import { AgendaMode } from './AgendaMode'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

let host: HTMLDivElement
let root: Root

function stubList(result: AgendaListResult): void {
  ;(globalThis as { window?: unknown }).window = globalThis
  ;(globalThis as { nexus?: unknown }).nexus = { agenda: { list: vi.fn(async () => result) } }
}

async function mount(): Promise<void> {
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
  await act(async () => {
    root.render(<AgendaMode />)
  })
  // Let the list-fetch promise resolve and re-render.
  await act(async () => {
    await Promise.resolve()
  })
}

afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

describe('AgendaMode', () => {
  it('renders tasks then events from the IPC', async () => {
    stubList({
      ok: true,
      tasks: [{ id: 't1', title: 'Buy milk', kind: 'task' }],
      events: [{ id: 'e1', title: 'Standup', kind: 'event' }],
    })
    await mount()
    const text = host.textContent ?? ''
    expect(text).toContain('Buy milk')
    expect(text).toContain('Standup')
  })

  it('shows the empty state when there are none', async () => {
    stubList({ ok: true, tasks: [], events: [] })
    await mount()
    expect(host.textContent).toContain('No tasks or events')
  })
})
