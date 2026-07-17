// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from 'vitest'
import { useSession } from '../store'
import { capturePreviewWarm, clearPreviewWarm, readPreviewWarm } from './previewWarm'

const page = (id: string) => ({ id, path: `Notes/${id}.md` })

beforeEach(() => {
  clearPreviewWarm()
  useSession.setState({
    preview: null,
    navOpen: false,
    previewsFile: { navSet: null, origins: {}, open: null },
  })
})

describe('previewTabs — the tab model (H-1/H-5/H-6/H-7)', () => {
  it('summon opens a single-tab window; re-summon of the same origin is a no-op (I-1)', () => {
    useSession.getState().openPreview(page('x'))
    const p1 = useSession.getState().preview
    expect(p1?.tabs.map((t) => t.target)).toEqual([{ kind: 'page', id: 'x', path: 'Notes/x.md' }])
    useSession.getState().openPreview(page('x'))
    expect(useSession.getState().preview).toBe(p1)
  })

  it('a wiki-click adds a deduped tab and focuses on re-click (H-1)', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    expect(useSession.getState().preview?.tabs).toHaveLength(2)
    useSession.getState().activatePreviewTab(useSession.getState().preview!.tabs[0].id)
    useSession.getState().openPreviewTab(page('y'))
    const p = useSession.getState().preview!
    expect(p.tabs).toHaveLength(2)
    expect(p.tabs.find((t) => t.id === p.activeTabId)?.target).toMatchObject({ id: 'y' })
  })

  it('closing the origin re-parents to the left-most survivor; last close kills the window (H-6)', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    const p = useSession.getState().preview!
    useSession.getState().closePreviewTab(p.tabs[0].id)
    const p2 = useSession.getState().preview!
    expect(p2.originId).toBe('y')
    useSession.getState().closePreviewTab(p2.tabs[0].id)
    expect(useSession.getState().preview).toBeNull()
  })

  it('a new summon overtakes — swaps to the new origin single-tab set (D-2)', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    useSession.getState().openPreview(page('z'))
    const p = useSession.getState().preview!
    expect(p.originId).toBe('z')
    expect(p.tabs).toHaveLength(1)
  })

  it('never touches app tabs/selection (D-1)', () => {
    const { tabs, activeTabId, selection } = useSession.getState()
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    const s = useSession.getState()
    expect(s.tabs).toBe(tabs)
    expect(s.activeTabId).toBe(activeTabId)
    expect(s.selection).toBe(selection)
  })

  it('closing a non-active, non-origin tab keeps origin and active untouched', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    useSession.getState().openPreviewTab(page('z'))
    const p = useSession.getState().preview!
    const yId = p.tabs[1].id
    useSession.getState().activatePreviewTab(p.tabs[2].id)
    useSession.getState().closePreviewTab(yId)
    const p2 = useSession.getState().preview!
    expect(p2.originId).toBe('x')
    expect(p2.tabs.map((t) => (t.target.kind === 'page' ? t.target.id : ''))).toEqual(['x', 'z'])
    expect(p2.tabs.find((t) => t.id === p2.activeTabId)?.target).toMatchObject({ id: 'z' })
  })

  it('closing the ACTIVE tab falls to its left neighbor', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    const p = useSession.getState().preview!
    useSession.getState().closePreviewTab(p.tabs[1].id)
    const p2 = useSession.getState().preview!
    expect(p2.tabs).toHaveLength(1)
    expect(p2.activeTabId).toBe(p2.tabs[0].id)
  })
})

describe('previewTabs — durable sets (H-3/H-6/H-10)', () => {
  it("a summon restores the origin's remembered set; the active pointer survives", () => {
    useSession.setState({
      previewsFile: {
        navSet: null,
        origins: {
          x: {
            tabs: [
              { target: { kind: 'page', id: 'x', path: 'Notes/x.md' } },
              { target: { kind: 'page', id: 'y', path: 'Notes/y.md' } },
            ],
            activeIndex: 1,
          },
        },
        open: null,
      },
    })
    useSession.getState().openPreview(page('x'))
    const p = useSession.getState().preview!
    expect(p.tabs.map((t) => (t.target.kind === 'page' ? t.target.id : ''))).toEqual(['x', 'y'])
    expect(p.tabs.find((t) => t.id === p.activeTabId)?.target).toMatchObject({ id: 'y' })
    expect(useSession.getState().previewTarget).toEqual({ id: 'y', path: 'Notes/y.md' })
  })

  it('a re-parent re-keys the record: the old origin retires, the survivor keys the set (H-6)', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    const p = useSession.getState().preview!
    useSession.getState().closePreviewTab(p.tabs[0].id)
    const file = useSession.getState().previewsFile
    expect(file.origins.x).toBeUndefined()
    expect(file.origins.y?.tabs).toEqual([
      { target: { kind: 'page', id: 'y', path: 'Notes/y.md' } },
    ])
    expect(file.open).toEqual({ flavor: 'page', originId: 'y' })
  })

  it('closing the last tab retires the set — a re-summon starts fresh; the X keeps it (H-3)', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    useSession.getState().closePreview() // X: the set stays remembered, open clears
    let file = useSession.getState().previewsFile
    expect(file.origins.x?.tabs).toHaveLength(2)
    expect(file.open).toBeNull()

    useSession.getState().openPreview(page('x'))
    const p = useSession.getState().preview!
    expect(p.tabs).toHaveLength(2)
    useSession.getState().closePreviewTab(p.tabs[1].id)
    useSession.getState().closePreviewTab(useSession.getState().preview!.tabs[0].id)
    file = useSession.getState().previewsFile
    expect(useSession.getState().preview).toBeNull()
    expect(file.origins.x).toBeUndefined() // emptied → retired
    useSession.getState().openPreview(page('x'))
    expect(useSession.getState().preview?.tabs).toHaveLength(1) // fresh
  })
})

