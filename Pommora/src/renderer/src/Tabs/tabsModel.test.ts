import { describe, it, expect } from 'vitest'
import type { PinEntry, SelectTarget, Tab } from '@shared/types'
import {
  activeUnpinnedTab,
  closeTab,
  cycle,
  derivePinnedTabs,
  insertUnpinned,
  isPinned,
  newTabTab,
  openNewTab,
  openTab,
  pinTabId,
  pushMru,
  reconcileTabs,
  reorderWithinZone,
} from './tabsModel'

const pt = (id: string): SelectTarget => ({ kind: 'page', id, path: `/${id}` })
const tab = (id: string, targetId: string): Tab => ({
  id,
  target: pt(targetId),
  navStack: [pt(targetId)],
  navIndex: 0,
})
const pin = (id: string, order: number): PinEntry => ({ kind: 'page', id, path: `/${id}`, order })
const navTab = (id: string): Tab => newTabTab(id)

describe('tabsModel — openTab', () => {
  it('focuses an already-open tab instead of duplicating (I-1)', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b')]
    const r = openTab(tabs, 't1', [], pt('b'), {}, 'NEW')
    expect(r.tabs).toBe(tabs)
    expect(r.activeTabId).toBe('t2')
  })

  it('replaces the active unpinned tab in place, pushing its history (D-1)', () => {
    const r = openTab([tab('t1', 'a')], 't1', [], pt('b'), {}, 'NEW')
    expect(r.tabs).toHaveLength(1)
    expect(r.tabs[0].id).toBe('t1')
    expect(r.tabs[0].target).toEqual(pt('b'))
    expect(r.tabs[0].navStack).toEqual([pt('a'), pt('b')])
    expect(r.tabs[0].navIndex).toBe(1)
    expect(r.activeTabId).toBe('t1')
  })

  it('truncates forward history on a replace mid-stack', () => {
    const branched: Tab = {
      id: 't1',
      target: pt('a'),
      navStack: [pt('a'), pt('b'), pt('c')],
      navIndex: 0,
    }
    const r = openTab([branched], 't1', [], pt('z'), {}, 'NEW')
    expect(r.tabs[0].navStack).toEqual([pt('a'), pt('z')])
    expect(r.tabs[0].navIndex).toBe(1)
  })

  it('spawns a new tab when the active tab is pinned (D-2)', () => {
    const pinned = derivePinnedTabs([pin('p', 0)])
    const r = openTab([], pinTabId(pt('p')), pinned, pt('b'), {}, 'NEW')
    expect(r.tabs).toHaveLength(1)
    expect(r.tabs[0].id).toBe('NEW')
    expect(r.activeTabId).toBe('NEW')
  })

  it('spawns on explicit Open in New Tab, appended right (D-3, D-12)', () => {
    const r = openTab([tab('t1', 'a')], 't1', [], pt('b'), { newTab: true }, 'NEW')
    expect(r.tabs.map((t) => t.id)).toEqual(['t1', 'NEW'])
    expect(r.activeTabId).toBe('NEW')
  })

  it('focuses a pinned tab when opening its entity from a scratch tab — never replaces the scratch (I-1)', () => {
    const pinned = derivePinnedTabs([pin('p', 0)])
    const tabs = [tab('t1', 'a')]
    const r = openTab(tabs, 't1', pinned, pt('p'), {}, 'NEW')
    expect(r.tabs).toBe(tabs)
    expect(r.activeTabId).toBe(pinTabId(pt('p')))
  })

  it('replaces a NavView scratch tab in place (E-2)', () => {
    const r = openTab([navTab('t1')], 't1', [], pt('a'), {}, 'NEW')
    expect(r.tabs).toHaveLength(1)
    expect(r.tabs[0].id).toBe('t1')
    expect(r.tabs[0].target).toEqual(pt('a'))
    expect(r.tabs[0].navStack).toEqual([pt('a')])
    expect(r.tabs[0].navIndex).toBe(0)
  })
})

describe('tabsModel — openNewTab', () => {
  it('appends a NavView tab', () => {
    const r = openNewTab([tab('t1', 'a')], 'NEW')
    expect(r.tabs).toHaveLength(2)
    expect(r.tabs[1].target).toEqual({ kind: 'newtab' })
    expect(r.activeTabId).toBe('NEW')
  })

  it('focuses the existing NavView instead of a second one — no duplicate (I-1)', () => {
    const r = openNewTab([navTab('n')], 'NEW')
    expect(r.tabs).toHaveLength(1)
    expect(r.activeTabId).toBe('n')
  })
})

