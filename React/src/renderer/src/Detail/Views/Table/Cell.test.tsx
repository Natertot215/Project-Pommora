// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { ColumnStyle } from '@shared/columnStyles'
import type { PropertyDefinition } from '@shared/properties'
import type { ResolvedColumn, ViewRow } from '@shared/types'
import { Cell } from './Cell'
import type { ResolveContext } from './resolveContext'
;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

// The Switch's GlassSegment (liquid glass) measures itself; jsdom has no ResizeObserver.
class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
;(globalThis as { ResizeObserver?: unknown }).ResizeObserver = ResizeObserverStub

const schema: PropertyDefinition[] = [
  {
    id: 'prop_status',
    name: 'Status',
    type: 'status',
    status_groups: [
      {
        id: 'upcoming',
        label: 'Upcoming',
        color: 'gray',
        options: [{ value: 'not_started', label: 'Not started', group_id: 'upcoming' }]
      },
      {
        id: 'in_progress',
        label: 'In Progress',
        color: 'blue',
        options: [{ value: 'active', label: 'Active', color: 'blue', group_id: 'in_progress' }]
      },
      {
        id: 'done',
        label: 'Done',
        color: 'green',
        options: [{ value: 'complete', label: 'Complete', color: 'green', group_id: 'done' }]
      }
    ]
  },
  { id: 'prop_done', name: 'Done', type: 'checkbox' },
  { id: 'prop_when', name: 'When', type: 'datetime' },
  { id: 'prop_n', name: 'Count', type: 'number' },
  { id: 'prop_files', name: 'Files', type: 'file' }
]
const ctx = { schema, contextsById: new Map() } as unknown as ResolveContext

const col = (id: string): ResolvedColumn => ({ id, kind: 'property' })
const rowWith = (properties: Record<string, unknown>): ViewRow =>
  ({ id: 'p1', title: 'Page', path: 'X/Page.md', frontmatter: { id: 'p1', properties } }) as unknown as ViewRow

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

const mount = (row: ViewRow, columnId: string, style: ColumnStyle): void => {
  act(() => root.render(<Cell row={row} column={col(columnId)} ctx={ctx} hideIcon={false} style={style} />))
}

describe('status looks', () => {
  const row = rowWith({ prop_status: { $status: 'active' } })

  it('pill renders the labeled chip', () => {
    mount(row, 'prop_status', { look: 'pill' })
    expect(host.textContent).toContain('Active')
  })

  it('capsule renders the icon-only chip — glyph by group, no label', () => {
    mount(row, 'prop_status', { look: 'capsule' })
    expect(host.textContent).not.toContain('Active')
    expect(host.querySelector('svg')).toBeTruthy()
  })

  it('checkbox renders the square with the group glyph — empty for upcoming, filled past it', () => {
    mount(rowWith({ prop_status: { $status: 'not_started' } }), 'prop_status', { look: 'checkbox' })
    expect(host.querySelector('svg')).toBeNull()
    mount(rowWith({ prop_status: { $status: 'complete' } }), 'prop_status', { look: 'checkbox' })
    expect(host.querySelector('svg')).toBeTruthy()
    expect(host.textContent).not.toContain('Complete')
  })
})

describe('checkbox looks', () => {
  it('switch renders the real Switch, checked from the value', () => {
    mount(rowWith({ prop_done: true }), 'prop_done', { look: 'switch' })
    const sw = host.querySelector('[role="switch"]')
    expect(sw).toBeTruthy()
    expect(sw?.getAttribute('aria-checked')).toBe('true')
  })

  it('checkbox keeps the chip square', () => {
    mount(rowWith({ prop_done: true }), 'prop_done', { look: 'checkbox' })
    expect(host.querySelector('[role="switch"]')).toBeNull()
    expect(host.querySelector('svg')).toBeTruthy()
  })
})

describe('formats', () => {
  it('datetime renders per the saved formats', () => {
    mount(rowWith({ prop_when: '2026-03-01' }), 'prop_when', { date_format: 'short', time_format: 'none' })
    expect(host.textContent).toBe('March 1st')
  })

  it('number renders per the saved format', () => {
    mount(rowWith({ prop_n: 0.42 }), 'prop_n', { number_format: 'percent' })
    expect(host.textContent).toBe('42%')
  })
})

describe('file looks', () => {
  const row = rowWith({ prop_files: [{ path: 'Assets/Photos/trip.png' }, { path: 'doc.pdf' }] })

  it('filename renders one chip per file, directory stripped', () => {
    mount(row, 'prop_files', { look: 'filename' })
    expect(host.textContent).toContain('trip.png')
    expect(host.textContent).toContain('doc.pdf')
    expect(host.textContent).not.toContain('Assets/Photos')
  })

  it('path renders the full path per chip', () => {
    mount(row, 'prop_files', { look: 'path' })
    expect(host.textContent).toContain('Assets/Photos/trip.png')
  })
})
