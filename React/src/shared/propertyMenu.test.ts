import { describe, expect, it } from 'vitest'
import { propertyMenuModel } from './propertyMenu'

describe('propertyMenuModel', () => {
  it('editor ⋮ yields Remove then a destructive Delete (A-8)', () => {
    expect(propertyMenuModel({ kind: 'editor', name: 'Status' })).toEqual([
      { label: 'Remove', action: 'property:remove' },
      { label: 'Delete', action: 'property:destroy', destructive: true }
    ])
  })

  it('an assigned row yields Rename · Remove (A-10)', () => {
    expect(propertyMenuModel({ kind: 'assigned-row', name: 'Status' }).map((i) => i.action)).toEqual([
      'property:rename',
      'property:remove'
    ])
  })

  it('a registry row yields Rename only', () => {
    expect(propertyMenuModel({ kind: 'registry-row', name: 'Effort' }).map((i) => i.action)).toEqual(['property:rename'])
  })
})
