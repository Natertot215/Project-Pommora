import { describe, expect, it } from 'vitest'
import { cardMenuModel } from './cardMenu'

describe('cardMenuModel', () => {
  it('lists the page-meta actions with separators (Open lead, Delete gated)', () => {
    const m = cardMenuModel({ addable: [] })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([
      ['Open in New Tab', 'title:newtab'],
      ['Rename', 'title:rename'],
      ['Change Icon', 'title:icon'],
      ['Delete', 'title:delete'],
    ])
    expect(m.items.find((i) => i.action === 'title:rename')?.separatorBefore).toBe(true)
    expect(m.items.find((i) => i.action === 'title:delete')?.separatorBefore).toBe(true)
  })

  it('an open page reads "Open"', () => {
    expect(cardMenuModel({ addable: [], alreadyOpen: true }).items[0].label).toBe('Open')
  })

  it('builds the Add Property submenu from the addable list, preserving order', () => {
    const m = cardMenuModel({
      addable: [
        { id: 'p1', name: 'Tags' },
        { id: 'p2', name: 'Due' },
      ],
    })
    expect(m.addProperty?.map((a) => [a.label, a.action])).toEqual([
      ['Tags', 'add:p1'],
      ['Due', 'add:p2'],
    ])
  })

  it('omits the Add Property submenu when nothing is addable', () => {
    expect(cardMenuModel({ addable: [] }).addProperty).toBeUndefined()
  })
})
