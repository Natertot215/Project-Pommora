// @vitest-environment jsdom
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { NexusTree, PageDetail, SelectTarget, Tab } from '@shared/types'
import { DEFAULT_LABELS } from '@shared/types'
import { useSession } from './store'
import { newTabTab } from './Tabs/tabsModel'
import { navKey } from './Navigation/navRecents'
import { clearWarm, readWarm } from './Tabs/warmCache'

// Stub the narrow window.nexus surface the tab glue reaches (page fetch, recents save, tab persist,
// the applyTree accent read) so it runs in isolation.
beforeEach(() => {
  clearWarm() // module state — never leaks across tests
  ;(window as unknown as { nexus: unknown }).nexus = {
    openPage: vi.fn(async () => ({ ok: true, page: {} })),
    nav: { saveRecents: vi.fn(async () => ({ ok: true })) },
    tabs: {
      save: vi.fn(async () => ({ ok: true })),
      load: vi.fn(async () => ({ ok: true, set: null })),
    },
    systemAccent: vi.fn(async () => '#000000'),
  }
})

const ctx = (id: string): SelectTarget => ({ kind: 'context', id })
const uTab = (
  id: string,
  target: Tab['target'],
  navStack: SelectTarget[] = [],
  navIndex = -1,
): Tab => ({
  id,
  target,
  navStack,
  navIndex,
})

type State = ReturnType<typeof useSession.getState>
const seed = (partial: Partial<State>): void => {
  useSession.setState({
    tabs: [],
    activeTabId: '',
    tabMru: [],
    pins: [],
    recents: [],
    selection: { kind: 'none' },
    tree: null,
    ...partial,
  })
}

