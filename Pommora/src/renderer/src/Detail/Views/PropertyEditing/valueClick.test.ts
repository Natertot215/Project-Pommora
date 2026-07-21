import { describe, it, expect } from 'vitest'
import type { PropertyDefinition } from '@shared/properties'
import { sharedValueClickAction } from './valueClick'

const statusDef = {
  id: 'p1',
  name: 'Status',
  type: 'status',
  status_groups: [
    {
      id: 'upcoming',
      label: 'Upcoming',
      color: 'gray',
      options: [{ value: 'todo', label: 'Todo', group_id: 'upcoming' }],
    },
    {
      id: 'done',
      label: 'Done',
      color: 'green',
      options: [{ value: 'done', label: 'Done', group_id: 'done' }],
    },
  ],
} as unknown as PropertyDefinition

describe('sharedValueClickAction', () => {
  it('cycles a filled checkbox-look status', () => {
    const a = sharedValueClickAction(
      'status',
      'checkbox',
      { kind: 'status', value: 'todo' },
      statusDef,
    )
    expect(a).toEqual({ kind: 'commit', value: { kind: 'status', value: 'done' } })
  })

  it('an empty checkbox-look status assigns via picker — never a blind write', () => {
    expect(sharedValueClickAction('status', 'checkbox', { kind: 'null' }, statusDef)).toEqual({
      kind: 'picker',
    })
  })

  it('checkbox is true-or-absent: unchecked sets true, checked clears the key', () => {
    expect(sharedValueClickAction('checkbox', undefined, { kind: 'null' }, undefined)).toEqual({
      kind: 'commit',
      value: { kind: 'checkbox', value: true },
    })
    expect(
      sharedValueClickAction('checkbox', undefined, { kind: 'checkbox', value: true }, undefined),
    ).toEqual({ kind: 'commit', value: null })
  })

  it('option kinds open their picker; datetime opens the calendar', () => {
    for (const t of ['status', 'select', 'multi_select', 'context'])
      expect(sharedValueClickAction(t, 'pill', { kind: 'null' }, undefined)).toEqual({
        kind: 'picker',
      })
    expect(sharedValueClickAction('datetime', undefined, { kind: 'null' }, undefined)).toEqual({
      kind: 'datetime',
    })
  })

  it('number/url/file/title fall through to the surface tail', () => {
    for (const t of ['number', 'url', 'file', 'last_edited_time', undefined])
      expect(sharedValueClickAction(t, undefined, { kind: 'null' }, undefined)).toBeNull()
  })
})