describe('tabsModel — closeTab', () => {
  it('focuses the MRU top when closing the active tab (D-9)', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b'), tab('t3', 'c')]
    const r = closeTab(tabs, 't3', ['t3', 't1', 't2'], [], 't3', 'NEW')
    expect(r.activeTabId).toBe('t1')
    expect(r.tabs.map((t) => t.id)).toEqual(['t1', 't2'])
  })

  it('falls back to the spatial neighbor when the MRU is empty (cold relaunch)', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b'), tab('t3', 'c')]
    expect(closeTab(tabs, 't2', [], [], 't2', 'NEW').activeTabId).toBe('t3')
  })

  it('keeps the previous tab when closing the rightmost with an empty MRU', () => {
    expect(closeTab([tab('t1', 'a'), tab('t2', 'b')], 't2', [], [], 't2', 'NEW').activeTabId).toBe(
      't1',
    )
  })

  it('leaves the active tab untouched when closing a background tab', () => {
    const r = closeTab([tab('t1', 'a'), tab('t2', 'b')], 't2', ['t2', 't1'], [], 't1', 'NEW')
    expect(r.activeTabId).toBe('t2')
    expect(r.tabs.map((t) => t.id)).toEqual(['t2'])
  })

  it('reseeds a lone NavView when the last tab closes (I-5)', () => {
    const r = closeTab([tab('t1', 'a')], 't1', ['t1'], [], 't1', 'NEW')
    expect(r.tabs).toHaveLength(1)
    expect(r.tabs[0].target).toEqual({ kind: 'newtab' })
    expect(r.activeTabId).toBe('NEW')
    expect(r.mru).toEqual(['NEW'])
  })

  it('does not reseed when pinned tabs remain — focuses a pin', () => {
    const r = closeTab([tab('t1', 'a')], 't1', ['t1'], ['pin:page:p'], 't1', 'NEW')
    expect(r.tabs).toHaveLength(0)
    expect(r.activeTabId).toBe('pin:page:p')
  })

  it('is a no-op for a pinned tab id (not closable here)', () => {
    const tabs = [tab('t1', 'a')]
    const r = closeTab(tabs, 't1', ['t1'], ['pin:page:p'], 'pin:page:p', 'NEW')
    expect(r.tabs).toBe(tabs)
    expect(r.activeTabId).toBe('t1')
  })
})

describe('tabsModel — reorderWithinZone', () => {
  it('moves a tab to a new index', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b'), tab('t3', 'c')]
    expect(reorderWithinZone(tabs, 't1', 2).map((t) => t.id)).toEqual(['t2', 't3', 't1'])
  })

  it('is a no-op at the same index', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b')]
    expect(reorderWithinZone(tabs, 't1', 0)).toBe(tabs)
  })

  it('returns the same list for an unknown id', () => {
    const tabs = [tab('t1', 'a')]
    expect(reorderWithinZone(tabs, 'x', 0)).toBe(tabs)
  })
})

describe('tabsModel — insertUnpinned (D-11)', () => {
  it('inserts at the front when the active tab is not the front one', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b')]
    expect(insertUnpinned(tabs, 't2', tab('t3', 'c')).map((t) => t.id)).toEqual(['t3', 't1', 't2'])
  })

  it('inserts behind the active tab when it is the front one', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b')]
    expect(insertUnpinned(tabs, 't1', tab('t3', 'c')).map((t) => t.id)).toEqual(['t1', 't3', 't2'])
  })
})

describe('tabsModel — cycle (I-11)', () => {
  const ids = ['p1', 'p2', 't1', 't2']

  it('advances forward and wraps', () => {
    expect(cycle(ids, 't2', 1)).toBe('p1')
    expect(cycle(ids, 'p1', 1)).toBe('p2')
  })

  it('advances backward and wraps', () => {
    expect(cycle(ids, 'p1', -1)).toBe('t2')
  })

  it('returns the active id when empty', () => {
    expect(cycle([], 'x', 1)).toBe('x')
  })
})

