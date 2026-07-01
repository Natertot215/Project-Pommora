import { describe, it, expect } from 'vitest'
import fixture from '@shared/__fixtures__/collection-with-status.json'
import registry from '@shared/__fixtures__/registry.json'
import type { CollectionNode, PageNode } from '@shared/types'
import { savedView, mintDefaultView, DEFAULT_VIEW_ID, type SavedView } from '@shared/views'
import { propertyDefinition, type PropertyDefinition } from '@shared/properties'
import type { PageFrontmatter } from '@shared/schemas'
import { flattenContainer } from './group'
import { resolveView } from './resolveView'

const page = (id: string): PageNode => ({ kind: 'page', id, title: id, path: `${id}.md` })
const collection = (pages: PageNode[]): CollectionNode => ({
  kind: 'collection',
  id: 'col',
  title: 'Col',
  path: 'Col',
  sets: [],
  pages
})

describe('resolveView — full pipeline over the fixture', () => {
  it('resolves columns (status-first) + grouped rows (manual order, empty bucket dropped, no-value band)', () => {
    const view = savedView.parse(fixture.views[0])
    const schema = fixture.properties.map((id) =>
      propertyDefinition.parse((registry as Record<string, unknown>)[id])
    )
    const values: Record<string, PageFrontmatter> = {
      p1: { id: 'p1', properties: { prop_status: { $status: 'in_progress' } } },
      p2: { id: 'p2', properties: { prop_status: { $status: 'opt_open' } } },
      p3: { id: 'p3', properties: { prop_status: { $status: 'not_started' } } },
      p4: { id: 'p4', properties: {} }
    }
    const { rows, setTree } = flattenContainer(collection([page('p1'), page('p2'), page('p3'), page('p4')]), values)
    const { columns, groups } = resolveView({ rows, setTree, view, schema })

    expect(columns[0].id).toBe('prop_status')
    expect(columns.map((c) => c.id)).toEqual(['prop_status', '_title', '_tier3', '_tier2', '_tier1', 'prop_when'])
    // manual order ['in_progress','opt_open','not_started','done'] — done empty → dropped; no-value band last
    expect(groups.map((g) => g.key)).toEqual(['in_progress', 'opt_open', 'not_started', '_ungrouped'])
    expect(groups.find((g) => g.key === 'in_progress')?.items.map((r) => r.id)).toEqual(['p1'])
    expect(groups.find((g) => g.key === '_ungrouped')?.items.map((r) => r.id)).toEqual(['p4'])
    expect(groups.some((g) => g.key === 'done')).toBe(false)
  })

  it('sorts rows within each group', () => {
    const schema: PropertyDefinition[] = [
      {
        id: 'prop_status',
        name: 'S',
        type: 'status',
        status_groups: [
          { id: 'in_progress', label: 'IP', color: 'blue', options: [{ value: 'in_progress', label: 'A', group_id: 'in_progress' }] }
        ]
      }
    ]
    const view: SavedView = {
      id: 'v',
      name: 'V',
      type: 'table',
      property_order: ['_title'],
      hidden_properties: [],
      group: { kind: 'property', property_id: 'prop_status', order_mode: 'configured', empty_placement: 'bottom', hide_empty_groups: false },
      sort: [{ property_id: '_title', direction: 'descending' }]
    }
    const values: Record<string, PageFrontmatter> = {
      a: { id: 'a', properties: { prop_status: { $status: 'in_progress' } } },
      b: { id: 'b', properties: { prop_status: { $status: 'in_progress' } } }
    }
    const { rows, setTree } = flattenContainer(collection([page('a'), page('b')]), values)
    const { groups } = resolveView({ rows, setTree, view, schema })
    expect(groups.find((g) => g.key === 'in_progress')?.items.map((r) => r.id)).toEqual(['b', 'a'])
  })
})

describe('mintDefaultView', () => {
  it('mints a Table view: sentinel id, Title-first, all user props, structural, no sort or _modified_at', () => {
    const schema: PropertyDefinition[] = [
      { id: 'prop_x', name: 'X', type: 'select' },
      { id: 'prop_y', name: 'Y', type: 'number' }
    ]
    const v = mintDefaultView(schema)
    expect(v.id).toBe(DEFAULT_VIEW_ID)
    expect(v.id).toBe('view_default')
    expect(v.type).toBe('table')
    expect(v.property_order).toEqual(['_title', 'prop_x', 'prop_y'])
    expect(v.group).toEqual({ kind: 'structural' })
    expect(v.sort).toBeUndefined()
    expect(v.property_order).not.toContain('_modified_at')
  })
})
