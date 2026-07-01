import { describe, it, expect } from 'vitest'
import { mergeOverrides } from './viewMerge'
import type { SavedView } from '@shared/views'

const base = (over: Partial<SavedView> = {}): SavedView =>
  ({
    id: 'v',
    name: 'V',
    type: 'table',
    property_order: ['_title'],
    hidden_properties: [],
    column_widths: { _title: 200 },
    collapsed_groups: [],
    sort: [],
    ...over
  }) as SavedView

describe('mergeOverrides', () => {
  it('folds the width + collapse overrides into the persisted view', () => {
    const out = mergeOverrides(base(), { _title: 300 }, {}, new Set(['g1']), {})
    expect(out.column_widths).toEqual({ _title: 300 })
    expect(out.collapsed_groups).toEqual(['g1'])
  })

  it('a patch (e.g. hide) does NOT drop an unsaved width, align, or collapse override — H-2', () => {
    const out = mergeOverrides(base(), { _title: 300 }, { a: 'center' }, new Set(['g1']), { hidden_properties: ['x'] })
    expect(out.hidden_properties).toEqual(['x']) // the patch applied
    expect(out.column_widths?._title).toBe(300) // ...without dropping the resize
    expect(out.column_alignments?.a).toBe('center') // ...or the alignment
    expect(out.collapsed_groups).toEqual(['g1']) // ...or the collapse
  })

  it('overlays the width + align overrides on the saved maps, keeping untouched columns', () => {
    const view = base({ column_widths: { _title: 200, a: 100 }, column_alignments: { a: 'center' } })
    const out = mergeOverrides(view, { a: 150 }, { b: 'right' }, new Set(), {})
    expect(out.column_widths).toEqual({ _title: 200, a: 150 })
    expect(out.column_alignments).toEqual({ a: 'center', b: 'right' })
  })

  it('an explicit column_widths patch wins over the fold (the resize-commit path)', () => {
    const out = mergeOverrides(base(), { a: 150 }, {}, new Set(), { column_widths: { a: 150, _title: 250 } })
    expect(out.column_widths).toEqual({ a: 150, _title: 250 })
  })
})