describe('store — tab wiring (Phase 0)', () => {
  it('activateTab re-surfaces the target without recording (C-5)', () => {
    seed({
      tabs: [uTab('t1', ctx('a'), [ctx('a')], 0), uTab('t2', ctx('b'), [ctx('b')], 0)],
      activeTabId: 't1',
    })
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

  it('re-selecting the shown entity after Back is a dedup no-op — Forward preserved', async () => {
    // target must move in lockstep with navIndex: after Back to b, clicking b in the sidebar must
    // dedup against the LIVE shown entity (not the pre-Back target) and leave the Forward stack alone.
    seed({ tabs: [uTab('t1', ctx('c'), [ctx('a'), ctx('b'), ctx('c')], 2)], activeTabId: 't1' })
    useSession.getState().goBack()
    expect(useSession.getState().tabs[0].target).toEqual(ctx('b'))
    await useSession.getState().select(ctx('b'))
    let s = useSession.getState()
    expect(s.tabs[0].navStack).toEqual([ctx('a'), ctx('b'), ctx('c')])
    expect(s.tabs[0].navIndex).toBe(1)
    expect(s.recents).toEqual([]) // a dedup-focus never records
    useSession.getState().goForward()
    s = useSession.getState()
    expect(s.selection).toEqual({ kind: 'context', id: 'c' })
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

describe('store — warm tabs (B-2/B-3)', () => {
  const pg = (id: string): SelectTarget => ({ kind: 'page', id, path: `/${id}` })
  const detail = (id: string): PageDetail => ({
    id,
    title: id.toUpperCase(),
    path: `/${id}`,
    frontmatter: {},
    body: 'x',
  })

  it('switching away captures the outgoing page detail; switching back is warm-instant — no fetch, no flash', () => {
    seed({
      tabs: [uTab('t1', pg('a'), [pg('a')], 0), uTab('t2', pg('b'), [pg('b')], 0)],
      activeTabId: 't1',
      selection: pg('a'),
      pageStatus: 'ready',
      pageDetail: detail('a'),
    })
    useSession.getState().activateTab('t2') // leaves t1 — captures its detail on the way out
    expect(readWarm('t1', 'page:a')?.pageDetail?.id).toBe('a')
    ;(window.nexus.openPage as ReturnType<typeof vi.fn>).mockClear()
    useSession.getState().activateTab('t1') // returns warm
    const s = useSession.getState()
    expect(s.pageStatus).toBe('ready') // never passed through 'loading' — no flash
    expect(s.pageDetail?.id).toBe('a')
    expect(window.nexus.openPage).not.toHaveBeenCalled()
  })

  it('a renamed entity misses the warm detail (path check) and falls through to the cold fetch', async () => {
    seed({
      tabs: [uTab('t1', pg('a'), [pg('a')], 0)],
      activeTabId: 't1',
      selection: pg('a'),
      pageStatus: 'ready',
      pageDetail: detail('a'),
    })
    useSession.getState().activateTab('t2-nonexistent') // capture fires on the way out
    await useSession
      .getState()
      .select({ kind: 'page', id: 'a', path: '/a-renamed' }, { record: false })
    expect(window.nexus.openPage).toHaveBeenCalledWith('/a-renamed')
  })

  it('a stale cold fetch resolving after a warm switch-back never clobbers the shown page', async () => {
    // Warm-instant finishes synchronously, so an earlier in-flight fetch resolves LAST — the fence
    // must drop it or the wrong file renders (and autosaves) under the wrong tab.
    let resolveB!: (v: unknown) => void
    ;(window.nexus.openPage as ReturnType<typeof vi.fn>).mockImplementation((path: string) =>
      path === '/b'
        ? new Promise((r) => (resolveB = r))
        : Promise.resolve({ ok: true, page: detail('a') }),
    )
    seed({
      tabs: [uTab('t1', pg('a'), [pg('a')], 0), uTab('t2', pg('b'), [pg('b')], 0)],
      activeTabId: 't1',
      selection: pg('a'),
      pageStatus: 'ready',
      pageDetail: detail('a'),
    })
    useSession.getState().activateTab('t2') // cold fetch of /b now in flight; A captured warm
    useSession.getState().activateTab('t1') // warm-instant back to A
    expect(useSession.getState().pageDetail?.id).toBe('a')
    resolveB({ ok: true, page: detail('b') }) // the stale response lands last
    await new Promise((r) => setTimeout(r, 0))
    const s = useSession.getState()
    expect(s.pageDetail?.id).toBe('a') // fence held — B never clobbered the shown page
    expect(s.selection).toEqual(pg('a'))
  })

  it('a cold switch pauses on the outgoing view — no loading intermediate, one-commit swap', async () => {
    let resolveB!: (v: unknown) => void
    ;(window.nexus.openPage as ReturnType<typeof vi.fn>).mockImplementation((path: string) =>
      path === '/b'
        ? new Promise((r) => (resolveB = r))
        : Promise.resolve({ ok: true, page: detail('a') }),
    )
    seed({
      tabs: [uTab('t1', pg('a'), [pg('a')], 0)],
      activeTabId: 't1',
      selection: pg('a'),
      pageStatus: 'ready',
      pageDetail: detail('a'),
      pageFrozen: false,
    })
    const p = useSession.getState().select(pg('b'))
    let s = useSession.getState()
    expect(s.selection).toEqual(pg('a')) // outgoing view still shown
    expect(s.pageStatus).toBe('ready') // never passes through 'loading'
    expect(s.pageFrozen).toBe(true) // ...but it's a held frame, not a live surface
    resolveB({ ok: true, page: detail('b') })
    await p
    s = useSession.getState()
    expect(s.selection).toEqual(pg('b'))
    expect(s.pageStatus).toBe('ready')
    expect(s.pageDetail?.id).toBe('b')
    expect(s.pageFrozen).toBe(false)
  })

  it('a navigation mid-pause supersedes the fetch — the stale response never lands', async () => {
    let resolveB!: (v: unknown) => void
    ;(window.nexus.openPage as ReturnType<typeof vi.fn>).mockImplementation((path: string) =>
      path === '/b'
        ? new Promise((r) => (resolveB = r))
        : Promise.resolve({ ok: true, page: detail('a') }),
    )
    seed({
      tabs: [uTab('t1', pg('a'), [pg('a')], 0)],
      activeTabId: 't1',
      selection: pg('a'),
      pageStatus: 'ready',
      pageDetail: detail('a'),
      pageFrozen: false,
    })
    const p = useSession.getState().select(pg('b')) // paused on A
    await useSession.getState().select({ kind: 'homepage' }) // user moves on mid-pause
    let s = useSession.getState()
    expect(s.selection).toEqual({ kind: 'homepage' })
    expect(s.pageFrozen).toBe(false)
    resolveB({ ok: true, page: detail('b') })
    await p
    s = useSession.getState()
    expect(s.selection).toEqual({ kind: 'homepage' }) // the stale B response was dropped
    expect(s.pageDetail).toBeNull()
  })

  it('a slow cold fetch falls back to the loading view at the deadline', async () => {
    vi.useFakeTimers()
    try {
      let resolveB!: (v: unknown) => void
      ;(window.nexus.openPage as ReturnType<typeof vi.fn>).mockImplementation((path: string) =>
        path === '/b'
          ? new Promise((r) => (resolveB = r))
          : Promise.resolve({ ok: true, page: detail('a') }),
      )
      seed({
        tabs: [uTab('t1', pg('a'), [pg('a')], 0)],
        activeTabId: 't1',
        selection: pg('a'),
        pageStatus: 'ready',
        pageDetail: detail('a'),
        pageFrozen: false,
      })
      const p = useSession.getState().select(pg('b'))
      expect(useSession.getState().pageFrozen).toBe(true)
      vi.advanceTimersByTime(300) // past the deadline — the loading view takes over
      let s = useSession.getState()
      expect(s.selection).toEqual(pg('b'))
      expect(s.pageStatus).toBe('loading')
      expect(s.pageFrozen).toBe(false)
      resolveB({ ok: true, page: detail('b') })
      await p
      s = useSession.getState()
      expect(s.pageStatus).toBe('ready')
      expect(s.pageDetail?.id).toBe('b')
    } finally {
      vi.useRealTimers()
    }
  })
})

/** A minimal tree with one Collection holding the given top-level pages (selection.test.ts's shape). */
function treeWith(pages: { id: string; path: string }[]): NexusTree {
  return {
    nexus: { id: 'nx', rootPath: '/x', name: 'x', profileImage: null, profileSubtitle: '' },
    homepage: { locked: false, headingIconHidden: false },
    navView: {},
    saved: [],
    contexts: { projects: [], topics: [], areas: [] },
    collections: [
      {
        kind: 'collection',
        id: 'c1',
        title: 'Notes',
        path: 'Notes',
        sets: [],
        pages: pages.map((p) => ({ kind: 'page', id: p.id, title: 'P', path: p.path })),
      },
    ],
    userSections: [],
    labels: DEFAULT_LABELS,
    accent: 'lavender',
    timeFormat: 'twelveHour',
    personalization: {},
    commands: {},
    registry: [],
  }
}

describe('store — applyTree reconciles EVERY tab (I-2a)', () => {
  const page = (id: string, path: string): SelectTarget => ({ kind: 'page', id, path })

  it('refreshes an inactive tab on a rename and closes it on a delete, without activating it', async () => {
    const col: SelectTarget = { kind: 'collection', id: 'c1' }
    const t1: Tab = { id: 't1', target: col, navStack: [col], navIndex: 0 }
    const t2: Tab = {
      id: 't2',
      target: page('b', 'Notes/B.md'),
      navStack: [page('b', 'Notes/B.md')],
      navIndex: 0,
    }
    seed({ tabs: [t1, t2], activeTabId: 't1', tabMru: ['t1', 't2'] })

    // Rename: page b moves — the inactive t2 refreshes in place, the active tab stays put.
    await useSession.getState().applyTree(treeWith([{ id: 'b', path: 'Notes/Renamed.md' }]))
    let s = useSession.getState()
    expect(s.activeTabId).toBe('t1')
    expect(s.tabs.find((t) => t.id === 't2')?.target).toEqual(page('b', 'Notes/Renamed.md'))

    // Delete: page b is gone — the inactive unpinned t2 closes; the active tab is untouched.
    await useSession.getState().applyTree(treeWith([]))
    s = useSession.getState()
    expect(s.tabs.map((t) => t.id)).toEqual(['t1'])
    expect(s.activeTabId).toBe('t1')
  })
})

describe('store — recents reorder + batched close', () => {
  const savedRecents = (): unknown =>
    (window as unknown as { nexus: { nav: { saveRecents: { mock: { calls: unknown[][] } } } } })
      .nexus.nav.saveRecents

  it('reorderRecent rewrites the order to the source and persists immediately (drag)', () => {
    const a = ctx('a')
    const b = ctx('b')
    const c = ctx('c')
    seed({ recents: [a, b, c] })
    useSession.getState().reorderRecent(navKey(a), navKey(c)) // drop a onto c's slot
    expect(useSession.getState().recents).toEqual([b, c, a])
    expect(savedRecents()).toHaveBeenCalledWith([b, c, a], true) // immediate write, like the pin toggle
  })

  it('reorderRecent is a no-op on same/unknown key (no state churn, no write)', () => {
    const a = ctx('a')
    const b = ctx('b')
    seed({ recents: [a, b] })
    useSession.getState().reorderRecent(navKey(a), navKey(a))
    useSession.getState().reorderRecent('missing', navKey(b))
    expect(useSession.getState().recents).toEqual([a, b])
    expect(savedRecents()).not.toHaveBeenCalled()
  })
})