describe('tabsModel — reconcileTabs (I-2a)', () => {
  // A reconcile stub over a live-path map: absent id = deleted, changed path = renamed/moved.
  const against = (live: Record<string, string>) => (t: SelectTarget) => {
    if (!('id' in t)) return t // homepage — the singleton never reconciles away
    const path = live[t.id]
    if (path === undefined) return null
    return 'path' in t && t.path !== path ? ({ ...t, path } as SelectTarget) : t
  }

  it('returns changed:false with the same references when nothing moved', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b')]
    const r = reconcileTabs(tabs, 't1', ['t1'], [], against({ a: '/a', b: '/b' }), 'NEW')
    expect(r.changed).toBe(false)
    expect(r.tabs).toBe(tabs)
  })

  it('refreshes an INACTIVE tab target + history on a rename without activating it', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b')]
    const r = reconcileTabs(
      tabs,
      't1',
      ['t1', 't2'],
      [],
      against({ a: '/a', b: '/renamed' }),
      'NEW',
    )
    expect(r.changed).toBe(true)
    expect(r.activeTabId).toBe('t1')
    expect(r.tabs[0]).toBe(tabs[0]) // untouched tab keeps its identity
    expect(r.tabs[1].target).toEqual({ kind: 'page', id: 'b', path: '/renamed' })
    expect(r.tabs[1].navStack).toEqual([{ kind: 'page', id: 'b', path: '/renamed' }])
  })

  it('closes an inactive unpinned tab whose entity was deleted', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b')]
    const r = reconcileTabs(tabs, 't1', ['t1', 't2'], [], against({ a: '/a' }), 'NEW')
    expect(r.tabs.map((t) => t.id)).toEqual(['t1'])
    expect(r.activeTabId).toBe('t1')
    expect(r.mru).toEqual(['t1'])
  })

  it('deleting the ACTIVE tab focuses the MRU survivor', () => {
    const tabs = [tab('t1', 'a'), tab('t2', 'b'), tab('t3', 'c')]
    const r = reconcileTabs(
      tabs,
      't2',
      ['t2', 't3', 't1'],
      [],
      against({ a: '/a', c: '/c' }),
      'NEW',
    )
    expect(r.activeTabId).toBe('t3')
  })

  it('drops dead history entries and recomputes navIndex around them', () => {
    const t: Tab = { id: 't1', target: pt('c'), navStack: [pt('a'), pt('b'), pt('c')], navIndex: 2 }
    const r = reconcileTabs([t], 't1', ['t1'], [], against({ a: '/a', c: '/c' }), 'NEW')
    expect(r.tabs[0].navStack).toEqual([pt('a'), pt('c')])
    expect(r.tabs[0].navIndex).toBe(1)
  })

  it('everything gone with no pins reseeds a lone NavView (I-5)', () => {
    const r = reconcileTabs([tab('t1', 'a')], 't1', ['t1'], [], against({}), 'NEW')
    expect(r.tabs).toHaveLength(1)
    expect(r.tabs[0].target).toEqual({ kind: 'newtab' })
    expect(r.activeTabId).toBe('NEW')
  })

  it('keeps a newtab tab through any reconcile', () => {
    const tabs = [navTab('n'), tab('t1', 'a')]
    const r = reconcileTabs(tabs, 'n', ['n'], [], against({}), 'NEW')
    expect(r.tabs.map((t) => t.id)).toEqual(['n'])
    expect(r.activeTabId).toBe('n')
  })
})

describe('tabsModel — pushMru', () => {
  it('moves an id to the front, deduped', () => {
    expect(pushMru(['a', 'b', 'c'], 'c')).toEqual(['c', 'a', 'b'])
    expect(pushMru(['a', 'b'], 'x')).toEqual(['x', 'a', 'b'])
  })
})

describe('tabsModel — activeUnpinnedTab', () => {
  it('finds the active tab in the unpinned set; a pinned/unknown active id reads undefined', () => {
    const tabs = [tab('t1', 'a')]
    expect(activeUnpinnedTab(tabs, 't1')?.id).toBe('t1')
    expect(activeUnpinnedTab(tabs, 'pin:page:p')).toBeUndefined()
  })
})

describe('tabsModel — isPinned', () => {
  it('derives membership from the pins set; never the newtab sentinel', () => {
    const pins = [pin('a', 0)]
    expect(isPinned(pt('a'), pins)).toBe(true)
    expect(isPinned(pt('b'), pins)).toBe(false)
    expect(isPinned({ kind: 'newtab' }, pins)).toBe(false)
  })
})

describe('tabsModel — derivePinnedTabs', () => {
  it('sorts by order and derives stable ids + a one-entry history', () => {
    const tabs = derivePinnedTabs([pin('b', 1), pin('a', 0)])
    expect(tabs.map((t) => t.id)).toEqual(['pin:page:a', 'pin:page:b'])
    expect(tabs[0].navStack).toEqual([pt('a')])
    expect(tabs[0].navIndex).toBe(0)
  })

  it('skips agenda pins (legacy migration) — select cannot drive them', () => {
    const agendaPin = { kind: 'task', id: 'tk', order: 0 } as PinEntry
    expect(derivePinnedTabs([agendaPin, pin('a', 1)]).map((t) => t.id)).toEqual(['pin:page:a'])
  })
})