describe('previewTabs — the nav flavor (H-2)', () => {
  it('the map sentinel tab refuses to close; page tabs around it close normally', () => {
    useSession.getState().openNavPreview()
    useSession.getState().openPreviewTab(page('x'))
    const p = useSession.getState().preview!
    expect(p.flavor).toBe('nav')
    const mapId = p.tabs[0].id
    useSession.getState().closePreviewTab(mapId)
    expect(useSession.getState().preview).toBe(p)
    useSession.getState().closePreviewTab(p.tabs[1].id)
    const p2 = useSession.getState().preview!
    expect(p2.tabs.map((t) => t.target.kind)).toEqual(['navwindow'])
  })
})

describe('previewTabs — warmth (H-8)', () => {
  it('round-trips per tab id; a tab close evicts its entry; the window close clears all', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    const p = useSession.getState().preview!
    const [xTab, yTab] = p.tabs
    capturePreviewWarm(xTab.id, { editorState: { doc: 'X' }, scrollTop: 5 })
    capturePreviewWarm(yTab.id, { editorState: { doc: 'Y' }, scrollTop: 9 })
    expect(readPreviewWarm(xTab.id)?.scrollTop).toBe(5)

    useSession.getState().closePreviewTab(yTab.id)
    expect(readPreviewWarm(yTab.id)).toBeUndefined()
    expect(readPreviewWarm(xTab.id)?.scrollTop).toBe(5)

    useSession.getState().closePreview()
    expect(readPreviewWarm(xTab.id)).toBeUndefined()
  })

  it('a summon clears prior warmth — restored ids are fresh, old entries unreachable', () => {
    useSession.getState().openPreview(page('x'))
    const xTab = useSession.getState().preview!.tabs[0]
    capturePreviewWarm(xTab.id, { scrollTop: 7 })
    useSession.getState().openPreview(page('z'))
    expect(readPreviewWarm(xTab.id)).toBeUndefined()
  })
})

describe('previewTabs — the NavWindow flavor entry (H-2/H-3)', () => {
  it('openNav seeds the nav flavor with the remembered set (map tab active); closeNav keeps it durable', () => {
    useSession.setState({
      previewsFile: {
        navSet: {
          tabs: [{ target: { kind: 'page', id: 'n', path: 'Notes/n.md' } }],
          activeIndex: 0,
        },
        origins: {},
        open: null,
      },
    })
    useSession.getState().openNav()
    const p = useSession.getState().preview!
    expect(useSession.getState().navOpen).toBe(true)
    expect(p.flavor).toBe('nav')
    expect(p.tabs.map((t) => t.target.kind)).toEqual(['navwindow', 'page'])
    expect(p.activeTabId).toBe(p.tabs[0].id) // the map tab lands active (the gallery is the landing)

    useSession.getState().closeNav()
    expect(useSession.getState().preview).toBeNull()
    expect(useSession.getState().navOpen).toBe(false)
    expect(useSession.getState().previewsFile.navSet?.tabs).toHaveLength(2) // durable (H-3)
  })

  it('the B-2 override toggle persists in the previews file', () => {
    expect(useSession.getState().previewsFile.navOverride ?? true).toBe(true)
    useSession.getState().setNavOverride(false)
    expect(useSession.getState().previewsFile.navOverride).toBe(false)
  })
})

describe('previewTabs — the engulf exit flag (A-4)', () => {
  it("a promote's engulf flag never leaks onto the next window's close", () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().closePreview('engulf')
    expect(useSession.getState().previewExit).toBe('engulf')
    // Re-opening re-seeds — the six close paths that never write the flag can't replay the FLIP.
    useSession.getState().openPreview(page('y'))
    expect(useSession.getState().previewExit).toBe('dismiss')
  })
})

describe('previewTabs — the slide stamp (Task 1.3)', () => {
  it('stamps fwd on spawn, direction by strip order on activate, monotonic seq', () => {
    useSession.getState().openPreview(page('x'))
    useSession.getState().openPreviewTab(page('y'))
    const s1 = useSession.getState().previewSlide!
    expect(s1.dir).toBe('fwd')
    const p = useSession.getState().preview!
    useSession.getState().activatePreviewTab(p.tabs[0].id)
    const s2 = useSession.getState().previewSlide!
    expect(s2.dir).toBe('back')
    expect(s2.seq).toBeGreaterThan(s1.seq)
    useSession.getState().activatePreviewTab(p.tabs[1].id)
    expect(useSession.getState().previewSlide!.dir).toBe('fwd')
  })
})
