import { describe, expect, it } from 'vitest'
import { cellMenuModel } from './cellMenu'

describe('cellMenuModel', () => {
  it('title: Rename + Change Icon + separator-gated Delete', () => {
    const m = cellMenuModel({ kind: 'title' })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([
      ['Rename', 'title:rename'],
      ['Change Icon', 'title:icon'],
      ['Delete', 'title:delete']
    ])
    expect(m.items.find((i) => i.action === 'title:delete')?.separatorBefore).toBe(true)
    expect(m.style).toBeUndefined()
  })

  it('style-only: the per-type Style radios, no plain items', () => {
    const m = cellMenuModel({ kind: 'style-only', type: 'status', current: { look: 'pill' } })
    expect(m.items).toEqual([])
    expect(m.style?.map((r) => r.label)).toEqual(['Pill', 'Capsule', 'Checkbox'])
    expect(m.style?.find((r) => r.value === 'pill')?.checked).toBe(true)
  })

  it('style-edit: Style radios plus the Edit entry', () => {
    const m = cellMenuModel({ kind: 'style-edit', type: 'url', current: { look: 'full' } })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([['Edit', 'cell:edit']])
    expect(m.style?.map((r) => r.label)).toEqual(['Title', 'Full Link'])
  })
})
