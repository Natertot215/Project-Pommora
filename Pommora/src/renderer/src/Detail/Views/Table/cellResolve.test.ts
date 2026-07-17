import { describe, it, expect } from 'vitest'
import {
  buildSetIcons,
  buildSetNames,
  cellText,
  findOption,
  groupLabel,
  optionLabel,
} from './cellResolve'
import {
  DEFAULT_LABELS,
  UNGROUPED,
  type CollectionNode,
  type ResolvedGroup,
  type ViewRow,
} from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type { ResolveContext } from './resolveContext'

const schema: PropertyDefinition[] = [
  {
    id: 'prop_status',
    name: 'Status',
    type: 'status',
    status_groups: [
      {
        id: 'in_progress',
        label: 'In Progress',
        color: 'blue',
        options: [{ value: 'doing', label: 'Doing', group_id: 'in_progress' }],
      },
    ],
  },
  {
    id: 'prop_tag',
    name: 'Tag',
    type: 'select',
    select_options: [{ value: 'opt_a', label: 'Alpha', color: 'green' }],
  },
]

const ctx: ResolveContext = {
  schema,
  contextsById: new Map([['ctx1', { title: 'Personal' }]]),
  labels: DEFAULT_LABELS,
}

const mkRow = (fm: Record<string, unknown>): ViewRow => ({
  id: 'p1',
  title: 'Page',
  path: 'p',
  frontmatter: { id: 'p1', ...fm } as ViewRow['frontmatter'],
})

describe('optionLabel', () => {
  it('resolves a select option value to its label', () => {
    expect(optionLabel('prop_tag', 'opt_a', schema)).toBe('Alpha')
  })
  it('resolves a status option value to its label', () => {
    expect(optionLabel('prop_status', 'doing', schema)).toBe('Doing')
  })
  it('returns undefined for an unknown value', () => {
    expect(optionLabel('prop_tag', 'opt_zz', schema)).toBeUndefined()
  })
})

describe('findOption', () => {
  it('returns the option with its label + color (the chip tint)', () => {
    expect(findOption('prop_tag', 'opt_a', schema)).toMatchObject({
      label: 'Alpha',
      color: 'green',
    })
  })
  it('returns undefined for an unknown value', () => {
    expect(findOption('prop_tag', 'nope', schema)).toBeUndefined()
  })
})

describe('cellText', () => {
  it('renders the page title for the title column', () => {
    expect(cellText(mkRow({}), '_title', ctx)).toBe('Page')
  })
  it('resolves tier ULIDs to Context titles (unknown id falls back to the id)', () => {
    expect(cellText(mkRow({ tier1: ['ctx1', 'ctx_x'] }), '_tier1', ctx)).toBe('Personal, ctx_x')
  })
})

describe('groupLabel', () => {
  const setNames = new Map([['set1', 'Inbox']])
  const view = { group: { kind: 'property', property_id: 'prop_status' } } as unknown as Parameters<
    typeof groupLabel
  >[1]

  it('resolves a structural Set group to its name', () => {
    const g = {
      key: 'set1',
      kind: 'structural-set',
      items: [],
      isCollapsed: false,
    } as ResolvedGroup
    expect(groupLabel(g, view, ctx, setNames)).toBe('Inbox')
  })
  it('resolves a property group bucket to its option label', () => {
    const g = { key: 'doing', kind: 'property', items: [], isCollapsed: false } as ResolvedGroup
    expect(groupLabel(g, view, ctx, setNames)).toBe('Doing')
  })
  it('returns empty for the no-value band', () => {
    const g = { key: UNGROUPED, kind: 'ungrouped', items: [], isCollapsed: false } as ResolvedGroup
    expect(groupLabel(g, view, ctx, setNames)).toBe('')
  })
})

describe('buildSetNames', () => {
  it('maps set ids to titles across the subtree', () => {
    const source = {
      kind: 'collection',
      sets: [
        {
          id: 's1',
          kind: 'set',
          title: 'Top',
          pages: [],
          sets: [{ id: 's2', kind: 'set', title: 'Nested', pages: [] }],
        },
      ],
    } as unknown as CollectionNode
    const m = buildSetNames(source)
    expect(m.get('s1')).toBe('Top')
    expect(m.get('s2')).toBe('Nested')
  })
})

describe('buildSetIcons', () => {
  it('maps set ids to their icon across the subtree (undefined when unset)', () => {
    const source = {
      kind: 'collection',
      sets: [
        {
          id: 's1',
          kind: 'set',
          title: 'Top',
          icon: 'star',
          pages: [],
          sets: [{ id: 's2', kind: 'set', title: 'Nested', pages: [] }],
        },
      ],
    } as unknown as CollectionNode
    const m = buildSetIcons(source)
    expect(m.get('s1')).toBe('star')
    expect(m.get('s2')).toBeUndefined()
  })
})
