import { describe, expect, it } from 'vitest'
import type { PropertyDefinition } from '@shared/properties'
import { nextCycleValue, statusGroupOf } from './statusCycle'

const def: PropertyDefinition = {
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
      options: [{ value: 'active', label: 'Active', group_id: 'in_progress' }]
    },
    {
      id: 'done',
      label: 'Done',
      color: 'green',
      options: [{ value: 'complete', label: 'Complete', group_id: 'done' }]
    }
  ]
}

describe('statusGroupOf', () => {
  it('maps a value to its fixed group id', () => {
    expect(statusGroupOf('not_started', def)).toBe('upcoming')
    expect(statusGroupOf('active', def)).toBe('in_progress')
    expect(statusGroupOf('complete', def)).toBe('done')
  })

  it('returns undefined for an unknown value or a missing def', () => {
    expect(statusGroupOf('nope', def)).toBeUndefined()
    expect(statusGroupOf('active', undefined)).toBeUndefined()
  })
})

describe('nextCycleValue', () => {
  it('advances group→group, writing each group\'s first-in-order option', () => {
    expect(nextCycleValue('not_started', def)).toBe('active')
    expect(nextCycleValue('active', def)).toBe('complete')
  })

  it('wraps done back to the upcoming (empty-box) state', () => {
    expect(nextCycleValue('complete', def)).toBe('not_started')
  })

  it('a null or unknown current reads as the empty box (upcoming) and advances', () => {
    expect(nextCycleValue(undefined, def)).toBe('active')
    expect(nextCycleValue('rogue', def)).toBe('active')
  })

  it('skips a group with no options', () => {
    const gappy: PropertyDefinition = {
      ...def,
      status_groups: def.status_groups?.map((g) => (g.id === 'in_progress' ? { ...g, options: [] } : g))
    }
    expect(nextCycleValue('not_started', gappy)).toBe('complete')
  })

  it('returns null when no group holds any option', () => {
    const empty: PropertyDefinition = { ...def, status_groups: def.status_groups?.map((g) => ({ ...g, options: [] })) }
    expect(nextCycleValue('x', empty)).toBeNull()
  })

  it('picks the FIRST option of a multi-option group', () => {
    const wide: PropertyDefinition = {
      ...def,
      status_groups: def.status_groups?.map((g) =>
        g.id === 'in_progress'
          ? { ...g, options: [{ value: 'first_ip', label: 'F', group_id: 'in_progress' as const }, ...g.options] }
          : g
      )
    }
    expect(nextCycleValue('not_started', wide)).toBe('first_ip')
  })
})
