import { describe, expect, it } from 'vitest'
import type { PropertyDefinition } from '@shared/properties'
import { statusGroupOf } from './statusCycle'

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
