import { describe, it, expect } from 'vitest'
import fixture from '@shared/__fixtures__/collection-with-status.json'
import registry from '@shared/__fixtures__/registry.json'
import type { CollectionNode, PageNode } from '@shared/types'
import {
  savedView,
  mintDefaultView,
  DEFAULT_VIEW_ID,
  LOCATION_SORT,
  type SavedView,
} from '@shared/views'
import type { SetNode } from '@shared/types'
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
  pages,
})

describe('resolveView — Sort By: Location (cards)', () => {
  const setNode = (id: string, pages: PageNode[]): SetNode => ({
    kind: 'set',
    id,
    title: id,
    path: id,
    pages,
    sets: [],
  })
  const withSets: CollectionNode = {
    kind: 'collection',
    id: 'c',
    title: 'C',
    path: 'C',
    sets: [setNode('sA', [page('p_a')])],
    pages: [page('p_root')],
  }
  const cardsView = (patch: Partial<SavedView>): SavedView =>
    savedView.parse({
      id: 'v',
      name: 'V',
      type: 'cards',
      property_order: [],
      hidden_properties: [],
      ...patch,
    })

  it('Group: None + Sort By: Location (Location order) → one flat band in filesystem order', () => {
    const { rows, setTree } = flattenContainer(withSets, {})
    const view = cardsView({
      group: { kind: 'flat' },
      sort: [{ property_id: LOCATION_SORT, direction: 'ascending' }],
      structural_order_mode: 'location',
    })
    const { groups } = resolveView({ rows, setTree, view, schema: [], flattenStructural: true })
    expect(groups.map((g) => g.kind)).toEqual(['ungrouped'])
    expect(groups[0].items.map((r) => r.id)).toEqual(['p_a', 'p_root']) // set page, then the root tail
  })

  it('the reserved location primary contributes nothing to a table (no flattenStructural)', () => {
    const { rows, setTree } = flattenContainer(withSets, {})
    const view = cardsView({
      group: { kind: 'flat' },
      sort: [{ property_id: LOCATION_SORT, direction: 'ascending' }],
      structural_order_mode: 'location',
    })
    // Without flattenStructural the location flatten never engages — flat() yields one band, but the
    // pipeline never routes through the structural walk (the table can't be flattened by this field).
    const { groups } = resolveView({ rows, setTree, view, schema: [] })
    expect(groups.map((g) => g.kind)).toEqual(['ungrouped'])
  })
})

describe('resolveView — full pipeline over the fixture', () => {
  it('resolves columns (status-first) + grouped rows (manual order, empty band rendered, no-value tail)', () => {
    const view = savedView.parse(fixture.views[0])
    const schema = fixture.properties.map((id) =>
      propertyDefinition.parse((registry as Record<string, unknown>)[id]),
    )
    const values: Record<string, PageFrontmatter> = {
      p1: { id: 'p1', properties: { prop_status: { $status: 'in_progress' } } },
      p2: { id: 'p2', properties: { prop_status: { $status: 'opt_open' } } },
      p3: { id: 'p3', properties: { prop_status: { $status: 'not_started' } } },
      p4: { id: 'p4', properties: {} },
    }
    const { rows, setTree } = flattenContainer(
      collection([page('p1'), page('p2'), page('p3'), page('p4')]),
      values,
    )
    const { columns, groups } = resolveView({ rows, setTree, view, schema })

    expect(columns[0].id).toBe('prop_status')
    expect(columns.map((c) => c.id)).toEqual([
      'prop_status',
      '_title',
      '_tier3',
      '_tier2',
      '_tier1',
      'prop_when',
    ])
    // manual order ['in_progress','opt_open','not_started','done'] — done empty → an empty band; no-value tail last
    expect(groups.map((g) => g.key)).toEqual([
      'in_progress',
      'opt_open',
      'not_started',
      'done',
      '_ungrouped',
    ])
    expect(groups.find((g) => g.key === 'in_progress')?.items.map((r) => r.id)).toEqual(['p1'])
    expect(groups.find((g) => g.key === '_ungrouped')?.items.map((r) => r.id)).toEqual(['p4'])
    expect(groups.find((g) => g.key === 'done')?.items).toEqual([])
  })

  it('sorts rows within each group', () => {
    const schema: PropertyDefinition[] = [
      {
        id: 'prop_status',
        name: 'S',
        type: 'status',
        status_groups: [
          {
            id: 'in_progress',
            label: 'IP',
            color: 'blue',
            options: [{ value: 'in_progress', label: 'A', group_id: 'in_progress' }],
          },
        ],
      },
    ]
    const view: SavedView = {
      id: 'v',
      name: 'V',
      type: 'table',
      property_order: ['_title'],
      hidden_properties: [],
      group: {
        kind: 'property',
        property_id: 'prop_status',
        order_mode: 'configured',
        empty_placement: 'bottom',
        hide_empty_groups: false,
      },
      sort: [{ property_id: '_title', direction: 'descending' }],
    }
    const values: Record<string, PageFrontmatter> = {
      a: { id: 'a', properties: { prop_status: { $status: 'in_progress' } } },
      b: { id: 'b', properties: { prop_status: { $status: 'in_progress' } } },
    }
    const { rows, setTree } = flattenContainer(collection([page('a'), page('b')]), values)
    const { groups } = resolveView({ rows, setTree, view, schema })
    expect(groups.find((g) => g.key === 'in_progress')?.items.map((r) => r.id)).toEqual(['b', 'a'])
  })
})

