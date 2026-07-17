import { describe, expect, it } from 'vitest'
import { cellMenuModel } from './cellMenu'

describe('cellMenuModel', () => {
  it('title: stateful Open lead + Rename + Change Icon + separator-gated Delete', () => {
    const m = cellMenuModel({ kind: 'title' })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([
      ['Open in New Tab', 'title:newtab'],
      ['Rename', 'title:rename'],
      ['Change Icon', 'title:icon'],
      ['Delete', 'title:delete'],
    ])
    // An already-open page reads "Open" (focus, I-1) — same action either way.
    expect(cellMenuModel({ kind: 'title', alreadyOpen: true }).items[0].label).toBe('Open')
    expect(m.items.find((i) => i.action === 'title:rename')?.separatorBefore).toBe(true)
    expect(m.items.find((i) => i.action === 'title:delete')?.separatorBefore).toBe(true)
    expect(m.style).toBeUndefined()
  })

  it('style-only: the per-type Style radios, no plain items', () => {
    const m = cellMenuModel({ kind: 'style-only', type: 'number', current: { look: 'bar' } })
    expect(m.items).toEqual([])
    expect(m.style?.map((r) => r.label)).toEqual(['Number', 'Bar'])
  })

  it('a clearable style-only (status) adds Clear under the Style radios', () => {
    const m = cellMenuModel({
      kind: 'style-only',
      type: 'status',
      current: { look: 'pill' },
      clearable: true,
    })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([['Clear', 'cell:clear']])
    expect(m.style?.map((r) => r.label)).toEqual(['Pill', 'Capsule', 'Checkbox'])
    expect(m.style?.find((r) => r.value === 'pill')?.checked).toBe(true)
  })

  it('clear-only (select/multi/context/tier): just Clear', () => {
    const m = cellMenuModel({ kind: 'clear-only' })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([['Clear', 'cell:clear']])
    expect(m.style).toBeUndefined()
  })

  it('style-edit: Style radios plus the Edit entry', () => {
    const m = cellMenuModel({ kind: 'style-edit', type: 'url', current: { look: 'full' } })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([['Edit', 'cell:edit']])
    expect(m.style?.map((r) => r.label)).toEqual(['Title', 'Full Link'])
  })

  it('link (a filled url cell): Edit + Rename + Remove, no Style (its look is per-property)', () => {
    const m = cellMenuModel({ kind: 'link', filled: true })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([
      ['Edit', 'cell:edit'],
      ['Rename', 'cell:rename'],
      ['Remove', 'cell:clear'],
    ])
    expect(m.style).toBeUndefined()
  })

  it('link (an empty url cell): Edit alone — Rename/Remove are no-ops with no value', () => {
    const m = cellMenuModel({ kind: 'link', filled: false })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([['Edit', 'cell:edit']])
  })
})
