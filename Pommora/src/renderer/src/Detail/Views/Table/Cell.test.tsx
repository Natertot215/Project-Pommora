// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import type { ColumnStyle } from '@shared/columnStyles'
import type { PropertyDefinition } from '@shared/properties'
import type { ResolvedColumn, ViewRow } from '@shared/types'
import { chipColor } from '@renderer/design-system/tokens'
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
  { id: 'prop_pin', name: 'Pinned', type: 'checkbox', checkbox_color: 'blue' },
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

  it('renders the empty box even with no stored value — always checkable in place', () => {
    mount(rowWith({}), 'prop_done', { look: 'checkbox' })
    expect(host.querySelector('span')).toBeTruthy() // the box renders...
    expect(host.querySelector('svg')).toBeNull() // ...unchecked, no glyph
  })

  it('switch renders unchecked with no stored value', () => {
    mount(rowWith({}), 'prop_done', { look: 'switch' })
    expect(host.querySelector('[role="switch"]')?.getAttribute('aria-checked')).toBe('false')
  })

  it('checked box tints the property color, check at label-control', () => {
    mount(rowWith({ prop_pin: true }), 'prop_pin', { look: 'checkbox' })
    const box = host.querySelector('span')
    expect(box?.style.background).not.toBe('') // tinted fill, not the grey default class
    expect(box?.className).not.toContain(chipColor.default)
    expect(box?.style.color).toBe('var(--label-control)')
  })

  it('unchecked box is the neutral grey default, untinted', () => {
    mount(rowWith({}), 'prop_pin', { look: 'checkbox' })
    const box = host.querySelector('span')
    expect(box?.className).toContain(chipColor.default)
    expect(box?.style.background).toBe('')
  })

  it('a colorless checked box tints the configured accent via var(--accent), matching the switch', () => {
    mount(rowWith({ prop_done: true }), 'prop_done', { look: 'checkbox' }) // prop_done has no checkbox_color
    const box = host.querySelector('span')
    expect(box?.style.background).toContain('var(--accent)')
  })

  it('scopes --accent to the property color so the switch on-track tints', () => {
    mount(rowWith({ prop_pin: true }), 'prop_pin', { look: 'switch' })
    const wrap = host.querySelector('span')
    expect(wrap?.style.getPropertyValue('--accent')).not.toBe('')
  })

  it('leaves --accent unset when no color is chosen so the switch inherits the configured accent', () => {
    mount(rowWith({ prop_done: true }), 'prop_done', { look: 'switch' })
    const wrap = host.querySelector('span')
    expect(wrap?.style.getPropertyValue('--accent')).toBe('')
  })
})

describe('formats', () => {
  it('datetime renders per the saved formats', () => {
    mount(rowWith({ prop_when: '2026-03-01' }), 'prop_when', { date_format: 'short', time_format: 'none' })
    expect(host.textContent).toBe('March 1st')
  })

  it('number renders per the def-level format (grouped by default)', () => {
    mount(rowWith({ prop_n: 1234.5 }), 'prop_n', {})
    expect(host.textContent).toBe('1,234.5')
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