describe('resolveView — group_order', () => {
  it('reorders structural bands from the view-level flat array (ungrouped stays last)', () => {
    const setNode = (id: string): CollectionNode['sets'][number] => ({
      kind: 'set',
      id,
      title: id,
      path: id,
      pages: [],
      sets: [],
    })
    const col: CollectionNode = {
      kind: 'collection',
      id: 'col',
      title: 'Col',
      path: 'Col',
      sets: [setNode('sA'), setNode('sB')],
      pages: [page('loose')],
    }
    const view: SavedView = {
      id: 'v',
      name: 'V',
      type: 'table',
      property_order: ['_title'],
      hidden_properties: [],
      group: { kind: 'structural' },
      group_order: ['sB', 'sA'],
    }
    const { rows, setTree } = flattenContainer(col, {})
    const { groups } = resolveView({ rows, setTree, view, schema: [] })
    expect(groups.map((g) => g.key)).toEqual(['sB', 'sA', '_ungrouped'])
  })

  it('structural_order_mode location ignores group_order (fs order wins, preserved not cleared)', () => {
    const setNode = (id: string): CollectionNode['sets'][number] => ({
      kind: 'set',
      id,
      title: id,
      path: id,
      pages: [],
      sets: [],
    })
    const col: CollectionNode = {
      kind: 'collection',
      id: 'col',
      title: 'Col',
      path: 'Col',
      sets: [setNode('sA'), setNode('sB')],
      pages: [],
    }
    const view: SavedView = {
      id: 'v',
      name: 'V',
      type: 'table',
      property_order: ['_title'],
      hidden_properties: [],
      group: { kind: 'structural' },
      structural_order_mode: 'location',
      group_order: ['sB', 'sA'],
    }
    const { rows, setTree } = flattenContainer(col, {})
    const { groups } = resolveView({ rows, setTree, view, schema: [] })
    expect(groups.map((g) => g.key)).toEqual(['sA', 'sB'])
    expect(view.group_order).toEqual(['sB', 'sA'])
  })

  it('location mode under PROPERTY grouping is inert (the mode is structural-only)', () => {
    const view = savedView.parse({
      ...fixture.views[0],
      structural_order_mode: 'location',
    })
    const schema = fixture.properties.map((id) =>
      propertyDefinition.parse((registry as Record<string, unknown>)[id]),
    )
    const { rows, setTree } = flattenContainer(collection([page('p1')]), {
      p1: { id: 'p1', properties: {} },
    })
    expect(() => resolveView({ rows, setTree, view, schema })).not.toThrow()
  })

  it('a DEAD-property grouping is effectively structural: location gate honored, tail placed, sub-group threaded', () => {
    const nested: CollectionNode = {
      kind: 'collection',
      id: 'col',
      title: 'Col',
      path: 'Col',
      sets: [
        { kind: 'set', id: 's1', title: 'S1', path: 'Col/S1', sets: [], pages: [page('p1')] },
        { kind: 'set', id: 's2', title: 'S2', path: 'Col/S2', sets: [], pages: [page('p2')] },
      ],
      pages: [page('root1')],
    }
    const schema: PropertyDefinition[] = [
      {
        id: 'prop_status',
        name: 'S',
        type: 'status',
        status_groups: [
          {
            id: 'g',
            label: 'G',
            color: 'blue',
            options: [{ value: 'todo', label: 'T', group_id: 'g' }],
          },
        ],
      },
    ]
    const values: Record<string, PageFrontmatter> = {
      p1: { id: 'p1', properties: { prop_status: { $status: 'todo' } } },
      p2: { id: 'p2', properties: {} },
      root1: { id: 'root1', properties: {} },
    }
    const base: SavedView = {
      id: 'v',
      name: 'V',
      type: 'table',
      property_order: ['_title'],
      hidden_properties: [],
      group: {
        kind: 'property',
        property_id: 'prop_gone',
        order_mode: 'configured',
        empty_placement: 'bottom',
        hide_empty_groups: false,
      },
    }
    const { rows, setTree } = flattenContainer(nested, values)
    // Location ignores group_order (fs order stands) and the view-level tail placement holds top.
    const located = resolveView({
      rows,
      setTree,
      view: {
        ...base,
        structural_order_mode: 'location',
        group_order: ['s2', 's1'],
        ungrouped_placement: 'top',
      },
      schema,
    })
    expect(located.groups.map((g) => g.key)).toEqual(['_ungrouped', 's1', 's2'])
    // The sub-group buckets inside the structural fallback exactly as under real Location grouping.
    const subbed = resolveView({
      rows,
      setTree,
      view: { ...base, sub_group: { property_id: 'prop_status', order_mode: 'configured' } },
      schema,
    })
    expect(
      subbed.groups.find((g) => g.key === 's1')?.children?.map((c) => c.bucket ?? c.key),
    ).toEqual(['todo'])
  })
})

describe('mintDefaultView', () => {
  it('mints a Table view: sentinel id, Title-first, all user props, structural, no sort or _modified_at', () => {
    const schema: PropertyDefinition[] = [
      { id: 'prop_x', name: 'X', type: 'select' },
      { id: 'prop_y', name: 'Y', type: 'number' },
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
