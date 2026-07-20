import { describe, expect, it } from 'vitest'
import { cellMenuContextFor, cellMenuModel } from './cellMenu'
import type { ResolvedColumn } from './types'

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

  it('link (a filled url cell): Edit + Rename + Clear, no Style (its look is per-property)', () => {
    const m = cellMenuModel({ kind: 'link', filled: true })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([
      ['Edit', 'cell:edit'],
      ['Rename', 'cell:rename'],
      ['Clear', 'cell:clear'],
    ])
    expect(m.style).toBeUndefined()
  })

  it('link (an empty url cell): Edit alone — Rename/Clear are no-ops with no value', () => {
    const m = cellMenuModel({ kind: 'link', filled: false })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([['Edit', 'cell:edit']])
  })

  it('hideable (cards) appends a separated Remove after the base items', () => {
    const m = cellMenuModel({ kind: 'clear-only', hideable: true })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([
      ['Clear', 'cell:clear'],
      ['Remove', 'cell:hide'],
    ])
    expect(m.items.find((i) => i.action === 'cell:hide')?.separatorBefore).toBe(true)
  })

  it('remove-only (a hideable cell with no other menu): Remove alone, no separator', () => {
    const m = cellMenuModel({ kind: 'remove-only', hideable: true })
    expect(m.items.map((i) => [i.label, i.action])).toEqual([['Remove', 'cell:hide']])
    expect(m.items[0].separatorBefore).toBe(false)
  })

  it('a hideable title never gets Remove — the title can never be dropped', () => {
    const m = cellMenuModel({ kind: 'title', hideable: true })
    expect(m.items.some((i) => i.action === 'cell:hide')).toBe(false)
  })
})

describe('cellMenuContextFor', () => {
  const prop = (id = 'p'): ResolvedColumn => ({ id, kind: 'property' })

  it('a title column → the page-meta title menu', () => {
    expect(cellMenuContextFor({ id: 'title', kind: 'title' }, 'title', {}, true)).toEqual({
      kind: 'title',
    })
  })

  it('a tier column → clear-only when filled, no menu when empty', () => {
    const tier: ResolvedColumn = { id: 'tier1', kind: 'tier' }
    expect(cellMenuContextFor(tier, 'tier', {}, true)).toEqual({ kind: 'clear-only' })
    expect(cellMenuContextFor(tier, 'tier', {}, false)).toBeNull()
  })

  it('url → link (carrying filled); file → style-edit with the column style', () => {
    expect(cellMenuContextFor(prop(), 'url', {}, true)).toEqual({ kind: 'link', filled: true })
    expect(cellMenuContextFor(prop(), 'file', {}, false)).toEqual({
      kind: 'style-edit',
      type: 'file',
      current: {},
    })
  })

  it('status/datetime → style-only, Clear gated on filled', () => {
    expect(cellMenuContextFor(prop(), 'status', {}, true)).toEqual({
      kind: 'style-only',
      type: 'status',
      current: {},
      clearable: true,
    })
    expect(cellMenuContextFor(prop(), 'status', {}, false)).toEqual({
      kind: 'style-only',
      type: 'status',
      current: {},
      clearable: false,
    })
  })

  it('checkbox/number/last_edited_time → style-only with no Clear', () => {
    expect(cellMenuContextFor(prop(), 'number', {}, true)).toEqual({
      kind: 'style-only',
      type: 'number',
      current: {},
    })
  })

  it('select/multi/context → clear-only when filled, no menu when empty', () => {
    expect(cellMenuContextFor(prop(), 'select', {}, true)).toEqual({ kind: 'clear-only' })
    expect(cellMenuContextFor(prop(), 'multi_select', {}, false)).toBeNull()
  })

  it('an unsupported/undefined type → no menu', () => {
    expect(cellMenuContextFor(prop(), undefined, {}, true)).toBeNull()
  })

  it('hideable (cards): a filled cell carries hideable; a menu-less cell becomes remove-only', () => {
    expect(cellMenuContextFor(prop(), 'select', {}, true, true)).toEqual({
      kind: 'clear-only',
      hideable: true,
    })
    // Empty select would be null (no menu) — but hideable still needs a Remove, so it's remove-only.
    expect(cellMenuContextFor(prop(), 'select', {}, false, true)).toEqual({ kind: 'remove-only' })
    expect(cellMenuContextFor(prop(), undefined, {}, true, true)).toEqual({ kind: 'remove-only' })
  })
})
