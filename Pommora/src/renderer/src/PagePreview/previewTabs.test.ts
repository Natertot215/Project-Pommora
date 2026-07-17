import { beforeEach, describe, expect, it } from 'vitest'
import { useSession } from '../store'

const page = (id: string) => ({ id, path: `Notes/${id}.md` })

beforeEach(() => useSession.setState({ preview: null }))

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
