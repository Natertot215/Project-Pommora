import { describe, it, expect } from 'vitest'
import { addOption, addStatusOption, renameOption, recolorOption, reorderOption, fallbackTitle } from './optionModel'
import type { StatusGroup } from './properties'

const opt = (t: string, color?: string) => ({ value: t, label: t, ...(color ? { color } : {}) })

describe('optionModel', () => {
  it('addOption appends an uncolored option (renders default) with value=label=title', () => {
    expect(addOption([opt('A')], 'B')).toEqual([opt('A'), { value: 'B', label: 'B' }])
  })

  it('fallbackTitle yields Label for select and the group name for status', () => {
    expect(fallbackTitle('select')).toBe('Label')
    expect(fallbackTitle('status', 'Active')).toBe('Active')
  })

  it('renameOption rewrites value+label together (stable identity is the OLD value)', () => {
    expect(renameOption([opt('A'), opt('B')], 'A', 'C')).toEqual([{ value: 'C', label: 'C' }, opt('B')])
  })

  it('recolorOption sets the color key; clearing removes it', () => {
    expect(recolorOption([opt('A')], 'A', 'blue')).toEqual([{ value: 'A', label: 'A', color: 'blue' }])
    expect(recolorOption([opt('A', 'blue')], 'A', undefined)).toEqual([opt('A')])
  })

  it('reorderOption moves an option to a new index', () => {
    expect(reorderOption([opt('A'), opt('B'), opt('C')], 'C', 0)).toEqual([opt('C'), opt('A'), opt('B')])
  })

  it('addStatusOption appends to the matched group only, carrying its group_id', () => {
    const groups: StatusGroup[] = [
      { id: 'upcoming', label: 'Open', color: 'grey', options: [{ value: 'Open', label: 'Open', group_id: 'upcoming' }] },
      { id: 'done', label: 'Done', color: 'green', options: [{ value: 'Done', label: 'Done', group_id: 'done' }] }
    ]
    const next = addStatusOption(groups, 'upcoming', 'Backlog')
    expect(next[0].options).toEqual([
      { value: 'Open', label: 'Open', group_id: 'upcoming' },
      { value: 'Backlog', label: 'Backlog', group_id: 'upcoming' }
    ])
    expect(next[1]).toBe(groups[1]) // the other group is left untouched (same reference)
  })
})
