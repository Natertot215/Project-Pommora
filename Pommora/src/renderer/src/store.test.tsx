// @vitest-environment jsdom
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { SelectTarget, Tab } from '@shared/types'
import { useSession } from './store'
import { newTabTab } from './Tabs/tabsModel'

// The store only reaches window.nexus for the page fetch + recents save. Stub both so the tab glue runs
// in isolation — the tests drive context targets (no fetch) and tree:null (no reconcile).
beforeEach(() => {
  ;(window as unknown as { nexus: unknown }).nexus = {
    openPage: vi.fn(async () => ({ ok: true, page: {} })),
    nav: { saveRecents: vi.fn() },
  }
})

const ctx = (id: string): SelectTarget => ({ kind: 'context', id })
const uTab = (id: string, target: Tab['target'], navStack: SelectTarget[] = [], navIndex = -1): Tab => ({
  id,
  target,
  navStack,
  navIndex,
})

type State = ReturnType<typeof useSession.getState>
const seed = (partial: Partial<State>): void => {
  useSession.setState({ tabs: [], activeTabId: '', tabMru: [], pins: [], recents: [], selection: { kind: 'none' }, tree: null, ...partial })
}

describe('store — tab wiring (Phase 0)', () => {
  it('activateTab re-surfaces the target without recording (C-5)', () => {
    seed({ tabs: [uTab('t1', ctx('a'), [ctx('a')], 0), uTab('t2', ctx('b'), [ctx('b')], 0)], activeTabId: 't1' })
    useSession.getState().activateTab('t2')
    const s = useSession.getState()
    expect(s.activeTabId).toBe('t2')
    expect(s.selection).toEqual({ kind: 'context', id: 'b' })
    expect(s.recents).toEqual([]) // a plain activate never records
    expect(s.tabMru[0]).toBe('t2')
  })

  it('activating a newtab tab routes to the empty state (E-2)', () => {
    seed({ tabs: [newTabTab('n')], activeTabId: 't-prev' })
    useSession.getState().activateTab('n')
    expect(useSession.getState().selection).toEqual({ kind: 'none' })
  })

  it('a genuine select replaces the scratch tab in place and records recents', async () => {
    seed({ tabs: [uTab('t1', ctx('a'), [ctx('a')], 0)], activeTabId: 't1' })
    await useSession.getState().select(ctx('b'))
    const s = useSession.getState()
    expect(s.tabs).toHaveLength(1)
    expect(s.tabs[0].target).toEqual(ctx('b'))
    expect(s.tabs[0].navStack).toEqual([ctx('a'), ctx('b')])
    expect(s.selection).toEqual({ kind: 'context', id: 'b' })
    expect(s.recents.map((r) => ('id' in r ? r.id : r.kind))).toEqual(['b'])
  })

  it('per-tab Back/Forward walks the active tab own history (D-7)', () => {
    seed({ tabs: [uTab('t1', ctx('c'), [ctx('a'), ctx('b'), ctx('c')], 2)], activeTabId: 't1' })
    useSession.getState().goBack()
    let s = useSession.getState()
    expect(s.tabs[0].navIndex).toBe(1)
    expect(s.selection).toEqual({ kind: 'context', id: 'b' })
    useSession.getState().goForward()
    s = useSession.getState()
    expect(s.tabs[0].navIndex).toBe(2)
    expect(s.selection).toEqual({ kind: 'context', id: 'c' })
  })

  it('closing the active tab focuses the MRU top (D-9)', () => {
    seed({
      tabs: [uTab('t1', ctx('a'), [ctx('a')], 0), uTab('t2', ctx('b'), [ctx('b')], 0)],
      activeTabId: 't2',
      tabMru: ['t2', 't1'],
    })
    useSession.getState().closeTab('t2')
    const s = useSession.getState()
    expect(s.activeTabId).toBe('t1')
    expect(s.selection).toEqual({ kind: 'context', id: 'a' })
  })

  it('closing the last tab reseeds a NavView, routing to the empty state (I-5)', () => {
    seed({ tabs: [uTab('t1', ctx('a'), [ctx('a')], 0)], activeTabId: 't1', tabMru: ['t1'] })
    useSession.getState().closeTab('t1')
    const s = useSession.getState()
    expect(s.tabs).toHaveLength(1)
    expect(s.tabs[0].target).toEqual({ kind: 'newtab' })
    expect(s.selection).toEqual({ kind: 'none' })
  })
})
